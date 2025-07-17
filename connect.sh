#!/bin/bash

# WireGuard VPN Connection Helper Script
# This script helps you connect to your WireGuard VPN server
#
# Note: This script works with the two-stack architecture:
# - OwnvpnInfrastructureStack: Contains VPC, security groups, IAM roles, key pairs
# - OwnvpnComputeStack: Contains EC2 instance and Elastic IP
#
# Both stacks must be deployed for this script to work properly.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if both stacks are deployed
check_stacks() {
    print_status "Checking stack deployments..."
    
    # Check infrastructure stack
    if ! aws cloudformation describe-stacks --stack-name OwnvpnInfrastructureStack --region eu-central-1 >/dev/null 2>&1; then
        print_error "Infrastructure stack (OwnvpnInfrastructureStack) not found."
        print_error "Please deploy the infrastructure stack first using: ./deploy.sh"
        return 1
    fi
    
    # Check compute stack
    if ! aws cloudformation describe-stacks --stack-name OwnvpnComputeStack --region eu-central-1 >/dev/null 2>&1; then
        print_error "Compute stack (OwnvpnComputeStack) not found."
        print_error "Please deploy the compute stack using: ./deploy.sh or ./compute-stack-manager.sh deploy"
        return 1
    fi
    
    print_success "Both stacks are deployed."
}

# Get VPN server IP from compute stack outputs
get_server_ip() {
    local server_ip=$(aws cloudformation describe-stacks \
        --stack-name OwnvpnComputeStack \
        --region eu-central-1 \
        --query 'Stacks[0].Outputs[?OutputKey==`VPNServerIP`].OutputValue' \
        --output text 2>/dev/null)
    
    if [ -z "$server_ip" ] || [ "$server_ip" = "None" ]; then
        print_error "Could not retrieve server IP. Is the compute stack deployed?"
        return 1
    fi
    
    echo "$server_ip"
}

# Ensure SSH key exists
ensure_ssh_key() {
    if [ ! -f "wireguard-vpn-key.pem" ]; then
        print_status "SSH key not found. Retrieving from AWS Systems Manager..."
        
        local key_pair_id=$(aws cloudformation describe-stacks \
            --stack-name OwnvpnInfrastructureStack \
            --region eu-central-1 \
            --query 'Stacks[0].Outputs[?OutputKey==`KeyPairId`].OutputValue' \
            --output text 2>/dev/null)
        
        if [ -z "$key_pair_id" ] || [ "$key_pair_id" = "None" ]; then
            print_error "Could not retrieve key pair ID from infrastructure stack outputs"
            return 1
        fi
        
        aws ssm get-parameter \
            --name "/ec2/keypair/${key_pair_id}" \
            --with-decryption \
            --query Parameter.Value \
            --output text \
            --region eu-central-1 > wireguard-vpn-key.pem
        
        chmod 600 wireguard-vpn-key.pem
        print_success "SSH key retrieved and saved as wireguard-vpn-key.pem"
    fi
}

# SSH to server
ssh_to_server() {
    local server_ip=$(get_server_ip)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    ensure_ssh_key
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_status "Connecting to VPN server at $server_ip..."
    ssh -i wireguard-vpn-key.pem ubuntu@"$server_ip"
}

# Get client configuration
get_client_config() {
    local server_ip=$(get_server_ip)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    ensure_ssh_key
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_status "Retrieving client configuration from server..."
    ssh -i wireguard-vpn-key.pem ubuntu@"$server_ip" \
        "sudo cat /etc/wireguard/clients/macos-client/macos-client.conf" > macos-client.conf
    
    if [ $? -eq 0 ]; then
        print_success "Client configuration saved as macos-client.conf"
        echo
        print_status "To import to WireGuard app:"
        echo "1. Open WireGuard app on macOS"
        echo "2. Click 'Import tunnel(s) from file'"
        echo "3. Select the macos-client.conf file"
        echo "4. Click 'Import' and then toggle to connect"
    else
        print_error "Failed to retrieve client configuration"
        return 1
    fi
}

# Check VPN status
check_vpn_status() {
    local server_ip=$(get_server_ip)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    ensure_ssh_key
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_status "Checking VPN server status..."
    ssh -i wireguard-vpn-key.pem ubuntu@"$server_ip" \
        "sudo /etc/wireguard/vpn-status.sh"
}

# Add new client
add_client() {
    local client_name=$1
    
    if [ -z "$client_name" ]; then
        print_error "Client name is required"
        echo "Usage: $0 add-client <client-name>"
        return 1
    fi
    
    local server_ip=$(get_server_ip)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    ensure_ssh_key
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    print_status "Adding new client: $client_name"
    ssh -i wireguard-vpn-key.pem ubuntu@"$server_ip" \
        "sudo /etc/wireguard/add-client.sh $client_name"
    
    if [ $? -eq 0 ]; then
        print_success "Client $client_name added successfully"
        print_status "Downloading client configuration..."
        
        ssh -i wireguard-vpn-key.pem ubuntu@"$server_ip" \
            "sudo cat /etc/wireguard/clients/$client_name/$client_name.conf" > "$client_name.conf"
        
        if [ $? -eq 0 ]; then
            print_success "Client configuration saved as $client_name.conf"
        fi
    else
        print_error "Failed to add client"
        return 1
    fi
}

# Show usage
usage() {
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  ssh                     SSH into the VPN server"
    echo "  config                  Download client configuration"
    echo "  status                  Check VPN server status"
    echo "  add-client <name>       Add a new VPN client"
    echo "  help                    Show this help message"
    echo
    echo "Examples:"
    echo "  $0 ssh"
    echo "  $0 config"
    echo "  $0 status"
    echo "  $0 add-client iphone"
}

# Main function
main() {
    case "$1" in
        ssh)
            ssh_to_server
            ;;
        config)
            get_client_config
            ;;
        status)
            check_vpn_status
            ;;
        add-client)
            add_client "$2"
            ;;
        help)
            usage
            ;;
        *)
            if [ -z "$1" ]; then
                print_error "No command specified"
            else
                print_error "Unknown command: $1"
            fi
            usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"