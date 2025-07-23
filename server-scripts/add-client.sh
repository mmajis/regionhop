#!/bin/bash

# Source environment variables
source "$(dirname "$0")/env.sh"

if [ -z "$1" ]; then
  echo "Usage: $0 <client-name>"
  exit 1
fi

CLIENT_NAME=$1
CLIENT_DIR="/etc/wireguard/clients/$CLIENT_NAME"
SERVER_PUBLIC_KEY=$(cat /etc/wireguard/server_public_key)

mkdir -p $CLIENT_DIR
cd $CLIENT_DIR

# Generate client keys
wg genkey | tee client_private_key | wg pubkey > client_public_key
CLIENT_PUBLIC_KEY=$(cat client_public_key)
CLIENT_PRIVATE_KEY=$(cat client_private_key)

# Assign client IP (find next available IP, including gaps)
get_next_available_ip() {
  local subnet_base="$VPN_SUBNET_BASE"
  local start_ip=2  # Server uses .1
  local max_ip=254
  
  # Extract used IPs from wg0.conf (look for AllowedIPs = x.x.x.x/32)
  local used_ips=$(grep "AllowedIPs = " /etc/wireguard/wg0.conf | grep "/32" | sed "s/.*AllowedIPs = //" | sed "s|/32||")
  
  # Convert IPs to just the last octet for easier processing
  local used_octets=$(echo "$used_ips" | sed "s|$VPN_SUBNET_BASE||g" | sort -n)
  
  # Find the first available IP
  for ip in $(seq $start_ip $max_ip); do
    if ! echo "$used_octets" | grep -qx "$ip"; then
      echo "${subnet_base}${ip}"
      return 0
    fi
  done
  
  # If no IP available, return error
  echo "ERROR: No available IPs in subnet $VPN_SUBNET" >&2
  return 1
}

CLIENT_IP=$(get_next_available_ip)
if [ $? -ne 0 ]; then
  echo "Failed to assign IP address" >&2
  exit 1
fi

# Create client configuration
cat > ${CLIENT_NAME}.conf << CLIENTEOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IP/24
DNS = 1.1.1.1, 8.8.8.8

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT:$VPN_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
CLIENTEOF

# Add client to server configuration
cat >> /etc/wireguard/wg0.conf << CLIENTEOF

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $CLIENT_IP/32
CLIENTEOF

# Restart WireGuard to apply changes
systemctl restart wg-quick@wg0

echo "Client $CLIENT_NAME created successfully!"
echo "Configuration file: $CLIENT_DIR/${CLIENT_NAME}.conf"
echo "QR Code:"
qrencode -t ansiutf8 < $CLIENT_DIR/${CLIENT_NAME}.conf

# Backup updated configuration to S3
aws s3 sync /etc/wireguard s3://$S3_BUCKET/wireguard-config/ --exclude "*.tmp" --region $AWS_REGION
echo "Configuration backed up to S3"