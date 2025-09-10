#!/bin/bash

NAMESPACE="argocd"
REVISION=${1:-""}

echo "=== ArgoCD Rollback Procedure ==="

if [ -z "$REVISION" ]; then
    echo "Available revisions:"
    helm history argocd -n $NAMESPACE
    echo ""
    echo "Usage: ./rollback.sh <revision-number>"
    echo "Example: ./rollback.sh 1"
    exit 1
fi

echo "Rolling back to revision: $REVISION"

# Perform rollback
helm rollback argocd $REVISION -n $NAMESPACE

# Monitor rollback
echo "Monitoring rollback progress..."
kubectl rollout status deploy/argocd-server -n $NAMESPACE --timeout=300s
kubectl rollout status deploy/argocd-repo-server -n $NAMESPACE --timeout=300s

# Verify rollback
echo "=== Post-Rollback Verification ==="
helm list -n $NAMESPACE
kubectl get deploy -n $NAMESPACE -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image

echo "=== Rollback Completed ==="