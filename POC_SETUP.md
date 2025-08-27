# Network Policy POC Setup Guide

## Quick Start for Learning

### 1. Prerequisites
```bash
# Install required tools
aws configure  # Set up AWS credentials
kubectl version --client
eksctl version
```

### 2. Create Cost-Efficient EKS Cluster
```bash
# Create minimal cluster for POC (cost-efficient)
eksctl create cluster \
  --name network-policy-poc \
  --region us-east-1 \
  --nodegroup-name poc-workers \
  --node-type t3.small \
  --nodes 1 \
  --nodes-min 1 \
  --nodes-max 2 \
  --managed \
  --spot

# Enable VPC CNI Network Policy support
kubectl set env daemonset aws-node -n kube-system ENABLE_NETWORK_POLICY=true
kubectl rollout restart daemonset/aws-node -n kube-system

# Wait for network policy support to be ready
kubectl rollout status daemonset/aws-node -n kube-system
```

### 3. Deploy Test Applications
```bash
# Deploy test apps
kubectl apply -f test-apps/

# Verify deployments
kubectl get pods -o wide
```

### 4. Test Default Behavior (No Restrictions)
```bash
# Test connectivity between pods
kubectl exec -it <frontend-pod> -- wget -qO- http://web-app-service:8080
# Should work - no restrictions yet
```

### 5. Apply Network Policies
```bash
# Apply default deny-all policy
kubectl apply -f network-policies/01-default-deny-all.yaml

# Test connectivity again
kubectl exec -it <frontend-pod> -- wget -qO- http://web-app-service:8080
# Should fail - traffic blocked

# Apply specific allow policy
kubectl apply -f network-policies/02-web-app-policy.yaml

# Test again
kubectl exec -it <frontend-pod> -- wget -qO- http://web-app-service:8080
# Should work - specific rule allows it
```

### 6. Verify Network Policy Status
```bash
# Check network policies
kubectl get networkpolicy
kubectl describe networkpolicy default-deny-all

# Check VPC CNI logs
kubectl logs -n kube-system -l k8s-app=aws-node
```

## Key Learning Points

1. **Default Behavior**: Without policies, all traffic is allowed
2. **Deny-All**: First policy should block all traffic
3. **Selective Allow**: Add specific rules to allow required communication
4. **Pod Selectors**: Use labels to target specific pods
5. **Namespace Isolation**: Control cross-namespace communication

## Troubleshooting Commands
```bash
# Check pod labels
kubectl get pods --show-labels

# Test connectivity
kubectl run test-pod --image=busybox --rm -it -- sh

# Check network policy events
kubectl get events --field-selector reason=NetworkPolicyViolation
```