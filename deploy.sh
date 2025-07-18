#!/bin/bash

# WireGuard VPN Service Deployment Script
# This script automates the deployment of your personal WireGuard VPN service
# Now supports multi-region deployment and management

set -e

# Source shared helper functions
if [ -f "scripts/region-helpers.sh" ]; then
    source scripts/region-helpers.sh
else
    echo "Error: scripts/region-helpers.sh not found"
    exit 1
fi

# Global variables
DEPLOY_REGIONS=()
OPERATION="deploy"
FORCE_DESTROY=false

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --region)
                if [ -z "$2" ]; then
                    print_error "Region parameter requires a value"
                    exit 1
                fi
                validate_region "$2"
                if [ $? -ne 0 ]; then
                    exit 1
                fi
                DEPLOY_REGIONS=("$2")
                shift 2
                ;;
            --regions)
                if [ -z "$2" ]; then
                    print_error "Regions parameter requires a value"
                    exit 1
                fi
                local regions=($(parse_regions "$2"))
                if [ $? -ne 0 ]; then
                    exit 1
                fi
                DEPLOY_REGIONS=("${regions[@]}")
                shift 2
                ;;
            --list-regions)
                list_available_regions
                exit 0
                ;;
            --status)
                show_deployment_status
                exit 0
                ;;
            --destroy)
                OPERATION="destroy"
                shift
                ;;
            --force)
                FORCE_DESTROY=true
                shift
                ;;
            deploy)
                OPERATION="deploy"
                shift
                ;;
            destroy)
                OPERATION="destroy"
                shift
                ;;
            status)
                show_deployment_status
                exit 0
                ;;
            help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # If no regions specified, use default
    if [ ${#DEPLOY_REGIONS[@]} -eq 0 ]; then
        DEPLOY_REGIONS=($(get_default_region))
    fi
}

# List available regions
list_available_regions() {
    print_status "Available regions:"
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
        echo
    done
}

# Show deployment status across all regions
show_deployment_status() {
    print_status "Checking deployment status across all regions..."
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
        print_warning "No deployments found in any region"
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [COMMAND]"
    echo
    echo "Commands:"
    echo "  deploy                  Deploy VPN service (default)"
    echo "  destroy                 Destroy VPN service"
    echo "  status                  Show deployment status"
    echo "  help                    Show this help message"
    echo
    echo "Options:"
    echo "  --region <region>       Deploy to specific region"
    echo "  --regions <r1,r2>       Deploy to multiple regions (comma-separated)"
    echo "  --list-regions          List all available regions"
    echo "  --status                Show deployment status across all regions"
    echo "  --destroy               Destroy deployment in specified region(s)"
    echo "  --force                 Skip confirmation prompts (use with --destroy)"
    echo
    echo "Examples:"
    echo "  $0                              # Deploy to default region"
    echo "  $0 --region us-east-1          # Deploy to us-east-1"
    echo "  $0 --regions us-east-1,us-west-2  # Deploy to multiple regions"
    echo "  $0 --list-regions              # List available regions"
    echo "  $0 --status                    # Show status across all regions"
    echo "  $0 --destroy --region us-east-1   # Destroy us-east-1 deployment"
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

# Deploy to multiple regions
deploy_multiple_regions() {
    local regions=("${DEPLOY_REGIONS[@]}")
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
}

# Destroy multiple regions
destroy_multiple_regions() {
    local regions=("${DEPLOY_REGIONS[@]}")
    
    print_status "Destroying VPN service in ${#regions[@]} region(s): ${regions[*]}"
    
    local success_count=0
    local failed_regions=()
    
    for region in "${regions[@]}"; do
        if destroy_region "$region" "$FORCE_DESTROY"; then
            success_count=$((success_count + 1))
        else
            failed_regions+=("$region")
        fi
        
        echo
    done
    
    if [ $success_count -eq ${#regions[@]} ]; then
        print_success "All regions destroyed successfully!"
    else
        print_warning "Destruction completed with some failures:"
        print_success "$success_count out of ${#regions[@]} regions destroyed successfully"
        if [ ${#failed_regions[@]} -gt 0 ]; then
            print_error "Failed regions: ${failed_regions[*]}"
        fi
    fi
}


# Main deployment function
main() {
    print_status "Starting WireGuard VPN Service deployment..."
    echo
    
    check_prerequisites
    install_dependencies
    build_project
    deploy_multiple_regions
    
    print_status "Waiting for deployment to complete..."
    sleep 5
    
    # Show final status
    echo
    print_success "🎉 WireGuard VPN Service deployment completed!"
    echo
    print_status "Use './connect.sh list' to see deployed regions"
    print_status "Use './connect.sh ssh <region>' to connect to a specific region"
    print_status "Use './deploy.sh --status' to check deployment status"
    echo
    print_warning "Remember: This service will incur AWS charges (~$15/month per region)"
    print_warning "To destroy deployments: ./deploy.sh --destroy --region <region>"
}

# Main script execution
main_script() {
    parse_arguments "$@"
    
    case "$OPERATION" in
        deploy)
            main
            ;;
        destroy)
            destroy_multiple_regions
            ;;
        *)
            print_error "Unknown operation: $OPERATION"
            show_usage
            exit 1
            ;;
    esac
}

# Call main script with all arguments
main_script "$@"