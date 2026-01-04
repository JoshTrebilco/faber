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

# Helper: Setup SSL certificate for domain
setup_ssl_certificate() {
    local domain=$1
    local app=$2
    local php_version=$3
    local domain_data=$4
    
    echo "  → Setting up SSL certificate..."
    local ssl_email=$(get_config "ssl_email")
    
    if [ -z "$ssl_email" ]; then
        echo -e "  ${YELLOW}⚠ SSL email not configured, skipping SSL setup${NC}"
        echo -e "  ${YELLOW}Configure with: cipi config set ssl_email your@email.com${NC}"
        return 1
    fi
    
    # Ensure HTTP-only config exists (should already exist from app creation and update_nginx_domain)
    # The HTTP config is needed for certbot validation
    local config_file="${NGINX_SITES_AVAILABLE}/${app}"
    if [ ! -f "$config_file" ]; then
        echo -e "  ${YELLOW}⚠ HTTP config not found, creating it...${NC}"
        create_nginx_config "$app" "$domain" "$php_version"
        nginx_reload
    fi
    
    # Request SSL certificate (certbot will use existing HTTP config for validation)
    if certbot certonly --nginx -d "$domain" --non-interactive --agree-tos --email "$ssl_email" >/dev/null 2>&1; then
        # Check if certificate was actually obtained
        if [ -d "/etc/letsencrypt/live/$domain" ]; then
            # Create full SSL config (overwrites certbot's auto-config with our standardized config)
            if add_ssl_to_nginx "$app" "$domain" "$php_version"; then
                # Update domain storage to set ssl: true
                local updated_data=$(echo "$domain_data" | jq '.ssl = true')
                json_set "${DOMAINS_FILE}" "$domain" "$updated_data"
                nginx_reload
                echo -e "  ${GREEN}✓ SSL certificate installed and configured${NC}"
                return 0
            else
                echo -e "  ${YELLOW}⚠ Certificate obtained but failed to update Nginx config${NC}"
                return 1
            fi
        else
            echo -e "  ${YELLOW}⚠ Certificate directory not found${NC}"
            return 1
        fi
    else
        echo -e "  ${YELLOW}⚠ SSL certificate setup failed (DNS may not be configured yet)${NC}"
        echo -e "  ${YELLOW}Domain will work on HTTP. SSL can be configured later.${NC}"
        return 1
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
    
    # Check if domain already exists
    if domain_exists "$domain"; then
        local owner_app=$(get_domain_field "$domain" "app")
        echo -e "${RED}Error: Domain '$domain' is already taken${NC}"
        echo -e "  Used by app: ${CYAN}$owner_app${NC}"
        exit 1
    fi
    
    # Check if app exists
    check_app_exists "$app"
    
    # Check if app already has a domain
    local existing_domain=$(get_domain_by_app "$app")
    if [ -n "$existing_domain" ]; then
        echo -e "${RED}Error: App '$app' already has a domain assigned${NC}"
        echo -e "  Existing domain: ${CYAN}$existing_domain${NC}"
        echo -e "  Delete the existing domain first: ${CYAN}cipi domain delete $existing_domain${NC}"
        exit 1
    fi
    
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
    
    # Save to storage (initially without SSL)
    local domain_data=$(jq -n \
        --arg vh "$app" \
        '{app: $vh, ssl: false}')
    
    json_set "${DOMAINS_FILE}" "$domain" "$domain_data"
    
    # Attempt automatic SSL setup
    local ssl_success=false
    if setup_ssl_certificate "$domain" "$app" "$php_version" "$domain_data"; then
        ssl_success=true
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}Domain assigned successfully!${NC}"
    echo "─────────────────────────────────────"
    echo -e "Domain:       ${CYAN}$domain${NC}"
    echo -e "Virtual Host: ${CYAN}$app${NC}"
    if [ "$ssl_success" = true ]; then
        echo -e "SSL:          ${GREEN}Enabled${NC}"
    else
        echo -e "SSL:          ${YELLOW}Not configured${NC}"
    fi
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

