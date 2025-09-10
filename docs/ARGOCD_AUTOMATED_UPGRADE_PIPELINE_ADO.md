# ArgoCD Automated Upgrade Pipeline - Azure DevOps

## Overview
This document provides a complete automated solution for upgrading ArgoCD using Azure DevOps Pipelines with comprehensive validation, backup, and error handling.

## Architecture
```
Azure DevOps Pipeline
├── Dry Run Validation Stage (with Docker image validation)
├── Manual Approval Gate
├── Actual Upgrade Stage (with S3 backup)
└── Post-Upgrade Verification
```

## Key Features
- ✅ **Docker Image Validation** - Prevents upgrades with non-existent images
- ✅ **Comprehensive Dry Run** - Full validation before actual upgrade
- ✅ **S3 Backup Integration** - Persistent backup storage
- ✅ **Manual Approval Gates** - Safety controls for production
- ✅ **Proper Error Handling** - Stops on failures, provides rollback guidance
- ✅ **Version Verification** - Confirms successful upgrade

---

## File 1: Azure DevOps Pipeline

**Location:** `azure-pipelines/argocd-upgrade-pipeline.yml`

### Purpose
Orchestrates the complete upgrade workflow with safety gates and validation.

### Pipeline Stages
1. **DryRunValidation** - Validates upgrade feasibility
2. **ManualApproval** - Manual approval for production safety
3. **ActualUpgrade** - Executes the upgrade with monitoring

### Usage
```bash
# Navigate to Azure DevOps Pipelines
Pipelines → "ArgoCD Upgrade Pipeline" → "Run pipeline"

# Set Parameters:
targetVersion: v2.14.12
helmChartVersion: 7.6.12
skipDryRun: false
```

