#!/usr/bin/env bash
# Creates a complete hostPath Deployment YAML from the original AI-platform Deployment.
# This script reads your cluster and writes YAML files; it does NOT apply changes.
set -euo pipefail
NS=ns-18948
RS=qwen3-5-122b-a10b-16811793587402-mt-qwen3-5-122b-5454b5858
NODE=mtt-s5000-01
MODEL_DIR=/data01/models/Qwen3.5-122B-A10B
if [ "$#" -gt 0 ]; then MODEL_DIR="$1"; fi
case "$MODEL_DIR" in /*) ;; *) echo "Error: absolute model path required"; exit 1 ;; esac
if [ -n "${DEPLOYMENT:-}" ]; then
  DEPLOY="$DEPLOYMENT"
else
  KIND=$(kubectl get rs "$RS" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].kind}')
  DEPLOY=$(kubectl get rs "$RS" -n "$NS" -o jsonpath='{.metadata.ownerReferences[0].name}')
  if [ "$KIND" != Deployment ] || [ -z "$DEPLOY" ]; then
    echo "Error: RS has no Deployment owner; set DEPLOYMENT=your-deployment-name"
    exit 1
  fi
fi
BACKUP="$DEPLOY.original.backup.yaml"
PATCH="$DEPLOY.hostpath.patch.yaml"
FULL="$DEPLOY.hostpath.full.yaml"
kubectl get deploy "$DEPLOY" -n "$NS" -o yaml > "$BACKUP"
if ! grep -q '8cbd0001-79bc-4a42-8634-cb394fd3d76b' "$BACKUP"; then
  echo "Error: source volume was not found in original deployment"; exit 1
fi
cat > "$PATCH" <<EOF
spec:
  template:
    spec:
      nodeSelector:
        kubernetes.io/hostname: $NODE
      containers:
        - name: mt-musa-s5000-736
          resources:
            requests:
              memory: 512Gi
            limits:
              memory: 512Gi
      volumes:
        - name: 8cbd0001-79bc-4a42-8634-cb394fd3d76b
          \$patch: replace
          hostPath:
            path: $MODEL_DIR
            type: Directory
EOF
kubectl patch --local -f "$BACKUP" --type=strategic --patch-file "$PATCH" -o yaml > "$FULL.raw"
awk '
  /^status:/ { skip=1; next }
  skip && /^[^[:space:]]/ { skip=0 }
  skip { next }
  /^  (creationTimestamp|generation|resourceVersion|uid|selfLink):/ { next }
  {print}
' "$FULL.raw" > "$FULL"
echo "Generated full deployment YAML: $FULL"
echo "Backup: $BACKUP"
echo "Verify $MODEL_DIR/start.sh and config.json exist on $NODE"
echo "Review: kubectl diff -n $NS -f $FULL"
echo "Apply: kubectl apply -n $NS -f $FULL"
echo "WARNING: applying restarts the platform-managed Deployment."
