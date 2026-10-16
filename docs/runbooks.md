# Runbooks

Each alert in `platform/observability/slo-rules.yaml` links here. Steps assume the
production design (EKS, Argo Rollouts, KEDA, RDS, ElastiCache). Commands marked
*(kind-tested)* were exercised on the local harness; the rest are not executed.

## API error budget burn
**Alert:** `ErrorBudgetFastBurn` (page) / `ErrorBudgetSlowBurn` (ticket), per `tenant`.

1. Is a rollout in progress for that tenant's stack?
   `kubectl -n continuity get rollout api -o jsonpath='{.status.phase} {.status.currentStepIndex}'`
   - Yes: abort it. `kubectl argo rollouts abort api -n continuity` — the canary is scaled
     away and stable takes all traffic *(kind-tested: `docs/evidence/canary-auto-rollback.log`)*.
     Then revert the GitOps commit so the desired state matches.
2. No rollout: check dependencies before the app.
   - DB: RDS `DatabaseConnections` vs. the connection budget (architecture §5), CPU, replica lag.
   - Redis: `EngineCPUUtilization`, evictions, recent failover events.
3. Errors on one tenant only, others healthy → tenant-specific data or config; check that
   stack's last change in git. Errors on every stack → shared dependency or the release.
4. Record the budget consumed (`tenant:slo_errors:ratio_rate1h`) in the incident.

## API latency
**Alert:** `ApiLatencyP95High` (p95 > 400 ms for 10 min).

1. Saturation? `kubectl get hpa -n continuity`: at `maxReplicas` → raise max via the tenant
   file (`tenants/<name>.yaml`, reviewed PR). Pods Pending → node capacity; check the
   autoscaler and the warm-headroom setting `app_nodes_min`.
2. HPA not at max but latency high → downstream: DB slow queries (`log_min_duration_statement=500`),
   pool waits, Redis latency. Scaling API pods does not fix a saturated database and
   adds connections — check the connection budget before raising replicas.

## Job backlog
**Alert:** `JobBacklogAging` (oldest pending job > 2 min) or `JobsDuplicated`.

1. Workers at `maxReplicaCount`? `kubectl get scaledobject -n continuity`. If yes and the
   DB has headroom, raise `workers_max` for the tenant (PR). Each worker adds DB connections.
2. Workers below max but backlog grows → KEDA cannot read the queue: `kubectl describe scaledobject worker`,
   check `TriggerAuthentication` and the `app-secrets` ExternalSecret sync status.
3. Duplicates: expected rarely (at-least-once delivery after a worker crash or Redis failover).
   A sustained rate means workers are being killed before finishing — check OOMKilled
   and that `terminationGracePeriodSeconds` (90 s) still exceeds the longest job.
4. Never `FLUSHDB` or delete `jobs:processing:*` lists: they are the in-flight jobs. Orphaned lists
   are requeued automatically once the owner's heartbeat expires *(kind-tested: `worker-drain.log` scenario B)*.

## Bad release
Automatic: the canary analysis aborts on > 1% 5xx or p95 ≥ 400 ms on canary pods.
Manual, if a problem appears after full promotion:
1. Revert the release commit in the GitOps repo (the previous digest). Argo Rollouts treats
   a return to the stable spec as an immediate rollback, without canary steps.
2. If the release contained a migration: the schema stays expanded; the previous app version
   still works by design (expand/contract). Do **not** run a down-migration under load.
3. Halt the fleet: later rings do not start while a ring is failed (`promote-production`
   runs one ring at a time with fail-fast).

## Failed or stuck migration
1. Migrations must be additive in the release that ships them (expand). A lock timeout
   (`lock_timeout=5s` in the parameter group) fails the migration fast instead of blocking traffic.
2. Failed expand step: fix forward with a new migration; the old app version keeps running.
3. Never contract (drop/rename) in the same release as the code change; contract only when no
   pod runs the old version and the rollback window has closed
   *(kind-tested: `docs/evidence/migration-expand-contract.log`)*.

## Database restore
Targets (assumed, to be agreed): RPO ≤ 5 min (PITR), RTO ≤ 1 h for a single stack.
1. Restore to a **new** instance; never overwrite the damaged one (it is evidence and fallback):
   `aws rds restore-db-instance-to-point-in-time --source-db-instance-identifier <tenant>-prod --target-db-instance-identifier <tenant>-prod-restore --restore-time <UTC before the incident>`
2. Verify before switching: row counts and checksums of key tables against the last known-good
   values, plus application smoke queries (the method is kind-tested with pg_dump/pg_restore:
   `docs/evidence/restore-test.log`).
3. Switch: update `<tenant>/prod/app-secrets` DATABASE_URL to the restored endpoint;
   ESO refreshes the Secret; restart API and workers (rolling, no downtime).
4. Jobs in Redis may reference rows newer than the restore point: pause producers, reconcile, resume.
5. EU tenants: the restore target must be in the same EU region (the Terraform guard enforces
   this for new stacks; for CLI restores it is a manual check in this runbook).

## Restore drill (monthly, per stack)
Restore the latest snapshot into an isolated account/VPC, run the verification in step 2
above, record duration (actual RTO) and data age (actual RPO), destroy the copy. A backup
is not considered valid until a drill has restored it.
