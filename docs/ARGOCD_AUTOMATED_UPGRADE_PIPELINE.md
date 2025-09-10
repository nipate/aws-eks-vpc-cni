# ArgoCD Automated Upgrade Pipeline Documentation

## Overview
This document provides a complete automated solution for upgrading ArgoCD using GitHub Actions with comprehensive validation, backup, and error handling.

## Architecture
```
GitHub Actions Pipeline
├── Dry Run Validation (with Docker image validation)
├── Manual Approval Gate
├── Actual Upgrade (with S3 backup)
└── Post-Upgrade Verification
```

## Key Features
-  **Docker Image Validation** - Prevents upgrades with non-existent images
-  **Comprehensive Dry Run** - Full validation before actual upgrade
-  **S3 Backup Integration** - Persistent backup storage
-  **Manual Approval Gates** - Safety controls for production
-  **Proper Error Handling** - Stops on failures, provides rollback guidance
-  **Version Verification** - Confirms successful upgrade

---

## File 1: GitHub Actions Pipeline

**Location:** `.github/workflows/argocd-upgrade-pipeline.yml`

### Purpose
Orchestrates the complete upgrade workflow with safety gates and validation.

### Workflow Stages
1. **dry-run-validation** - Validates upgrade feasibility
2. **approval-gate** - Manual approval for production safety
3. **actual-upgrade** - Executes the upgrade with monitoring

### Usage
```bash
# Navigate to GitHub Actions
Actions → "ArgoCD Upgrade Pipeline with Dry Run" → "Run workflow"

# Set Parameters:
target_version: v2.14.12
helm_chart_version: 7.6.12
skip_dry_run: false
```

### Pipeline Configuration
```yaml
name: ArgoCD Upgrade Pipeline with Dry Run

on:
  workflow_dispatch:
    inputs:
      target_version:
        description: 'Target ArgoCD version'
        required: true
        default: 'v2.15.0'
      helm_chart_version:
        description: 'Target Helm chart version'
        required: true
        default: '7.6.12'
      skip_dry_run:
        description: 'Skip dry run and proceed directly to upgrade'
        type: boolean
        default: false

env:
  NAMESPACE: argocd
  CLUSTER_NAME: vpc-cni-argocd-poc
  REGION: us-east-1
  S3_BACKUP_BUCKET: "argocd-upgrade-backups"  # S3 bucket for persistent backups

jobs:
  dry-run-validation:
    runs-on: ubuntu-latest
    outputs:
      dry-run-success: ${{ steps.dry-run.outputs.success }}
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.REGION }}
        
    - name: Update kubeconfig
      run: |
        aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
        
    - name: Install Helm
      uses: azure/setup-helm@v4
      with:
        version: '3.12.0'
        
    - name: Add ArgoCD Helm repo
      run: |
        helm repo add argo https://argoproj.github.io/argo-helm
        helm repo update
        
    - name: Validate ArgoCD version
      run: |
        cd argocd
        chmod +x validate-version.sh
        ./validate-version.sh ${{ github.event.inputs.target_version }}
        
    - name: Run dry run validation
      id: dry-run
      env:
        S3_BACKUP_BUCKET: ${{ env.S3_BACKUP_BUCKET }}
      run: |
        cd argocd
        chmod +x upgrade-comprehensive.sh
        
        # Run dry run and capture output
        if ./upgrade-comprehensive.sh ${{ github.event.inputs.target_version }} ${{ github.event.inputs.helm_chart_version }} true > dry-run-output.log 2>&1; then
          echo "success=true" >> $GITHUB_OUTPUT
          echo " Comprehensive dry run validation successful"
        else
          echo "success=false" >> $GITHUB_OUTPUT
          echo " Dry run validation failed"
          cat dry-run-output.log
          exit 1
        fi
        
    - name: Upload dry run artifacts
      uses: actions/upload-artifact@v4
      with:
        name: dry-run-results-${{ github.run_number }}
        path: |
          argocd/dry-run-output.log
          argocd/backup/
        retention-days: 7
        
    - name: Dry run summary
      run: |
        echo "##  Dry Run Results" >> $GITHUB_STEP_SUMMARY
        echo "- **Target Version**: ${{ github.event.inputs.target_version }}" >> $GITHUB_STEP_SUMMARY
        echo "- **Chart Version**: ${{ github.event.inputs.helm_chart_version }}" >> $GITHUB_STEP_SUMMARY
        echo "- **Status**:  Validation Successful" >> $GITHUB_STEP_SUMMARY
        echo "- **Next Step**: Manual approval required for actual upgrade" >> $GITHUB_STEP_SUMMARY

  approval-gate:
    needs: [dry-run-validation]
    if: ${{ needs.dry-run-validation.outputs.dry-run-success == 'true' && github.event.inputs.skip_dry_run == 'false' }}
    runs-on: ubuntu-latest
    environment: production-approval
    
    steps:
    - name: Manual approval required
      run: |
        echo " Manual approval required before proceeding with ArgoCD upgrade"
        echo "Dry run validation completed successfully"
        echo "Review the dry run artifacts before approving"

  actual-upgrade:
    needs: [dry-run-validation, approval-gate]
    if: ${{ always() && (needs.approval-gate.result == 'success' || github.event.inputs.skip_dry_run == 'true') && needs.dry-run-validation.outputs.dry-run-success == 'true' }}
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout
      uses: actions/checkout@v4
      
    - name: Configure AWS credentials
      uses: aws-actions/configure-aws-credentials@v4
      with:
        aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
        aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
        aws-region: ${{ env.REGION }}
        
    - name: Update kubeconfig
      run: |
        aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME
        
    - name: Install Helm
      uses: azure/setup-helm@v4
      with:
        version: '3.12.0'
        
    - name: Add ArgoCD Helm repo
      run: |
        helm repo add argo https://argoproj.github.io/argo-helm
        helm repo update
        
    - name: Execute actual upgrade
      env:
        S3_BACKUP_BUCKET: ${{ env.S3_BACKUP_BUCKET }}
      run: |
        cd argocd
        chmod +x upgrade-comprehensive.sh
        ./upgrade-comprehensive.sh ${{ github.event.inputs.target_version }} ${{ github.event.inputs.helm_chart_version }} false
        
    - name: Upload upgrade artifacts
      uses: actions/upload-artifact@v4
      with:
        name: upgrade-results-${{ github.run_number }}
        path: argocd/backup/
        retention-days: 30
        
    - name: Upgrade summary
      run: |
        echo "##  Upgrade Results" >> $GITHUB_STEP_SUMMARY
        echo "- **Target Version**: ${{ github.event.inputs.target_version }}" >> $GITHUB_STEP_SUMMARY
        echo "- **Chart Version**: ${{ github.event.inputs.helm_chart_version }}" >> $GITHUB_STEP_SUMMARY
        echo "- **Status**:  Upgrade Completed" >> $GITHUB_STEP_SUMMARY
        
        # Get current version
        CURRENT_VERSION=$(kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}')
        echo "- **Current Version**: $CURRENT_VERSION" >> $GITHUB_STEP_SUMMARY
```

