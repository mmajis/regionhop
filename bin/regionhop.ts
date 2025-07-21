#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { RegionHopInfrastructureStack } from '../lib/regionhop-infrastructure-stack';
import { RegionHopComputeStack } from '../lib/regionhop-compute-stack';
import { RegionHopPersistenceStack } from '../lib/regionhop-persistence-stack';
import { getTargetRegion, getStackName, getExportName } from '../lib/region-config';

const app = new cdk.App();

// Get target region from environment variable or default
const targetRegion = getTargetRegion();

console.log(`Deploying to region: ${targetRegion}`);

// Create the persistence stack first (S3 bucket for state backup)
const persistenceStack = new RegionHopPersistenceStack(app, getStackName('Persistence', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Persistence (S3 State Backup) - ${targetRegion}`,
});

// Create the infrastructure stack (VPC, security group, IAM role, key pair)
const infrastructureStack = new RegionHopInfrastructureStack(app, getStackName('Infrastructure', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Infrastructure (VPC, Security Group, IAM Role, Key Pair) - ${targetRegion}`,
  
  // Pass the S3 bucket access policy ARN from persistence stack
  bucketAccessPolicyArn: cdk.Fn.importValue(getExportName('BucketAccessPolicy-ARN', targetRegion)),
});

// Create the compute stack (EC2 instance, Elastic IP) that depends on infrastructure
const computeStack = new RegionHopComputeStack(app, getStackName('Compute', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Compute Resources (EC2 Instance, Elastic IP) - ${targetRegion}`,
  infrastructureStack: infrastructureStack,
  s3BucketName: cdk.Fn.importValue(getExportName('StateBackupBucket-Name', targetRegion)),
});

// Set up stack dependencies
infrastructureStack.addDependency(persistenceStack);
computeStack.addDependency(infrastructureStack);