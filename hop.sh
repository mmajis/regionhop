#!/bin/bash
set -e

VERSION="1.0.0"

# Source shared helper functions
if [ -f "scripts/region-helpers.sh" ]; then
    source scripts/region-helpers.sh
else
    echo "Error: scripts/region-helpers.sh not found"
    exit 1
fi

# Global variables for deployment
DEPLOY_REGIONS=()
FORCE_DESTROY=false

#==========================================
# COMMAND IMPLEMENTATIONS
#==========================================

# Infrastructure Management Commands
cmd_deploy() {
    local target_regions=()

    # Parse deploy arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --regions)
                if [ -z "$2" ]; then
                    print_error "Regions parameter requires a value"
                    exit 1
                fi
                local regions=($(parse_regions "$2"))
                if [ $? -ne 0 ]; then
                    exit 1
                fi
                target_regions=("${regions[@]}")
                shift 2
                ;;
            --help|-h)
                show_deploy_help
                return 0
                ;;
            *)
                if [ ${#target_regions[@]} -eq 0 ]; then
                    validate_region "$1"
                    if [ $? -ne 0 ]; then
                        exit 1
                    fi
                    target_regions=("$1")
                else
                    print_error "Unknown option: $1"
                    show_deploy_help
                    exit 1
                fi
                shift
                ;;
        esac
    done

    # If no regions specified, use default
    if [ ${#target_regions[@]} -eq 0 ]; then
        target_regions=($(get_default_region))
    fi

    # Check prerequisites
    check_prerequisites
    if [ $? -ne 0 ]; then
        exit 1
    fi

    deploy_multiple_regions "${target_regions[@]}"
}

cmd_destroy() {
    local region=$1
    local force=false

    if [ "$2" = "--force" ]; then
        force=true
    fi

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop destroy <region> [--force]"
        return 1
    fi

    destroy_region "$region" "$force"
}

cmd_bootstrap() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop bootstrap <region>"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check prerequisites
    check_prerequisites
    if [ $? -ne 0 ]; then
        return 1
    fi

    bootstrap_region "$region"
}

# Status & Information Commands
cmd_list() {
    print_warning "Region listing is no longer available since supportedRegions was removed."
    print_status "Use 'hop deployed' to see deployed regions, or specify any AWS region directly."
    echo
    print_status "Example regions you can use:"
    echo "  us-east-1      - US East (N. Virginia)"
    echo "  us-west-2      - US West (Oregon)"
    echo "  eu-central-1   - Europe (Frankfurt)"
    echo "  ap-southeast-1 - Asia Pacific (Singapore)"
    echo "  ap-northeast-1 - Asia Pacific (Tokyo)"
    echo
    print_status "For deployed regions: hop deployed"
}

cmd_deployed() {
    print_status "Deployed VPN regions:"
    echo

    local deployed_regions=$(list_deployed_regions_by_stacks)
    if [ $? -ne 0 ]; then
        return 1
    fi

    for region in $deployed_regions; do
        local status=$(get_region_comprehensive_status "$region")
        local vpn_ip=$(get_vpn_server_ip "$region")

        case "$status" in
            "RUNNING")
                print_success "$region ($vpn_ip) - RUNNING"
                ;;
            "STOPPED")
                print_warning "$region - STOPPED"
                ;;
            "UNHEALTHY")
                if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
                    print_error "$region ($vpn_ip) - UNHEALTHY"
                else
                    print_error "$region - UNHEALTHY"
                fi
                ;;
            *)
                print_warning "$region - $status"
                ;;
        esac
    done

    echo
    print_status "Use 'hop status' for detailed status information"
    print_status "Use 'hop ssh <region>' to connect to a specific region"
}

cmd_regions() {
    print_warning "Region listing is no longer available since supportedRegions was removed."
    print_status "You can now use any valid AWS region directly with hop commands."
    echo
    print_status "Popular AWS regions:"
    echo "  us-east-1      - US East (N. Virginia)"
    echo "  us-west-1      - US West (N. California)"
    echo "  us-west-2      - US West (Oregon)"
    echo "  eu-west-1      - Europe (Ireland)"
    echo "  eu-central-1   - Europe (Frankfurt)"
    echo "  ap-southeast-1 - Asia Pacific (Singapore)"
    echo "  ap-northeast-1 - Asia Pacific (Tokyo)"
    echo "  ap-south-1     - Asia Pacific (Mumbai)"
    echo
    print_status "Default region: $(get_default_region)"
    print_status "For deployed regions: hop deployed"
}

