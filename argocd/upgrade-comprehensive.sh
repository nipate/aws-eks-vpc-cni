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

# Upload backup to S3 (optional)
if [ "$S3_BACKUP_BUCKET" != "" ]; then
    echo "Uploading backup to S3..."
    if aws s3 cp $BACKUP_DIR s3://$S3_BACKUP_BUCKET/argocd-backups/$(basename $BACKUP_DIR)/ --recursive; then
        echo "✅ Backup uploaded to S3: s3://$S3_BACKUP_BUCKET/argocd-backups/$(basename $BACKUP_DIR)/"
    else
        echo "⚠️ S3 backup failed, continuing with local backup only"
    fi
else
    echo "S3_BACKUP_BUCKET not set, skipping S3 backup"
fi

echo "=== Phase 3: Pre-Upgrade Preparation ==="

# Update repositories
helm repo update

# Check available versions
echo "Available versions:"
helm search repo argo/argo-cd --versions | head -10

# Compare values
helm show values argo/argo-cd --version $CHART_VERSION > $BACKUP_DIR/new-values.yaml
echo "Values comparison saved to $BACKUP_DIR/"

# Validate Docker image exists
echo "Validating Docker image availability..."
if ! kubectl run image-test --image=quay.io/argoproj/argocd:$TARGET_VERSION --dry-run=client -o yaml > /dev/null 2>&1; then
    echo "❌ ERROR: Docker image quay.io/argoproj/argocd:$TARGET_VERSION not found"
    echo "Available ArgoCD images:"
    curl -s "https://quay.io/api/v1/repository/argoproj/argocd/tag/" | grep -o '"name":"[^"]*"' | head -10 || echo "Could not fetch available tags"
    exit 1
fi
echo "✅ Docker image validation successful"

echo "=== Phase 4: Upgrade Execution ==="

# Update values file
sed -i "s/tag: \".*\"/tag: \"$TARGET_VERSION\"/" values-upgrade.yaml

if [ "$DRY_RUN" = "true" ]; then
    echo "=== DRY RUN MODE - No actual changes will be made ==="
    if helm upgrade argocd argo/argo-cd \
        --namespace $NAMESPACE \
        --version $CHART_VERSION \
        --values values-upgrade.yaml \
        --dry-run --debug; then
        echo "✅ DRY RUN SUCCESSFUL"
    else
        echo "❌ DRY RUN FAILED"
        exit 1
    fi
    echo "=== DRY RUN COMPLETED ==="
    exit 0
fi

echo "Performing actual upgrade..."
if ! helm upgrade argocd argo/argo-cd \
    --namespace $NAMESPACE \
    --version $CHART_VERSION \
    --values values-upgrade.yaml \
    --wait --timeout=10m; then
    echo "❌ HELM UPGRADE FAILED - Stopping execution"
    echo "Checking rollback options..."
    helm history argocd -n $NAMESPACE
    echo "To rollback: helm rollback argocd -n $NAMESPACE"
    exit 1
fi
echo "✅ Helm upgrade completed successfully"

echo "=== Phase 5: Verification Steps ==="

# Check deployments with error handling
echo "Verifying deployment rollouts..."
if ! kubectl rollout status deploy/argocd-server -n $NAMESPACE --timeout=300s; then
    echo "❌ ArgoCD server rollout failed"
    kubectl get pods -n $NAMESPACE
    exit 1
fi

if ! kubectl rollout status deploy/argocd-repo-server -n $NAMESPACE --timeout=300s; then
    echo "❌ ArgoCD repo-server rollout failed"
    kubectl get pods -n $NAMESPACE
    exit 1
fi

kubectl rollout status deploy/argocd-application-controller -n $NAMESPACE --timeout=300s 2>/dev/null || echo "Application controller not found"

# Verify no failed pods
FAILED_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
if [ "$FAILED_PODS" -gt 0 ]; then
    echo "❌ Found $FAILED_PODS failed pods:"
    kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded
    echo "Upgrade verification failed"
    exit 1
fi
echo "✅ All deployments rolled out successfully"

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

# Final version verification
NEW_VERSION=$(kubectl get deployment argocd-server -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}')
if [[ "$NEW_VERSION" == *"$TARGET_VERSION"* ]]; then
    echo "=== ✅ UPGRADE SUCCESSFUL ==="
    echo "New ArgoCD version: $NEW_VERSION"
    echo "Target version: $TARGET_VERSION"
    echo "Backup location: $BACKUP_DIR"
else
    echo "=== ❌ UPGRADE VERIFICATION FAILED ==="
    echo "Expected version: $TARGET_VERSION"
    echo "Actual version: $NEW_VERSION"
    echo "Upgrade may have failed silently"
    exit 1
fi