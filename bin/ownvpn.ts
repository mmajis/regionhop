#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { OwnvpnInfrastructureStack } from '../lib/ownvpn-infrastructure-stack';
import { OwnvpnComputeStack } from '../lib/ownvpn-compute-stack';
import { OwnvpnPersistenceStack } from '../lib/ownvpn-persistence-stack';
import { getTargetRegion, getStackName, getRegionInfo, validateRegion, getExportName } from '../lib/region-config';

const app = new cdk.App();

// Get target region from environment variable or default
const targetRegion = getTargetRegion();
validateRegion(targetRegion);

const regionInfo = getRegionInfo(targetRegion);
console.log(`Deploying to region: ${targetRegion} (${regionInfo?.name})`);

// Create the persistence stack first (S3 bucket for state backup)
const persistenceStack = new OwnvpnPersistenceStack(app, getStackName('Persistence', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Persistence (S3 State Backup) - ${regionInfo?.name}`,
});

// Create the infrastructure stack (VPC, security group, IAM role, key pair)
const infrastructureStack = new OwnvpnInfrastructureStack(app, getStackName('Infrastructure', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Infrastructure (VPC, Security Group, IAM Role, Key Pair) - ${regionInfo?.name}`,
  
  // Pass the S3 bucket access policy ARN from persistence stack
  bucketAccessPolicyArn: cdk.Fn.importValue(getExportName('BucketAccessPolicy-ARN', targetRegion)),
});

// Create the compute stack (EC2 instance, Elastic IP) that depends on infrastructure
const computeStack = new OwnvpnComputeStack(app, getStackName('Compute', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Compute Resources (EC2 Instance, Elastic IP) - ${regionInfo?.name}`,
  infrastructureStack: infrastructureStack,
});

// Set up stack dependencies
infrastructureStack.addDependency(persistenceStack);
computeStack.addDependency(infrastructureStack);