### Pipeline Configuration
```yaml
trigger: none

parameters:
- name: targetVersion
  displayName: 'Target ArgoCD Version'
  type: string
  default: 'v2.15.0'
- name: helmChartVersion
  displayName: 'Target Helm Chart Version'
  type: string
  default: '7.6.12'
- name: skipDryRun
  displayName: 'Skip Dry Run'
  type: boolean
  default: false

variables:
  NAMESPACE: 'argocd'
  CLUSTER_NAME: 'vpc-cni-argocd-poc'
  REGION: 'us-east-1'
  S3_BACKUP_BUCKET: 'argocd-upgrade-backups'

pool:
  vmImage: 'ubuntu-latest'

stages:
- stage: DryRunValidation
  displayName: 'Dry Run Validation'
  jobs:
  - job: ValidateUpgrade
    displayName: 'Validate ArgoCD Upgrade'
    steps:
    - checkout: self
    
    - task: AWSShellScript@1
      displayName: 'Configure AWS CLI'
      inputs:
        awsCredentials: 'AWS-Service-Connection'
        regionName: '$(REGION)'
        scriptType: 'inline'
        inlineScript: |
          aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
          
    - task: HelmInstaller@1
      displayName: 'Install Helm'
      inputs:
        helmVersionToInstall: '3.12.0'
        
    - task: Bash@3
      displayName: 'Add ArgoCD Helm Repository'
      inputs:
        targetType: 'inline'
        script: |
          helm repo add argo https://argoproj.github.io/argo-helm
          helm repo update
          
    - task: Bash@3
      displayName: 'Validate ArgoCD Version'
      inputs:
        targetType: 'inline'
        script: |
          cd argocd
          chmod +x validate-version.sh
          ./validate-version.sh ${{ parameters.targetVersion }}
          
    - task: AWSShellScript@1
      displayName: 'Run Comprehensive Dry Run'
      inputs:
        awsCredentials: 'AWS-Service-Connection'
        regionName: '$(REGION)'
        scriptType: 'inline'
        inlineScript: |
          cd argocd
          chmod +x upgrade-comprehensive.sh
          export S3_BACKUP_BUCKET=$(S3_BACKUP_BUCKET)
          
          if ./upgrade-comprehensive.sh ${{ parameters.targetVersion }} ${{ parameters.helmChartVersion }} true > dry-run-output.log 2>&1; then
            echo "##vso[task.setvariable variable=DryRunSuccess;isOutput=true]true"
            echo "✅ Comprehensive dry run validation successful"
          else
            echo "##vso[task.setvariable variable=DryRunSuccess;isOutput=true]false"
            echo "❌ Dry run validation failed"
            cat dry-run-output.log
            exit 1
          fi
      name: DryRunStep
      
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Dry Run Artifacts'
      inputs:
        pathToPublish: 'argocd/dry-run-output.log'
        artifactName: 'dry-run-results'
        
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Backup Artifacts'
      inputs:
        pathToPublish: 'argocd/backup'
        artifactName: 'backup-files'
        condition: succeededOrFailed()

- stage: ManualApproval
  displayName: 'Manual Approval Gate'
  dependsOn: DryRunValidation
  condition: and(succeeded(), eq('${{ parameters.skipDryRun }}', false), eq(dependencies.DryRunValidation.outputs['ValidateUpgrade.DryRunStep.DryRunSuccess'], 'true'))
  jobs:
  - job: waitForValidation
    displayName: 'Wait for Manual Approval'
    pool: server
    timeoutInMinutes: 4320 # 3 days
    steps:
    - task: ManualValidation@0
      displayName: 'Manual Approval Required'
      inputs:
        notifyUsers: |
          $(Build.RequestedForEmail)
        instructions: |
          🔒 Manual approval required before proceeding with ArgoCD upgrade
          
          Dry run validation completed successfully
          Review the dry run artifacts before approving
          
          Target Version: ${{ parameters.targetVersion }}
          Chart Version: ${{ parameters.helmChartVersion }}
          
          Check artifacts for detailed validation results.

- stage: ActualUpgrade
  displayName: 'Execute ArgoCD Upgrade'
  dependsOn: 
  - DryRunValidation
  - ManualApproval
  condition: |
    and(
      in(dependencies.DryRunValidation.result, 'Succeeded'),
      or(
        in(dependencies.ManualApproval.result, 'Succeeded'),
        eq('${{ parameters.skipDryRun }}', true)
      ),
      eq(dependencies.DryRunValidation.outputs['ValidateUpgrade.DryRunStep.DryRunSuccess'], 'true')
    )
  jobs:
  - job: UpgradeArgoCD
    displayName: 'Upgrade ArgoCD'
    steps:
    - checkout: self
    
    - task: AWSShellScript@1
      displayName: 'Configure AWS CLI'
      inputs:
        awsCredentials: 'AWS-Service-Connection'
        regionName: '$(REGION)'
        scriptType: 'inline'
        inlineScript: |
          aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
          
    - task: HelmInstaller@1
      displayName: 'Install Helm'
      inputs:
        helmVersionToInstall: '3.12.0'
        
    - task: Bash@3
      displayName: 'Add ArgoCD Helm Repository'
      inputs:
        targetType: 'inline'
        script: |
          helm repo add argo https://argoproj.github.io/argo-helm
          helm repo update
          
    - task: AWSShellScript@1
      displayName: 'Execute ArgoCD Upgrade'
      inputs:
        awsCredentials: 'AWS-Service-Connection'
        regionName: '$(REGION)'
        scriptType: 'inline'
        inlineScript: |
          cd argocd
          chmod +x upgrade-comprehensive.sh
          export S3_BACKUP_BUCKET=$(S3_BACKUP_BUCKET)
          ./upgrade-comprehensive.sh ${{ parameters.targetVersion }} ${{ parameters.helmChartVersion }} false
          
    - task: AWSShellScript@1
      displayName: 'Post-Upgrade Verification'
      inputs:
        awsCredentials: 'AWS-Service-Connection'
        regionName: '$(REGION)'
        scriptType: 'inline'
        inlineScript: |
          echo "=== Post-Upgrade Verification ==="
          
          # Get current version
          CURRENT_VERSION=$(kubectl get deployment argocd-server -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}')
          echo "Current ArgoCD Version: $CURRENT_VERSION"
          
          # Check pod status
          kubectl get pods -n $(NAMESPACE)
          
          # Verify S3 backup
          aws s3 ls s3://$(S3_BACKUP_BUCKET)/argocd-backups/ --recursive | tail -10
          
          echo "##vso[task.setvariable variable=FinalVersion]$CURRENT_VERSION"
          
    - task: PublishBuildArtifacts@1
      displayName: 'Publish Upgrade Artifacts'
      inputs:
        pathToPublish: 'argocd/backup'
        artifactName: 'upgrade-results'
        
    - task: Bash@3
      displayName: 'Upgrade Summary'
      inputs:
        targetType: 'inline'
        script: |
          echo "## 🚀 ArgoCD Upgrade Results"
          echo "- **Target Version**: ${{ parameters.targetVersion }}"
          echo "- **Chart Version**: ${{ parameters.helmChartVersion }}"
          echo "- **Final Version**: $(FinalVersion)"
          echo "- **Status**: ✅ Upgrade Completed Successfully"
          echo "- **Backup Location**: S3 bucket $(S3_BACKUP_BUCKET)"
```