cmd_status() {
    local region=$1

    if [ -n "$region" ]; then
        # Show status for specific region
        validate_region "$region"
        if [ $? -ne 0 ]; then
            return 1
        fi

        show_region_comprehensive_status "$region"
    else
        # Show status for all deployed regions (discovered automatically)
        print_status "VPN status across all deployed regions:"
        echo

        local deployed_regions=$(list_deployed_regions_by_stacks)
        if [ $? -ne 0 ]; then
            print_warning "No VPN deployments found in any region"
            return 1
        fi

        local running_count=0
        local stopped_count=0
        local unhealthy_count=0
        local total_count=0

        for region in $deployed_regions; do
            local status=$(get_region_comprehensive_status "$region")
            local vpn_ip=$(get_vpn_server_ip "$region")

            total_count=$((total_count + 1))

            case "$status" in
                "RUNNING")
                    print_success "  $region: RUNNING ($vpn_ip)"
                    running_count=$((running_count + 1))
                    ;;
                "STOPPED")
                    print_warning "  $region: STOPPED (Auto scaling group capacity is 0)"
                    stopped_count=$((stopped_count + 1))
                    ;;
                "UNHEALTHY")
                    print_error "  $region: UNHEALTHY (Server not responding on VPN port)"
                    unhealthy_count=$((unhealthy_count + 1))
                    ;;
                "UNDEPLOYED")
                    # This shouldn't happen as we're listing deployed regions
                    print_warning "  $region: UNDEPLOYED"
                    ;;
                *)
                    print_error "  $region: UNKNOWN STATUS"
                    unhealthy_count=$((unhealthy_count + 1))
                    ;;
            esac
        done

        echo
        print_status "Status Summary:"
        print_success "RUNNING: $running_count"
        print_warning "STOPPED: $stopped_count"
        print_error "UNHEALTHY: $unhealthy_count"
        echo "Total deployed regions: $total_count"
    fi
}

# Connection & Access Commands
cmd_ssh() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop ssh <region>"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if region is deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    if ! stack_exists "$infra_stack" "$region" || ! stack_exists "$compute_stack" "$region"; then
        print_error "VPN service is not deployed in region $region"
        print_status "Available regions:"
        list_deployed_regions 2>/dev/null || print_warning "No regions deployed"
        return 1
    fi

    local server_ip=$(get_vpn_server_ip "$region")
    if [ -z "$server_ip" ] || [ "$server_ip" = "null" ]; then
        print_error "Could not retrieve server IP for region $region"
        return 1
    fi

    local key_file=$(get_ssh_key "$region")
    if [ $? -ne 0 ]; then
        return 1
    fi

    print_status "Connecting to VPN server in $region at $server_ip..."
    ssh -i "$key_file" ubuntu@"$server_ip"
}

cmd_list_clients() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop list-clients <region>"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if region is deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    if ! stack_exists "$infra_stack" "$region" || ! stack_exists "$compute_stack" "$region"; then
        print_error "VPN service is not deployed in region $region"
        return 1
    fi

    local server_ip=$(get_vpn_server_ip "$region")
    if [ -z "$server_ip" ] || [ "$server_ip" = "null" ]; then
        print_error "Could not retrieve server IP for region $region"
        return 1
    fi

    local key_file=$(get_ssh_key "$region")
    if [ $? -ne 0 ]; then
        return 1
    fi

    print_status "Listing VPN clients in region $region..."

    # Execute SSH command without command substitution to properly capture exit code
    local temp_file=$(mktemp)
    # Temporarily disable exit on error to capture SSH exit code
    set +e
    ssh -i "$key_file" ubuntu@"$server_ip" \
        "sudo find /etc/wireguard/clients -maxdepth 1 -type d -not -path '/etc/wireguard/clients' -exec basename {} \;" 2>/dev/null > "$temp_file"
    local ssh_exit_code=$?
    set -e
    if [ $ssh_exit_code -ne 0 ]; then
        rm -f "$temp_file"
        print_error "Failed to connect to VPN server in region $region or execute remote command"
        return 1
    fi
    # Sort the output after successful SSH
    local clients=$(sort "$temp_file")
    rm -f "$temp_file"
    echo $clients
    if [ -z "$clients" ]; then
        print_warning "No clients found in region $region"
        return 0
    fi

    echo "Available clients in $region:"
    echo "$clients" | while read -r client; do
        echo "  • $client"
    done
}

