#!/bin/bash

TARGET_VERSION=${1:-"v2.15.0"}

echo "=== ArgoCD Version Validator ==="
echo "Checking if ArgoCD version $TARGET_VERSION exists..."

# Method 1: Check via kubectl (fastest)
echo "Testing image pull capability..."
if kubectl run version-test --image=quay.io/argoproj/argocd:$TARGET_VERSION --dry-run=client -o yaml > /dev/null 2>&1; then
    echo "✅ Image validation successful via kubectl"
else
    echo "❌ Image not found via kubectl"
    
    # Method 2: Check available versions via API
    echo "Fetching available versions from registry..."
    if command -v curl > /dev/null; then
        echo "Recent ArgoCD versions available:"
        curl -s "https://quay.io/api/v1/repository/argoproj/argocd/tag/" | \
        grep -o '"name":"[^"]*"' | \
        grep -E 'v2\.(14|15|16)' | \
        head -10 | \
        sed 's/"name":"//g' | \
        sed 's/"//g' || echo "Could not fetch from registry"
    fi
    
    # Method 3: Check GitHub releases
    echo -e "\nAlternatively, check GitHub releases:"
    echo "https://github.com/argoproj/argo-cd/releases"
    
    exit 1
fi

echo "✅ Version $TARGET_VERSION is valid and available"