# CR-001 Addendum — Dedicated tenant on GCP, US-West primary, US-East failover

**Status:** proposed; `infra/providers/gcp` validated, never planned · **Type:** additive new stack, existing stacks unchanged · **Residency:** US only

**Topology.** GCP project per tenant (own VPC, no peering, Workload Identity, CMEK planned). Same image digest, platform layer and tenant workflow as AWS; only the provider root differs.

| | `us-west1` primary (active) | `us-east1` standby (warm) |
|---|---|---|
| Compute | GKE regional, 3 zones, prod size | GKE regional at minimum size, workers at 0 |
| PostgreSQL | Cloud SQL HA (sync standby, other zone), PITR | cross-region **async read replica** |
| Redis | Memorystore Standard HA | separate empty instance (**no cross-region replication**) |
| Traffic | Cloud DNS failover policy, health check `/readyz`, TTL 30 s | backup target |

**Isolation and residency.** Org policy `gcp.resourceLocations` = {us-west1, us-east1} (equivalent of the EU Terraform guard); GKE control plane restricted to the VPC and operator ranges; secrets in Secret Manager replicated only to the two regions; CI deploys through Workload Identity Federation (no keys).

**Repository changes.** `infra/providers/gcp` (same outputs as AWS); `tenant.py`: add `gcp`, a `failover_region` field and US region allowlist; the tenant enters production as its own ring. Not portable, rebuilt: IAM, Cloud SQL, Memorystore, DNS/LB, KMS, ExternalSecret store.

**Failover.** *Zone:* automatic (GKE reschedules, Cloud SQL HA ~1–2 min, RPO 0). *Region:* **human-approved, scripted**: confirm outage → promote replica (irreversible) → repoint `app-secrets` → raise HPA/KEDA minimums → DNS follows health checks. Automatic DB promotion is rejected: a false positive splits the brain. *Failback:* new replica in `us-west1` from the new primary, lag ≈ 0, planned switchover (RPO 0).

**Targets — to validate, not guarantees.** Region: RPO ≤ 5 min (replica lag, alert at 60 s), RTO ≤ 60 min. Zone: RPO 0, RTO ≤ 5 min. 99.95 % allows 21.6 min/month: a regional failover exceeds a month's budget, so the SLO rests on zonal resilience; the region pair is disaster protection.

**Jobs.** Memorystore does not replicate across regions: on regional failover, queued and in-flight jobs in `us-west1` are lost unless the app persists job intent in PostgreSQL (outbox) for re-enqueue after promotion — which also requires idempotent jobs. The app is a black box: **open question for the tenant**; without it, job RPO = everything queued at failure time.

**Cost (estimate, no quote).** Primary $5–7k + warm standby $2–3k + replication/DNS $0.3–0.6k ≈ **$7.5–10.5k/month**, billed to the tenant contract. Ops: second cloud's IAM, quotas, monitoring, on-call skills; quarterly game days.

**Risks.** Replica lag at write peaks breaks RPO · job loss without outbox · AWS/GCP platform drift (same manifests, cloud overlays only) · clients caching DNS past TTL · team unfamiliar with GCP under pressure.

**Acceptance.** (1) Reviewed plans for both regions; (2) resource in a non-US region is denied; (3) canary auto-rollback reproduced on GKE; (4) zone-drain drill within SLO; (5) **regional game day**: measured RTO/RPO, job loss/duplicates, failback; (6) restore drill in `us-east1`; (7) 30-day cost within ±20 %.

**Approvals.** Tenant owner (RTO/RPO, job-loss acceptance, cost) · Security (isolation, residency) · Platform lead (operability) · Finance · Change advisory board (go-live after the game day passes).
