import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as autoscaling from 'aws-cdk-lib/aws-autoscaling';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as lambdaNodejs from 'aws-cdk-lib/aws-lambda-nodejs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import { RegionHopInfrastructureStack } from './regionhop-infrastructure-stack';
import { getVpnSubnet, getVpnPort, getDomain, getHostedZoneId, getDnsRecordTtl, getVpnSubdomain, isDnsManagementEnabled } from './region-config';

export interface RegionHopComputeStackProps extends cdk.StackProps {
  infrastructureStack: RegionHopInfrastructureStack;
  s3BucketName: string;
}

export class RegionHopComputeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: RegionHopComputeStackProps) {
    super(scope, id, props);

    const { infrastructureStack, s3BucketName } = props;

    // Get the target region from the stack's environment
    const targetRegion = this.region;

    // Use Ubuntu 24.04 LTS AMI (works across all regions)
    const ubuntuAmi = ec2.MachineImage.fromSsmParameter(
      '/aws/service/canonical/ubuntu/server/24.04/stable/current/arm64/hvm/ebs-gp3/ami-id',
      {
        os: ec2.OperatingSystemType.LINUX,
      }
    );

    // Get VPN configuration from region config
    const vpnSubnet = getVpnSubnet();
    const vpnPort = getVpnPort();
    const vpnServerIP = vpnSubnet.replace('/24', '').replace(/\d+$/, '1'); // 10.8.0.1
    const vpnSubnetBase = vpnSubnet.replace('/24', '').replace(/\.\d+$/, '.'); // 10.8.0.

    // Deploy server scripts to S3 bucket
    const s3Bucket = s3.Bucket.fromBucketName(this, 'StateBackupBucket', s3BucketName);
    
    const scriptDeployment = new s3deploy.BucketDeployment(this, 'ServerScriptsDeployment', {
      sources: [s3deploy.Source.asset('./server-scripts')],
      destinationBucket: s3Bucket,
      destinationKeyPrefix: 'server-scripts/',
      prune: true, // Remove files not present in source
      retainOnDelete: false, // Clean up on stack deletion
    });