---

## File 2: Azure DevOps Variable Groups

**Location:** Azure DevOps → Library → Variable Groups

### Create Variable Group: `ArgoCD-Upgrade-Config`
```yaml
Variables:
- NAMESPACE: argocd
- CLUSTER_NAME: vpc-cni-argocd-poc
- REGION: us-east-1
- S3_BACKUP_BUCKET: argocd-upgrade-backups
```

### Create Variable Group: `ArgoCD-Upgrade-Secrets`
```yaml
Variables (Mark as Secret):
- AWS_ACCESS_KEY_ID: [Your AWS Access Key]
- AWS_SECRET_ACCESS_KEY: [Your AWS Secret Key]
```

---

## File 3: Service Connections

### AWS Service Connection
**Name:** `AWS-Service-Connection`
**Type:** AWS for Azure DevOps
**Configuration:**
- Access Key ID: `$(AWS_ACCESS_KEY_ID)`
- Secret Access Key: `$(AWS_SECRET_ACCESS_KEY)`
- Region: `us-east-1`

---

## File 4: Enhanced Pipeline with Environments

**Location:** `azure-pipelines/argocd-upgrade-with-environments.yml`

```yaml
trigger: none

parameters:
- name: targetVersion
  displayName: 'Target ArgoCD Version'
  type: string
  default: 'v2.15.0'
- name: helmChartVersion
  displayName: 'Target Helm Chart Version'
  type: string
  default: '7.6.12'
- name: environment
  displayName: 'Target Environment'
  type: string
  default: 'production'
  values:
  - development
  - staging
  - production

variables:
- group: ArgoCD-Upgrade-Config
- group: ArgoCD-Upgrade-Secrets

pool:
  vmImage: 'ubuntu-latest'

stages:
- stage: DryRunValidation
  displayName: 'Dry Run Validation'
  jobs:
  - job: ValidateUpgrade
    displayName: 'Validate ArgoCD Upgrade'
    steps:
    - template: templates/dry-run-validation.yml
      parameters:
        targetVersion: ${{ parameters.targetVersion }}
        helmChartVersion: ${{ parameters.helmChartVersion }}

- stage: DeployToEnvironment
  displayName: 'Deploy to ${{ parameters.environment }}'
  dependsOn: DryRunValidation
  condition: succeeded()
  jobs:
  - deployment: UpgradeArgoCD
    displayName: 'Upgrade ArgoCD'
    environment: ${{ parameters.environment }}
    strategy:
      runOnce:
        deploy:
          steps:
          - template: templates/argocd-upgrade.yml
            parameters:
              targetVersion: ${{ parameters.targetVersion }}
              helmChartVersion: ${{ parameters.helmChartVersion }}
```

---

## File 5: Pipeline Templates

