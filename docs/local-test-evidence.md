# Local test evidence (superseded)

The first local tests (2026-10-16 morning: synthetic v1 → v2 rolling update and
`kubectl rollout undo` on a plain Deployment, pre-remediation image, no raw logs kept) are
superseded by reproducible scripts with captured logs. See `docs/evidence/README.md` for every
current result, what each one shows and what it does not show, and
`bash scripts/evidence/run-all.sh` to regenerate them.
