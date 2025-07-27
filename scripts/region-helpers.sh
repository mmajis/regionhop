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


# Get default region
get_default_region() {
    if [ ! -f "config.json" ]; then
        echo "eu-central-1"
        return
    fi

    cat config.json | jq -r '.defaultRegion' 2>/dev/null || echo "eu-central-1"
}


# Validate region (simplified - trust user input and AWS validation)
validate_region() {
    local region=$1
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    # No validation - let AWS handle invalid regions during deployment
    return 0
}

# Get region-aware stack name
get_stack_name() {
    local base_name=$1
    local region=$2

    if [ -z "$base_name" ] || [ -z "$region" ]; then
        print_error "Both base_name and region parameters are required"
        return 1
    fi

    echo "RegionHop-${region}-${base_name}"
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
}

# Get SSH key for region
get_ssh_key() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    local key_file="regionhop-vpn-key-${region}.pem"

    if [ ! -f "$key_file" ]; then
        # print_status "SSH key not found for region $region. Retrieving from AWS Systems Manager..."

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
            # print_success "SSH key retrieved and saved as $key_file"
            sync  # Ensure the file is written to disk
        else
            print_error "Failed to retrieve SSH key for region $region"
            return 1
        fi
    fi

    echo "$key_file"
}

# List deployed regions (discover by checking AWS CloudFormation stacks)
list_deployed_regions() {
    local deployed_regions=()

    # Get all regions where we might have deployments
    local all_regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n')

    if [ $? -ne 0 ] || [ -z "$all_regions" ]; then
        print_error "Failed to get AWS regions list"
        return 1
    fi

    for region in $all_regions; do
        # Skip empty lines
        if [ -z "$region" ]; then
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

    echo
    print_status "Status for region: $region"
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

# Show comprehensive region status with detailed information
show_region_comprehensive_status() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    echo
    print_status "Comprehensive status for region: $region"
    echo "============================================="

    local status=$(get_region_comprehensive_status "$region")
    local vpn_ip=$(get_vpn_server_ip "$region")
    local desired_capacity=$(get_asg_desired_capacity "$region")

    case "$status" in
        "RUNNING")
            print_success "Status: RUNNING"
            print_success "VPN Server IP: $vpn_ip"
            print_success "Auto Scaling Group Capacity: $desired_capacity"
            print_success "VPN Port Response: Server responding on configured VPN port"
            ;;
        "STOPPED")
            print_warning "Status: STOPPED"
            print_warning "Auto Scaling Group Capacity: $desired_capacity (deployment complete but server not running)"
            if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
                print_status "Last Known VPN Server IP: $vpn_ip"
            fi
            ;;
        "UNHEALTHY")
            print_error "Status: UNHEALTHY"
            print_error "Auto Scaling Group Capacity: $desired_capacity"
            if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
                print_warning "VPN Server IP: $vpn_ip"
                print_error "VPN Port Response: Server not responding on configured VPN port"
            else
                print_error "VPN Server IP: Not available"
            fi
            ;;
        "UNDEPLOYED")
            print_warning "Status: UNDEPLOYED"
            print_warning "No RegionHop CloudFormation stacks found in this region"
            ;;
        *)
            print_error "Status: UNKNOWN"
            print_error "Unable to determine region status"
            ;;
    esac

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
    REGIONHOP_REGION="$region" npx cdk bootstrap 

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

    # Split by comma - no validation, trust user input
    local regions=($(echo "$regions_string" | tr ',' ' '))
    local clean_regions=()

    for region in "${regions[@]}"; do
        # Trim whitespace
        region=$(echo "$region" | xargs)

        if [ -n "$region" ]; then
            clean_regions+=("$region")
        fi
    done

    printf '%s\n' "${clean_regions[@]}"
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

    # Confirmation prompt unless forced
    if [ "$force" != "true" ]; then
        print_warning "This will destroy the VPN service in region $region"
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
    export REGIONHOP_REGION="$region"

    npx cdk destroy --all --require-approval never --force

    if [ $? -ne 0 ]; then
        print_error "Failed to destroy RegionHop in region $region"
        return 1
    fi

    # Clean up SSH key file
    local key_file="regionhop-vpn-key-${region}.pem"
    if [ -f "$key_file" ]; then
        rm -f "$key_file"
        print_status "Cleaned up SSH key file: $key_file"
    fi

    print_success "RegionHop destroyed successfully in region $region"
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

    print_status "Deploying RegionHop to region: $region"

    # Bootstrap region if needed
    bootstrap_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Set region environment variable for CDK
    export REGIONHOP_REGION="$region"

    npx cdk deploy --all --require-approval never

    if [ $? -ne 0 ]; then
        print_error "Failed to deploy to region $region"
        return 1
    fi

    print_success "VPN service deployed successfully to region $region"
}

