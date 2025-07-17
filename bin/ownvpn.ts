#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { OwnvpnInfrastructureStack } from '../lib/ownvpn-infrastructure-stack';
import { OwnvpnComputeStack } from '../lib/ownvpn-compute-stack';

const app = new cdk.App();

// Create the infrastructure stack first (VPC, security group, IAM role, key pair)
const infrastructureStack = new OwnvpnInfrastructureStack(app, 'OwnvpnInfrastructureStack', {
  // Deploy to EU Frankfurt (eu-central-1) for European privacy and access
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'eu-central-1'
  },
  
  description: 'WireGuard VPN Service - Infrastructure (VPC, Security Group, IAM Role, Key Pair)',
});

// Create the compute stack (EC2 instance, Elastic IP) that depends on infrastructure
const computeStack = new OwnvpnComputeStack(app, 'OwnvpnComputeStack', {
  // Deploy to EU Frankfurt (eu-central-1) for European privacy and access
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT,
    region: 'eu-central-1'
  },
  
  description: 'WireGuard VPN Service - Compute Resources (EC2 Instance, Elastic IP)',
  infrastructureStack: infrastructureStack,
});

// Ensure compute stack depends on infrastructure stack
computeStack.addDependency(infrastructureStack);