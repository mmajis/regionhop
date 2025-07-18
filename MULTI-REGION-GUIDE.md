# Multi-Region VPN Management Guide

This guide covers the new multi-region capabilities added to the WireGuard VPN service. You can now deploy and manage VPN servers across multiple AWS regions for improved performance, redundancy, and global access.

## Overview

The VPN service now supports:
- **5 AWS regions**: `eu-central-1`, `us-east-1`, `us-west-2`, `ap-southeast-1`, `ap-northeast-1`
- **Multi-region deployment**: Deploy to multiple regions simultaneously
- **Region-specific management**: Connect, configure, and manage each region independently
- **Cost optimization**: Deploy only to regions you need, destroy when not needed

## Available Scripts

### 1. Enhanced `deploy.sh` - Multi-Region Deployment

#### Basic Usage
```bash
./deploy.sh                              # Deploy to default region (eu-central-1)
./deploy.sh --region us-east-1          # Deploy to specific region
./deploy.sh --regions us-east-1,us-west-2  # Deploy to multiple regions
```

#### Advanced Options
```bash
./deploy.sh --list-regions              # List all available regions
./deploy.sh --status                    # Show deployment status across all regions
./deploy.sh --destroy --region us-east-1   # Destroy specific region
./deploy.sh --destroy --regions us-east-1,us-west-2 --force  # Destroy multiple regions without confirmation
```

### 2. Enhanced `connect.sh` - Region-Specific Connection

#### Basic Usage
```bash
./connect.sh list                       # List all deployed regions
./connect.sh ssh us-east-1             # SSH to specific region
./connect.sh config eu-central-1       # Download client config for region
./connect.sh status us-west-2          # Check VPN status in region
```

#### Client Management
```bash
./connect.sh add-client us-east-1 iphone    # Add client to specific region
./connect.sh add-client eu-central-1 laptop # Add client to different region
```

### 3. New `region-manager.sh` - Comprehensive Region Management

#### Region Information
```bash
./region-manager.sh list               # List all regions with deployment status
./region-manager.sh deployed          # Show only deployed regions
./region-manager.sh status             # Status of all regions
./region-manager.sh status us-east-1   # Status of specific region
```

#### Region Operations
```bash
./region-manager.sh deploy us-east-1   # Deploy to specific region
./region-manager.sh destroy us-east-1  # Destroy specific region
./region-manager.sh bootstrap us-east-1 # Bootstrap CDK for region
./region-manager.sh health             # Health check all deployed regions
```

## Region Configuration

### Available Regions
- **eu-central-1** (Europe - Frankfurt) - DEFAULT
- **us-east-1** (US East - N. Virginia)
- **us-west-2** (US West - Oregon)
- **ap-southeast-1** (Asia Pacific - Singapore)
- **ap-northeast-1** (Asia Pacific - Tokyo)

### Cost Considerations
- Each region incurs approximately **$15/month** in AWS charges
- Deploy only to regions you need to minimize costs
- Use `./deploy.sh --destroy --region <region>` to clean up unused regions

## Workflow Examples

### 1. Global VPN Setup
```bash
# Deploy to multiple regions for global coverage
./deploy.sh --regions eu-central-1,us-east-1,ap-southeast-1

# Check status of all deployments
./deploy.sh --status

# List all deployed regions
./connect.sh list
```

### 2. Add New Region
```bash
# Add a new region to existing deployment
./region-manager.sh deploy us-west-2

# Verify deployment
./region-manager.sh status us-west-2
```

### 3. Client Configuration
```bash
# Get client config for specific region
./connect.sh config us-east-1

# Connect to different region
./connect.sh ssh eu-central-1

# Add client to multiple regions
./connect.sh add-client us-east-1 phone
./connect.sh add-client eu-central-1 phone
```

### 4. Cost Optimization
```bash
# Check which regions are deployed
./region-manager.sh deployed

# Destroy unused regions
./deploy.sh --destroy --region ap-northeast-1

# Health check remaining regions
./region-manager.sh health
```

## File Structure

The multi-region implementation includes:

```
├── deploy.sh                    # Enhanced with multi-region support
├── connect.sh                   # Enhanced with region selection
├── region-manager.sh            # New comprehensive region management
├── scripts/
│   └── region-helpers.sh        # Shared helper functions
├── regions.json                 # Region configuration
└── lib/
    └── region-config.ts         # TypeScript region utilities
```

## Key Features

### 1. Region Validation
- All scripts validate region names against supported regions
- Clear error messages for invalid regions
- Auto-completion friendly region codes

### 2. Stack Naming
- Region-aware stack names: `OwnVPN-{region}-Infrastructure`, `OwnVPN-{region}-Compute`
- Prevents conflicts between region deployments
- Easy identification in AWS Console

### 3. SSH Key Management
- Region-specific SSH keys: `wireguard-vpn-key-{region}.pem`
- Automatic key retrieval from AWS Systems Manager
- Secure key handling per region

### 4. Status Monitoring
- Real-time deployment status across all regions
- Health checks for deployed regions
- VPN server IP tracking per region

### 5. Backward Compatibility
- Original `./deploy.sh` behavior preserved (deploys to default region)
- Existing scripts continue to work
- Gradual migration path for users

## Troubleshooting

### Common Issues

1. **AWS Credentials**
   ```bash
   # Set up AWS credentials
   source ~/bin/aws-majakorpi-iki  # If available
   # or
   aws configure
   ```

2. **Region Not Bootstrapped**
   ```bash
   ./region-manager.sh bootstrap us-east-1
   ```

3. **Stack Status Check**
   ```bash
   ./region-manager.sh status us-east-1
   ```

4. **Clean Up Failed Deployments**
   ```bash
   ./deploy.sh --destroy --region us-east-1 --force
   ```

### Prerequisites
- Node.js v18+
- AWS CLI configured
- AWS CDK installed
- jq (JSON processor)

## Security Notes

- Each region maintains its own VPC and security groups
- SSH keys are region-specific and stored securely in AWS Systems Manager
- Client configurations are region-specific
- No cross-region access by default

## Cost Management

- Monitor AWS costs in CloudWatch
- Use `./region-manager.sh deployed` to track active regions
- Regular cleanup of unused regions
- Consider regional data transfer costs for global deployments

## Migration from Single Region

If you have an existing single-region deployment:

1. **Check current deployment**
   ```bash
   ./deploy.sh --status
   ```

2. **Add new regions**
   ```bash
   ./region-manager.sh deploy us-east-1
   ```

3. **Verify multi-region setup**
   ```bash
   ./connect.sh list
   ```

The new multi-region system is fully compatible with existing deployments and provides a smooth migration path.