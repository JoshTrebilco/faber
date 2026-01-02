#!/bin/bash

#############################################
# Domain Management Functions
#############################################

# Helper: Cleanup SSL certificate for a domain
cleanup_ssl_certificate() {
    local domain=$1
    if [ -d "/etc/letsencrypt/live/$domain" ]; then
        certbot revoke --cert-name "$domain" --non-interactive 2>/dev/null || true
        certbot delete --cert-name "$domain" --non-interactive 2>/dev/null || true
    fi
}

# Create domain
domain_create() {
    local domain=""
    local app=""
    local interactive=true
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --domain=*)
                domain="${arg#*=}"
                ;;
            --app=*)
                app="${arg#*=}"
                ;;
        esac
    done
    
    # If all parameters provided, non-interactive mode
    if [ -n "$domain" ] && [ -n "$app" ]; then
        interactive=false
    fi
    
    # Interactive prompts
    if [ $interactive = true ]; then
        echo -e "${BOLD}Create/Assign Domain${NC}"
        echo "─────────────────────────────────────"
        echo ""
        
        if [ -z "$domain" ]; then
            read -p "Domain name: " domain
        fi
        
        if [ -z "$app" ]; then
            echo ""
            echo "Select virtual host:"
            
            # Get available apps (those without domains)
            local available_vhosts=()
            local all_vhosts=($(json_keys "${APPS_FILE}"))
            
            for vh in "${all_vhosts[@]}"; do
                if [ -z "$(get_domain_by_app "$vh")" ]; then
                    available_vhosts+=("$vh")
                fi
            done
            
            if [ ${#available_vhosts[@]} -eq 0 ]; then
                echo -e "${YELLOW}No available virtual hosts found. Creating new one...${NC}"
                echo ""
                app_create
                # Get the last created app
                app=$(json_keys "${APPS_FILE}" | tail -n 1)
            else
                local i=1
                for vh in "${available_vhosts[@]}"; do
                    echo "  $i. $vh"
                    ((i++))
                done
                read -p "Choice: " choice
                app=${available_vhosts[$((choice-1))]}
            fi
        fi
    fi
    
    # Validate inputs
    if [ -z "$domain" ]; then
        echo -e "${RED}Error: Domain required${NC}"
        exit 1
    fi
    
    # Check for wildcard domain
    if [[ "$domain" == *"*"* ]]; then
        echo -e "${YELLOW}${BOLD}Warning: Wildcard domains detected${NC}"
        echo ""
        echo "Wildcard domains (*.example.com) require DNS validation."
        echo "You'll need to:"
        echo "  1. Create the domain first"
        echo "  2. Use a DNS provider plugin with certbot"
        echo "  3. Manually configure DNS TXT records"
        echo ""
        echo "Supported DNS providers:"
        echo "  - Cloudflare (certbot-dns-cloudflare)"
        echo "  - Route53 (certbot-dns-route53)"
        echo "  - DigitalOcean (certbot-dns-digitalocean)"
        echo "  - And more..."
        echo ""
        read -p "Continue anyway? (y/N): " confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    
    # Check if domain already exists
    if domain_exists "$domain"; then
        local owner_app=$(get_domain_field "$domain" "app")
        echo -e "${RED}Error: Domain '$domain' is already taken${NC}"
        echo -e "  Used by app: ${CYAN}$owner_app${NC}"
        exit 1
    fi
    
    # Check if app exists
    check_app_exists "$app"
    
    echo ""
    echo -e "${CYAN}Assigning domain...${NC}"
    
    # Get app data
    local php_version=$(get_app_field "$app" "php_version")
    
    # Update Nginx configuration
    echo "  → Updating Nginx configuration..."
    update_nginx_domain "$app" "$domain"
    
    # Reload nginx
    echo "  → Reloading Nginx..."
    nginx_reload
    
    # Save to storage
    local domain_data=$(jq -n \
        --arg vh "$app" \
        '{app: $vh, ssl: false}')
    
    json_set "${DOMAINS_FILE}" "$domain" "$domain_data"
    
    echo ""
    echo -e "${GREEN}${BOLD}Domain assigned successfully!${NC}"
    echo "─────────────────────────────────────"
    echo -e "Domain:       ${CYAN}$domain${NC}"
    echo -e "Virtual Host: ${CYAN}$app${NC}"
    echo ""
    echo -e "${YELLOW}To enable SSL, run:${NC}"
    echo -e "  sudo -u $app /home/$app/ssl.sh"
    echo ""
}

# List domains
domain_list() {
    echo -e "${BOLD}Domains${NC}"
    echo "─────────────────────────────────────"
    echo ""
    
    local domains=$(json_keys "${DOMAINS_FILE}")
    
    if [ -z "$domains" ]; then
        echo "No domains found."
        echo ""
        return
    fi
    
    printf "%-30s %-15s\n" "DOMAIN" "VIRTUALHOST"
    echo "─────────────────────────────────────────────"
    
    for domain in $domains; do
        local app=$(get_domain_field "$domain" "app")
        printf "%-30s %-15s\n" "$domain" "$app"
    done
    
    echo ""
}

# Delete domain
domain_delete() {
    local domain=$1
    local force=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --force)
                force=true
                ;;
            *)
                domain="$arg"
                ;;
        esac
    done
    
    if [ -z "$domain" ]; then
        echo -e "${RED}Error: Domain required${NC}"
        echo "Usage: cipi domain delete <domain> [--force]"
        exit 1
    fi
    
    if ! json_has_key "${DOMAINS_FILE}" "$domain"; then
        echo -e "${RED}Error: Domain '$domain' not found${NC}"
        exit 1
    fi
    
    # Get domain data
    local has_ssl=$(get_domain_field "$domain" "ssl")
    has_ssl=${has_ssl:-false}
    
    # Confirm deletion
    echo -e "${YELLOW}${BOLD}Warning: This will unassign the domain from the virtual host${NC}"
    if [ "$has_ssl" = "true" ]; then
        echo -e "${YELLOW}SSL certificate for this domain will be revoked and deleted${NC}"
    fi
    
    if [ "$force" != "true" ]; then
        read -p "Continue? (y/N): " confirm
        
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Deletion cancelled."
            exit 0
        fi
    fi
    
    local app=$(get_domain_field "$domain" "app")
    
    # Revoke and delete SSL certificate if exists
    if [ "$has_ssl" = "true" ]; then
        echo ""
        echo -e "${CYAN}→ Revoking SSL certificate...${NC}"
        cleanup_ssl_certificate "$domain"
    fi
    
    # Reset Nginx configuration to use username only
    echo -e "${CYAN}→ Resetting Nginx configuration...${NC}"
    local php_version=$(get_app_field "$app" "php_version")
    
    create_nginx_config "$app" "" "$php_version"
    
    # Remove from storage
    json_delete "${DOMAINS_FILE}" "$domain"
    
    # Reload nginx
    nginx_reload
    
    echo ""
    echo -e "${GREEN}${BOLD}Domain deleted successfully!${NC}"
    echo -e "The virtual host '${CYAN}$app${NC}' is now accessible only via its username"
    echo ""
}