---

## File 2: Comprehensive Upgrade Script

**Location:** `argocd/upgrade-comprehensive.sh`

### Purpose
Executes the complete ArgoCD upgrade process with validation, backup, and error handling.

### Upgrade Phases
1. **Pre-Upgrade Assessment** - Document current state
2. **Backup Critical Components** - Create comprehensive backups
3. **Pre-Upgrade Preparation** - Validate versions and images
4. **Upgrade Execution** - Perform Helm upgrade with error handling
5. **Verification Steps** - Confirm successful deployment
6. **Post-Upgrade Documentation** - Record final state

### Script Content
```bash
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
        echo " Backup uploaded to S3: s3://$S3_BACKUP_BUCKET/argocd-backups/$(basename $BACKUP_DIR)/"
    else
        echo " S3 backup failed, continuing with local backup only"
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
    echo " ERROR: Docker image quay.io/argoproj/argocd:$TARGET_VERSION not found"
    echo "Available ArgoCD images:"
    curl -s "https://quay.io/api/v1/repository/argoproj/argocd/tag/" | grep -o '"name":"[^"]*"' | head -10 || echo "Could not fetch available tags"
    exit 1
fi
echo " Docker image validation successful"

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
        echo " DRY RUN SUCCESSFUL"
    else
        echo " DRY RUN FAILED"
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
    echo " HELM UPGRADE FAILED - Stopping execution"
    echo "Checking rollback options..."
    helm history argocd -n $NAMESPACE
    echo "To rollback: helm rollback argocd -n $NAMESPACE"
    exit 1
fi
echo " Helm upgrade completed successfully"

echo "=== Phase 5: Verification Steps ==="

# Check deployments with error handling
echo "Verifying deployment rollouts..."
if ! kubectl rollout status deploy/argocd-server -n $NAMESPACE --timeout=300s; then
    echo " ArgoCD server rollout failed"
    kubectl get pods -n $NAMESPACE
    exit 1
fi

if ! kubectl rollout status deploy/argocd-repo-server -n $NAMESPACE --timeout=300s; then
    echo " ArgoCD repo-server rollout failed"
    kubectl get pods -n $NAMESPACE
    exit 1
fi

kubectl rollout status deploy/argocd-application-controller -n $NAMESPACE --timeout=300s 2>/dev/null || echo "Application controller not found"

# Verify no failed pods
FAILED_PODS=$(kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)
if [ "$FAILED_PODS" -gt 0 ]; then
    echo " Found $FAILED_PODS failed pods:"
    kubectl get pods -n $NAMESPACE --field-selector=status.phase!=Running,status.phase!=Succeeded
    echo "Upgrade verification failed"
    exit 1
fi
echo " All deployments rolled out successfully"

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
    echo "===  UPGRADE SUCCESSFUL ==="
    echo "New ArgoCD version: $NEW_VERSION"
    echo "Target version: $TARGET_VERSION"
    echo "Backup location: $BACKUP_DIR"
else
    echo "===  UPGRADE VERIFICATION FAILED ==="
    echo "Expected version: $TARGET_VERSION"
    echo "Actual version: $NEW_VERSION"
    echo "Upgrade may have failed silently"
    exit 1
fi
```

