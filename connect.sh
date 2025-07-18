#!/bin/bash

# WireGuard VPN Connection Helper Script
# This script helps you connect to your WireGuard VPN server across multiple regions
# Now supports region selection and multi-region management

set -e

# Source shared helper functions
if [ -f "scripts/region-helpers.sh" ]; then
    source scripts/region-helpers.sh
else
    echo "Error: scripts/region-helpers.sh not found"
    exit 1
fi

# Show deployed regions
list_deployed() {
    print_status "Deployed VPN regions:"
    echo
    
    local deployed_regions=$(list_deployed_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    for region in $deployed_regions; do
        local region_info=$(get_region_info "$region")
        local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)
        local vpn_ip=$(get_vpn_server_ip "$region")
        
        if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
            print_success "$region - $region_name ($vpn_ip)"
        else
            print_warning "$region - $region_name (IP not available)"
        fi
    done
    
    echo
    print_status "Use './connect.sh ssh <region>' to connect to a specific region"
}

# SSH to specific region
ssh_to_region() {
    local region=$1
    
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: $0 ssh <region>"
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

# Get client configuration for specific region
get_client_config() {
    local region=$1
    
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: $0 config <region>"
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

# Check VPN status for specific region
check_region_status() {
    local region=$1
    
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: $0 status <region>"
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
    
    print_status "Checking VPN server status in $region..."
    ssh -i "$key_file" ubuntu@"$server_ip" \
        "sudo /etc/wireguard/vpn-status.sh"
}

# Add new client to specific region
add_client_to_region() {
    local region=$1
    local client_name=$2
    
    if [ -z "$region" ] || [ -z "$client_name" ]; then
        print_error "Both region and client name are required"
        echo "Usage: $0 add-client <region> <client-name>"
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

# Show usage
show_usage() {
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  list                        List all deployed regions"
    echo "  ssh <region>               SSH into VPN server in specific region"
    echo "  config <region>            Download client configuration for region"
    echo "  status <region>            Check VPN server status in region"
    echo "  add-client <region> <name> Add new VPN client to region"
    echo "  help                       Show this help message"
    echo
    echo "Examples:"
    echo "  $0 list                           # List all deployed regions"
    echo "  $0 ssh us-east-1                 # SSH to us-east-1 VPN server"
    echo "  $0 config eu-central-1           # Get config for eu-central-1"
    echo "  $0 status us-west-2              # Check status in us-west-2"
    echo "  $0 add-client us-east-1 iphone   # Add iPhone client to us-east-1"
    echo
    echo "Region Management:"
    echo "  Use './deploy.sh --list-regions' to see all available regions"
    echo "  Use './deploy.sh --region <region>' to deploy to a specific region"
    echo "  Use './region-manager.sh' for advanced region management"
}

# Backward compatibility function - if no arguments, show deployed regions
show_legacy_behavior() {
    print_status "WireGuard VPN Connection Helper"
    echo
    list_deployed
}

# Main function
main() {
    case "$1" in
        help)
            show_usage
            return 0
            ;;
        *)
            # Check prerequisites for all other commands
            check_prerequisites
            if [ $? -ne 0 ]; then
                exit 1
            fi
            ;;
    esac
    
    case "$1" in
        list)
            list_deployed
            ;;
        ssh)
            ssh_to_region "$2"
            ;;
        config)
            get_client_config "$2"
            ;;
        status)
            check_region_status "$2"
            ;;
        add-client)
            add_client_to_region "$2" "$3"
            ;;
        help)
            # Already handled above
            ;;
        "")
            # Backward compatibility - if no command, show deployed regions
            show_legacy_behavior
            ;;
        *)
            print_error "Unknown command: $1"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"