### Dry Run Validation Template
**Location:** `azure-pipelines/templates/dry-run-validation.yml`

```yaml
parameters:
- name: targetVersion
  type: string
- name: helmChartVersion
  type: string

steps:
- checkout: self

- task: AWSShellScript@1
  displayName: 'Configure AWS and Kubernetes'
  inputs:
    awsCredentials: 'AWS-Service-Connection'
    regionName: '$(REGION)'
    scriptType: 'inline'
    inlineScript: |
      aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
      
- task: HelmInstaller@1
  displayName: 'Install Helm'
  inputs:
    helmVersionToInstall: '3.12.0'
    
- task: Bash@3
  displayName: 'Setup Helm Repository'
  inputs:
    targetType: 'inline'
    script: |
      helm repo add argo https://argoproj.github.io/argo-helm
      helm repo update
      
- task: AWSShellScript@1
  displayName: 'Run Comprehensive Validation'
  inputs:
    awsCredentials: 'AWS-Service-Connection'
    regionName: '$(REGION)'
    scriptType: 'inline'
    inlineScript: |
      cd argocd
      chmod +x validate-version.sh upgrade-comprehensive.sh
      
      # Validate version exists
      ./validate-version.sh ${{ parameters.targetVersion }}
      
      # Run comprehensive dry run
      export S3_BACKUP_BUCKET=$(S3_BACKUP_BUCKET)
      if ./upgrade-comprehensive.sh ${{ parameters.targetVersion }} ${{ parameters.helmChartVersion }} true > dry-run-output.log 2>&1; then
        echo "##vso[task.setvariable variable=ValidationSuccess;isOutput=true]true"
        echo "✅ Validation successful"
      else
        echo "##vso[task.setvariable variable=ValidationSuccess;isOutput=true]false"
        echo "❌ Validation failed"
        cat dry-run-output.log
        exit 1
      fi
  name: ValidationStep
  
- task: PublishBuildArtifacts@1
  displayName: 'Publish Validation Results'
  inputs:
    pathToPublish: 'argocd'
    artifactName: 'validation-results-$(Build.BuildNumber)'
  condition: always()
```

### ArgoCD Upgrade Template
**Location:** `azure-pipelines/templates/argocd-upgrade.yml`

