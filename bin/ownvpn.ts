#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { OwnvpnInfrastructureStack } from '../lib/ownvpn-infrastructure-stack';
import { OwnvpnComputeStack } from '../lib/ownvpn-compute-stack';
import { getTargetRegion, getStackName, getRegionInfo, validateRegion } from '../lib/region-config';

const app = new cdk.App();

// Get target region from environment variable or default
const targetRegion = getTargetRegion();
validateRegion(targetRegion);

const regionInfo = getRegionInfo(targetRegion);
console.log(`Deploying to region: ${targetRegion} (${regionInfo?.name})`);

// Create the infrastructure stack first (VPC, security group, IAM role, key pair)
const infrastructureStack = new OwnvpnInfrastructureStack(app, getStackName('Infrastructure', targetRegion), {
  // Deploy to the target region
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: targetRegion
  },
  
  description: `WireGuard VPN Service - Infrastructure (VPC, Security Group, IAM Role, Key Pair) - ${regionInfo?.name}`,
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

// Ensure compute stack depends on infrastructure stack
computeStack.addDependency(infrastructureStack);