cmd_download_client() {
    local region=""
    local client_name=""
    local download_all=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all|-a)
                download_all=true
                shift
                ;;
            --help|-h)
                show_download_client_help
                return 0
                ;;
            *)
                if [ -z "$region" ]; then
                    region="$1"
                elif [ -z "$client_name" ] && [ "$download_all" = false ]; then
                    client_name="$1"
                else
                    print_error "Unknown option or too many arguments: $1"
                    show_download_client_help
                    return 1
                fi
                shift
                ;;
        esac
    done

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        show_download_client_help
        return 1
    fi

    if [ "$download_all" = false ] && [ -z "$client_name" ]; then
        print_error "Client name is required unless using --all flag"
        show_download_client_help
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if region is deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    if ! stack_exists "$infra_stack" "$region" || ! stack_exists "$compute_stack" "$region"; then
        print_error "VPN service is not deployed in region $region"
        return 1
    fi

    local server_ip=$(get_vpn_server_ip "$region")
    if [ -z "$server_ip" ] || [ "$server_ip" = "null" ]; then
        print_error "Could not retrieve server IP for region $region"
        return 1
    fi

    local key_file=$(get_ssh_key "$region")
    if [ $? -ne 0 ]; then
        return 1
    fi

    mkdir -p client-configs

    if [ "$download_all" = true ]; then
        print_status "Downloading all client configurations from region $region..."

        # Get list of all clients
        local clients=$(ssh -i "$key_file" ubuntu@"$server_ip" \
            "sudo find /etc/wireguard/clients -maxdepth 1 -type d -not -path '/etc/wireguard/clients' -exec basename {} \;" 2>/dev/null)

        if [ -z "$clients" ]; then
            print_warning "No clients found in region $region"
            return 0
        fi

        local download_count=0
        local failed_count=0

        echo "$clients" | while read -r client; do
            if [ -n "$client" ]; then
                local config_file="client-configs/${client}-${region}.conf"

                if ssh -i "$key_file" ubuntu@"$server_ip" \
                    "sudo cat /etc/wireguard/clients/$client/$client.conf" > "$config_file" 2>/dev/null; then
                    print_success "Downloaded: $config_file"
                    download_count=$((download_count + 1))
                else
                    print_error "Failed to download configuration for client: $client"
                    failed_count=$((failed_count + 1))
                fi
            fi
        done

    else
        print_status "Downloading client configuration for '$client_name' from region $region..."

        # Check if client exists
        if ! ssh -i "$key_file" ubuntu@"$server_ip" \
            "sudo test -d /etc/wireguard/clients/$client_name" 2>/dev/null; then
            print_error "Client '$client_name' does not exist in region $region"
            print_status "Use 'hop list-clients $region' to see available clients"
            return 1
        fi

        local config_file="client-configs/${client_name}-${region}.conf"

        if ssh -i "$key_file" ubuntu@"$server_ip" \
            "sudo cat /etc/wireguard/clients/$client_name/$client_name.conf" > "$config_file"; then
            print_success "Client configuration saved as $config_file"
            echo
            print_status "To import to WireGuard app:"
            echo "1. Open WireGuard app"
            echo "2. Click 'Import tunnel(s) from file'"
            echo "3. Select the $config_file file"
            echo "4. Click 'Import' and then toggle to connect"
        else
            print_error "Failed to download client configuration for '$client_name'"
            return 1
        fi
    fi
}