```yaml
parameters:
- name: targetVersion
  type: string
- name: helmChartVersion
  type: string

steps:
- checkout: self

- task: DownloadBuildArtifacts@0
  displayName: 'Download Validation Artifacts'
  inputs:
    buildType: 'current'
    downloadType: 'single'
    artifactName: 'validation-results-$(Build.BuildNumber)'
    downloadPath: '$(System.ArtifactsDirectory)'

- task: AWSShellScript@1
  displayName: 'Configure AWS and Kubernetes'
  inputs:
    awsCredentials: 'AWS-Service-Connection'
    regionName: '$(REGION)'
    scriptType: 'inline'
    inlineScript: |
      aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
      
- task: HelmInstaller@1
  displayName: 'Install Helm'
  inputs:
    helmVersionToInstall: '3.12.0'
    
- task: Bash@3
  displayName: 'Setup Helm Repository'
  inputs:
    targetType: 'inline'
    script: |
      helm repo add argo https://argoproj.github.io/argo-helm
      helm repo update
      
- task: AWSShellScript@1
  displayName: 'Execute ArgoCD Upgrade'
  inputs:
    awsCredentials: 'AWS-Service-Connection'
    regionName: '$(REGION)'
    scriptType: 'inline'
    inlineScript: |
      cd argocd
      chmod +x upgrade-comprehensive.sh
      export S3_BACKUP_BUCKET=$(S3_BACKUP_BUCKET)
      
      echo "Starting ArgoCD upgrade to ${{ parameters.targetVersion }}"
      if ./upgrade-comprehensive.sh ${{ parameters.targetVersion }} ${{ parameters.helmChartVersion }} false; then
        echo "##vso[task.setvariable variable=UpgradeSuccess]true"
        echo "✅ Upgrade completed successfully"
      else
        echo "##vso[task.setvariable variable=UpgradeSuccess]false"
        echo "❌ Upgrade failed"
        exit 1
      fi
      
- task: AWSShellScript@1
  displayName: 'Post-Upgrade Verification'
  condition: eq(variables['UpgradeSuccess'], 'true')
  inputs:
    awsCredentials: 'AWS-Service-Connection'
    regionName: '$(REGION)'
    scriptType: 'inline'
    inlineScript: |
      echo "=== Post-Upgrade Verification ==="
      
      # Verify version
      CURRENT_VERSION=$(kubectl get deployment argocd-server -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}')
      echo "Current Version: $CURRENT_VERSION"
      
      # Check all pods are running
      kubectl get pods -n $(NAMESPACE)
      
      # Verify no failed pods
      FAILED_PODS=$(kubectl get pods -n $(NAMESPACE) --field-selector=status.phase!=Running,status.phase!=Succeeded --no-headers 2>/dev/null | wc -l)
      if [ "$FAILED_PODS" -gt 0 ]; then
        echo "❌ Found failed pods"
        kubectl get pods -n $(NAMESPACE) --field-selector=status.phase!=Running,status.phase!=Succeeded
        exit 1
      fi
      
      # Check S3 backup
      echo "Verifying S3 backup..."
      aws s3 ls s3://$(S3_BACKUP_BUCKET)/argocd-backups/ --recursive | tail -5
      
      echo "##vso[task.setvariable variable=FinalVersion]$CURRENT_VERSION"
      echo "✅ All verifications passed"
      
- task: PublishBuildArtifacts@1
  displayName: 'Publish Upgrade Artifacts'
  inputs:
    pathToPublish: 'argocd/backup'
    artifactName: 'upgrade-artifacts-$(Build.BuildNumber)'
  condition: always()
```

---

## Prerequisites

### 1. Azure DevOps Setup
- Azure DevOps organization and project
- AWS service connection configured
- Variable groups created
- Environments configured (optional)

### 2. AWS Setup
- EKS cluster running
- S3 bucket: `argocd-upgrade-backups`
- IAM user with EKS and S3 permissions

### 3. ArgoCD Installation
- Deployed via Helm in `argocd` namespace
- LoadBalancer service type

---

## Usage Instructions

### 1. Automated Pipeline (Recommended)
```bash
# Navigate to Azure DevOps Pipelines
Pipelines → "ArgoCD Upgrade Pipeline" → "Run pipeline"

# Set Parameters:
Target ArgoCD Version: v2.14.12
Target Helm Chart Version: 7.6.12
Skip Dry Run: false
```

### 2. Environment-Based Deployment
```bash
# Use environment-specific pipeline
Pipelines → "ArgoCD Upgrade with Environments" → "Run pipeline"

# Select Environment: production
# Pipeline will use environment-specific approvals
```

### 3. Local Testing
```bash
# Same as GitHub Actions version
cd argocd
./upgrade-comprehensive.sh v2.14.12 7.6.12 true  # Dry run
./upgrade-comprehensive.sh v2.14.12 7.6.12 false # Actual upgrade
```

---

## Azure DevOps Specific Features

### 1. **Environments**
- Configure approval gates per environment
- Track deployment history
- Environment-specific variable overrides

### 2. **Variable Groups**
- Centralized configuration management
- Secret variable protection
- Environment-specific values

### 3. **Service Connections**
- Secure AWS credential management
- Automatic token refresh
- Audit trail for access

### 4. **Artifacts**
- Automatic artifact publishing
- Retention policies
- Download for troubleshooting

### 5. **Manual Validation Tasks**
- Built-in approval workflows
- Email notifications
- Timeout configurations

---

## Verification Commands
*(Same as GitHub Actions version)*

```bash
# Check ArgoCD version
kubectl get deployment argocd-server -n argocd -o jsonpath='{.spec.template.spec.containers[0].image}'

# Check all pods
kubectl get pods -n argocd

# Check Helm release
helm list -n argocd
helm history argocd -n argocd

# Verify S3 backup
aws s3 ls s3://argocd-upgrade-backups/argocd-backups/ --recursive
```

