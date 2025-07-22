import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { getExportName, getResourceName, getVpnPort } from './region-config';

export interface RegionHopInfrastructureStackProps extends cdk.StackProps {
  bucketAccessPolicyArn?: string;
}

export class RegionHopInfrastructureStack extends cdk.Stack {
  public readonly vpc: ec2.Vpc;
  public readonly securityGroup: ec2.SecurityGroup;
  public readonly keyPair: ec2.KeyPair;
  public readonly serverRole: iam.Role;

  constructor(scope: Construct, id: string, props: RegionHopInfrastructureStackProps = {}) {
    super(scope, id, props);

    // Get the target region from the stack's environment
    const targetRegion = this.region;

    // Create VPC with public subnet for VPN server
    this.vpc = new ec2.Vpc(this, 'VPC', {
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

    this.securityGroup = new ec2.SecurityGroup(this, 'VPNServerSecurityGroup', {
      vpc: this.vpc,
      description: `Security group for RegionHop VPN server - ${targetRegion}`,
      allowAllOutbound: true,
      securityGroupName: getResourceName('RegionHop', targetRegion) + '-SG',
    });

    // Allow SSH access (port 22) for administration
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.tcp(22),
      'SSH access for server administration'
    );

    // Allow WireGuard VPN traffic from anywhere on the internet
    // Security Note: WireGuard uses strong cryptographic authentication,
    // making it safe to expose to 0.0.0.0/0. Only authenticated peers can connect.
    const vpnPort = this.getValidatedVpnPort();
    this.securityGroup.addIngressRule(
      ec2.Peer.anyIpv4(),
      ec2.Port.udp(vpnPort),
      `WireGuard VPN traffic on port ${vpnPort}`
    );

    // Add resource tags for better management and cost tracking
    cdk.Tags.of(this.securityGroup).add('Purpose', 'RegionHop-VPN');
    cdk.Tags.of(this.securityGroup).add('Protocol', 'WireGuard');
    cdk.Tags.of(this.securityGroup).add('Port', vpnPort.toString());

    // Create IAM role for EC2 instance
    this.serverRole = new iam.Role(this, 'VPNServerRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      description: `IAM role for RegionHop VPN server - ${targetRegion}`,
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
    this.keyPair = new ec2.KeyPair(this, 'SSHKeyPair', {
      keyPairName: getResourceName('regionhop-vpn-key', targetRegion),
      type: ec2.KeyPairType.RSA,
      format: ec2.KeyPairFormat.PEM,
    });

    // Outputs for cross-stack references
    new cdk.CfnOutput(this, 'VPCId', {
      value: this.vpc.vpcId,
      description: `VPC ID for RegionHop VPN - ${targetRegion}`,
      exportName: getExportName('VPC-ID', targetRegion),
    });

    new cdk.CfnOutput(this, 'SecurityGroupId', {
      value: this.securityGroup.securityGroupId,
      description: `Security Group ID for RegionHop VPN - ${targetRegion}`,
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

  /**
   * Validates and returns the VPN port from configuration
   * @returns The validated VPN port number
   * @throws Error if port is invalid
   */
  private getValidatedVpnPort(): number {
    try {
      const port = getVpnPort();

      // Validate port range (1-65535, avoiding well-known ports below 1024)
      if (!Number.isInteger(port) || port < 1024 || port > 65535) {
        throw new Error(`Invalid VPN port: ${port}. Port must be between 1024-65535`);
      }

      // Additional validation for common WireGuard ports
      if (port !== 51820 && (port < 51800 || port > 51830)) {
        cdk.Annotations.of(this).addWarning(
          `Non-standard WireGuard port ${port} detected. Standard port is 51820.`
        );
      }

      return port;
    } catch (error) {
      // Fallback to standard WireGuard port with warning
      const fallbackPort = 51820;
      cdk.Annotations.of(this).addWarning(
        `Failed to load VPN port configuration: ${error}. Using fallback port ${fallbackPort}`
      );
      return fallbackPort;
    }
  }
}