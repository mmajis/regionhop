#!/bin/bash

# Hop - Unified WireGuard VPN Management Tool
# Consolidates deploy.sh, region-manager.sh, and connect.sh into a single interface
# Usage: ./hop <command> [options] [arguments]

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

    local deployed_regions=$(list_deployed_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi

    for region in $deployed_regions; do
        local vpn_ip=$(get_vpn_server_ip "$region")

        if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
            print_success "$region ($vpn_ip)"
        else
            print_warning "$region (IP not available)"
        fi
    done

    echo
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

        show_region_status "$region"
    else
        # Show status for all deployed regions (discovered automatically)
        print_status "VPN deployment status across all deployed regions:"
        echo

        local deployed_regions=$(list_deployed_regions)
        if [ $? -ne 0 ]; then
            print_warning "No VPN deployments found in any region"
            return 1
        fi

        for region in $deployed_regions; do
            show_region_status "$region"
        done
    fi
}

cmd_health() {
    print_status "Performing health check on all deployed regions..."
    echo

    local deployed_regions=$(list_deployed_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi

    local healthy_count=0
    local unhealthy_regions=()

    for region in $deployed_regions; do
        print_status "Checking $region..."

        # Check if stacks are healthy
        local infra_stack=$(get_stack_name "Infrastructure" "$region")
        local compute_stack=$(get_stack_name "Compute" "$region")

        local infra_status=$(get_stack_status "$infra_stack" "$region")
        local compute_status=$(get_stack_status "$compute_stack" "$region")

        if [ "$infra_status" = "CREATE_COMPLETE" ] || [ "$infra_status" = "UPDATE_COMPLETE" ]; then
            if [ "$compute_status" = "CREATE_COMPLETE" ] || [ "$compute_status" = "UPDATE_COMPLETE" ]; then
                local vpn_ip=$(get_vpn_server_ip "$region")
                if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
                    print_success "  $region: HEALTHY ($vpn_ip)"
                    healthy_count=$((healthy_count + 1))
                else
                    print_warning "  $region: UNHEALTHY (No IP available)"
                    unhealthy_regions+=("$region")
                fi
            else
                print_warning "  $region: UNHEALTHY (Compute stack: $compute_status)"
                unhealthy_regions+=("$region")
            fi
        else
            print_warning "  $region: UNHEALTHY (Infrastructure stack: $infra_status)"
            unhealthy_regions+=("$region")
        fi
    done

    echo
    print_status "Health check summary:"
    print_success "Healthy regions: $healthy_count"

    if [ ${#unhealthy_regions[@]} -gt 0 ]; then
        print_warning "Unhealthy regions: ${#unhealthy_regions[@]} (${unhealthy_regions[*]})"
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

cmd_config() {
    local region=$1

    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: hop config <region>"
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
    local config_file="client-configs/macos-client-${region}.conf"

    print_status "Retrieving client configuration from $region..."
    ssh -i "$key_file" ubuntu@"$server_ip" \
        "sudo cat /etc/wireguard/clients/macos-client/macos-client.conf" > "$config_file"

    if [ $? -eq 0 ]; then
        print_success "Client configuration saved as $config_file"
        echo
        print_status "To import to WireGuard app:"
        echo "1. Open WireGuard app on macOS"
        echo "2. Click 'Import tunnel(s) from file'"
        echo "3. Select the $config_file file"
        echo "4. Click 'Import' and then toggle to connect"
    else
        print_error "Failed to retrieve client configuration from $region"
        return 1
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
    local cost_per_region=15
    local total_cost=$((${#regions[@]} * $cost_per_region))

    print_status "Deploying WireGuard VPN to ${#regions[@]} region(s): ${regions[*]}"
    print_warning "This will create AWS resources that may incur charges (~$${total_cost}/month total)."

    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled."
        exit 0
    fi

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
    print_warning "Remember: This service will incur AWS charges (~$15/month per region)"
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
    echo "  deployed                     Show only deployed regions"
    echo "  regions                      Show example regions (supportedRegions removed)"
    echo "  status [region]              Show deployment status"
    echo "  health                       Health check all deployed regions"
    echo
    echo "Connection & Access:"
    echo "  ssh <region>                 SSH to VPN server in region"
    echo "  config <region>              Download client configuration"
    echo "  add-client <region> <name>   Add new VPN client to region"
    echo
    echo "Examples:"
    echo "  hop deploy                   # Deploy to default region"
    echo "  hop deploy us-east-1         # Deploy to specific region"
    echo "  hop start eu-central-1       # Start VPN server in EU Central"
    echo "  hop stop eu-central-1        # Stop VPN server in EU Central"
    echo "  hop deployed                 # See deployed regions"
    echo "  hop ssh eu-central-1         # Connect to EU server"
    echo "  hop config us-east-1         # Get US East client config"
    echo "  hop destroy us-west-2        # Remove US West deployment"
    echo
    echo "Note: You can now use any valid AWS region. Region validation is handled by AWS."
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

#==========================================
# LEGACY COMPATIBILITY
#==========================================

# Check if script was called via legacy symlinks
detect_legacy_mode() {
    case "${0##*/}" in
        "deploy.sh")
            legacy_deploy_handler "$@"
            ;;
        "connect.sh")
            legacy_connect_handler "$@"
            ;;
        "region-manager.sh")
            legacy_region_manager_handler "$@"
            ;;
    esac
}

legacy_deploy_handler() {
    echo "⚠️  WARNING: deploy.sh is deprecated. Use 'hop deploy' instead."
    echo "   This legacy interface will be removed in a future version."
    echo

    # Map legacy deploy.sh arguments to new commands
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                check_prerequisites || exit 1
                cmd_deploy "$2"
                exit 0
                ;;
            --regions)
                check_prerequisites || exit 1
                cmd_deploy --regions "$2"
                exit 0
                ;;
            --list-regions)
                cmd_regions
                exit 0
                ;;
            --status)
                check_prerequisites || exit 1
                cmd_status
                exit 0
                ;;
            --destroy)
                check_prerequisites || exit 1
                if [ -n "$2" ] && [ "$2" != "--region" ]; then
                    shift
                fi
                if [ "$1" = "--region" ]; then
                    cmd_destroy "$2"
                else
                    print_error "Region required for destroy operation"
                fi
                exit 0
                ;;
            *)
                # Default behavior - deploy
                check_prerequisites || exit 1
                cmd_deploy
                exit 0
                ;;
        esac
        shift
    done

    # Default behavior if no args
    check_prerequisites || exit 1
    cmd_deploy
    exit 0
}

