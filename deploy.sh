#!/bin/bash

# WireGuard VPN Service Deployment Script
# This script automates the deployment of your personal WireGuard VPN service

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

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists node; then
        print_error "Node.js is not installed. Please install Node.js v18 or later."
        exit 1
    fi
    
    if ! command_exists npm; then
        print_error "npm is not installed. Please install npm."
        exit 1
    fi
    
    if ! command_exists aws; then
        print_error "AWS CLI is not installed. Please install AWS CLI."
        exit 1
    fi
    
    if ! command_exists cdk; then
        print_error "AWS CDK is not installed. Installing globally..."
        npm install -g aws-cdk
    fi
    
    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials are not configured. Please run 'aws configure'."
        exit 1
    fi
    
    print_success "All prerequisites are met!"
}

# Install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    npm install
    print_success "Dependencies installed successfully!"
}

# Bootstrap CDK
bootstrap_cdk() {
    print_status "Bootstrapping CDK for eu-central-1..."
    cdk bootstrap --region eu-central-1
    print_success "CDK bootstrapped successfully!"
}

# Build the project
build_project() {
    print_status "Building the project..."
    npm run build
    print_success "Project built successfully!"
}

# Deploy the stacks
deploy_stack() {
    print_status "Deploying WireGuard VPN stacks..."
    print_warning "This will create AWS resources that may incur charges (~$10-15/month)."
    
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled."
        exit 0
    fi
    
    print_status "Deploying infrastructure stack first..."
    cdk deploy OwnvpnInfrastructureStack --require-approval never
    print_success "Infrastructure stack deployed successfully!"
    
    print_status "Deploying compute stack..."
    cdk deploy OwnvpnComputeStack --require-approval never
    print_success "Compute stack deployed successfully!"
}

# Extract outputs
extract_outputs() {
    print_status "Extracting deployment outputs..."
    
    # Get infrastructure stack outputs
    INFRA_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name OwnvpnInfrastructureStack \
        --region eu-central-1 \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo "[]")
    
    # Get compute stack outputs
    COMPUTE_OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name OwnvpnComputeStack \
        --region eu-central-1 \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$INFRA_OUTPUTS" = "[]" ] || [ "$COMPUTE_OUTPUTS" = "[]" ]; then
        print_warning "Could not retrieve stack outputs. Please check AWS Console."
        return 1
    fi
    
    # Extract specific outputs from both stacks
    VPN_IP=$(echo $COMPUTE_OUTPUTS | jq -r '.[] | select(.OutputKey=="VPNServerIP") | .OutputValue')
    SSH_CMD=$(echo $COMPUTE_OUTPUTS | jq -r '.[] | select(.OutputKey=="SSHCommand") | .OutputValue')
    INSTANCE_ID=$(echo $COMPUTE_OUTPUTS | jq -r '.[] | select(.OutputKey=="VPNServerInstanceId") | .OutputValue')
    KEY_PAIR_ID=$(echo $INFRA_OUTPUTS | jq -r '.[] | select(.OutputKey=="KeyPairId") | .OutputValue')
    GET_KEY_CMD=$(echo $INFRA_OUTPUTS | jq -r '.[] | select(.OutputKey=="GetPrivateKeyCommand") | .OutputValue')
    
    # Create outputs file
    cat > deployment-outputs.txt << EOF
WireGuard VPN Service - Deployment Outputs
==========================================

VPN Server IP: $VPN_IP
Instance ID: $INSTANCE_ID
Key Pair ID: $KEY_PAIR_ID

SSH Connection Steps:
1. Run: $GET_KEY_CMD
2. Then: $SSH_CMD

Client Configuration: /etc/wireguard/clients/macos-client/macos-client.conf
VPN Status Command: sudo /etc/wireguard/vpn-status.sh

Important Notes:
- The private key is stored in AWS Systems Manager Parameter Store
- The server needs 2-3 minutes to complete setup after deployment
- Client configuration will be ready after server initialization
EOF
    
    print_success "Deployment outputs saved to deployment-outputs.txt"
}

# Retrieve private key from AWS Systems Manager
retrieve_private_key() {
    print_status "Retrieving private key from AWS Systems Manager..."
    
    # Get infrastructure stack outputs
    OUTPUTS=$(aws cloudformation describe-stacks \
        --stack-name OwnvpnInfrastructureStack \
        --region eu-central-1 \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null || echo "[]")
    
    if [ "$OUTPUTS" = "[]" ]; then
        print_warning "Could not retrieve stack outputs."
        return 1
    fi
    
    KEY_PAIR_ID=$(echo $OUTPUTS | jq -r '.[] | select(.OutputKey=="KeyPairId") | .OutputValue')
    
    if [ -z "$KEY_PAIR_ID" ] || [ "$KEY_PAIR_ID" = "null" ]; then
        print_warning "Key pair ID not found in outputs."
        return 1
    fi
    
    # Retrieve private key from Systems Manager
    aws ssm get-parameter \
        --name "/ec2/keypair/${KEY_PAIR_ID}" \
        --with-decryption \
        --query Parameter.Value \
        --output text \
        --region eu-central-1 > wireguard-vpn-key.pem
    
    if [ $? -eq 0 ]; then
        chmod 600 wireguard-vpn-key.pem
        print_success "Private key saved to wireguard-vpn-key.pem"
    else
        print_error "Failed to retrieve private key from Systems Manager"
        return 1
    fi
}

