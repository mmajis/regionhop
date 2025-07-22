# WireGuard VPN Client Setup for macOS

## Step 1: Wait for Server Setup
The server needs 2-3 minutes to complete setup after deployment.

## Step 2: Download WireGuard App
Download the official WireGuard app from the Mac App Store.

## Step 3: Get SSH Key
1. Go to AWS Console > EC2 > Key Pairs
2. Find "regionhop-vpn-key"
3. Download the private key file (.pem)

## Step 4: SSH into Server
```bash
chmod 600 regionhop-vpn-key.pem
ssh -i regionhop-vpn-key.pem ubuntu@63.177.119.32
```

## Step 5: Get Client Configuration
```bash
sudo cat /etc/wireguard/clients/macos-client/macos-client.conf
```

## Step 6: Import to WireGuard App
1. Copy the configuration text
2. Open WireGuard app
3. Click "Import tunnel(s) from file"
4. Create a new .conf file and paste the content
5. Import the file

## Step 7: Connect
Click the toggle switch in WireGuard app to connect.

## Troubleshooting
If you have issues, check the server status:
```bash
sudo /etc/wireguard/vpn-status.sh
```
