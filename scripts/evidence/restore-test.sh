#!/usr/bin/env bash
# Evidence: a logical backup restores to an identical dataset after the
# database is destroyed. Measures restore time and verifies a content checksum.
# Scope: pg_dump/pg_restore on kind. Production uses managed PITR + snapshots;
# the same verification (row counts + checksum + smoke query) applies to a
# restored RDS instance. Usage:
#   bash scripts/evidence/restore-test.sh | tee docs/evidence/restore-test.log
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ROWS="${ROWS:-500000}"
WORK=$(mktemp -d)
psql() { kubectl -n "$NS" exec -i deploy/postgres -- psql -v ON_ERROR_STOP=1 -U app -d app -qtA "$@"; }
wait_pg() {
  kubectl -n "$NS" rollout status deploy/postgres --timeout=180s >/dev/null
  for _ in $(seq 60); do psql -c 'select 1' >/dev/null 2>&1 && return 0; sleep 2; done
  echo "postgres not ready"; return 1
}
fingerprint() {
  psql -c "select 'orders=' || count(*) || ' md5=' || md5(string_agg(id || ':' || tenant || ':' || amount, ',' order by id)) from orders;"
  psql -c "select 'tenants=' || count(*) || ' md5=' || md5(string_agg(name || ':' || region, ',' order by name)) from tenants;"
}

echo "== $(ts) setup: commit $(git rev-parse --short HEAD)"
if ! kubectl -n "$NS" get secret postgres-auth >/dev/null 2>&1; then
  kubectl -n "$NS" create secret generic postgres-auth --from-literal=password="$(head -c 24 /dev/urandom | base64 | tr -d '/+=')" >/dev/null
fi
kubectl apply -f tests/harness/k8s/postgres.yaml >/dev/null
wait_pg

echo "== $(ts) seed $ROWS rows"
psql <<SQL
drop table if exists orders; drop table if exists tenants;
create table tenants (name text primary key, region text not null);
insert into tenants values ('shared','eu-central-1'), ('acme-eu','eu-west-1'), ('globex-us','us-west-2');
create table orders (id bigint primary key, tenant text not null references tenants(name),
                     amount numeric(12,2) not null, created_at timestamptz not null default now());
insert into orders (id, tenant, amount)
  select g, (array['shared','acme-eu','globex-us'])[1 + g % 3], round((random() * 1000)::numeric, 2)
  from generate_series(1, $ROWS) g;
SQL
before=$(fingerprint)
echo "$before" | sed 's/^/   before: /'

echo "== $(ts) backup (pg_dump custom format)"
t0=$(date +%s)
kubectl -n "$NS" exec deploy/postgres -- pg_dump -U app -d app -Fc > "$WORK/app.dump"
echo "   backup took $(( $(date +%s) - t0 ))s, size $(du -h "$WORK/app.dump" | cut -f1), sha256 $(sha256sum "$WORK/app.dump" | cut -c1-16)…"

echo "== $(ts) disaster: delete the database pod (emptyDir data is destroyed)"
kubectl -n "$NS" delete pod -l app=postgres --wait=true >/dev/null
wait_pg
echo "   after disaster: $(psql -c "select count(*) from pg_tables where schemaname='public';") public tables"

echo "== $(ts) restore"
t0=$(date +%s)
kubectl -n "$NS" exec -i deploy/postgres -- pg_restore -U app -d app --no-owner --exit-on-error < "$WORK/app.dump"
echo "   restore took $(( $(date +%s) - t0 ))s"

after=$(fingerprint)
echo "$after" | sed 's/^/   after:  /'
echo "== $(ts) smoke query: $(psql -c "select tenant || '=' || count(*) from orders group by tenant order by tenant;" | paste -sd' ')"
rm -rf "$WORK"

if [ "$before" = "$after" ]; then
  echo "== RESULT: PASS — row counts and content checksums identical after restore"
else
  echo "== RESULT: FAIL — restored data differs"; exit 1
fi
