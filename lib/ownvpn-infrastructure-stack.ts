import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { getExportName, getResourceName } from './region-config';

export interface OwnvpnInfrastructureStackProps extends cdk.StackProps {
  bucketAccessPolicyArn?: string;
}

export class OwnvpnInfrastructureStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly securityGroup: ec2.SecurityGroup;
  public readonly keyPair: ec2.KeyPair;
  public readonly serverRole: iam.Role;

  constructor(scope: Construct, id: string, props: OwnvpnInfrastructureStackProps = {}) {
    super(scope, id, props);

    // Get the target region from the stack's environment
    const targetRegion = this.region;

    // Create VPC with public subnet for VPN server
    this.vpc = new ec2.Vpc(this, 'WireGuardVPC', {
      maxAzs: 1, // Single AZ for cost optimization
      natGateways: 0, // No NAT gateway needed for public subnet
      subnetConfiguration: [
        {
          cidrMask: 24,
          name: 'Public',
          subnetType: ec2.SubnetType.PUBLIC,
        },
      ],
    });

    // Security group for WireGuard VPN server
    this.securityGroup = new ec2.SecurityGroup(this, 'WireGuardSecurityGroup', {
      vpc: this.vpc,
      description: `Security group for WireGuard VPN server - ${targetRegion}`,
      allowAllOutbound: true,
      securityGroupName: getResourceName('WireGuard', targetRegion) + '-SG',
    });

    // Allow SSH access (port 22) for administration
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'SSH access for server administration'
    );

    // Allow WireGuard VPN traffic (UDP 51820)
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.udp(51820),
      'WireGuard VPN traffic'
    );

    // Create IAM role for EC2 instance
    this.serverRole = new iam.Role(this, 'WireGuardServerRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: `IAM role for WireGuard VPN server - ${targetRegion}`,
    });

    // Add CloudWatch agent permissions for monitoring
    this.serverRole.addManagedPolicy(
      iam.ManagedPolicy.fromAwsManagedPolicyName('CloudWatchAgentServerPolicy')
    );

    // Add S3 bucket access policy if provided
    if (props.bucketAccessPolicyArn) {
      this.serverRole.addManagedPolicy(
        iam.ManagedPolicy.fromManagedPolicyArn(this, 'S3BucketAccessPolicy', props.bucketAccessPolicyArn)
      );
    }

    // Create key pair for SSH access
    this.keyPair = new ec2.KeyPair(this, 'WireGuardKeyPair', {
      keyPairName: getResourceName('wireguard-vpn-key', targetRegion),
      type: ec2.KeyPairType.RSA,
      format: ec2.KeyPairFormat.PEM,
    });

    // Outputs for cross-stack references
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: `VPC ID for WireGuard VPN - ${targetRegion}`,
      exportName: getExportName('VPC-ID', targetRegion),
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: `Security Group ID for WireGuard VPN - ${targetRegion}`,
      exportName: getExportName('SecurityGroup-ID', targetRegion),
    });

    new cdk.CfnOutput(this, 'KeyPairId', {
      value: this.keyPair.keyPairId,
      description: `EC2 Key Pair ID for Systems Manager parameter - ${targetRegion}`,
      exportName: getExportName('KeyPair-ID', targetRegion),
    });

    new cdk.CfnOutput(this, 'KeyPairName', {
      value: this.keyPair.keyPairName,
      description: `EC2 Key Pair Name - ${targetRegion}`,
      exportName: getExportName('KeyPair-Name', targetRegion),
    });

    new cdk.CfnOutput(this, 'ServerRoleArn', {
      value: this.serverRole.roleArn,
      description: `IAM Role ARN for VPN server - ${targetRegion}`,
      exportName: getExportName('ServerRole-ARN', targetRegion),
    });

    new cdk.CfnOutput(this, 'GetPrivateKeyCommand', {
      value: `aws ssm get-parameter --name /ec2/keypair/${this.keyPair.keyPairId} --with-decryption --query Parameter.Value --output text --region ${targetRegion} > ${this.keyPair.keyPairName}.pem && chmod 600 ${this.keyPair.keyPairName}.pem`,
      description: 'Command to retrieve the private key from AWS Systems Manager',
    });
  }
}