    // WireGuard server installation and configuration script
    const userDataScript = ec2.UserData.forLinux();
    userDataScript.addCommands(
      '#!/bin/bash',
      'set -e',
      '',
      '# Update system packages',
      'apt-get update -y',
      'apt-get upgrade -y',
      '',
      '# Install required packages',
      'apt-get install -y wireguard-tools fail2ban ufw curl qrencode',
      'snap install aws-cli --classic',
      '',
      '# Check for existing WireGuard configuration in S3 bucket',
      `S3_BUCKET="${s3BucketName}"`,
      `AWS_REGION="${targetRegion}"`,
      'WIREGUARD_CONFIG_EXISTS=false',
      '',
      '# Function to check if S3 objects exist',
      'check_s3_config() {',
      '    aws s3api head-object --bucket "$S3_BUCKET" --key "wireguard-config/server_private_key" --region "$AWS_REGION" >/dev/null 2>&1 && \\',
      '    aws s3api head-object --bucket "$S3_BUCKET" --key "wireguard-config/server_public_key" --region "$AWS_REGION" >/dev/null 2>&1 && \\',
      '    aws s3api head-object --bucket "$S3_BUCKET" --key "wireguard-config/wg0.conf" --region "$AWS_REGION" >/dev/null 2>&1',
      '}',
      '',
      '# Check if WireGuard configuration exists in S3',
      'echo "Checking for existing WireGuard configuration in S3 bucket: $S3_BUCKET"',
      'if check_s3_config; then',
      '    echo "Existing WireGuard configuration found in S3. Restoring from backup..."',
      '    WIREGUARD_CONFIG_EXISTS=true',
      '    ',
      '    # Create wireguard directory if it doesn\'t exist',
      '    mkdir -p /etc/wireguard',
      '    ',
      '    # Restore WireGuard configuration from S3 (only /etc/wireguard files)',
      '    aws s3 sync "s3://$S3_BUCKET/wireguard-config/" /etc/wireguard --region "$AWS_REGION"',
      '    ',
      '    # Ensure proper permissions on private key',
      '    chmod 600 /etc/wireguard/server_private_key 2>/dev/null || true',
      '    chmod 600 /etc/wireguard/client_private_key 2>/dev/null || true',
      '    find /etc/wireguard/clients -name "client_private_key" -exec chmod 600 {} \\; 2>/dev/null || true',
      '    ',
      '    echo "WireGuard configuration restored successfully from S3"',
      'else',
      '    echo "No existing WireGuard configuration found in S3. Will create new configuration."',
      'fi',
      '',
      '# Configure UFW firewall',
      'ufw --force reset',
      'ufw default deny incoming',
      'ufw default allow outgoing',
      'ufw allow 22/tcp',
      `ufw allow ${vpnPort}/udp`,
      'ufw route allow in on wg0 out on ens5',
      'ufw --force enable',
      '',
      '# Enable IP forwarding',
      'echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf',
      'echo "net.ipv6.conf.all.forwarding=1" >> /etc/sysctl.conf',
      'sysctl -p',
      '',
      '# Only create new WireGuard configuration if it doesn\'t exist in S3',
      'if [ "$WIREGUARD_CONFIG_EXISTS" = "false" ]; then',
      '    echo "Creating new WireGuard server configuration..."',
      '    ',
      '    # Generate WireGuard server keys',
      '    cd /etc/wireguard',
      '    wg genkey | tee server_private_key | wg pubkey > server_public_key',
      '    chmod 600 server_private_key',
      '    ',
      '    # Get server public IP using IMDSv2',
      '    TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)',
      '    SERVER_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)',
      '    ',
      '    # Create WireGuard server configuration',
      '    printf "[Interface]\\n" > /etc/wireguard/wg0.conf',
      '    printf "PrivateKey = \$(cat server_private_key)\\n" >> /etc/wireguard/wg0.conf',
      `    printf "Address = ${vpnServerIP}/24\\n" >> /etc/wireguard/wg0.conf`,
      `    printf "ListenPort = ${vpnPort}\\n" >> /etc/wireguard/wg0.conf`,
      '    printf "PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE\\n" >> /etc/wireguard/wg0.conf',
      '    printf "PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE\\n" >> /etc/wireguard/wg0.conf',
      'fi',
      '',
      '# Configure fail2ban for SSH protection',
      'cat > /etc/fail2ban/jail.local << \'EOF\'',
      '[DEFAULT]',
      'bantime = 3600',
      'findtime = 600',
      'maxretry = 3',
      '',
      '[sshd]',
      'enabled = true',
      'port = ssh',
      'logpath = /var/log/auth.log',
      'backend = %(sshd_backend)s',
      'EOF',
      '',
      '# Start and enable services',
      'systemctl enable wg-quick@wg0',
      'systemctl start wg-quick@wg0',
      'systemctl enable fail2ban',
      'systemctl start fail2ban',
      '',
      '# Sync server scripts from S3 and generate dynamic environment variables',
      'echo "Syncing server scripts from S3..."',
      `aws s3 sync s3://${s3BucketName}/server-scripts/ /etc/wireguard/ --region ${targetRegion}`,
      '',
      '# Generate dynamic environment variables file',
      'echo "Generating environment variables..."',
      'cat > /etc/wireguard/env.sh << EOF',
      '#!/bin/bash',
      '',
      '# Environment variables for WireGuard server scripts',
      '# This file is dynamically generated during EC2 instance startup',
      '',
      '# AWS Configuration',
      `export S3_BUCKET="${s3BucketName}"`,
      `export AWS_REGION="${targetRegion}"`,
      '',
      '# VPN Configuration',
      `export VPN_SUBNET_BASE="${vpnSubnetBase}"`,
      `export VPN_SUBNET="${vpnSubnet}"`,
      `export VPN_PORT="${vpnPort}"`,
      ...(isDnsManagementEnabled() ? [
        // Use DNS name when DNS management is enabled
        `export SERVER_ENDPOINT="${getVpnSubdomain(targetRegion)}"`,
      ] : [
        // Get current public IP when DNS management is disabled
        'export SERVER_ENDPOINT=$(curl -H "X-aws-ec2-metadata-token: $(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)" -s http://169.254.169.254/latest/meta-data/public-ipv4)',
      ]),
      'EOF',
      '',
      '# Make scripts executable',
      'chmod +x /etc/wireguard/add-client.sh',
      'chmod +x /etc/wireguard/remove-client.sh',
      'chmod +x /etc/wireguard/vpn-status.sh',
      'chmod +x /etc/wireguard/env.sh',
      '',
      'echo "Server scripts deployed and configured successfully!"',
      'echo "RegionHop VPN server setup completed!"',
    );

