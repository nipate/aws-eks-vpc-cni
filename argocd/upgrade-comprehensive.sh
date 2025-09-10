#!/bin/bash

TARGET_VERSION=${1:-"v2.15.0"}
CHART_VERSION=${2:-"7.10.0"}
DRY_RUN=${3:-"false"}

NAMESPACE="argocd"
BACKUP_DIR="backup/$(date +%Y%m%d_%H%M%S)"

echo "=== ArgoCD Comprehensive Upgrade Process ==="
echo "Target Version: $TARGET_VERSION"
echo "Chart Version: $CHART_VERSION"
echo "Dry Run: $DRY_RUN"
echo "Backup Directory: $BACKUP_DIR"

# Create backup directory
mkdir -p $BACKUP_DIR

echo "=== Phase 1: Pre-Upgrade Assessment ==="

# Document current versions
echo "Current versions:"
helm list -n $NAMESPACE
kubectl get deploy -n $NAMESPACE -o custom-columns=NAME:.metadata.name,IMAGE:.spec.template.spec.containers[*].image

# Save current configuration
helm get values argocd -n $NAMESPACE > $BACKUP_DIR/current-values.yaml

# Health check
echo "Pod health:"
kubectl get pods -n $NAMESPACE
kubectl get events -n $NAMESPACE --sort-by='.metadata.creationTimestamp' | tail -10

# Application status
kubectl get applications.argoproj.io -n $NAMESPACE 2>/dev/null || echo "No applications found"
kubectl get applicationsets.argoproj.io -n $NAMESPACE 2>/dev/null || echo "No applicationsets found"

# Resource utilization
echo "Resource usage:"
kubectl top pods -n $NAMESPACE 2>/dev/null || echo "Metrics not available"

echo "=== Phase 2: Backup Critical Components ==="

# ConfigMaps
kubectl get configmap argocd-cm -n $NAMESPACE -o yaml > $BACKUP_DIR/argocd-cm.yaml
kubectl get configmap argocd-rbac-cm -n $NAMESPACE -o yaml > $BACKUP_DIR/argocd-rbac.yaml 2>/dev/null || echo "RBAC CM not found"
kubectl get configmap argocd-ssh-known-hosts-cm -n $NAMESPACE -o yaml > $BACKUP_DIR/ssh-known-hosts.yaml 2>/dev/null || echo "SSH known hosts CM not found"

# Secrets
kubectl get secret -n $NAMESPACE -o yaml > $BACKUP_DIR/secrets.yaml

# Applications
kubectl get applications.argoproj.io -n $NAMESPACE -o yaml > $BACKUP_DIR/applications.yaml 2>/dev/null || echo "No applications to backup"
kubectl get applicationsets.argoproj.io -n $NAMESPACE -o yaml > $BACKUP_DIR/applicationsets.yaml 2>/dev/null || echo "No applicationsets to backup"

echo "=== Phase 3: Pre-Upgrade Preparation ==="

# Update repositories
helm repo update

# Check available versions
echo "Available versions:"
helm search repo argo/argo-cd --versions | head -10

# Compare values
helm show values argo/argo-cd --version $CHART_VERSION > $BACKUP_DIR/new-values.yaml
echo "Values comparison saved to $BACKUP_DIR/"

echo "=== Phase 4: Upgrade Execution ==="

# Update values file
sed -i "s/tag: \".*\"/tag: \"$TARGET_VERSION\"/" values-upgrade.yaml

if [ "$DRY_RUN" = "true" ]; then
    echo "=== DRY RUN MODE - No actual changes will be made ==="
    helm upgrade argocd argo/argo-cd \
        --namespace $NAMESPACE \
        --version $CHART_VERSION \
        --values values-upgrade.yaml \
        --dry-run --debug
    echo "=== DRY RUN COMPLETED ==="
    exit 0
fi

echo "Performing actual upgrade..."
helm upgrade argocd argo/argo-cd \
    --namespace $NAMESPACE \
    --version $CHART_VERSION \
    --values values-upgrade.yaml \
    --wait --timeout=10m

echo "=== Phase 5: Verification Steps ==="

# Check deployments
kubectl rollout status deploy/argocd-server -n $NAMESPACE --timeout=300s
kubectl rollout status deploy/argocd-repo-server -n $NAMESPACE --timeout=300s
kubectl rollout status deploy/argocd-application-controller -n $NAMESPACE --timeout=300s 2>/dev/null || echo "Application controller not found"

# Check services
kubectl get svc -n $NAMESPACE

# Application health
kubectl get applications.argoproj.io -n $NAMESPACE 2>/dev/null || echo "No applications found"

echo "=== Phase 6: Post-Upgrade Documentation ==="

# Record new version
helm list -n $NAMESPACE > $BACKUP_DIR/post-upgrade-version.txt
kubectl get deploy -n $NAMESPACE -o yaml > $BACKUP_DIR/post-upgrade-deployments.yaml

echo "=== Final Health Check ==="
kubectl get all -n $NAMESPACE
kubectl get events -n $NAMESPACE --sort-by='.metadata.creationTimestamp' | tail -5

echo "=== Upgrade Process Completed ==="
echo "New ArgoCD version:"
kubectl get deployment argocd-server -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}'
echo -e "\nBackup location: $BACKUP_DIR"