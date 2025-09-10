#!/bin/bash

# Install ArgoCD using Helm (recommended for upgrades)
echo "Installing ArgoCD using Helm..."
./argocd/helm-install.sh

# Apply network policies application
echo "Applying network policies application..."
kubectl apply -f argocd/application.yaml

echo "Setup complete! Use ARGOCD_UPGRADE_POC.md for upgrade procedures."