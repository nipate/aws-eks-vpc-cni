#!/bin/bash

CLUSTER_NAME="argocd-upgrade-poc"
REGION="us-east-1"

echo "=== Deploying EKS Cluster ==="
# Update cluster name in config
sed -i "s/name: .*/name: $CLUSTER_NAME/" eks-cluster.yaml

# Deploy EKS
kubectl apply -f eks-cluster.yaml

# Wait for cluster
echo "Waiting for EKS cluster to be ready..."
aws eks wait cluster-active --name $CLUSTER_NAME --region $REGION

# Update kubeconfig
aws eks update-kubeconfig --region $REGION --name $CLUSTER_NAME

# Wait for nodes
kubectl wait --for=condition=ready nodes --all --timeout=600s

echo "=== Deploying ArgoCD v2.14.11 ==="
# Install ArgoCD
../argocd/helm-install.sh

echo "=== Verifying Current Version ==="
echo "Current ArgoCD version:"
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

echo -e "\n\nPods status:"
kubectl get pods -n argocd

echo -e "\n\nArgoCD access info:"
echo "Admin password:"
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
echo -e "\n\nArgoCD URL:"
kubectl get svc argocd-server -n argocd -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

echo -e "\n\n=== Deployment Complete ==="
echo "To upgrade ArgoCD, run: ./argocd/upgrade-local.sh v2.15.0 7.10.0"