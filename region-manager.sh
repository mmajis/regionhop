#!/bin/bash

# WireGuard VPN Region Manager Script
# This script provides comprehensive region management capabilities
# for the WireGuard VPN service deployment

set -e

# Source shared helper functions
if [ -f "scripts/region-helpers.sh" ]; then
    source scripts/region-helpers.sh
else
    echo "Error: scripts/region-helpers.sh not found"
    exit 1
fi

# List all available regions
list_available() {
    print_status "Available regions for VPN deployment:"
    echo
    
    local regions=$(load_regions)
    local default_region=$(get_default_region)
    
    for region in $regions; do
        local region_info=$(get_region_info "$region")
        local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)
        local region_desc=$(echo "$region_info" | jq -r '.description' 2>/dev/null)
        
        if [ "$region" = "$default_region" ]; then
            print_success "$region - $region_name (DEFAULT)"
        else
            echo "  $region - $region_name"
        fi
        echo "    $region_desc"
        
        # Check if region is deployed
        local infra_stack=$(get_stack_name "Infrastructure" "$region")
        local compute_stack=$(get_stack_name "Compute" "$region")
        
        if stack_exists "$infra_stack" "$region" && stack_exists "$compute_stack" "$region"; then
            local vpn_ip=$(get_vpn_server_ip "$region")
            if [ -n "$vpn_ip" ] && [ "$vpn_ip" != "null" ]; then
                print_success "    Status: DEPLOYED ($vpn_ip)"
            else
                print_warning "    Status: DEPLOYED (IP not available)"
            fi
        else
            echo "    Status: NOT DEPLOYED"
        fi
        echo
    done
}

# Show only deployed regions
show_deployed() {
    print_status "Deployed VPN regions:"
    echo
    
    local deployed_regions=$(list_deployed_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    for region in $deployed_regions; do
        show_region_status "$region"
    done
}

# Deploy to specific region
deploy_region() {
    local region=$1
    
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: $0 deploy <region>"
        return 1
    fi
    
    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Check if already deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")
    
    if stack_exists "$infra_stack" "$region" && stack_exists "$compute_stack" "$region"; then
        print_warning "VPN service is already deployed in region $region"
        print_status "Use './region-manager.sh status $region' to check status"
        return 0
    fi
    
    local region_info=$(get_region_info "$region")
    local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)
    
    print_warning "This will deploy VPN service to region $region ($region_name)"
    print_warning "This will incur AWS charges (~$15/month)"
    echo
    read -p "Do you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warning "Deployment cancelled."
        return 0
    fi
    
    # Check prerequisites
    check_prerequisites
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Deploy to region
    deploy_to_region "$region"
    
    if [ $? -eq 0 ]; then
        print_success "Region $region deployed successfully!"
        echo
        print_status "Next steps:"
        echo "1. Use './connect.sh ssh $region' to connect"
        echo "2. Use './connect.sh config $region' to get client configuration"
        echo "3. Use './region-manager.sh status $region' to check status"
    fi
}

# Destroy region deployment
destroy_region_deployment() {
    local region=$1
    
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: $0 destroy <region>"
        return 1
    fi
    
    validate_region "$region"
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    # Check if deployed
    local infra_stack=$(get_stack_name "Infrastructure" "$region")
    local compute_stack=$(get_stack_name "Compute" "$region")
    
    if ! stack_exists "$infra_stack" "$region" && ! stack_exists "$compute_stack" "$region"; then
        print_warning "No VPN deployment found in region $region"
        return 0
    fi
    
    destroy_region "$region" false
}

# Show status for specific region or all regions
show_status() {
    local region=$1
    
    if [ -n "$region" ]; then
        # Show status for specific region
        validate_region "$region"
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        show_region_status "$region"
    else
        # Show status for all regions
        print_status "VPN deployment status across all regions:"
        echo
        
        local regions=$(load_regions)
        local found_deployments=false
        
        for region in $regions; do
            local infra_stack=$(get_stack_name "Infrastructure" "$region")
            local compute_stack=$(get_stack_name "Compute" "$region")
            
            if stack_exists "$infra_stack" "$region" || stack_exists "$compute_stack" "$region"; then
                show_region_status "$region"
                found_deployments=true
            fi
        done
        
        if [ "$found_deployments" = false ]; then
            print_warning "No VPN deployments found in any region"
        fi
    fi
}

# Bootstrap region for CDK
bootstrap_region_cdk() {
    local region=$1
    
    if [ -z "$region" ]; then
        print_error "Region parameter is required"
        echo "Usage: $0 bootstrap <region>"
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

# Show usage
show_usage() {
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  list                    List all available regions with deployment status"
    echo "  deployed                Show only deployed regions"
    echo "  deploy <region>         Deploy VPN service to specific region"
    echo "  destroy <region>        Destroy VPN service in specific region"
    echo "  status [region]         Show deployment status (all or specific region)"
    echo "  bootstrap <region>      Bootstrap CDK for specific region"
    echo "  help                    Show this help message"
    echo
    echo "Examples:"
    echo "  $0 list                 # List all regions with status"
    echo "  $0 deployed             # Show only deployed regions"
    echo "  $0 deploy us-east-1     # Deploy to us-east-1"
    echo "  $0 destroy us-east-1    # Destroy us-east-1 deployment"
    echo "  $0 status               # Show status of all regions"
    echo "  $0 status us-west-2     # Show status of us-west-2"
    echo "  $0 bootstrap eu-central-1  # Bootstrap CDK for eu-central-1"
    echo
    echo "Region Management Tips:"
    echo "  - Use 'deploy' to add new regions"
    echo "  - Use 'destroy' to remove regions and save costs"
    echo "  - Use 'status' to monitor deployments"
    echo "  - Each region incurs ~$15/month in AWS charges"
}

# Health check for all deployed regions
health_check() {
    print_status "Performing health check on all deployed regions..."
    echo
    
    local deployed_regions=$(list_deployed_regions)
    if [ $? -ne 0 ]; then
        return 1
    fi
    
    local healthy_count=0
    local unhealthy_regions=()
    
    for region in $deployed_regions; do
        local region_info=$(get_region_info "$region")
        local region_name=$(echo "$region_info" | jq -r '.name' 2>/dev/null)
        
        print_status "Checking $region ($region_name)..."
        
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

# Main function
main() {
    case "$1" in
        list)
            list_available
            ;;
        deployed)
            show_deployed
            ;;
        deploy)
            deploy_region "$2"
            ;;
        destroy)
            destroy_region_deployment "$2"
            ;;
        status)
            show_status "$2"
            ;;
        bootstrap)
            bootstrap_region_cdk "$2"
            ;;
        health)
            health_check
            ;;
        help)
            show_usage
            ;;
        "")
            print_error "No command specified"
            show_usage
            exit 1
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