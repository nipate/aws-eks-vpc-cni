#!/bin/bash

TARGET_VERSION=${1:-"v2.15.0"}
CHART_VERSION=${2:-"7.10.0"}

echo "Upgrading ArgoCD to version: $TARGET_VERSION"
echo "Using Helm chart version: $CHART_VERSION"

# Update Helm repo
helm repo update

# Backup current config
kubectl get secret argocd-secret -n argocd -o yaml > argocd-secret-backup.yaml
kubectl get configmap argocd-cm -n argocd -o yaml > argocd-cm-backup.yaml

# Update values file
sed -i "s/tag: \".*\"/tag: \"$TARGET_VERSION\"/" values-upgrade.yaml

# Perform upgrade
helm upgrade argocd argo/argo-cd \
  --version $CHART_VERSION \
  --namespace argocd \
  --values argocd/values-upgrade.yaml \
  --wait --timeout=10m

# Verify upgrade
kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
kubectl get pods -n argocd

echo "Upgrade completed!"
echo "New ArgoCD version:"
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'