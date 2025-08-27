# Network Policy Segmentation Learning Guide

## Prerequisites Knowledge
- Basic Kubernetes concepts (pods, services, namespaces)
- AWS EKS fundamentals
- Basic networking concepts (IP, ports, protocols)
- YAML syntax

## Key Concepts to Understand

### 1. Amazon VPC CNI
- Default networking plugin for EKS
- Assigns actual VPC IP addresses to pods
- Supports Network Policies (requires enabling)

### 2. Network Policies
- Kubernetes-native way to control pod-to-pod communication
- Works at Layer 3/4 (IP/Port level)
- Default behavior: All traffic allowed
- Policies are additive (multiple policies = combined rules)

### 3. Policy Types
- **Ingress**: Controls incoming traffic to pods
- **Egress**: Controls outgoing traffic from pods

## Learning Path

### Phase 1: Setup & Understanding
1. Create test EKS cluster
2. Enable VPC CNI Network Policy support
3. Deploy test applications
4. Understand default behavior (no restrictions)

### Phase 2: Basic Policies
1. Implement default deny-all policy
2. Create service-specific allow rules
3. Test connectivity between pods

### Phase 3: Advanced Scenarios
1. Cross-namespace communication
2. External traffic control
3. Port/protocol specific rules

### Phase 4: Production Ready
1. Monitoring and metrics
2. Troubleshooting techniques
3. Best practices implementation