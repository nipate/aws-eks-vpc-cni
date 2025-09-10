# ArgoCD Upgrade POC

## Overview
This POC demonstrates automated ArgoCD upgrade using GitHub Actions with Helm-based deployment.

## Current Setup
- **Helm Chart**: argo-cd-7.9.0
- **ArgoCD Version**: v2.14.11
- **Namespace**: argocd
- **Deployment Method**: Helm

## Upgrade Target
- **Helm Chart**: argo-cd-7.10.0
- **ArgoCD Version**: v2.15.0

## Files Created
```
argocd/
├── values.yaml           # Current version config
├── values-upgrade.yaml   # Upgrade version config
├── helm-install.sh       # Initial Helm installation
└── upgrade-local.sh      # Local upgrade script

.github/workflows/
├── argocd-upgrade.yml        # GitHub Actions upgrade workflow
└── deploy-and-upgrade.yml    # Complete deployment + upgrade workflow

deploy-poc.sh             # Complete EKS + ArgoCD deployment
verify-version.sh         # Version verification script
```

## Quick Start

### 1. Complete Local Deployment
```bash
# Deploy EKS + ArgoCD v2.14.11
./deploy-poc.sh

# Verify current version
./verify-version.sh

# Upgrade to v2.15.0
./argocd/upgrade-local.sh v2.15.0 7.10.0
```

### 2. GitHub Actions Setup
1. Add AWS credentials to GitHub secrets:
   - `AWS_ACCESS_KEY_ID`
   - `AWS_SECRET_ACCESS_KEY`

2. Update cluster name in workflow:
   ```yaml
   aws eks update-kubeconfig --region us-west-2 --name your-cluster-name
   ```

3. Trigger workflow:
   - Go to Actions tab
   - Select "ArgoCD Upgrade POC"
   - Click "Run workflow"
   - Enter target versions

## Verification Steps
1. Check pod status: `kubectl get pods -n argocd`
2. Verify version: `kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'`
3. Access ArgoCD UI via LoadBalancer URL

## Rollback Plan
```bash
# Rollback using Helm
helm rollback argocd -n argocd

# Or restore from backup
kubectl apply -f argocd-secret-backup.yaml
kubectl apply -f argocd-cm-backup.yaml
```