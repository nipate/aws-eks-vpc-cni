# AWS EKS ArgoCD Upgrade & Network Policy POC

## Repository Structure
```
├── .github/workflows/          # GitHub Actions workflows
├── argocd/                     # ArgoCD deployment and upgrade files
├── eks/                        # EKS cluster deployment files
├── network-policies/           # Network policy YAML files and tests
├── test-apps/                  # Test applications for validation
└── docs/                       # Documentation files
```

## Quick Start

### ArgoCD Upgrade POC
```bash
# Deploy EKS + ArgoCD v2.14.11
cd eks && ./deploy-poc.sh

# Verify current version
./verify-version.sh

# Upgrade to v2.15.0
cd ../argocd && ./upgrade-local.sh v2.15.0 7.10.0
```

### Network Policy POC
```bash
# Follow network policy setup
# See docs/POC_SETUP.md for detailed instructions
```

## Documentation
- [ArgoCD Upgrade POC](docs/ARGOCD_UPGRADE_POC.md) - ArgoCD upgrade procedures
- [Network Policy Learning Guide](docs/LEARNING_GUIDE.md) - Network policy concepts
- [POC Setup](docs/POC_SETUP.md) - Network policy setup instructions
- [Production Checklist](docs/PRODUCTION_CHECKLIST.md) - Production deployment guide

## GitHub Actions
- **deploy-and-upgrade.yml** - Complete EKS + ArgoCD deployment and upgrade
- **argocd-upgrade.yml** - ArgoCD upgrade only workflow