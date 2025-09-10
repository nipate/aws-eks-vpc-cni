#!/bin/bash

echo "=== ArgoCD Version Check ==="
echo "Current ArgoCD image:"
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

echo -e "\n\nHelm release info:"
helm list -n argocd

echo -e "\n\nPod status:"
kubectl get pods -n argocd

echo -e "\n\nService status:"
kubectl get svc -n argocd

echo -e "\n\nArgoCD server health:"
kubectl get deployment argocd-server -n argocd -o jsonpath='{.status.conditions[?(@.type=="Available")].status}'