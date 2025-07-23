#!/bin/bash

# Source environment variables
source "$(dirname "$0")/env.sh"

echo "=== WireGuard VPN Status ==="
echo "Server Status:"
systemctl is-active wg-quick@wg0
echo ""
echo "Connected Clients:"
wg show
echo ""
echo "Fail2ban Status:"
fail2ban-client status sshd