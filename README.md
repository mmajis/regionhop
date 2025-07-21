# WireGuard VPN Service on AWS

A complete AWS CDK implementation of a personal WireGuard VPN service with multi-region support for privacy, security, and geo-unblocking.

## 🎯 Quick Start with Hop

This project now includes **`hop`** - a unified command-line tool that consolidates all VPN management functions into a single, intuitive interface:

```bash
./hop.sh deploy                    # Deploy VPN to default region
./hop.sh list                      # See all regions and their status
./hop.sh ssh eu-central-1          # Connect to your VPN server
./hop.sh config eu-central-1       # Get client configuration
./hop.sh destroy us-west-2         # Remove unused regions
```

**Why Hop?** Previously, this project had 3 separate scripts (`deploy.sh`, `connect.sh`, `region-manager.sh`) which created confusion. Hop unifies all functionality into one tool while maintaining backward compatibility.

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
    ↓
S3 Bucket (Encrypted State Backup)
```

### Three-Stack Architecture

The deployment consists of three CDK stacks per region:

1. **Persistence Stack**: Encrypted S3 bucket for WireGuard state backup
2. **Infrastructure Stack**: VPC, security groups, IAM roles, and SSH key pairs
3. **Compute Stack**: EC2 instances, Auto Scaling Groups, and Lambda functions

## 🛠️ Deployment

### 1. Clone and Setup

```bash
git clone <your-repo>
cd regionhop
npm install
```

### 2. Deploy with Hop - The Unified VPN Tool

The service uses **`hop`** - a unified command-line tool that consolidates all VPN management functions:

```bash
# Deploy to default region (eu-central-1)
./hop.sh deploy

# Deploy to specific region
./hop.sh deploy us-east-1

# Deploy to multiple regions
./hop.sh deploy --regions us-east-1,eu-central-1,ap-southeast-1

# List available regions
./hop.sh regions

# Check deployment status
./hop.sh status
```

For manual deployment:

```bash
# Bootstrap CDK for target region (first-time only)
cdk bootstrap --region eu-central-1

# Set region environment variable
export VPN_REGION=eu-central-1

# Optional: Set deployment ID for unique resource naming (prevents conflicts)
export VPN_DEPLOYMENT_ID=mydeployment

# Deploy the stacks (in order)
cdk deploy RegionHop-eu-central-1-Persistence
cdk deploy RegionHop-eu-central-1-Infrastructure
cdk deploy RegionHop-eu-central-1-Compute
```

### Configuration Options

#### Deployment ID (Important for Multiple Deployments)
The system includes a configurable `deploymentId` to ensure unique S3 bucket names and prevent conflicts when multiple instances of this app are deployed in the same regions:

**Configuration Methods:**
1. **Environment Variable** (recommended): `export VPN_DEPLOYMENT_ID=myuniqueid`
2. **Config File**: Edit `deploymentId` in `config.json` (default: `"default"`)

**Why This Matters:**
- S3 bucket names must be globally unique across all AWS accounts
- Without unique deployment IDs, multiple deployments would conflict
- Each deployment gets its own isolated S3 bucket: `regionhop-state-backup-{region}-{deploymentId}`

**Example Usage:**
```bash
# Production deployment
export VPN_DEPLOYMENT_ID=prod
./hop.sh deploy us-east-1

# Development deployment
export VPN_DEPLOYMENT_ID=dev
./hop.sh deploy us-east-1

# Personal deployment
export VPN_DEPLOYMENT_ID=personal
./hop.sh deploy us-east-1
```

The deployment will:
- Create an encrypted S3 bucket for state backup per region
- Create a VPC with public subnet in each region
- Launch Ubuntu 24.04 LTS EC2 instance with S3 access permissions
- Configure WireGuard server automatically
- Set up fail2ban and firewall rules
- Generate server and client keys
- Create a default macOS client configuration
- **Automatically retrieve the SSH private key**

### 3. Region Management

Use hop for all region management operations:

```bash
# List all regions with deployment status
./hop.sh list

# Deploy to specific region
./hop.sh deploy us-west-2

# Destroy region deployment
./hop.sh destroy us-west-2

# Check health of all deployed regions
./hop.sh health
```

## 📱 Client Setup (macOS)

### 1. Download WireGuard App

Download the official WireGuard app from the Mac App Store.

### 2. List Available Regions

First, see which regions are deployed:
```bash
./hop.sh deployed
```

### 3. Manage VPN Clients

First, add a VPN client to a region:
```bash
# Add a new client (e.g., for your iPhone)
./hop.sh add-client us-east-1 iphone

# Add another client (e.g., for your laptop)
./hop.sh add-client us-east-1 laptop
```

List available clients in a region:
```bash
./hop.sh list-clients us-east-1
```

### 4. Download Client Configurations

Download specific client configuration:
```bash
# Download configuration for a specific client
./hop.sh download-client us-east-1 iphone