legacy_connect_handler() {
    echo "⚠️  WARNING: connect.sh is deprecated. Use 'hop' commands instead."
    echo "   This legacy interface will be removed in a future version."
    echo

    case "$1" in
        list)
            cmd_deployed
            ;;
        ssh)
            cmd_ssh "$2"
            ;;
        config)
            cmd_config "$2"
            ;;
        status)
            cmd_status "$2"
            ;;
        add-client)
            cmd_add_client "$2" "$3"
            ;;
        "")
            cmd_deployed
            ;;
        *)
            print_error "Unknown command: $1"
            ;;
    esac
}

legacy_region_manager_handler() {
    echo "⚠️  WARNING: region-manager.sh is deprecated. Use 'hop' commands instead."
    echo "   This legacy interface will be removed in a future version."
    echo

    case "$1" in
        list)
            cmd_list
            ;;
        deployed)
            cmd_deployed
            ;;
        deploy)
            cmd_deploy "$2"
            ;;
        destroy)
            cmd_destroy "$2"
            ;;
        status)
            cmd_status "$2"
            ;;
        bootstrap)
            cmd_bootstrap "$2"
            ;;
        health)
            cmd_health
            ;;
        *)
            print_error "Unknown command: $1"
            ;;
    esac
}

#==========================================
# MAIN ENTRY POINT
#==========================================

main() {
    # Check for legacy mode first
    detect_legacy_mode "$@"

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
        health)
            check_prerequisites || exit 1
            cmd_health "${@:2}"
            ;;

        # Connection commands
        ssh)
            check_prerequisites || exit 1
            cmd_ssh "${@:2}"
            ;;
        config)
            check_prerequisites || exit 1
            cmd_config "${@:2}"
            ;;
        add-client)
            check_prerequisites || exit 1
            cmd_add_client "${@:2}"
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