# Create client setup instructions
create_client_instructions() {
    print_status "Creating client setup instructions..."
    
    cat > client-setup.md << EOF
# WireGuard VPN Client Setup for macOS

## Step 1: Wait for Server Setup
The server needs 2-3 minutes to complete setup after deployment.

## Step 2: Download WireGuard App
Download the official WireGuard app from the Mac App Store.

## Step 3: Get SSH Key
1. Go to AWS Console > EC2 > Key Pairs
2. Find "wireguard-vpn-key"
3. Download the private key file (.pem)

## Step 4: SSH into Server
\`\`\`bash
chmod 600 wireguard-vpn-key.pem
ssh -i wireguard-vpn-key.pem ubuntu@$VPN_IP
\`\`\`

## Step 5: Get Client Configuration
\`\`\`bash
sudo cat /etc/wireguard/clients/macos-client/macos-client.conf
\`\`\`

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
\`\`\`bash
sudo /etc/wireguard/vpn-status.sh
\`\`\`
EOF
    
    print_success "Client setup instructions saved to client-setup.md"
}

# Main deployment function
main() {
    print_status "Starting WireGuard VPN Service deployment..."
    echo
    
    check_prerequisites
    install_dependencies
    bootstrap_cdk
    build_project
    deploy_stack
    
    print_status "Waiting for stack deployment to complete..."
    sleep 5
    
    extract_outputs
    retrieve_private_key
    create_client_instructions
    
    echo
    print_success "🎉 WireGuard VPN Service deployed successfully!"
    echo
    print_status "Next steps:"
    echo "1. SSH key is now available as wireguard-vpn-key.pem"
    echo "2. Read deployment-outputs.txt for connection details"
    echo "3. Follow client-setup.md for macOS client configuration"
    echo "4. Wait 2-3 minutes for server initialization to complete"
    echo
    print_warning "Remember: This service will incur AWS charges (~$10-15/month)"
    echo "To destroy the stack: cdk destroy"
}

# Cleanup function
cleanup() {
    print_status "Cleaning up deployment..."
    read -p "Are you sure you want to destroy the VPN service? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_status "Destroying compute stack first..."
        cdk destroy OwnvpnComputeStack --force
        print_success "Compute stack destroyed successfully!"
        
        print_status "Destroying infrastructure stack..."
        cdk destroy OwnvpnInfrastructureStack --force
        print_success "Infrastructure stack destroyed successfully!"
        
        print_success "VPN service destroyed successfully!"
    else
        print_warning "Cleanup cancelled."
    fi
}

# Script usage
usage() {
    echo "Usage: $0 [command]"
    echo
    echo "Commands:"
    echo "  deploy    Deploy the WireGuard VPN service (default)"
    echo "  destroy   Destroy the VPN service and all resources"
    echo "  status    Check the deployment status"
    echo "  help      Show this help message"
    echo
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 destroy"
    echo "  $0 status"
}

# Check deployment status
check_status() {
    print_status "Checking deployment status..."
    
    # Check infrastructure stack
    if aws cloudformation describe-stacks --stack-name OwnvpnInfrastructureStack --region eu-central-1 >/dev/null 2>&1; then
        INFRA_STATUS=$(aws cloudformation describe-stacks \
            --stack-name OwnvpnInfrastructureStack \
            --region eu-central-1 \
            --query 'Stacks[0].StackStatus' \
            --output text)
        
        print_success "Infrastructure Stack Status: $INFRA_STATUS"
    else
        print_warning "Infrastructure stack is not deployed."
        return 1
    fi
    
    # Check compute stack
    if aws cloudformation describe-stacks --stack-name OwnvpnComputeStack --region eu-central-1 >/dev/null 2>&1; then
        COMPUTE_STATUS=$(aws cloudformation describe-stacks \
            --stack-name OwnvpnComputeStack \
            --region eu-central-1 \
            --query 'Stacks[0].StackStatus' \
            --output text)
        
        print_success "Compute Stack Status: $COMPUTE_STATUS"
        
        if [ "$COMPUTE_STATUS" = "CREATE_COMPLETE" ] || [ "$COMPUTE_STATUS" = "UPDATE_COMPLETE" ]; then
            extract_outputs
        fi
    else
        print_warning "Compute stack is not deployed."
    fi
}

# Parse command line arguments
case "${1:-deploy}" in
    deploy)
        main
        ;;
    destroy)
        cleanup
        ;;
    status)
        check_status
        ;;
    help)
        usage
        ;;
    *)
        print_error "Unknown command: $1"
        usage
        exit 1
        ;;
esac