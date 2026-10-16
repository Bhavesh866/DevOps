# Cost model — planning envelope only

The assignment sets budgets of $9,000/month steady state and $16,000/month peak. No live pricing lookup or account calculator was run; figures below are hypotheses, not a quote.

| Cost area | Steady monthly envelope | Peak monthly envelope |
|---|---:|---:|
| EKS/control plane, nodes and headroom | $2,000–$3,000 | $4,000–$5,500 |
| RDS PostgreSQL, I/O, storage, backups | $1,500–$2,500 | $2,000–$3,000 |
| ElastiCache Redis | $500–$1,000 | $800–$1,500 |
| Load balancers, NAT, endpoints, transfer | $700–$1,300 | $1,000–$2,000 |
| Observability and log retention | $500–$900 | $700–$1,200 |
| ECR, KMS, secrets and miscellaneous | $300–$700 | $400–$900 |
| **Indicative subtotal** | **$5,500–$9,400** | **$8,900–$14,100** |

The steady-state range can exceed budget at its high end. Dedicated tenant stacks and multi-region DR add cost. Validate exact region, instance sizes, traffic, log retention, storage, I/O and tenant count in AWS Pricing Calculator. Do not meet budget by silently weakening SLO or residency requirements.

Controls: rightsize from measurements; schedule non-prod off where safe; measure NAT/egress; control log retention/cardinality; scale workers using queue signals; configure budget/forecast alerts at 70%, 85%, 100%.