---

## Rollback Procedure
*(Same as GitHub Actions version)*

### If Upgrade Fails
```bash
# Check rollback options
helm history argocd -n argocd

# Rollback to previous version
helm rollback argocd <revision-number> -n argocd

# Verify rollback
kubectl get pods -n argocd
```

### Create Rollback Pipeline
**Location:** `azure-pipelines/argocd-rollback-pipeline.yml`

```yaml
trigger: none

parameters:
- name: rollbackRevision
  displayName: 'Rollback to Revision'
  type: string
  default: '1'

variables:
- group: ArgoCD-Upgrade-Config

pool:
  vmImage: 'ubuntu-latest'

stages:
- stage: RollbackArgoCD
  displayName: 'Rollback ArgoCD'
  jobs:
  - job: ExecuteRollback
    displayName: 'Execute Rollback'
    steps:
    - task: AWSShellScript@1
      displayName: 'Rollback ArgoCD'
      inputs:
        awsCredentials: 'AWS-Service-Connection'
        regionName: '$(REGION)'
        scriptType: 'inline'
        inlineScript: |
          aws eks update-kubeconfig --region $(REGION) --name $(CLUSTER_NAME)
          
          echo "Rolling back ArgoCD to revision ${{ parameters.rollbackRevision }}"
          helm rollback argocd ${{ parameters.rollbackRevision }} -n $(NAMESPACE)
          
          echo "Verifying rollback..."
          kubectl rollout status deployment/argocd-server -n $(NAMESPACE) --timeout=300s
          
          CURRENT_VERSION=$(kubectl get deployment argocd-server -n $(NAMESPACE) -o jsonpath='{.spec.template.spec.containers[0].image}')
          echo "Current Version after rollback: $CURRENT_VERSION"
```

---

## Best Practices

### 1. **Pipeline Organization**
- Use templates for reusable components
- Separate pipelines for different environments
- Version control all pipeline definitions

### 2. **Security**
- Store secrets in Azure Key Vault
- Use service connections for AWS access
- Implement least privilege access

### 3. **Monitoring**
- Enable pipeline notifications
- Set up alerts for failed deployments
- Monitor artifact retention

### 4. **Approval Gates**
- Configure environment-specific approvals
- Set timeout policies
- Document approval criteria

---

## Troubleshooting

### Common Azure DevOps Issues
- **Service connection failures**: Check AWS credentials and permissions
- **Pipeline timeouts**: Increase timeout values in manual validation tasks
- **Artifact publishing fails**: Check file paths and permissions
- **Variable group access**: Ensure pipeline has access to variable groups

### Pipeline Debugging
```yaml
# Add debug steps to pipeline
- task: Bash@3
  displayName: 'Debug Environment'
  inputs:
    targetType: 'inline'
    script: |
      echo "Current directory: $(pwd)"
      echo "Available files:"
      ls -la
      echo "Environment variables:"
      env | grep -E "(AWS|NAMESPACE|CLUSTER)"
```

---

## Migration from GitHub Actions

### Key Differences
1. **Triggers**: `workflow_dispatch` → `trigger: none` with parameters
2. **Secrets**: GitHub secrets → Azure DevOps variable groups
3. **Artifacts**: GitHub artifacts → Azure DevOps build artifacts
4. **Approvals**: GitHub environments → Azure DevOps manual validation tasks
5. **AWS Auth**: GitHub OIDC → Azure DevOps service connections

### Migration Checklist
- [ ] Create Azure DevOps project
- [ ] Set up AWS service connection
- [ ] Create variable groups
- [ ] Configure environments (optional)
- [ ] Import pipeline YAML files
- [ ] Test dry run functionality
- [ ] Validate approval workflows
- [ ] Update documentation references

This Azure DevOps version provides the same comprehensive ArgoCD upgrade automation with platform-specific optimizations and features.