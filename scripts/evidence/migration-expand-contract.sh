#!/usr/bin/env bash
# Evidence: why a non-backward-compatible migration breaks a rolling update,
# and how expand/contract keeps old and new app versions working, including
# rolling the app back after the migration ran.
# The "apps" are the SQL each version issues (the real app is a black box).
# Scenario: split users.full_name into first_name/last_name.
# Usage: bash scripts/evidence/migration-expand-contract.sh | tee docs/evidence/migration-expand-contract.log
set -uo pipefail
source "$(dirname "$0")/lib.sh"

psql() { kubectl -n "$NS" exec -i deploy/postgres -- psql -v ON_ERROR_STOP=1 -U app -d app -qtA "$@" 2>&1; }
run() {  # run <label> <sql>: print OK or the error, never abort the script
  local out
  if out=$(psql -c "$2"); then echo "   [OK]   $1"; else echo "   [FAIL] $1 -> $(echo "$out" | grep -m1 ERROR)"; fi
}
V1_WRITE="insert into users (full_name) values ('Ada Lovelace')"
V1_READ="select full_name from users limit 1"
V2_WRITE="insert into users (first_name, last_name) values ('Grace', 'Hopper')"
V2_READ="select first_name, last_name from users limit 1"
reset() { psql -c "drop table if exists users cascade; drop function if exists users_sync_names cascade;
  create table users (id bigserial primary key, full_name text not null);
  insert into users (full_name) select 'user ' || g || ' example' from generate_series(1, 10000) g;" >/dev/null; }

kubectl -n "$NS" rollout status deploy/postgres --timeout=120s >/dev/null
echo "== $(ts) A. naive one-step migration while v1 pods are still running (rolling update)"
reset
run "migration: rename full_name -> first_name, add last_name" \
  "alter table users rename column full_name to first_name; alter table users add column last_name text;"
run "v1 pod write" "$V1_WRITE"
run "v1 pod read"  "$V1_READ"
run "v2 pod write" "$V2_WRITE"
echo "   => v1 pods fail the moment the migration runs; rolling the app back to v1 also fails,"
echo "      because a Kubernetes rollback does not undo the schema change."

echo
echo "== $(ts) B. expand / migrate / contract"
reset
echo "-- phase 1 EXPAND (additive only; safe with v1 running)"
run "add nullable first_name, last_name" "alter table users add column first_name text, add column last_name text;"
run "sync trigger: writes from either version populate both shapes" "
create function users_sync_names() returns trigger language plpgsql as \$\$
begin
  if new.first_name is null and new.full_name is not null then
    new.first_name := split_part(new.full_name, ' ', 1);
    new.last_name  := nullif(substr(new.full_name, length(split_part(new.full_name, ' ', 1)) + 2), '');
  elsif new.full_name is null and new.first_name is not null then
    new.full_name := trim(new.first_name || ' ' || coalesce(new.last_name, ''));
  end if;
  return new;
end \$\$;
create trigger users_sync_names before insert or update on users
  for each row execute function users_sync_names();
alter table users alter column full_name drop not null;"
run "backfill in batches of 2,500 rows (bounded lock time)" "
do \$\$ declare n int; begin
  loop
    update users set first_name = split_part(full_name, ' ', 1),
                     last_name  = nullif(substr(full_name, length(split_part(full_name, ' ', 1)) + 2), '')
    where id in (select id from users where first_name is null limit 2500);
    get diagnostics n = row_count; exit when n = 0;
  end loop; end \$\$;"
echo "   rows not yet backfilled: $(psql -c 'select count(*) from users where first_name is null')"
echo "-- mixed versions during the rolling update"
run "v1 pod write" "$V1_WRITE"
run "v1 pod read"  "$V1_READ"
run "v2 pod write" "$V2_WRITE"
run "v2 pod read"  "$V2_READ"
echo "-- app ROLLBACK to v1 after the migration (schema left in expanded state)"
run "v1 write after rollback" "$V1_WRITE"
run "v1 read of a row written by v2" "select full_name from users where first_name = 'Grace'"
echo "   v2-written row as seen by v1: '$(psql -c "select full_name from users where first_name = 'Grace' limit 1")'"
echo "-- phase 3 CONTRACT (separate release, only after no v1 pods remain and the rollback window has closed)"
run "drop trigger, function and full_name" \
  "drop trigger users_sync_names on users; drop function users_sync_names; alter table users drop column full_name;"
run "v2 pod write" "$V2_WRITE"
run "v1 pod write (expected to fail: v1 is no longer a valid rollback target)" "$V1_WRITE"
echo
echo "== $(ts) RESULT: expand kept v1 and v2 working together and allowed an app rollback after the migration;"
echo "   the breaking step was deferred to a contract release. The naive migration broke v1 immediately."
