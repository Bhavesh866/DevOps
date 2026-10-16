#!/usr/bin/env bash
# Start a k6 Job inside the cluster. Usage:
#   PROFILE=steady RATE=150 DURATION=4m bash scripts/run-k6.sh <job-name>
# Then: kubectl -n continuity-demo wait --for=condition=complete job/<job-name>
set -euo pipefail

NAME="${1:-k6}"
NS=continuity-demo
kubectl -n "$NS" create configmap k6-script --from-file=tests/load/k6-api.js \
  --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$NS" delete job "$NAME" --ignore-not-found >/dev/null

kubectl apply -f - >/dev/null <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: $NAME
  namespace: $NS
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: k6
    spec:
      restartPolicy: Never
      securityContext:
        runAsNonRoot: true
        runAsUser: 12345
        seccompProfile:
          type: RuntimeDefault
      containers:
        - name: k6
          image: grafana/k6:0.55.0
          args: ["run", "--quiet", "/scripts/k6-api.js"]
          env:
            - {name: PROFILE, value: "${PROFILE:-steady}"}
            - {name: RATE, value: "${RATE:-150}"}
            - {name: DURATION, value: "${DURATION:-5m}"}
          resources:
            requests: {cpu: "1", memory: 256Mi}
            limits: {cpu: "4", memory: 2Gi}
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
          volumeMounts:
            - {name: script, mountPath: /scripts}
      volumes:
        - name: script
          configMap:
            name: k6-script
EOF
echo "k6 job $NAME started (profile=${PROFILE:-steady})"
