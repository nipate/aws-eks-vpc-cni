#!/bin/bash
# Daily cleanup script to delete all resources

echo "Cleaning up EKS cluster and resources..."

# Delete the cluster (this removes all associated resources)
eksctl delete cluster --name network-policy-poc --region us-east-1

echo "Cleanup complete. All resources deleted."
echo "Cost for today: Approximately $2-5 depending on usage time"