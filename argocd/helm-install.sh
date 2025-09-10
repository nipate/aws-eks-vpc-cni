#!/bin/bash

# Install ArgoCD using Helm
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

# Create namespace
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

# Install ArgoCD with current version
helm install argocd argo/argo-cd \
  --version 7.9.0 \
  --namespace argocd \
  --values values.yaml \
  --wait

# Wait for deployment
kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd

echo "ArgoCD installed successfully!"
echo "Admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo -e "\n\nArgoCD URL:"
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'