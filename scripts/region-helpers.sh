#!/bin/bash

# Shared helper functions for region management
# This file contains common functions used by deploy.sh, connect.sh, and region-manager.sh

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
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Load regions from regions.json
load_regions() {
    if [ ! -f "regions.json" ]; then
        print_error "regions.json not found" >&2
        return 1
    fi

    cat regions.json | jq -r '.supportedRegions[].code' 2>/dev/null || {
        print_error "Failed to parse regions.json or jq not installed" >&2
        return 1
    }
}

# Get default region
get_default_region() {
    if [ ! -f "regions.json" ]; then
        echo "eu-central-1"
        return
    fi

    cat regions.json | jq -r '.defaultRegion' 2>/dev/null || echo "eu-central-1"
}

# Get region info
get_region_info() {
    local region=$1
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    if [ ! -f "regions.json" ]; then
        print_error "regions.json not found"
        return 1
    fi

    cat regions.json | jq -r ".supportedRegions[] | select(.code == \"$region\")" 2>/dev/null
}

# Validate region
validate_region() {
    local region=$1
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    local supported_regions=$(load_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi

    if echo "$supported_regions" | grep -q "^$region$"; then
        return 0
    else
        print_error "Unsupported region: $region"
        print_error "Supported regions: $(echo "$supported_regions" | tr '\n' ' ')"
        return 1
    fi
}

# Get region-aware stack name
get_stack_name() {
    local base_name=$1
    local region=$2

    if [ -z "$base_name" ] || [ -z "$region" ]; then
        print_error "Both base_name and region parameters are required"
        return 1
    fi

    echo "OwnVPN-${region}-${base_name}"
}

# Check if stack exists
stack_exists() {
    local stack_name=$1
    local region=$2

    if [ -z "$stack_name" ] || [ -z "$region" ]; then
        print_error "Both stack_name and region parameters are required"
        return 1
    fi

    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$region" >/dev/null 2>&1
}

# Get stack status
get_stack_status() {
    local stack_name=$1
    local region=$2

    if [ -z "$stack_name" ] || [ -z "$region" ]; then
        print_error "Both stack_name and region parameters are required"
        return 1
    fi

    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].StackStatus' \
        --output text 2>/dev/null
}

# Get stack outputs
get_stack_outputs() {
    local stack_name=$1
    local region=$2

    if [ -z "$stack_name" ] || [ -z "$region" ]; then
        print_error "Both stack_name and region parameters are required"
        return 1
    fi

    aws cloudformation describe-stacks \
        --stack-name "$stack_name" \
        --region "$region" \
        --query 'Stacks[0].Outputs' \
        --output json 2>/dev/null
}

# Get VPN server DNS name for region
get_vpn_server_dns() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    # Get domain from regions.json
    local domain=$(cat regions.json | jq -r '.domain' 2>/dev/null || echo "majakorpi.net")
    echo "${region}.vpn.${domain}"
}

