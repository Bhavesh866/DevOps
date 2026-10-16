# Cost model — planning envelope, not a quote

Budget: $9,000/month steady state, $16,000/month at peak (shared stack, one EU region).
No pricing calculator export was produced; figures are planning ranges from list-price
experience and must be replaced by a calculator export before commitment.

## Shared stack (eu-central-1)

Assumptions: 150 req/s baseline with a few peaks per day to 2,250 req/s; real app at
~100 req/s/pod (not benchmarked); 20,000 jobs/h; on-demand pricing; 30-day log retention.

| Cost area | Steady / month | Peak month / month | Driver |
|---|---:|---:|---|
| EKS control plane | $75 | $75 | fixed |
| Nodes: system 2× m6i.large + apps (warm min 4× c6i.xlarge; peak adds up to ~10) | $1,600–2,400 | $3,200–4,800 | warm headroom for the 5-minute target is the main fixed cost |
| RDS PostgreSQL db.r6g.2xlarge Multi-AZ, 200 GB gp3, PITR 14 d | $1,700–2,200 | $1,800–2,400 | Multi-AZ doubles instance cost |
| ElastiCache cache.r7g.large × 2 (replicated) | $450–550 | $450–550 | fixed |
| NAT gateways × 3, load balancer, data transfer | $500–900 | $800–1,500 | NAT per AZ removes a cross-AZ dependency at ~$100/month each + GB processed |
| Observability (metrics, logs 30 d, traces sampled) | $500–900 | $700–1,200 | cardinality and log volume |
| KMS, Secrets Manager, ECR, backups beyond free tier | $150–300 | $150–300 | |
| **Total** | **$4,975–7,325** | **$7,175–10,825** | within $9k / $16k |

Peak months stay inside the envelope because peaks are short (autoscaling pays for minutes,
not a month of peak capacity). The largest uncertainty is pods per req/s for the real app:
at 50 req/s/pod the node line roughly doubles at peak.

## Each dedicated tenant stack

A dedicated stack duplicates the fixed floor even when idle: EKS ($75), 2 system + 3 app
nodes (~$1,100), RDS Multi-AZ db.r6g.large (~$700), ElastiCache × 2 (~$450), NAT × 3 (~$300+),
observability (~$300). **Floor ≈ $3,000–3,500/month per dedicated tenant**, before load.
Dedicated stacks are priced into the tenant's contract, not the shared budget.

## CR-001: dedicated tenant on GCP, US-West + US-East standby

≈ $7,500–10,500/month (primary $5–7k, warm standby $2–3k, cross-region replication and DNS
$0.3–0.6k). See `docs/change-request-us-west.md`.

## Controls

Rightsize from measured utilisation after 30 days; Savings Plans/committed use for the warm floor
only (not for burst); schedule non-production down outside working hours; VPC endpoints for
ECR/S3 to cut NAT processing; log retention and metric cardinality limits; worker scaling on
queue signals so idle workers scale in; cost-allocation tags per `Tenant` (set by Terraform
default tags); budget alerts at 70 / 85 / 100 % per stack. Do not meet budget by weakening
the SLO or EU residency.
