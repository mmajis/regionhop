#!/bin/bash

# Source environment variables
source "$(dirname "$0")/env.sh"

if [ -z "$1" ]; then
  echo "Usage: $0 <client-name>"
  exit 1
fi

CLIENT_NAME=$1
CLIENT_DIR="/etc/wireguard/clients/$CLIENT_NAME"

# Check if client exists
if [ ! -d "$CLIENT_DIR" ]; then
  echo "Error: Client $CLIENT_NAME does not exist" >&2
  exit 1
fi

# Get client public key for config removal
if [ ! -f "$CLIENT_DIR/client_public_key" ]; then
  echo "Warning: Client public key file not found, will remove by name pattern"
  CLIENT_PUBLIC_KEY=""
else
  CLIENT_PUBLIC_KEY=$(cat "$CLIENT_DIR/client_public_key")
fi

# Create backup of current config
cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.backup.$(date +%s)

# Remove client peer from server configuration
if [ -n "$CLIENT_PUBLIC_KEY" ]; then
  # Use grep to find the PublicKey line
  PEER_LINE=$(grep -n "PublicKey = $CLIENT_PUBLIC_KEY" /etc/wireguard/wg0.conf | cut -d: -f1)
  if [ -n "$PEER_LINE" ]; then
    # Find [Peer] section start (search backwards from PublicKey line)
    PEER_START=$(head -n $PEER_LINE /etc/wireguard/wg0.conf | tac | grep -n "^\[Peer\]$" | head -1 | cut -d: -f1)
    if [ -n "$PEER_START" ]; then
      PEER_START=$((PEER_LINE - PEER_START + 1))
      # Find next section or end of file
      PEER_END=$(tail -n +$((PEER_LINE + 1)) /etc/wireguard/wg0.conf | grep -n "^\[" | head -1 | cut -d: -f1)
      if [ -n "$PEER_END" ]; then
        PEER_END=$((PEER_LINE + PEER_END - 1))
      else
        PEER_END=$(wc -l < /etc/wireguard/wg0.conf)
      fi
      # Create new config without the peer section
      head -n $((PEER_START - 1)) /etc/wireguard/wg0.conf > /tmp/wg0_temp
      tail -n +$((PEER_END + 1)) /etc/wireguard/wg0.conf >> /tmp/wg0_temp
      mv /tmp/wg0_temp /etc/wireguard/wg0.conf
    fi
  fi
else
  echo "Warning: Could not remove peer from config - manual cleanup may be required"
fi

# Remove client directory and files
rm -rf "$CLIENT_DIR"

# Restart WireGuard to apply changes
systemctl restart wg-quick@wg0

# Backup updated configuration to S3
aws s3 sync /etc/wireguard s3://$S3_BUCKET/wireguard-config/ --exclude "*.tmp" --exclude "*.backup.*" --region $AWS_REGION --delete

echo "Client $CLIENT_NAME removed successfully!"
echo "WireGuard service restarted and configuration backed up to S3"