# Get VPN server IP (now uses DNS resolution)
get_vpn_server_ip() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    # Check if DNS management is enabled by looking at compute stack outputs
    local compute_stack=$(get_stack_name "Compute" "$region")
    local outputs=$(get_stack_outputs "$compute_stack" "$region")

    if [ -z "$outputs" ] || [ "$outputs" = "null" ]; then
        print_error "Could not retrieve stack outputs for region $region"
        return 1
    fi

    # Check if we have a VPNServerDomain output (DNS management enabled)
    local dns_domain=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNServerDomain") | .OutputValue' 2>/dev/null)

    if [ -n "$dns_domain" ] && [ "$dns_domain" != "null" ]; then
        # DNS management is enabled, resolve the DNS name to get current IP
        if command -v dig >/dev/null 2>&1; then
            local resolved_ip=$(dig +short "$dns_domain" | tail -n1)
            if [ -n "$resolved_ip" ] && [[ "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$resolved_ip"
                return 0
            fi
        elif command -v nslookup >/dev/null 2>&1; then
            local resolved_ip=$(nslookup "$dns_domain" | awk '/^Address: / { print $2 }' | tail -n1)
            if [ -n "$resolved_ip" ] && [[ "$resolved_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                echo "$resolved_ip"
                return 0
            fi
        fi

        # If DNS resolution failed, return the DNS name itself
        echo "$dns_domain"
        return 0
    fi

    # Fallback: try to get IP from stack outputs (legacy behavior)
    local stack_ip=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNServerIP") | .OutputValue' 2>/dev/null)
    if [ -n "$stack_ip" ] && [ "$stack_ip" != "null" ] && [ "$stack_ip" != "Dynamic IP - Check DNS record or ASG instances" ]; then
        echo "$stack_ip"
    else
        # Last resort: return the DNS name
        get_vpn_server_dns "$region"
    fi
}

# Get SSH key for region
get_ssh_key() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    local key_file="wireguard-vpn-key-${region}.pem"

    if [ ! -f "$key_file" ]; then
        print_status "SSH key not found for region $region. Retrieving from AWS Systems Manager..."

        local infra_stack=$(get_stack_name "Infrastructure" "$region")
        local outputs=$(get_stack_outputs "$infra_stack" "$region")

        if [ -z "$outputs" ] || [ "$outputs" = "null" ]; then
            print_error "Could not retrieve infrastructure stack outputs for region $region"
            return 1
        fi

        local key_pair_id=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="KeyPairId") | .OutputValue' 2>/dev/null)

        if [ -z "$key_pair_id" ] || [ "$key_pair_id" = "null" ]; then
            print_error "Could not retrieve key pair ID for region $region"
            return 1
        fi

        aws ssm get-parameter \
            --name "/ec2/keypair/${key_pair_id}" \
            --with-decryption \
            --query Parameter.Value \
            --output text \
            --region "$region" > "$key_file"

        if [ $? -eq 0 ]; then
            chmod 600 "$key_file"
            print_success "SSH key retrieved and saved as $key_file"
        else
            print_error "Failed to retrieve SSH key for region $region"
            return 1
        fi
    fi

    echo "$key_file"
}

# List deployed regions
list_deployed_regions() {
    local regions=$(load_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi

    local deployed_regions=()

    for region in $regions; do
        # Skip empty lines or error messages that might contain brackets
        if [ -z "$region" ] || [[ "$region" == *"["* ]]; then
            continue
        fi

        local infra_stack=$(get_stack_name "Infrastructure" "$region")
        local compute_stack=$(get_stack_name "Compute" "$region")

        if stack_exists "$infra_stack" "$region" && stack_exists "$compute_stack" "$region"; then
            deployed_regions+=("$region")
        fi
    done

    if [ ${#deployed_regions[@]} -eq 0 ]; then
        print_warning "No deployed regions found"
        return 1
    fi

    printf '%s\n' "${deployed_regions[@]}"
}

# Show region deployment status
show_region_status() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    local region_info=$(get_region_info "$region")
    local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)

    echo
    print_status "Status for region: $region ($region_name)"
    echo "============================================="

    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    # Check infrastructure stack
    if stack_exists "$infra_stack" "$region"; then
        local infra_status=$(get_stack_status "$infra_stack" "$region")
        print_success "Infrastructure Stack: $infra_status"
    else
        print_warning "Infrastructure Stack: NOT DEPLOYED"
    fi

    # Check compute stack
    if stack_exists "$compute_stack" "$region"; then
        local compute_status=$(get_stack_status "$compute_stack" "$region")
        print_success "Compute Stack: $compute_status"

        # If compute stack is healthy, show VPN server details
        if [ "$compute_status" = "CREATE_COMPLETE" ] || [ "$compute_status" = "UPDATE_COMPLETE" ]; then
            local vpn_ip=$(get_vpn_server_ip "$region")
            if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
                print_success "VPN Server IP: $vpn_ip"
            fi
        fi
    else
        print_warning "Compute Stack: NOT DEPLOYED"
    fi

    echo
}

# Check if region is bootstrapped for CDK
is_region_bootstrapped() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    aws cloudformation describe-stacks \
        --stack-name "CDKToolkit" \
        --region "$region" >/dev/null 2>&1
}

# Bootstrap region for CDK
bootstrap_region() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    if is_region_bootstrapped "$region"; then
        print_success "Region $region is already bootstrapped"
        return 0
    fi

    print_status "Bootstrapping CDK for region $region..."
    cdk bootstrap --region "$region"

    if [ $? -eq 0 ]; then
        print_success "Region $region bootstrapped successfully"
    else
        print_error "Failed to bootstrap region $region"
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    local missing_deps=()

    if ! command_exists node; then
        missing_deps+=("Node.js")
    fi

    if ! command_exists npm; then
        missing_deps+=("npm")
    fi

    if ! command_exists aws; then
        missing_deps+=("AWS CLI")
    fi

    if ! command_exists jq; then
        missing_deps+=("jq")
    fi

    if ! command_exists cdk; then
        print_warning "AWS CDK not found. Installing globally..."
        npm install -g aws-cdk
        if [ $? -ne 0 ]; then
            missing_deps+=("AWS CDK")
        fi
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        print_error "Please install the missing dependencies and try again."
        return 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        print_error "AWS credentials are not configured."
        print_error "Please run 'aws configure' or use your preferred method to set up your AWS credentials."
        return 1
    fi

    return 0
}