cmd_add_client() {
    local region=$1
    local client_name=$2

    if [ -z "$region" ] || [ -z "$client_name" ]; then
        print_error "Both region and client name are required"
        echo "Usage: hop add-client <region> <client-name>"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if region is deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    if ! stack_exists "$infra_stack" "$region" || ! stack_exists "$compute_stack" "$region"; then
        print_error "VPN service is not deployed in region $region"
        return 1
    fi

    local server_ip=$(get_vpn_server_ip "$region")
    if [ -z "$server_ip" ] || [ "$server_ip" = "null" ]; then
        print_error "Could not retrieve server IP for region $region"
        return 1
    fi

    local key_file=$(get_ssh_key "$region")
    if [ $? -ne 0 ]; then
        return 1
    fi

    print_status "Adding new client '$client_name' to region $region..."
    ssh -i "$key_file" ubuntu@"$server_ip" \
        "sudo /etc/wireguard/add-client.sh $client_name"

    if [ $? -eq 0 ]; then
        print_success "Client $client_name added successfully to region $region"
        print_status "Downloading client configuration..."

        mkdir -p client-configs
        local config_file="client-configs/${client_name}-${region}.conf"
        ssh -i "$key_file" ubuntu@"$server_ip" \
            "sudo cat /etc/wireguard/clients/$client_name/$client_name.conf" > "$config_file"

        if [ $? -eq 0 ]; then
            print_success "Client configuration saved as $config_file"
        fi
    else
        print_error "Failed to add client to region $region"
        return 1
    fi
}

cmd_remove_client() {
    local region=$1
    local client_name=$2

    if [ -z "$region" ] || [ -z "$client_name" ]; then
        print_error "Both region and client name are required"
        echo "Usage: hop remove-client <region> <client-name>"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if region is deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")

    if ! stack_exists "$infra_stack" "$region" || ! stack_exists "$compute_stack" "$region"; then
        print_error "VPN service is not deployed in region $region"
        return 1
    fi

    local server_ip=$(get_vpn_server_ip "$region")
    if [ -z "$server_ip" ] || [ "$server_ip" = "null" ]; then
        print_error "Could not retrieve server IP for region $region"
        return 1
    fi

    local key_file=$(get_ssh_key "$region")
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if client exists first
    print_status "Checking if client '$client_name' exists in region $region..."
    if ! ssh -i "$key_file" ubuntu@"$server_ip" \
        "sudo test -d /etc/wireguard/clients/$client_name" 2>/dev/null; then
        print_error "Client '$client_name' does not exist in region $region"
        print_status "Use 'hop list-clients $region' to see available clients"
        return 1
    fi

    # Confirm removal
    echo
    print_warning "This will permanently remove client '$client_name' from region $region"
    print_warning "The following will be deleted:"
    echo "  • Client configuration files"
    echo "  • Client private/public keys"
    echo "  • WireGuard peer configuration"
    echo "  • S3 backup data"
    echo
    read -p "Are you sure you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Client removal cancelled"
        return 0
    fi

    print_status "Removing client '$client_name' from region $region..."
    ssh -i "$key_file" ubuntu@"$server_ip" \
        "sudo /etc/wireguard/remove-client.sh $client_name"

    if [ $? -eq 0 ]; then
        print_success "Client '$client_name' removed successfully from region $region"
        echo
        print_status "The client configuration is no longer valid and should be removed from client devices"

        # Clean up local config file if it exists
        local config_file="client-configs/${client_name}-${region}.conf"
        if [ -f "$config_file" ]; then
            print_status "Removing local configuration file: $config_file"
            rm -f "$config_file"
        fi
    else
        print_error "Failed to remove client '$client_name' from region $region"
        return 1
    fi
}

# Infrastructure Control Commands
cmd_start() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop start <region>"
        return 1
    fi

    local asg_name=$(get_asg_name "$region")
    if [ $? -ne 0 ] || [ -z "$asg_name" ]; then
        return 1
    fi

    print_status "Starting VPN server in region $region..."
    aws autoscaling set-desired-capacity \
        --auto-scaling-group-name "$asg_name" \
        --desired-capacity 1 \
        --region "$region"

    if [ $? -eq 0 ]; then
        print_success "VPN server start initiated in region $region"
        print_status "It may take a few minutes for the server to become available"
        print_status "Use 'hop status $region' to monitor the deployment status"
    else
        print_error "Failed to start VPN server in region $region"
        return 1
    fi
}

