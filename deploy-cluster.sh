#!/bin/bash

echo "Deploying EKS cluster for VPC CNI + ArgoCD POC..."

# Create EKS cluster
eksctl create cluster -f eks-cluster.yaml

# Verify cluster
kubectl get nodes

# Enable network policy support
kubectl set env daemonset aws-node -n kube-system ENABLE_NETWORK_POLICY=true

echo "EKS cluster ready for VPC CNI network policies and ArgoCD!"
echo "Next step: Run ./argocd/setup.sh"