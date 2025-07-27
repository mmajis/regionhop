#!/bin/bash

# Source environment variables
source "$(dirname "$0")/env.sh"

echo "=== WireGuard VPN Status ==="
echo ""
echo "VPN Configuration:"
if [ "$HAS_IPV4_SUBNET" = "true" ]; then
  echo "  IPv4 Subnet: $VPN_SUBNET_IPV4"
  echo "  IPv4 Server: $VPN_SERVER_IPV4"
fi
if [ "$HAS_IPV6_SUBNET" = "true" ]; then
  echo "  IPv6 Subnet: $VPN_SUBNET_IPV6"
  echo "  IPv6 Server: $VPN_SERVER_IPV6"
fi
echo "  Port: $VPN_PORT"
echo "  Endpoint: $SERVER_ENDPOINT"
echo ""
echo "Server Status:"
systemctl is-active wg-quick@wg0
echo ""
echo "Connected Clients:"
wg show
echo ""
echo "Fail2ban Status:"
fail2ban-client status sshd