# Check if VPN server responds on configured port
check_vpn_connectivity() {
    local region=$1
    local server_ip=$2
    local vpn_port

    if [ -z "$region" ] || [ -z "$server_ip" ]; then
        print_error "Both region and server_ip parameters are required"
        return 1
    fi

    # Get VPN port from config.json
    if [ -f "config.json" ]; then
        vpn_port=$(cat config.json | jq -r '.vpnPort' 2>/dev/null)
        if [ -z "$vpn_port" ] || [ "$vpn_port" = "null" ]; then
            vpn_port=51820  # Default WireGuard port
        fi
    else
        vpn_port=51820  # Default WireGuard port
    fi

    # Test UDP connectivity to VPN port using netcat or timeout
    if command -v nc >/dev/null 2>&1; then
        # Use netcat with timeout for UDP port check
        timeout 3 nc -u -z "$server_ip" "$vpn_port" >/dev/null 2>&1
        return $?
    else
        # Fallback: try to connect using /dev/udp (bash built-in)
        timeout 3 bash -c "echo > /dev/udp/$server_ip/$vpn_port" >/dev/null 2>&1
        return $?
    fi
}

# Get Auto Scaling Group desired capacity
get_asg_desired_capacity() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Get ASG name from compute stack outputs
    local compute_stack=$(get_stack_name "Compute" "$region")
    if ! stack_exists "$compute_stack" "$region"; then
        echo "0"  # No compute stack means capacity is effectively 0
        return 0
    fi

    local outputs=$(get_stack_outputs "$compute_stack" "$region")
    if [ -z "$outputs" ] || [ "$outputs" = "null" ]; then
        echo "0"
        return 0
    fi

    local asg_name=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNServerAutoScalingGroup") | .OutputValue' 2>/dev/null)
    if [ -z "$asg_name" ] || [ "$asg_name" = "null" ]; then
        echo "0"
        return 0
    fi

    # Get desired capacity from ASG
    local desired_capacity=$(aws autoscaling describe-auto-scaling-groups \
        --auto-scaling-group-names "$asg_name" \
        --region "$region" \
        --query 'AutoScalingGroups[0].DesiredCapacity' \
        --output text 2>/dev/null)

    if [ -z "$desired_capacity" ] || [ "$desired_capacity" = "None" ] || [ "$desired_capacity" = "null" ]; then
        echo "0"
    else
        echo "$desired_capacity"
    fi
}

# List deployed regions by checking for any CloudFormation stack starting with RegionHop
list_deployed_regions_by_stacks() {
    local deployed_regions=()

    # Get all regions where we might have deployments
    local all_regions=$(aws ec2 describe-regions --query 'Regions[].RegionName' --output text 2>/dev/null | tr '\t' '\n')

    if [ $? -ne 0 ] || [ -z "$all_regions" ]; then
        print_error "Failed to get AWS regions list"
        return 1
    fi

    for region in $all_regions; do
        # Skip empty lines
        if [ -z "$region" ]; then
            continue
        fi

        # Check if any stack starting with "RegionHop" exists in this region
        local regionhop_stacks=$(aws cloudformation list-stacks \
            --region "$region" \
            --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_IN_PROGRESS UPDATE_IN_PROGRESS \
            --query 'StackSummaries[?starts_with(StackName, `RegionHop`)].StackName' \
            --output text 2>/dev/null)

        if [ -n "$regionhop_stacks" ] && [ "$regionhop_stacks" != "None" ]; then
            deployed_regions+=("$region")
        fi
    done

    if [ ${#deployed_regions[@]} -eq 0 ]; then
        print_warning "No deployed regions found"
        return 1
    fi

    printf '%s\n' "${deployed_regions[@]}"
}

# Get comprehensive region status
get_region_comprehensive_status() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if any RegionHop stacks exist
    local regionhop_stacks=$(aws cloudformation list-stacks \
        --region "$region" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE CREATE_IN_PROGRESS UPDATE_IN_PROGRESS \
        --query 'StackSummaries[?starts_with(StackName, `RegionHop`)].StackName' \
        --output text 2>/dev/null)

    if [ -z "$regionhop_stacks" ] || [ "$regionhop_stacks" = "None" ]; then
        echo "UNDEPLOYED"
        return 0
    fi

    # Get ASG desired capacity
    local desired_capacity=$(get_asg_desired_capacity "$region")

    if [ "$desired_capacity" = "0" ]; then
        echo "STOPPED"
        return 0
    fi

    # Check if we can get the VPN server IP
    local vpn_ip=$(get_vpn_server_ip "$region")
    if [ -z "$vpn_ip" ] || [ "$vpn_ip" = "null" ]; then
        echo "UNHEALTHY"
        return 0
    fi

    # Test VPN connectivity
    if check_vpn_connectivity "$region" "$vpn_ip"; then
        echo "RUNNING"
    else
        echo "UNHEALTHY"
    fi
}