# WireGuard VPN Service on AWS

A complete AWS CDK implementation of a personal WireGuard VPN service deployed to EU Frankfurt for privacy, security, and geo-unblocking.

## 🚀 Features

- **Modern VPN Protocol**: WireGuard for high performance and security
- **Privacy-Focused**: Deployed in EU Frankfurt (eu-central-1)
- **Easy macOS Integration**: Official WireGuard app support
- **Automated Setup**: One-command deployment with CDK
- **Enhanced Security**: fail2ban protection and UFW firewall
- **Cost-Effective**: ~$10-15/month on t3.micro instance
- **Client Management**: Easy client configuration generation

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

Use the included deployment script for the easiest setup:

```bash
./deploy.sh deploy
```

Or deploy manually:

```bash
# Bootstrap CDK (first-time only)
cdk bootstrap --region eu-central-1

# Deploy the stack
cdk deploy
```

The deployment will:
- Create a VPC with public subnet
- Launch Ubuntu 24.04 LTS EC2 instance
- Configure WireGuard server automatically
- Set up fail2ban and firewall rules
- Generate server and client keys
- Create a default macOS client configuration
- **Automatically retrieve the SSH private key**

### 3. SSH Key Retrieval

The deployment script automatically retrieves your SSH private key from AWS Systems Manager. If you need to retrieve it manually:

```bash
# Get the key pair ID from deployment outputs
KEY_PAIR_ID=$(aws cloudformation describe-stacks \
  --stack-name OwnvpnStack \
  --region eu-central-1 \
  --query 'Stacks[0].Outputs[?OutputKey==`KeyPairId`].OutputValue' \
  --output text)

# Retrieve the private key
aws ssm get-parameter \
  --name "/ec2/keypair/${KEY_PAIR_ID}" \
  --with-decryption \
  --query Parameter.Value \
  --output text \
  --region eu-central-1 > wireguard-vpn-key.pem

chmod 600 wireguard-vpn-key.pem
```

## 📱 Client Setup (macOS)

### 1. Download WireGuard App

Download the official WireGuard app from the Mac App Store.

### 2. Get Client Configuration (Easy Way)

Use the connection helper script to automatically download the client configuration:
```bash
./connect.sh config
```

This will create a `macos-client.conf` file that you can directly import into the WireGuard app.

### 2. Get Client Configuration (Manual Way)

SSH into your server (the key file is automatically created by the deployment script):
```bash
ssh -i wireguard-vpn-key.pem ubuntu@YOUR_SERVER_IP
```

Retrieve your client configuration:
```bash
sudo cat /etc/wireguard/clients/macos-client/macos-client.conf
```

### 3. Import Configuration

1. Open WireGuard app
2. Click "Import tunnel(s) from file"
3. Select the `macos-client.conf` file (if using helper script) or create a new file with `.conf` extension
4. If manual: Paste the configuration content
5. Import the file

### 4. Connect

Click the toggle switch in WireGuard app to connect.

## 🔧 Management Commands

### Easy Connection Helper
Use the included connection helper script for common tasks:

```bash
# SSH to server
./connect.sh ssh

# Get client configuration
./connect.sh config

# Check VPN status
./connect.sh status

# Add new client
./connect.sh add-client iphone
```

### Manual SSH Access
```bash
ssh -i wireguard-vpn-key.pem ubuntu@YOUR_SERVER_IP
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

### Server Network
- **VPN Subnet**: 10.0.0.0/24
- **Server IP**: 10.0.0.1
- **Client Range**: 10.0.0.2-10.0.0.254

### DNS Configuration
- Primary: 1.1.1.1 (Cloudflare)
- Secondary: 8.8.8.8 (Google)

### Traffic Routing
- All client traffic routed through VPN
- IP forwarding enabled
- NAT configured for internet access

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

### Current Configuration
- **Instance Type**: t3.micro (Free tier eligible)
- **Storage**: 8GB gp3 EBS volume
- **Network**: Elastic IP included
- **Estimated Monthly Cost**: $10-15 USD

### Cost Reduction Tips
1. Use AWS Free Tier if eligible
2. Consider t3.nano for lower traffic
3. Monitor data transfer costs
4. Use CloudWatch alarms for usage alerts

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