    // Create Launch Template for spot instances
    const launchTemplate = new ec2.LaunchTemplate(this, 'WireGuardLaunchTemplate', {
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.NANO),
      machineImage: ubuntuAmi,
      securityGroup: infrastructureStack.securityGroup,
      keyPair: infrastructureStack.keyPair,
      role: infrastructureStack.serverRole,
      userData: userDataScript,
      spotOptions: {
        requestType: ec2.SpotRequestType.ONE_TIME,
        // Set a reasonable spot price limit (optional - if not set, uses on-demand price as max)
        //maxPrice: 0.01, // $0.01 per hour - adjust as needed
      },
    });

    // DNS Management Setup (if enabled) - CREATE BEFORE ASG
    let autoScalingGroup: autoscaling.AutoScalingGroup;

    if (isDnsManagementEnabled()) {
      const vpnDomain = getVpnSubdomain(targetRegion);
      const dnsRecordTtl = getDnsRecordTtl();

      // Create Lambda function for DNS management
      const dnsUpdaterLambda = new lambdaNodejs.NodejsFunction(this, 'DnsUpdaterLambda', {
        entry: 'lib/dns-updater-lambda.ts',
        runtime: lambda.Runtime.NODEJS_22_X,
        architecture: lambda.Architecture.ARM_64,
        environment: {
          DOMAIN_NAME: vpnDomain,
          HOSTED_ZONE_ID: getHostedZoneId() || '',
          DNS_RECORD_TTL: dnsRecordTtl.toString(),
        },
        timeout: cdk.Duration.minutes(5),
        memorySize: 256,
      });

      // Grant permissions to Lambda
      dnsUpdaterLambda.addToRolePolicy(new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'ec2:DescribeInstances',
        ],
        resources: ['*'],
      }));

      dnsUpdaterLambda.addToRolePolicy(new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'route53:ChangeResourceRecordSets',
          'route53:ListHostedZonesByName',
          'route53:GetHostedZone',
        ],
        resources: ['*'],
      }));

      dnsUpdaterLambda.addToRolePolicy(new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'autoscaling:DescribeAutoScalingGroups',
          'autoscaling:DescribeAutoScalingInstances',
        ],
        resources: ['*'],
      }));

      // Create Auto Scaling Group for spot instances with 0 initial capacity
      autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'WireGuardAutoScalingGroup', {
        vpc: infrastructureStack.vpc,
        launchTemplate: launchTemplate,
        minCapacity: 0,
        maxCapacity: 1,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PUBLIC,
        },
      });

      // Create EventBridge rule for ASG events (AFTER ASG is created so we can reference it)
      const asgEventRule = new events.Rule(this, 'ASGEventRule', {
        eventPattern: {
          source: ['aws.autoscaling'],
          detailType: ['EC2 Instance Launch Successful', 'EC2 Instance Launch Unsuccessful'],
          detail: {
            AutoScalingGroupName: [autoScalingGroup.autoScalingGroupName],
          },
        },
        description: 'Trigger DNS update when ASG instances change',
      });

      // Add Lambda as target for EventBridge rule
      asgEventRule.addTarget(new targets.LambdaFunction(dnsUpdaterLambda));

      // Create a custom resource to set the desired capacity after EventBridge is set up
      const setDesiredCapacityLambda = new lambda.Function(this, 'SetDesiredCapacityLambda', {
        runtime: lambda.Runtime.PYTHON_3_12,
        architecture: lambda.Architecture.ARM_64,
        handler: 'index.handler',
        code: lambda.Code.fromInline(`
import boto3
import json
import cfnresponse

def handler(event, context):
    try:
        if event['RequestType'] == 'Create':
            autoscaling = boto3.client('autoscaling')
            asg_name = event['ResourceProperties']['AutoScalingGroupName']

            # Set desired capacity to 1 to launch the instance
            autoscaling.set_desired_capacity(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=1
            )

        cfnresponse.send(event, context, cfnresponse.SUCCESS, {})
    except Exception as e:
        print(f"Error: {str(e)}")
        cfnresponse.send(event, context, cfnresponse.FAILED, {})
`),
        timeout: cdk.Duration.minutes(5),
      });

      // Grant permissions to update ASG
      setDesiredCapacityLambda.addToRolePolicy(new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: [
          'autoscaling:SetDesiredCapacity',
          'autoscaling:UpdateAutoScalingGroup',
        ],
        resources: [autoScalingGroup.autoScalingGroupArn],
      }));

      // Create custom resource that depends on the EventBridge rule
      const setDesiredCapacityResource = new cdk.CustomResource(this, 'SetDesiredCapacityResource', {
        serviceToken: setDesiredCapacityLambda.functionArn,
        properties: {
          AutoScalingGroupName: autoScalingGroup.autoScalingGroupName,
        },
      });

      // Ensure the custom resource depends on the EventBridge rule
      setDesiredCapacityResource.node.addDependency(asgEventRule);

      // Route 53 record will be created and managed by the Lambda function
    } else {
      // Create Auto Scaling Group for spot instances (DNS management disabled)
      autoScalingGroup = new autoscaling.AutoScalingGroup(this, 'WireGuardAutoScalingGroup', {
        vpc: infrastructureStack.vpc,
        launchTemplate: launchTemplate,
        minCapacity: 0,
        maxCapacity: 1,
        vpcSubnets: {
          subnetType: ec2.SubnetType.PUBLIC,
        },
      });
    }

    // Output important information
    if (isDnsManagementEnabled()) {
      const vpnDomain = getVpnSubdomain(targetRegion);

      new cdk.CfnOutput(this, 'VPNServerDomain', {
        value: vpnDomain,
        description: `VPN Server Domain Name - ${targetRegion}`,
      });

      new cdk.CfnOutput(this, 'DNSManagementEnabled', {
        value: 'DNS records will be automatically updated when spot instances are replaced',
        description: 'DNS auto-update status',
      });
    }

    new cdk.CfnOutput(this, 'VPNServerAutoScalingGroup', {
      value: autoScalingGroup.autoScalingGroupName,
      description: `VPN Server Auto Scaling Group Name - ${targetRegion}`,
    });
  }
}