# Download all client configurations from a region
./hop.sh download-client us-east-1 --all
```

This will create configuration files like `iphone-us-east-1.conf` that you can directly import into the WireGuard app.

### 5. Legacy Configuration Command (Deprecated)

For backward compatibility, the old `config` command still works but is deprecated:
```bash
./hop.sh config eu-central-1  # Downloads first available client
```

### 6. Manual Configuration (Advanced)

SSH into your server in a specific region:
```bash
./hop.sh ssh eu-central-1
```

List all clients on the server:
```bash
sudo find /etc/wireguard/clients -maxdepth 1 -type d -not -path '/etc/wireguard/clients' -exec basename {} \;
```

Retrieve a specific client configuration:
```bash
sudo cat /etc/wireguard/clients/CLIENT_NAME/CLIENT_NAME.conf
```

### 7. Import Configuration

1. Open WireGuard app
2. Click "Import tunnel(s) from file"
3. Select the `CLIENT_NAME-<region>.conf` file
4. Import the file
5. Repeat for each region you want to use

### 8. Connect

Click the toggle switch in WireGuard app to connect to your chosen region.

## 🔧 Management Commands

### Hop - Unified VPN Management Tool
Use the **hop** tool for all VPN management tasks:

```bash
# Infrastructure Management
./hop.sh deploy                    # Deploy to default region
./hop.sh deploy us-east-1          # Deploy to specific region
./hop.sh destroy us-west-2         # Destroy region deployment
./hop.sh bootstrap ap-northeast-1  # Bootstrap CDK for region

# Status & Information
./hop.sh list                      # List all regions with status
./hop.sh deployed                  # Show only deployed regions
./hop.sh regions                   # Show available regions
./hop.sh status                    # Show deployment status (all regions)
./hop.sh status us-east-1          # Show status for specific region
./hop.sh health                    # Health check all deployed regions

# Connection & Access
./hop.sh ssh us-east-1             # SSH to VPN server in region
./hop.sh config eu-central-1       # Download client configuration (deprecated)
./hop.sh add-client us-east-1 iphone # Add new VPN client to region
./hop.sh list-clients us-east-1    # List all VPN clients in region
./hop.sh download-client us-east-1 iphone  # Download specific client config
./hop.sh download-client us-east-1 --all   # Download all client configs
```

### Quick Reference
```bash
# Most common commands
./hop.sh deploy                    # Deploy VPN
./hop.sh deployed                  # See deployed regions
./hop.sh ssh eu-central-1          # Connect to server
./hop.sh config eu-central-1       # Get client config
./hop.sh destroy us-west-2         # Remove unused region
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
- **VPN Subnet**: 10.8.0.0/24 (configured in config.json)
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
3. Use `./hop.sh destroy <region>` to remove costly regions
4. Monitor data transfer costs between regions
5. Consider t3.nano for lower traffic regions
6. Use CloudWatch alarms for usage alerts per region
7. Regularly review deployed regions with `./hop.sh status`

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

### S3 State Backup (Automated)

Each region includes an encrypted S3 bucket for secure state backup. The EC2 instances have permissions to sync WireGuard configurations:

```bash
# Backup WireGuard configuration to S3 (automated via cron)
aws s3 sync /etc/wireguard s3://regionhop-state-backup-REGION/wireguard-config/ --exclude "*.tmp" --delete --region REGION

# Restore WireGuard configuration from S3
aws s3 sync s3://regionhop-state-backup-REGION/wireguard-config/ /etc/wireguard --delete --region REGION
```

**Security Features of S3 Backup:**
- **KMS Encryption**: All data encrypted with region-specific KMS keys
- **Versioning**: Previous configurations maintained for 30 days
- **Access Control**: Only EC2 instances with specific IAM roles can access
- **Block Public Access**: All public access blocked by default
- **Lifecycle Management**: Automatic transition to cheaper storage classes

### Manual Backup (Local)
```bash
# Create local backup directory
sudo mkdir -p /backup/wireguard

# Backup WireGuard configuration locally
sudo cp -r /etc/wireguard /backup/wireguard/
sudo cp /etc/fail2ban/jail.local /backup/wireguard/
sudo cp /etc/ufw/user.rules /backup/wireguard/

# Create tar archive
sudo tar -czf /backup/wireguard-backup-$(date +%Y%m%d).tar.gz /backup/wireguard/
```

### Restore Configuration
```bash
# From S3 (recommended)
aws s3 sync s3://regionhop-state-backup-REGION/wireguard-config/ /etc/wireguard --delete --region REGION

# From local backup
sudo tar -xzf wireguard-backup-YYYYMMDD.tar.gz -C /

# Restart services after restore
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

---
**🚀 NEW: Unified Management with Hop**
This project now includes `hop.sh` - a single, powerful command-line tool that replaces the previous 3-script setup (`deploy.sh`, `connect.sh`, `region-manager.sh`). All old scripts still work via symlinks for backward compatibility, but we recommend using `hop` for the best experience.
---
