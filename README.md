# WireGuard VPN Service on AWS

A complete AWS CDK implementation of a personal WireGuard VPN service with multi-region support for privacy, security, and geo-unblocking.

## 🚀 Features

- **Modern VPN Protocol**: WireGuard for high performance and security
- **Multi-Region Support**: Deploy to 5 AWS regions for global coverage
- **Privacy-Focused**: Default deployment in EU Frankfurt (eu-central-1)
- **Easy macOS Integration**: Official WireGuard app support
- **Automated Setup**: One-command deployment with CDK
- **Enhanced Security**: fail2ban protection and UFW firewall
- **Cost-Effective**: ~$15/month per region on t3.micro instance
- **Client Management**: Easy client configuration generation
- **Region Management**: Deploy, manage, and destroy regions independently

## 📋 Prerequisites

- AWS CLI configured with appropriate credentials
- Node.js (v18 or later)
- AWS CDK CLI installed globally
- Active AWS account with permissions to create VPC, EC2, and IAM resources

## 🏗️ Architecture

```
Internet
    ↓
Elastic IP (Static)
    ↓
VPC (Custom)
    ↓
Public Subnet
    ↓
EC2 Instance (Ubuntu 24.04)
    ↓
WireGuard Server
    ↓
Security Group (SSH + WireGuard)
    ↓
fail2ban + UFW Firewall
```

## 🛠️ Deployment

### 1. Clone and Setup

```bash
git clone <your-repo>
cd ownvpn
npm install
```

### 2. Deploy the Stack

The service now supports multi-region deployment. Use the deployment script for the easiest setup:

```bash
# Deploy to default region (eu-central-1)
./deploy.sh

# Deploy to specific region
./deploy.sh --region us-east-1

# Deploy to multiple regions
./deploy.sh --regions us-east-1,eu-central-1,ap-southeast-1

# List available regions
./deploy.sh --list-regions

# Check deployment status
./deploy.sh --status
```

For manual deployment:

```bash
# Bootstrap CDK for target region (first-time only)
cdk bootstrap --region eu-central-1

# Set region environment variable
export VPN_REGION=eu-central-1

# Deploy the stacks
cdk deploy OwnVPN-eu-central-1-Infrastructure
cdk deploy OwnVPN-eu-central-1-Compute
```

The deployment will:
- Create a VPC with public subnet in each region
- Launch Ubuntu 24.04 LTS EC2 instance
- Configure WireGuard server automatically
- Set up fail2ban and firewall rules
- Generate server and client keys
- Create a default macOS client configuration
- **Automatically retrieve the SSH private key**

### 3. Region Management

Use the region manager for advanced region operations:

```bash
# List all regions with deployment status
./region-manager.sh list

# Deploy to specific region
./region-manager.sh deploy us-west-2

# Destroy region deployment
./region-manager.sh destroy us-west-2

# Check health of all deployed regions
./region-manager.sh health
```

## 📱 Client Setup (macOS)

### 1. Download WireGuard App

Download the official WireGuard app from the Mac App Store.

### 2. List Available Regions

First, see which regions are deployed:
```bash
./connect.sh list
```

### 3. Get Client Configuration

Use the connection helper script to automatically download the client configuration for a specific region:
```bash
# Get configuration for default region
./connect.sh config eu-central-1

# Get configuration for US East
./connect.sh config us-east-1

# Get configuration for Asia Pacific
./connect.sh config ap-southeast-1
```

This will create a `macos-client-<region>.conf` file that you can directly import into the WireGuard app.

### 4. Manual Configuration (Advanced)

SSH into your server in a specific region:
```bash
./connect.sh ssh eu-central-1
```

Retrieve your client configuration:
```bash
sudo cat /etc/wireguard/clients/macos-client/macos-client.conf
```

### 5. Import Configuration

1. Open WireGuard app
2. Click "Import tunnel(s) from file"
3. Select the `macos-client-<region>.conf` file
4. Import the file
5. Repeat for each region you want to use

### 6. Connect

Click the toggle switch in WireGuard app to connect to your chosen region.

## 🔧 Management Commands

### Easy Connection Helper
Use the included connection helper script for region-specific tasks:

```bash
# List all deployed regions
./connect.sh list

# SSH to specific region
./connect.sh ssh us-east-1

# Get client configuration for region
./connect.sh config eu-central-1

# Check VPN status in region
./connect.sh status us-west-2

# Add new client to region
./connect.sh add-client us-east-1 iphone
```

### Region Management
```bash
# Deploy new region
./region-manager.sh deploy ap-northeast-1

# Check status of all regions
./region-manager.sh status

# Destroy region to save costs
./region-manager.sh destroy us-west-2
```

### Manual SSH Access
```bash
# SSH key files are created per region
ssh -i wireguard-vpn-key-<region>.pem ubuntu@YOUR_SERVER_IP
```

### Server Management Commands
Once connected via SSH:

```bash
# Check VPN Status
sudo /etc/wireguard/vpn-status.sh

# Add New Client
sudo /etc/wireguard/add-client.sh client-name

# View Connected Clients
sudo wg show

# Check Server Logs
sudo journalctl -u wg-quick@wg0 -f

# Check fail2ban Status
sudo fail2ban-client status
sudo fail2ban-client status sshd
```

## 🔐 Security Features

