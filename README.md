# AWS EKS VPC CNI Network Policy Segmentation POC

## Overview
This repository contains Network Policy implementations for Amazon EKS using VPC CNI to enhance security posture and control pod-to-pod communication.

## Repository Structure
```
├── network-policies/          # Production-ready network policy YAML files
├── test-apps/                # Test applications for POC validation
├── LEARNING_GUIDE.md         # Step-by-step learning path
├── POC_SETUP.md             # Quick POC setup instructions
└── PRODUCTION_CHECKLIST.md  # Production implementation guide
```

## Quick Start
1. Follow [POC_SETUP.md](POC_SETUP.md) for hands-on learning
2. Review [LEARNING_GUIDE.md](LEARNING_GUIDE.md) for concepts
3. Use [PRODUCTION_CHECKLIST.md](PRODUCTION_CHECKLIST.md) for customer implementation

## Network Policies Included
- **Default Deny-All**: Blocks all traffic by default
- **Service-Specific Rules**: Allows required service communication
- **Cross-Namespace Policies**: Controls inter-namespace traffic

## Key Features
- VPC CNI compatibility verified
- IAM permissions documented
- Metrics collection enabled
- Production-ready templates
- Comprehensive testing approach

## Deliverables
All network policy YAML files are production-ready and can be committed to Azure DevOps master branch for customer deployment.