# Parse comma-separated regions
parse_regions() {
    local regions_string=$1

    if [ -z "$regions_string" ]; then
        print_error "Regions string parameter is required"
        return 1
    fi

    # Split by comma and validate each region
    local regions=($(echo "$regions_string" | tr ',' ' '))
    local valid_regions=()

    for region in "${regions[@]}"; do
        # Trim whitespace
        region=$(echo "$region" | xargs)

        if validate_region "$region"; then
            valid_regions+=("$region")
        else
            return 1
        fi
    done

    printf '%s\n' "${valid_regions[@]}"
}

# Destroy region deployment
destroy_region() {
    local region=$1
    local force=${2:-false}

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    local region_info=$(get_region_info "$region")
    local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)

    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    # Check if anything is deployed
    if ! stack_exists "$infra_stack" "$region" && ! stack_exists "$compute_stack" "$region"; then
        print_warning "No VPN deployment found in region $region"
        return 0
    fi

    # Confirmation prompt unless forced
    if [ "$force" != "true" ]; then
        print_warning "This will destroy the VPN service in region $region ($region_name)"
        print_warning "This action cannot be undone!"
        echo
        read -p "Are you sure you want to continue? (y/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Destruction cancelled."
            return 0
        fi
    fi

    # Set region environment variable for CDK
    export VPN_REGION="$region"

    # Destroy compute stack first (if exists)
    if stack_exists "$compute_stack" "$region"; then
        print_status "Destroying compute stack: $compute_stack"
        cdk destroy "$compute_stack" --force

        if [ $? -ne 0 ]; then
            print_error "Failed to destroy compute stack for region $region"
            return 1
        fi

        print_success "Compute stack destroyed successfully"
    fi

    # Destroy infrastructure stack (if exists)
    if stack_exists "$infra_stack" "$region"; then
        print_status "Destroying infrastructure stack: $infra_stack"
        cdk destroy "$infra_stack" --force

        if [ $? -ne 0 ]; then
            print_error "Failed to destroy infrastructure stack for region $region"
            return 1
        fi

        print_success "Infrastructure stack destroyed successfully"
    fi

    # Clean up SSH key file
    local key_file="wireguard-vpn-key-${region}.pem"
    if [ -f "$key_file" ]; then
        rm -f "$key_file"
        print_status "Cleaned up SSH key file: $key_file"
    fi

    print_success "VPN service destroyed successfully in region $region"
}

# Deploy to region
deploy_to_region() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    local region_info=$(get_region_info "$region")
    local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)

    print_status "Deploying VPN service to region: $region ($region_name)"

    # Bootstrap region if needed
    bootstrap_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    # Set region environment variable for CDK
    export VPN_REGION="$region"

    # Deploy infrastructure stack first
    print_status "Deploying infrastructure stack: $infra_stack"
    cdk deploy "$infra_stack" --require-approval never

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy infrastructure stack for region $region"
        return 1
    fi

    print_success "Infrastructure stack deployed successfully"

    # Deploy compute stack
    print_status "Deploying compute stack: $compute_stack"
    cdk deploy "$compute_stack" --require-approval never

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy compute stack for region $region"
        return 1
    fi

    print_success "Compute stack deployed successfully"
    print_success "VPN service deployed successfully to region $region"
}