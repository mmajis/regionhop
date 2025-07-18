import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { OwnvpnInfrastructureStack } from './ownvpn-infrastructure-stack';
import { getVpnSubnet, getVpnPort } from './region-config';

export interface OwnvpnComputeStackProps extends cdk.StackProps {
  infrastructureStack: OwnvpnInfrastructureStack;
}

export class OwnvpnComputeStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: OwnvpnComputeStackProps) {
    super(scope, id, props);

    const { infrastructureStack } = props;

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
      '# Generate WireGuard server keys',
      'cd /etc/wireguard',
      'wg genkey | tee server_private_key | wg pubkey > server_public_key',
      'chmod 600 server_private_key',
      '',
      '# Get server public IP using IMDSv2',
      'TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600" -s)',
      'SERVER_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-ipv4)',
      '',
      '# Create WireGuard server configuration',
      'printf "[Interface]\\n" > /etc/wireguard/wg0.conf',
      'printf "PrivateKey = \$(cat server_private_key)\\n" >> /etc/wireguard/wg0.conf',
      `printf "Address = ${vpnServerIP}/24\\n" >> /etc/wireguard/wg0.conf`,
      `printf "ListenPort = ${vpnPort}\\n" >> /etc/wireguard/wg0.conf`,
      'printf "PostUp = iptables -A FORWARD -i wg0 -j ACCEPT; iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE\\n" >> /etc/wireguard/wg0.conf',
      'printf "PostDown = iptables -D FORWARD -i wg0 -j ACCEPT; iptables -t nat -D POSTROUTING -o ens5 -j MASQUERADE\\n" >> /etc/wireguard/wg0.conf',
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
      '# Create client configuration directory',
      'mkdir -p /etc/wireguard/clients',
      '',
      '# Create client key generation script using printf to avoid variable expansion issues',
      'printf "#!/bin/bash\\n" > /etc/wireguard/add-client.sh',
      'printf "if [ -z \\"\\$1\\" ]; then\\n" >> /etc/wireguard/add-client.sh',
      'printf "  echo \\"Usage: \\$0 <client-name>\\"\\n" >> /etc/wireguard/add-client.sh',
      'printf "  exit 1\\n" >> /etc/wireguard/add-client.sh',
      'printf "fi\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENT_NAME=\\$1\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENT_DIR=\\"/etc/wireguard/clients/\\$CLIENT_NAME\\"\\n" >> /etc/wireguard/add-client.sh',
      'printf "SERVER_PUBLIC_KEY=\\$(cat /etc/wireguard/server_public_key)\\n" >> /etc/wireguard/add-client.sh',
      'printf "TOKEN=\\$(curl -X PUT \\"http://169.254.169.254/latest/api/token\\" -H \\"X-aws-ec2-metadata-token-ttl-seconds: 21600\\" -s)\\n" >> /etc/wireguard/add-client.sh',
      'printf "SERVER_IP=\\$(curl -H \\"X-aws-ec2-metadata-token: \\$TOKEN\\" -s http://169.254.169.254/latest/meta-data/public-ipv4)\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "mkdir -p \\$CLIENT_DIR\\n" >> /etc/wireguard/add-client.sh',
      'printf "cd \\$CLIENT_DIR\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "# Generate client keys\\n" >> /etc/wireguard/add-client.sh',
      'printf "wg genkey | tee client_private_key | wg pubkey > client_public_key\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENT_PUBLIC_KEY=\\$(cat client_public_key)\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENT_PRIVATE_KEY=\\$(cat client_private_key)\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "# Assign client IP (simple increment)\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENT_COUNT=\\$(ls -1 /etc/wireguard/clients/ | wc -l)\\n" >> /etc/wireguard/add-client.sh',
      `printf "CLIENT_IP=\\"${vpnSubnetBase}\\$((CLIENT_COUNT + 1))\\"\\n\\n" >> /etc/wireguard/add-client.sh`,
      'printf "# Create client configuration\\n" >> /etc/wireguard/add-client.sh',
      'printf "cat > \\${CLIENT_NAME}.conf << CLIENTEOF\\n" >> /etc/wireguard/add-client.sh',
      'printf "[Interface]\\n" >> /etc/wireguard/add-client.sh',
      'printf "PrivateKey = \\$CLIENT_PRIVATE_KEY\\n" >> /etc/wireguard/add-client.sh',
      'printf "Address = \\$CLIENT_IP/24\\n" >> /etc/wireguard/add-client.sh',
      'printf "DNS = 1.1.1.1, 8.8.8.8\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "[Peer]\\n" >> /etc/wireguard/add-client.sh',
      'printf "PublicKey = \\$SERVER_PUBLIC_KEY\\n" >> /etc/wireguard/add-client.sh',
      `printf "Endpoint = \\$SERVER_IP:${vpnPort}\\n" >> /etc/wireguard/add-client.sh`,
      'printf "AllowedIPs = 0.0.0.0/0\\n" >> /etc/wireguard/add-client.sh',
      'printf "PersistentKeepalive = 25\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENTEOF\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "# Add client to server configuration\\n" >> /etc/wireguard/add-client.sh',
      'printf "cat >> /etc/wireguard/wg0.conf << CLIENTEOF\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "[Peer]\\n" >> /etc/wireguard/add-client.sh',
      'printf "PublicKey = \\$CLIENT_PUBLIC_KEY\\n" >> /etc/wireguard/add-client.sh',
      'printf "AllowedIPs = \\$CLIENT_IP/32\\n" >> /etc/wireguard/add-client.sh',
      'printf "CLIENTEOF\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "# Restart WireGuard to apply changes\\n" >> /etc/wireguard/add-client.sh',
      'printf "systemctl restart wg-quick@wg0\\n\\n" >> /etc/wireguard/add-client.sh',
      'printf "echo \\"Client \\$CLIENT_NAME created successfully!\\"\\n" >> /etc/wireguard/add-client.sh',
      'printf "echo \\"Configuration file: \\$CLIENT_DIR/\\${CLIENT_NAME}.conf\\"\\n" >> /etc/wireguard/add-client.sh',
      'printf "echo \\"QR Code:\\"\\n" >> /etc/wireguard/add-client.sh',
      'printf "qrencode -t ansiutf8 < \\$CLIENT_DIR/\\${CLIENT_NAME}.conf\\n" >> /etc/wireguard/add-client.sh',
      '',
      'chmod +x /etc/wireguard/add-client.sh',
      '',
      '# Create default client configuration',
      '/etc/wireguard/add-client.sh macos-client',
      '',
      '# Create status script',
      'cat > /etc/wireguard/vpn-status.sh << \'EOF\'',
      '#!/bin/bash',
      'echo "=== WireGuard VPN Status ==="',
      'echo "Server Status:"',
      'systemctl is-active wg-quick@wg0',
      'echo ""',
      'echo "Connected Clients:"',
      'wg show',
      'echo ""',
      'echo "Fail2ban Status:"',
      'fail2ban-client status sshd',
      'EOF',
      '',
      'chmod +x /etc/wireguard/vpn-status.sh',
      '',
      'echo "WireGuard VPN server setup completed!"',
      'echo "Client configuration available at: /etc/wireguard/clients/macos-client/"',
    );

    // Create EC2 instance for VPN server
    const vpnServer = new ec2.Instance(this, 'WireGuardVPNServer', {
      vpc: infrastructureStack.vpc,
      instanceType: ec2.InstanceType.of(ec2.InstanceClass.T4G, ec2.InstanceSize.NANO),
      machineImage: ubuntuAmi,
      securityGroup: infrastructureStack.securityGroup,
      keyPair: infrastructureStack.keyPair,
      role: infrastructureStack.serverRole,
      userData: userDataScript,
      vpcSubnets: {
        subnetType: ec2.SubnetType.PUBLIC,
      },
    });

    // Create Elastic IP for static endpoint
    const elasticIp = new ec2.CfnEIP(this, 'WireGuardElasticIP', {
      domain: 'vpc',
      instanceId: vpnServer.instanceId,
    });

    // Output important information
    new cdk.CfnOutput(this, 'VPNServerIP', {
      value: elasticIp.ref,
      description: `WireGuard VPN Server Public IP - ${targetRegion}`,
    });

    new cdk.CfnOutput(this, 'VPNServerInstanceId', {
      value: vpnServer.instanceId,
      description: `VPN Server EC2 Instance ID - ${targetRegion}`,
    });

    new cdk.CfnOutput(this, 'SSHCommand', {
      value: `ssh -i ${infrastructureStack.keyPair.keyPairName}.pem ubuntu@${elasticIp.ref}`,
      description: 'SSH command to connect to VPN server (after retrieving private key)',
    });

    new cdk.CfnOutput(this, 'ClientConfigLocation', {
      value: '/etc/wireguard/clients/macos-client/macos-client.conf',
      description: 'Location of client configuration file on server',
    });

    new cdk.CfnOutput(this, 'VPNStatusCommand', {
      value: 'sudo /etc/wireguard/vpn-status.sh',
      description: 'Command to check VPN server status',
    });

    new cdk.CfnOutput(this, 'VPNSubnet', {
      value: vpnSubnet,
      description: `VPN internal subnet - ${targetRegion}`,
    });

    new cdk.CfnOutput(this, 'VPNPort', {
      value: vpnPort.toString(),
      description: `VPN server port - ${targetRegion}`,
    });
  }
}