cmd_stop() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop stop <region>"
        return 1
    fi

    local asg_name=$(get_asg_name "$region")
    if [ $? -ne 0 ] || [ -z "$asg_name" ]; then
        return 1
    fi

    print_status "Stopping VPN server in region $region..."
    aws autoscaling set-desired-capacity \
        --auto-scaling-group-name "$asg_name" \
        --desired-capacity 0 \
        --region "$region"

    if [ $? -eq 0 ]; then
        print_success "VPN server stop initiated in region $region"
        print_status "The server instance will be terminated shortly"
        print_status "Use 'hop status $region' to monitor the status"
    else
        print_error "Failed to stop VPN server in region $region"
        return 1
    fi
}

# Get Auto Scaling Group name for region
get_asg_name() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        return 1
    fi

    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi

    # Check if region is deployed
    local compute_stack=$(get_stack_name "Compute" "$region")
    if ! stack_exists "$compute_stack" "$region"; then
        print_error "VPN service is not deployed in region $region"
        return 1
    fi

    local outputs=$(get_stack_outputs "$compute_stack" "$region")
    if [ -z "$outputs" ] || [ "$outputs" = "null" ]; then
        print_error "Could not retrieve compute stack outputs for region $region"
        return 1
    fi

    local asg_name=$(echo "$outputs" | jq -r '.[] | select(.OutputKey=="VPNServerAutoScalingGroup") | .OutputValue' 2>/dev/null)
    if [ -z "$asg_name" ] || [ "$asg_name" = "null" ]; then
        print_error "Could not retrieve Auto Scaling Group name for region $region"
        return 1
    fi

    echo "$asg_name"
}

#==========================================
# HELPER FUNCTIONS
#==========================================

