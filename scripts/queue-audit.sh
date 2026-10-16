#!/usr/bin/env bash
# Job accounting for the synthetic Redis queue on kind.
# A job is lost if it was enqueued but is neither done, pending nor in a
# worker's processing list. Exit code 1 if any job is lost.
set -euo pipefail

NS="${NS:-continuity-demo}"
rc() { kubectl -n "$NS" exec deploy/redis -- redis-cli --raw "$@"; }

enqueued=$(rc GET jobs:enqueued); enqueued=${enqueued:-0}
done_unique=$(rc SCARD jobs:done)
completions=$(rc GET jobs:completed); completions=${completions:-0}
duplicates=$(rc GET jobs:duplicates); duplicates=${duplicates:-0}
requeued=$(rc GET jobs:requeued); requeued=${requeued:-0}
released=$(rc GET jobs:released); released=${released:-0}
pending=$(rc LLEN jobs:pending)
processing=0
for key in $(rc KEYS 'jobs:processing:*'); do
  processing=$((processing + $(rc LLEN "$key")))
done
lost=$((enqueued - done_unique - pending - processing))

printf '%s\n' \
  "time=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  "enqueued=$enqueued" \
  "done_unique=$done_unique" \
  "completions=$completions" \
  "duplicates=$duplicates" \
  "pending=$pending" \
  "processing=$processing" \
  "released_on_drain=$released" \
  "requeued_orphans=$requeued" \
  "lost=$lost"

test "$lost" -eq 0
