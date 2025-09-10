# ArgoCD Upgrade Scripts

## Available Scripts

### 1. Comprehensive Upgrade (`upgrade-comprehensive.sh`)
Full production-ready upgrade with all phases:
```bash
# Dry run (recommended first)
./upgrade-comprehensive.sh v2.15.0 7.10.0 true

# Actual upgrade
./upgrade-comprehensive.sh v2.15.0 7.10.0 false
```

### 2. Simple Upgrade (`upgrade-local.sh`)
Basic upgrade for quick testing:
```bash
./upgrade-local.sh v2.15.0 7.10.0
```

### 3. Rollback (`rollback.sh`)
Emergency rollback procedure:
```bash
# Check available revisions
./rollback.sh

# Rollback to specific revision
./rollback.sh 1
```

## DevOps Workflow

### 1. Feature Branch Testing
```bash
git checkout -b feature/argocd-upgrade-v2.15.0

# Test with dry run
./upgrade-comprehensive.sh v2.15.0 7.10.0 true

git add . && git commit -m "feat: ArgoCD upgrade to v2.15.0"
git push origin feature/argocd-upgrade-v2.15.0
```

### 2. GitHub Actions Pipeline
- Use `argocd-comprehensive-upgrade.yml` workflow
- Set `dry_run: true` for testing
- Set `dry_run: false` for actual upgrade

### 3. Production Deployment
- Merge PR to main branch
- Run pipeline with `environment: production`
- Monitor upgrade process
- Keep backup artifacts for rollback

## Upgrade Phases

1. **Pre-Upgrade Assessment** - Version documentation, health checks
2. **Backup Critical Components** - ConfigMaps, secrets, applications
3. **Pre-Upgrade Preparation** - Repository updates, value comparisons
4. **Upgrade Execution** - Dry run option, actual upgrade
5. **Verification Steps** - Component health, service verification
6. **Post-Upgrade Tasks** - Documentation, final health check