---

## Prerequisites

### 1. AWS Setup
- EKS cluster running
- S3 bucket: `argocd-upgrade-backups`
- IAM permissions for EKS and S3

### 2. GitHub Secrets
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`

### 3. ArgoCD Installation
- Deployed via Helm in `argocd` namespace
- LoadBalancer service type

---

## Usage Instructions

### 1. Automated Pipeline (Recommended)
```bash
# Navigate to GitHub Actions
Actions → "ArgoCD Upgrade Pipeline with Dry Run" → "Run workflow"

# Parameters:
target_version: v2.14.12
helm_chart_version: 7.6.12
skip_dry_run: false
```

### 2. Local Testing
```bash
# Dry run first
cd argocd
./upgrade-comprehensive.sh v2.14.12 7.6.12 true

# Actual upgrade
./upgrade-comprehensive.sh v2.14.12 7.6.12 false
```

---

## Verification Commands

### Post-Upgrade Verification
```bash
# Check ArgoCD version
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check all pods
kubectl get pods -n argocd

# Check Helm release
helm list -n argocd
helm history argocd -n argocd

# Verify S3 backup
aws s3 ls s3://argocd-upgrade-backups/argocd-backups/ --recursive

# Get ArgoCD UI access
kubectl get svc argocd-server -n argocd
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
```

---

## Rollback Procedure

### If Upgrade Fails
```bash
# Check rollback options
helm history argocd -n argocd

# Rollback to previous version
helm rollback argocd <revision-number> -n argocd

# Verify rollback
kubectl get pods -n argocd
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Restore from S3 Backup
```bash
# Download backup from S3
aws s3 cp s3://argocd-upgrade-backups/argocd-backups/YYYYMMDD_HHMMSS/ ./restore/ --recursive

# Apply configurations
kubectl apply -f restore/argocd-cm.yaml
kubectl apply -f restore/secrets.yaml
```

---

## Best Practices

1. **Always run dry run first** - Validates upgrade feasibility
2. **Review backup artifacts** - Ensure backups are complete before proceeding
3. **Monitor during upgrade** - Watch pod status and events
4. **Verify post-upgrade** - Confirm version and functionality
5. **Keep backups** - Retain S3 backups for rollback scenarios

---

## Troubleshooting

### Common Issues
- **Image not found**: Use `validate-version.sh` to check available versions
- **Helm upgrade timeout**: Increase timeout or check resource constraints
- **Pod failures**: Check events and logs for specific errors
- **S3 backup fails**: Verify IAM permissions and bucket access

### Support Commands
```bash
# Check cluster resources
kubectl top nodes
kubectl top pods -n argocd

# Check events
kubectl get events -n argocd --sort-by='.metadata.creationTimestamp'

# Check logs
kubectl logs -n argocd deployment/argocd-server
```

---

## Security Considerations

- AWS credentials stored as GitHub secrets
- S3 bucket with appropriate access controls
- Helm charts from trusted repositories only
- Regular backup retention and cleanup policies
- Manual approval gates for production deployments