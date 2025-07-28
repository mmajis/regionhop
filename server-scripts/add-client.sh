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

# Assign client IPv4 address (if IPv4 subnet is enabled)
get_next_available_ipv4() {
  if [ "$HAS_IPV4_SUBNET" != "true" ] || [ -z "$VPN_SUBNET_IPV4_BASE" ]; then
    return 1  # IPv4 not enabled
  fi
  
  local subnet_base="$VPN_SUBNET_IPV4_BASE"
  local start_ip=2  # Server uses .1
  local max_ip=254
  
  # Extract used IPv4 IPs from wg0.conf (look for AllowedIPs = x.x.x.x/32)
  local used_ips=$(grep "AllowedIPs = " /etc/wireguard/wg0.conf | grep -E "[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/32" | sed "s/.*AllowedIPs = //" | sed "s|/32||")
  
  # Convert IPs to just the last octet for easier processing
  local used_octets=$(echo "$used_ips" | sed "s|$VPN_SUBNET_IPV4_BASE||g" | sort -n)
  
  # Find the first available IP
  for ip in $(seq $start_ip $max_ip); do
    if ! echo "$used_octets" | grep -qx "$ip"; then
      echo "${subnet_base}${ip}"
      return 0
    fi
  done
  
  # If no IP available, return error
  echo "ERROR: No available IPv4 IPs in subnet $VPN_SUBNET_IPV4" >&2
  return 1
}

# Assign client IPv6 address (if IPv6 subnet is enabled)
get_next_available_ipv6() {
  if [ "$HAS_IPV6_SUBNET" != "true" ] || [ -z "$VPN_SUBNET_IPV6" ]; then
    return 1  # IPv6 not enabled
  fi
  
  # For IPv6, we'll use a simple sequential assignment starting from ::2
  # Extract the prefix from VPN_SUBNET_IPV6 (e.g., "fd42:42:42::" from "fd42:42:42::/64")
  local ipv6_prefix=$(echo "$VPN_SUBNET_IPV6" | sed 's|/64||')
  local start_ip=2
  local max_ip=65534  # Reasonable limit for client IPs
  
  # Extract used IPv6 IPs from wg0.conf (look for AllowedIPs with IPv6)
  local used_ips=$(grep "AllowedIPs = " /etc/wireguard/wg0.conf | grep -E "[0-9a-fA-F:]+/128" | sed "s/.*AllowedIPs = //" | sed "s|/128||")
  
  # Find the first available IP
  for ip in $(seq $start_ip $max_ip); do
    local test_ip="${ipv6_prefix}${ip}"
    if ! echo "$used_ips" | grep -qx "$test_ip"; then
      echo "$test_ip"
      return 0
    fi
  done
  
  # If no IP available, return error
  echo "ERROR: No available IPv6 IPs in subnet $VPN_SUBNET_IPV6" >&2
  return 1
}

# Get client addresses
CLIENT_IPV4=""
CLIENT_IPV6=""

if [ "$HAS_IPV4_SUBNET" = "true" ]; then
  CLIENT_IPV4=$(get_next_available_ipv4)
  if [ $? -ne 0 ]; then
    echo "Failed to assign IPv4 address" >&2
    exit 1
  fi
fi

if [ "$HAS_IPV6_SUBNET" = "true" ]; then
  CLIENT_IPV6=$(get_next_available_ipv6)
  if [ $? -ne 0 ]; then
    echo "Failed to assign IPv6 address" >&2
    exit 1
  fi
fi

# Ensure at least one IP address is assigned
if [ -z "$CLIENT_IPV4" ] && [ -z "$CLIENT_IPV6" ]; then
  echo "ERROR: No IP subnets are configured" >&2
  exit 1
fi

# Build client address list
CLIENT_ADDRESSES=()
if [ -n "$CLIENT_IPV4" ]; then
  CLIENT_ADDRESSES+=("$CLIENT_IPV4/24")
fi
if [ -n "$CLIENT_IPV6" ]; then
  CLIENT_ADDRESSES+=("$CLIENT_IPV6/64")
fi

# Build AllowedIPs for client (route all traffic through VPN)
CLIENT_ALLOWED_IPS="0.0.0.0/0"
if [ "$HAS_IPV6_SUBNET" = "true" ]; then
  CLIENT_ALLOWED_IPS="0.0.0.0/0, ::/0"
fi

# Build AllowedIPs for server config (client's assigned IPs)
SERVER_ALLOWED_IPS=()
if [ -n "$CLIENT_IPV4" ]; then
  SERVER_ALLOWED_IPS+=("$CLIENT_IPV4/32")
fi
if [ -n "$CLIENT_IPV6" ]; then
  SERVER_ALLOWED_IPS+=("$CLIENT_IPV6/128")
fi

# Create client configuration
cat > ${CLIENT_NAME}.conf << CLIENTEOF
[Interface]
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $(IFS=', '; echo "${CLIENT_ADDRESSES[*]}")
DNS = 1.1.1.1, 8.8.8.8, 2606:4700:4700::1111, 2606:4700:4700::1001

[Peer]
PublicKey = $SERVER_PUBLIC_KEY
Endpoint = $SERVER_ENDPOINT:$VPN_PORT
AllowedIPs = $CLIENT_ALLOWED_IPS
PersistentKeepalive = 25
CLIENTEOF

# Add client to server configuration
cat >> /etc/wireguard/wg0.conf << CLIENTEOF

[Peer]
PublicKey = $CLIENT_PUBLIC_KEY
AllowedIPs = $(IFS=', '; echo "${SERVER_ALLOWED_IPS[*]}")
CLIENTEOF

# Restart WireGuard to apply changes
systemctl restart wg-quick@wg0

echo "Client $CLIENT_NAME created successfully!"
echo "Configuration file: $CLIENT_DIR/${CLIENT_NAME}.conf"
qrencode -t ansiutf8 < $CLIENT_DIR/${CLIENT_NAME}.conf > "$CLIENT_DIR/${CLIENT_NAME}.conf.qr"
echo "QR Code:"
cat "$CLIENT_DIR/${CLIENT_NAME}.conf.qr"

# Backup updated configuration to S3
aws s3 sync /etc/wireguard s3://$S3_BUCKET/wireguard-config/ --exclude "*.tmp" --region $AWS_REGION
echo "Configuration backed up to S3"