# Deploy to multiple regions (from deploy.sh)
deploy_multiple_regions() {
    local regions=("$@")

    print_status "Deploying RegionHop VPN to ${#regions[@]} region(s): ${regions[*]}"

    install_dependencies
    build_project

    local success_count=0
    local failed_regions=()

    for region in "${regions[@]}"; do
        print_status "Deploying to region: $region"

        if deploy_to_region "$region"; then
            success_count=$((success_count + 1))
        else
            failed_regions+=("$region")
        fi

        echo
    done

    if [ $success_count -eq ${#regions[@]} ]; then
        print_success "All regions deployed successfully!"
    else
        print_warning "Deployment completed with some failures:"
        print_success "$success_count out of ${#regions[@]} regions deployed successfully"
        if [ ${#failed_regions[@]} -gt 0 ]; then
            print_error "Failed regions: ${failed_regions[*]}"
        fi
    fi

    print_status "Waiting for deployment to complete..."
    sleep 5

    # Show final status
    echo
    print_success "🎉 WireGuard VPN Service deployment completed!"
    echo
    print_status "Use 'hop deployed' to see deployed regions"
    print_status "Use 'hop ssh <region>' to connect to a specific region"
    print_status "Use 'hop status' to check deployment status"
    echo
    print_warning "To destroy deployments: hop destroy <region>"
}

# Install dependencies
install_dependencies() {
    print_status "Installing dependencies..."
    npm install
    print_success "Dependencies installed successfully!"
}

# Build the project
build_project() {
    print_status "Building the project..."
    npm run build
    print_success "Project built successfully!"
}

#==========================================
# HELP FUNCTIONS
#==========================================

show_main_help() {
    echo "Hop - Unified WireGuard VPN Management Tool v$VERSION"
    echo
    echo "Usage: hop <command> [options] [arguments]"
    echo
    echo "Infrastructure Commands:"
    echo "  deploy [region]              Deploy VPN to region (default: eu-central-1)"
    echo "  deploy --regions r1,r2,r3    Deploy to multiple regions"
    echo "  destroy <region> [--force]   Destroy VPN deployment in region"
    echo "  bootstrap <region>           Bootstrap CDK for region"
    echo "  start <region>               Start VPN server (set ASG desired capacity to 1)"
    echo "  stop <region>                Stop VPN server (set ASG desired capacity to 0)"
    echo
    echo "Status & Information:"
    echo "  list                         Show example regions (supportedRegions removed)"
    echo "  deployed                     Show only deployed regions with status"
    echo "  regions                      Show example regions (supportedRegions removed)"
    echo "  status [region]              Show VPN status (RUNNING/STOPPED/UNHEALTHY/UNDEPLOYED)"
    echo
    echo "Connection & Access:"
    echo "  ssh <region>                 SSH to VPN server in region"
    echo "  add-client <region> <name>   Add new VPN client to region"
    echo "  remove-client <region> <name> Remove VPN client from region"
    echo "  list-clients <region>        List all VPN clients in region"
    echo "  download-client <region> [client-name] [--all|-a]  Download client configuration(s)"
    echo
    echo "Examples:"
    echo "  hop deploy                   # Deploy to default region"
    echo "  hop deploy us-east-1         # Deploy to specific region"
    echo "  hop start eu-central-1       # Start VPN server in EU Central"
    echo "  hop stop eu-central-1        # Stop VPN server in EU Central"
    echo "  hop deployed                 # See deployed regions with status"
    echo "  hop status                   # Check status of all deployed regions"
    echo "  hop status us-east-1         # Check status of specific region"
    echo "  hop ssh eu-central-1         # Connect to EU server"
    echo "  hop destroy us-west-2        # Remove US West deployment"
    echo
    echo "For command-specific help: hop <command> --help"
}

show_deploy_help() {
    echo "Usage: hop deploy [region] [options]"
    echo
    echo "Options:"
    echo "  --regions <r1,r2,r3>    Deploy to multiple regions (comma-separated)"
    echo "  --help, -h              Show this help message"
    echo
    echo "Examples:"
    echo "  hop deploy                              # Deploy to default region"
    echo "  hop deploy us-east-1                   # Deploy to specific region"
    echo "  hop deploy --regions us-east-1,eu-central-1  # Deploy to multiple regions"
}

show_download_client_help() {
    echo "Usage: hop download-client <region> [client-name] [options]"
    echo
    echo "Download VPN client configuration(s) from a region."
    echo
    echo "Arguments:"
    echo "  <region>        AWS region where VPN is deployed"
    echo "  [client-name]   Name of specific client to download (required unless using --all)"
    echo
    echo "Options:"
    echo "  --all, -a       Download all client configurations from the region"
    echo "  --help, -h      Show this help message"
    echo
    echo "Examples:"
    echo "  hop download-client us-east-1 iphone    # Download specific client config"
    echo "  hop download-client us-east-1 --all     # Download all client configs"
    echo "  hop download-client us-east-1 -a        # Same as above (short flag)"
    echo
    echo "Note: Use 'hop list-clients <region>' to see available clients."
}

#==========================================
# MAIN ENTRY POINT
#==========================================

main() {
    case "$1" in
        # Infrastructure commands
        deploy)
            check_prerequisites || exit 1
            cmd_deploy "${@:2}"
            ;;
        destroy)
            check_prerequisites || exit 1
            cmd_destroy "${@:2}"
            ;;
        bootstrap)
            check_prerequisites || exit 1
            cmd_bootstrap "${@:2}"
            ;;
        start)
            check_prerequisites || exit 1
            cmd_start "${@:2}"
            ;;
        stop)
            check_prerequisites || exit 1
            cmd_stop "${@:2}"
            ;;

        # Status commands
        list)
            check_prerequisites || exit 1
            cmd_list "${@:2}"
            ;;
        deployed)
            check_prerequisites || exit 1
            cmd_deployed "${@:2}"
            ;;
        regions)
            cmd_regions "${@:2}"
            ;;
        status)
            check_prerequisites || exit 1
            cmd_status "${@:2}"
            ;;

        # Connection commands
        ssh)
            check_prerequisites || exit 1
            cmd_ssh "${@:2}"
            ;;
        add-client)
            check_prerequisites || exit 1
            cmd_add_client "${@:2}"
            ;;
        remove-client)
            check_prerequisites || exit 1
            cmd_remove_client "${@:2}"
            ;;
        list-clients)
            check_prerequisites || exit 1
            cmd_list_clients "${@:2}"
            ;;
        download-client)
            check_prerequisites || exit 1
            cmd_download_client "${@:2}"
            ;;

        # Meta commands
        help|--help|-h)
            show_main_help
            ;;
        version|--version|-v)
            echo "Hop v$VERSION"
            ;;

        "")
            print_error "No command specified"
            echo
            show_main_help
            exit 1
            ;;

        *)
            print_error "Unknown command: $1"
            echo
            show_main_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