### Firewall (UFW)
- Only allows SSH (port 22) and WireGuard (port 51820)
- Blocks all other incoming traffic
- Allows all outgoing traffic

### fail2ban
- Protects SSH from brute force attacks
- Bans IPs after 3 failed attempts for 1 hour
- Monitors /var/log/auth.log

### Key Management
- Server keys generated automatically
- Client keys unique per client
- Private keys stored securely with 600 permissions

## 🛡️ Network Configuration

### Server Network (Per Region)
- **VPN Subnet**: 10.8.0.0/24 (configured in regions.json)
- **Server IP**: 10.8.0.1
- **Client Range**: 10.8.0.2-10.8.0.254
- **VPN Port**: 51820 (configurable per region)

### DNS Configuration
- Primary: 1.1.1.1 (Cloudflare)
- Secondary: 8.8.8.8 (Google)

### Traffic Routing
- All client traffic routed through VPN
- IP forwarding enabled
- NAT configured for internet access
- Each region operates independently

### Region Selection
Choose regions based on your needs:
- **eu-central-1**: European privacy, GDPR compliance
- **us-east-1**: US East Coast, low latency to East Coast
- **us-west-2**: US West Coast, low latency to West Coast
- **ap-southeast-1**: Asia Pacific, Singapore access
- **ap-northeast-1**: Asia Pacific, Japan access

## 📊 Monitoring

### CloudWatch Integration
- Basic EC2 monitoring enabled
- CloudWatch agent permissions configured
- System logs available in CloudWatch

### Server Monitoring
```bash
# Check system resources
htop

# Monitor network connections
sudo netstat -tulpn

# Check disk usage
df -h

# Monitor WireGuard interface
sudo wg show
```

## 💰 Cost Optimization

### Current Configuration (Per Region)
- **Instance Type**: t3.micro (Free tier eligible)
- **Storage**: 8GB gp3 EBS volume
- **Network**: Elastic IP included
- **Estimated Monthly Cost**: ~$15 USD per region

### Multi-Region Cost Considerations
- **Single Region**: ~$15/month
- **Two Regions**: ~$30/month
- **Global Coverage (5 regions)**: ~$75/month
- **Data Transfer**: Inter-region transfer charges apply

### Cost Reduction Tips
1. Use AWS Free Tier if eligible (first region only)
2. Deploy only needed regions - destroy unused ones
3. Use `./region-manager.sh destroy <region>` to remove costly regions
4. Monitor data transfer costs between regions
5. Consider t3.nano for lower traffic regions
6. Use CloudWatch alarms for usage alerts per region
7. Regularly review deployed regions with `./region-manager.sh status`

## 🔧 Troubleshooting

### Common Issues

#### 1. VPN Connection Fails
```bash
# Check WireGuard status
sudo systemctl status wg-quick@wg0

# Restart WireGuard
sudo systemctl restart wg-quick@wg0

# Check firewall
sudo ufw status
```

#### 2. No Internet Access Through VPN
```bash
# Check IP forwarding
cat /proc/sys/net/ipv4/ip_forward

# Check iptables rules
sudo iptables -L -n -v
sudo iptables -t nat -L -n -v
```

#### 3. Client Can't Connect
```bash
# Check server logs
sudo journalctl -u wg-quick@wg0 -f

# Verify client configuration
sudo cat /etc/wireguard/clients/CLIENT_NAME/CLIENT_NAME.conf
```

### Log Locations
- **WireGuard**: `sudo journalctl -u wg-quick@wg0`
- **fail2ban**: `sudo tail -f /var/log/fail2ban.log`
- **UFW**: `sudo tail -f /var/log/ufw.log`
- **System**: `sudo tail -f /var/log/syslog`

## 🔄 Backup and Recovery

### Backup Server Configuration
```bash
# Create backup directory
sudo mkdir -p /backup/wireguard

# Backup WireGuard configuration
sudo cp -r /etc/wireguard /backup/wireguard/
sudo cp /etc/fail2ban/jail.local /backup/wireguard/
sudo cp /etc/ufw/user.rules /backup/wireguard/

# Create tar archive
sudo tar -czf /backup/wireguard-backup-$(date +%Y%m%d).tar.gz /backup/wireguard/
```

### Restore Configuration
```bash
# Extract backup
sudo tar -xzf wireguard-backup-YYYYMMDD.tar.gz -C /

# Restart services
sudo systemctl restart wg-quick@wg0
sudo systemctl restart fail2ban
sudo ufw reload
```

## 🚨 Emergency Procedures

### Server Unresponsive
1. Check AWS Console for instance status
2. Reboot instance from AWS Console
3. Check security group rules
4. Verify Elastic IP association

### Lost SSH Access
1. Create new EC2 instance with same security group
2. Attach original EBS volume as secondary
3. Copy WireGuard configuration
4. Update DNS or recreate with new IP

### Compromised Server
1. Immediately stop EC2 instance
2. Create new instance from fresh AMI
3. Restore WireGuard configuration from backup
4. Generate new server keys
5. Update all client configurations

## 📚 Additional Resources

- [WireGuard Documentation](https://www.wireguard.com/)
- [AWS CDK Documentation](https://docs.aws.amazon.com/cdk/)
- [Ubuntu fail2ban Guide](https://help.ubuntu.com/community/Fail2ban)
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/)

## 🤝 Contributing

Feel free to submit issues and pull requests to improve this WireGuard VPN implementation.

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.
