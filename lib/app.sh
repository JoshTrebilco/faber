#!/bin/bash

#############################################
# App Management Functions
#############################################

# Create app
app_create() {
    local username=""
    local repository=""
    local branch=""
    local php_version="8.4"
    local interactive=true
    local skip_reverb=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --user=*)
                username="${arg#*=}"
                ;;
            --repository=*)
                repository="${arg#*=}"
                ;;
            --branch=*)
                branch="${arg#*=}"
                ;;
            --php=*)
                php_version="${arg#*=}"
                ;;
            --skip-reverb)
                skip_reverb=true
                ;;
        esac
    done
    
    # If all parameters provided, non-interactive mode
    if [ -n "$username" ] && [ -n "$repository" ] && [ -n "$php_version" ]; then
        interactive=false
    fi
    
    # Interactive prompts
    if [ $interactive = true ]; then
        echo -e "${BOLD}Create New App${NC}"
        echo "─────────────────────────────────────"
        echo ""
        
        if [ -z "$username" ]; then
            default_username=$(generate_username)
            read -p "Username [$default_username]: " username
            username=${username:-$default_username}
        fi
        
        if [ -z "$repository" ]; then
            read -p "Git repository URL: " repository
        fi
        
        if [ -z "$branch" ]; then
            read -p "Git branch [main]: " branch
            branch=${branch:-main}
        fi
        
        if [ -z "$php_version" ]; then
            echo ""
            echo "Select PHP version:"
            local php_versions=($(get_installed_php_versions))
            local i=1
            for version in "${php_versions[@]}"; do
                echo "  $i. PHP $version"
                ((i++))
            done
            read -p "Choice [1]: " php_choice
            php_choice=${php_choice:-1}
            php_version=${php_versions[$((php_choice-1))]}
        fi
        
        # Reverb configuration (if Reverb is set up)
        if reverb_is_configured && [ "$skip_reverb" = false ]; then
            echo ""
            read -p "Connect to Reverb WebSocket server? (Y/n): " enable_reverb
            if [ "$enable_reverb" = "n" ] || [ "$enable_reverb" = "N" ]; then
                skip_reverb=true
            fi
        fi
    fi
    
    # Validate inputs
    if [ -z "$username" ] || [ -z "$repository" ]; then
        echo -e "${RED}Error: Username and repository are required${NC}"
        exit 1
    fi
    
    # Validate HTTPS URL format (reject SSH)
    if ! github_validate_https_url "$repository"; then
        exit 1
    fi
    
    # Validate GitHub App is configured
    if ! github_app_is_configured; then
        echo -e "${RED}Error: GitHub App not configured${NC}"
        echo ""
        echo "Configure the GitHub App credentials:"
        echo "  faber github set app_id \"YOUR_APP_ID\""
        echo "  faber github set private_key \"\$(cat /path/to/key.pem)\""
        echo "  faber github set slug \"your-app-name\""
        exit 1
    fi
    
    # Check GitHub App is installed on this repo (fail fast)
    local owner_repo=$(github_parse_repo "$repository")
    echo -e "${CYAN}Checking GitHub App access...${NC}"
    if ! github_app_check_installation "$owner_repo"; then
        local app_slug=$(get_github_config "github_app_slug")
        app_slug=${app_slug:-"faber-deploy"}
        echo -e "${RED}Error: GitHub App not installed on $owner_repo${NC}"
        echo ""
        echo "Install the Faber GitHub App on this repository:"
        echo -e "${CYAN}https://github.com/apps/$app_slug/installations/new${NC}"
        echo ""
        echo "After installing, re-run this command."
        exit 1
    fi
    echo -e "${GREEN}✓ GitHub App access confirmed${NC}"
    
    # Check if app already exists
    if json_has_key "${APPS_FILE}" "$username"; then
        echo -e "${RED}Error: App '$username' already exists${NC}"
        exit 1
    fi
    
    # Check if PHP version is installed
    if ! is_php_installed "$php_version"; then
        echo -e "${YELLOW}PHP $php_version is not installed. Installing...${NC}"
        install_php_version "$php_version"
    fi
    
    echo ""
    echo -e "${CYAN}Creating virtual host...${NC}"
    
    # Generate password
    local password=$(generate_password 24)
    
    # Create system user (includes group creation and www-data access)
    echo "  → Creating system user..."
    if ! create_system_user "$username" "$password"; then
        echo -e "${RED}Error: Failed to create system user${NC}"
        exit 1
    fi
    
    # Create directory structure (Envoyer-style zero-downtime deployment)
    echo "  → Creating directory structure..."
    local home_dir="/home/$username"
    local release_name=$(date +%Y%m%d%H%M%S)
    local release_dir="$home_dir/releases/$release_name"
    
    mkdir -p "$home_dir"/{releases,logs}
    mkdir -p "$home_dir/storage"/{app,framework,logs}
    mkdir -p "$home_dir/storage/framework"/{cache,sessions,views}
    
    chown -R "$username:$username" "$home_dir"
    chmod 755 "$home_dir"  # Allow traversal (needed for nginx to reach current)
    chmod 755 "$home_dir/logs"  # Logs readable by web server if needed
    chmod -R 775 "$home_dir/storage"  # Shared storage needs to be writable
    
    # Repository URL is already validated as HTTPS
    local owner_repo=$(github_parse_repo "$repository")
    
    # Get installation token for cloning
    local clone_token=$(github_app_get_token "$owner_repo")
    local auth_url="https://x-access-token:${clone_token}@github.com/${owner_repo}.git"
    
    echo "  → Cloning repository..."
    sudo -u "$username" git clone -b "$branch" --depth 1 "$auth_url" "$release_dir" 2>/dev/null
    
    # Store plain HTTPS URL (without token) as remote for future pulls
    sudo -u "$username" git -C "$release_dir" remote set-url origin "$repository"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        delete_system_user "$username"
        rm -rf "$home_dir"
        exit 1
    fi
    
    # Set web-accessible permissions (group-based access for nginx)
    echo "  → Setting web permissions..."
    chown -R "$username:$username" "$release_dir"
    find "$release_dir" -type d -exec chmod 750 {} \;
    find "$release_dir" -type f -exec chmod 640 {} \;
    
    # Setup shared resources symlinks
    echo "  → Setting up shared resources..."
    
    # Remove storage from release and symlink to shared storage
    if [ -d "$release_dir/storage" ]; then
        # Copy initial storage structure to shared storage if needed
        if [ ! -d "$home_dir/storage/app/public" ]; then
            cp -r "$release_dir/storage/app/public" "$home_dir/storage/app/" 2>/dev/null || true
        fi
        rm -rf "$release_dir/storage"
    fi
    sudo -u "$username" ln -s "$home_dir/storage" "$release_dir/storage"
    
    # Create shared .env from .env.example if it exists
    if [ ! -f "$home_dir/.env" ]; then
        if [ -f "$release_dir/.env.example" ]; then
            cp "$release_dir/.env.example" "$home_dir/.env"
            chown "$username:$username" "$home_dir/.env"
            chmod 640 "$home_dir/.env"
        else
            touch "$home_dir/.env"
            chown "$username:$username" "$home_dir/.env"
            chmod 640 "$home_dir/.env"
        fi
    fi
    
    # Remove .env from release and symlink to shared .env
    rm -f "$release_dir/.env" 2>/dev/null || true
    sudo -u "$username" ln -s "$home_dir/.env" "$release_dir/.env"
    
    # Create current symlink pointing to first release
    echo "  → Activating release..."
    sudo -u "$username" ln -sfn "$release_dir" "$home_dir/current"
    
    # Create PHP-FPM pool
    echo "  → Creating PHP-FPM pool..."
    create_php_pool "$username" "$php_version"
    
    # Create Nginx configuration
    echo "  → Creating Nginx configuration..."
    create_nginx_config "$username" "" "$php_version"
    
    # Create deployment script
    echo "  → Creating deployment script..."
    create_deploy_script "$username" "$repository" "$branch"
    
    # Generate webhook secret
    echo "  → Generating webhook secret..."
    local webhook_secret=$(generate_webhook_secret)
    set_webhook "$username" "$webhook_secret"
    
    # Create GitHub webhook using the same token from earlier
    local webhook_create_failed=false
    if [ -n "$github_access_token" ] && [ -n "$owner_repo" ]; then
        local webhook_domain=$(get_config "webhook_domain")
        if [ -n "$webhook_domain" ]; then
            echo "  → Creating GitHub webhook..."
            local webhook_url="https://$webhook_domain/webhook/$username"
            
            if ! github_create_webhook "$github_access_token" "$owner_repo" "$webhook_url" "$webhook_secret"; then
                webhook_create_failed=true
            fi
        fi
    fi
    
    # Clear the token after use
    if [ -n "$github_access_token" ]; then
        unset github_access_token
    fi

    # Create log rotation
    echo "  → Creating log rotation..."
    create_log_rotation "$username"
    
    # Ensure web permissions are maintained
    find "$home_dir/current" -type d -exec chmod 750 {} \; 2>/dev/null || true
    find "$home_dir/current" -type f -exec chmod 640 {} \; 2>/dev/null || true
    
    # Laravel bootstrap/cache needs to be writable by app user
    if [ -d "$home_dir/current/bootstrap/cache" ]; then
        chmod -R 775 "$home_dir/current/bootstrap/cache"
        chgrp -R "$username" "$home_dir/current/bootstrap/cache"
    fi
    
    # Shared storage is already writable (set up earlier)
    
    # Configure Reverb client (if Reverb is set up and not skipped)
    if [ "$skip_reverb" = false ] && reverb_is_configured && [ -f "$home_dir/current/artisan" ]; then
        echo "  → Configuring Reverb client..."
        configure_app_for_reverb "$username"
    fi
    
    # Create crontab for user
    echo "  → Creating crontab..."
    create_user_crontab "$username"
    
    # Reload nginx to pick up new group membership
    echo "  → Reloading Nginx..."
    systemctl reload nginx 2>/dev/null || true
    nginx_reload
    
    # Save to storage (password not saved for security)
    local app_data=$(cat <<EOF
{
    "username": "$username",
    "repository": "$repository",
    "branch": "$branch",
    "php_version": "$php_version",
    "home_dir": "$home_dir",
    "created_at": "$(date -Iseconds)"
}
EOF
)
    json_set "${APPS_FILE}" "$username" "$app_data"
    
    # Display summary
    echo ""
    echo -e "${GREEN}${BOLD}App created successfully!${NC}"
    echo "─────────────────────────────────────"
    echo -e "Path:     ${CYAN}$home_dir${NC}"
    echo -e "Username: ${CYAN}$username${NC}"
    echo -e "Password: ${CYAN}$password${NC}"
    echo -e "PHP:      ${CYAN}$php_version${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}IMPORTANT: Save these credentials!${NC}"
    echo ""
    
    # Show manual webhook instructions only if auto-create failed or wasn't attempted
    if [ "$webhook_create_failed" = true ] || [ -z "$github_client_id" ]; then
        echo -e "${CYAN}${BOLD}GitHub Webhook (Auto-Deploy):${NC}"
        local webhook_domain=$(get_config "webhook_domain")
        if [ -n "$webhook_domain" ]; then
            echo -e "URL:           ${CYAN}https://$webhook_domain/webhook/$username${NC}"
        else
            echo -e "${YELLOW}Warning: Webhook domain not configured${NC}"
            echo -e "URL:           ${CYAN}(webhook domain required)${NC}"
        fi
        echo -e "Content type:  ${CYAN}application/json${NC}"
        echo -e "Secret:        ${CYAN}$webhook_secret${NC}"
        echo -e "Events:        ${CYAN}Just the push event${NC}"
        echo ""
        if [ "$webhook_create_failed" = true ]; then
            echo -e "${YELLOW}Automatic webhook creation failed. Please configure manually:${NC}"
        fi
        echo -e "${CYAN}${BOLD}Next Steps:${NC}"
        echo -e "1. Configure GitHub webhook with the above settings"
        echo -e "2. Assign domain: ${CYAN}faber domain create${NC}"
        echo ""
    fi
}

# List apps
app_list() {
    echo -e "${BOLD}Apps${NC}"
    echo "─────────────────────────────────────"
    echo ""
    
    local apps=$(json_keys "${APPS_FILE}")
    
    if [ -z "$apps" ]; then
        echo "No virtual hosts found."
        echo ""
        return
    fi
    
    printf "%-15s %-10s %-30s\n" "USERNAME" "PHP" "DOMAIN"
    echo "───────────────────────────────────────────────────────────"
    
    for username in $apps; do
        local php_version=$(get_app_field "$username" "php_version")
        local domain=$(get_domain_by_app "$username")
        domain=${domain:-"(no domain)"}
        
        printf "%-15s %-10s %-30s\n" "$username" "$php_version" "$domain"
    done
    
    echo ""
}

# Show app details
app_show() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app show <username>"
        exit 1
    fi
    
    check_app_exists "$username"
    
    local home_dir=$(get_app_field "$username" "home_dir")
    local php_version=$(get_app_field "$username" "php_version")
    local repository=$(get_app_field "$username" "repository")
    local branch=$(get_app_field "$username" "branch")
    local domain=$(get_domain_by_app "$username")
    local disk_space=$(get_disk_space "$home_dir")
    
    # Get current release info
    local current_release=""
    local release_count=0
    if [ -L "$home_dir/current" ]; then
        current_release=$(basename "$(readlink -f "$home_dir/current")")
    fi
    if [ -d "$home_dir/releases" ]; then
        release_count=$(ls -1d "$home_dir/releases"/*/ 2>/dev/null | wc -l)
    fi
    
    echo -e "${BOLD}App: $username${NC}"
    echo "─────────────────────────────────────"
    echo -e "Path:       ${CYAN}$home_dir${NC}"
    echo -e "Username:   ${CYAN}$username${NC}"
    echo -e "PHP:        ${CYAN}$php_version${NC}"
    echo -e "Repository: ${CYAN}$repository${NC}"
    echo -e "Branch:     ${CYAN}$branch${NC}"
    echo -e "Domain:     ${CYAN}${domain:-(no domain)}${NC}"
    echo -e "Disk Space: ${CYAN}$disk_space${NC}"
    echo ""
    echo -e "${BOLD}Releases:${NC}"
    echo -e "Current:    ${CYAN}${current_release:-(none)}${NC}"
    echo -e "Total:      ${CYAN}$release_count${NC}"
    if [ -d "$home_dir/releases" ] && [ "$release_count" -gt 0 ]; then
        echo -e "Available:  ${CYAN}$(ls -1d "$home_dir/releases"/*/ 2>/dev/null | xargs -n1 basename | tr '\n' ' ')${NC}"
    fi
    
    # Show webhook information
    webhook_show "$username"
}

# Edit app
app_edit() {
    local username=""
    local new_php_version=""
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --php=*)
                new_php_version="${arg#*=}"
                ;;
            *)
                if [ -z "$username" ]; then
                    username="$arg"
                fi
                ;;
        esac
    done
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app edit <username> --php=X.X"
        exit 1
    fi
    
    check_app_exists "$username"
    
    # Get current app data
    local vhost=$(get_app "$username")
    local current_php=$(get_app_field "$username" "php_version")
    local home_dir=$(get_app_field "$username" "home_dir")
    
    # Edit PHP version
    if [ -n "$new_php_version" ]; then
        echo -e "${CYAN}Changing PHP version from $current_php to $new_php_version...${NC}"
        
        # Check if new PHP version is installed
        if ! is_php_installed "$new_php_version"; then
            echo -e "${YELLOW}PHP $new_php_version is not installed. Installing...${NC}"
            install_php_version "$new_php_version"
        fi
        
        # Delete old PHP pool
        echo "  → Removing old PHP-FPM pool..."
        delete_php_pool "$username" "$current_php"
        
        # Create new PHP pool
        echo "  → Creating new PHP-FPM pool..."
        create_php_pool "$username" "$new_php_version"
        
        # Update Nginx configuration
        echo "  → Updating Nginx configuration..."
        local domain=$(get_domain_by_app "$username")
        if [ -n "$domain" ]; then
            local ssl=$(get_domain_field "$domain" "ssl")
            
            if [ "$ssl" = "true" ]; then
                add_ssl_to_nginx "$username" "$domain" "$new_php_version"
            else
                create_nginx_config "$username" "$domain" "$new_php_version"
            fi
        else
            create_nginx_config "$username" "" "$new_php_version"
        fi
        
        # Update storage
        set_app_field "$username" "php_version" "$new_php_version"
        
        # Reload services
        echo "  → Reloading services..."
        nginx_reload
        
        echo ""
        echo -e "${GREEN}PHP version updated successfully!${NC}"
        echo -e "Old version: ${CYAN}$current_php${NC}"
        echo -e "New version: ${CYAN}$new_php_version${NC}"
        echo ""
    else
        echo -e "${RED}Error: No changes specified${NC}"
        echo "Usage: faber app edit <username> --php=X.X"
        exit 1
    fi
}

# Edit app .env file
app_env() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app env <username>"
        exit 1
    fi
    
    check_app_exists "$username"
    
    local home_dir=$(get_app_field "$username" "home_dir")
    # Shared .env is in home directory (not in releases)
    local env_file="$home_dir/.env"
    
    if [ ! -f "$env_file" ]; then
        echo -e "${YELLOW}Warning: .env file not found at $env_file${NC}"
        echo ""
        read -p "Do you want to create it from .env.example? (y/N): " create_env
        
        if [ "$create_env" = "y" ] || [ "$create_env" = "Y" ]; then
            if [ -f "$home_dir/current/.env.example" ]; then
                cp "$home_dir/current/.env.example" "$env_file"
                chown "$username:$username" "$env_file"
                chmod 640 "$env_file"
                echo -e "${GREEN}Created .env from .env.example${NC}"
            else
                echo -e "${RED}Error: .env.example not found${NC}"
                exit 1
            fi
        else
            exit 0
        fi
    fi
    
    echo -e "${CYAN}Opening .env editor for: $username${NC}"
    echo -e "File: ${CYAN}$env_file${NC}"
    echo -e "${YELLOW}Note: This .env is shared across all releases${NC}"
    echo ""
    echo -e "${YELLOW}Tip: After editing, you may need to clear config cache:${NC}"
    echo -e "  ${CYAN}cd $home_dir/current && php artisan config:cache${NC}"
    echo ""
    sleep 2
    
    # Set nano as editor and open file as the app user
    export EDITOR=nano
    export VISUAL=nano
    sudo -u "$username" -E nano "$env_file"
    
    echo ""
    echo -e "${GREEN}.env file saved${NC}"
    echo ""
}

# Edit app crontab
app_crontab() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app crontab <username>"
        exit 1
    fi
    
    check_app_exists "$username"
    
    echo -e "${BOLD}Edit Crontab for: $username${NC}"
    echo "─────────────────────────────────────"
    echo ""
    echo -e "${CYAN}Opening crontab editor...${NC}"
    echo ""
    echo -e "${YELLOW}Tip: Add this line for Laravel scheduler:${NC}"
    echo -e "  ${CYAN}* * * * * cd /home/$username/current && php artisan schedule:run >> /dev/null 2>&1${NC}"
    echo ""
    echo -e "${YELLOW}Note: Use 'current' symlink to always run the active release${NC}"
    echo ""
    sleep 3
    
    # Set nano as editor and open crontab as the app user
    export EDITOR=nano
    export VISUAL=nano
    sudo -u "$username" -E crontab -e
    
    echo ""
    echo -e "${GREEN}Crontab updated${NC}"
    echo ""
    echo -e "${CYAN}View current crontab:${NC}"
    echo -e "  sudo crontab -u $username -l"
    echo ""
}

# Change app password
app_password() {
    local username=$1
    local new_password=""
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --password=*)
                new_password="${arg#*=}"
                ;;
        esac
    done
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app password <username> [--password=XXX]"
        exit 1
    fi
    
    check_app_exists "$username"
    
    echo -e "${BOLD}Change Password for: $username${NC}"
    echo "─────────────────────────────────────"
    echo ""
    
    # Generate or use provided password
    if [ -z "$new_password" ]; then
        new_password=$(generate_password 24)
        echo "Generated new password: ${CYAN}$new_password${NC}"
    else
        echo "Using provided password"
    fi
    
    echo ""
    echo -e "${CYAN}Changing password...${NC}"
    
    # Change system user password
    echo "$username:$new_password" | chpasswd
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to change password${NC}"
        exit 1
    fi
    
    # Note: Password is not stored in JSON for security reasons
    
    echo ""
    echo -e "${GREEN}${BOLD}Password changed successfully!${NC}"
    echo "─────────────────────────────────────"
    echo -e "Username: ${CYAN}$username${NC}"
    echo -e "New Password: ${CYAN}$new_password${NC}"
    echo ""
    echo -e "${YELLOW}${BOLD}IMPORTANT: Save this password!${NC}"
    echo ""
}

# Delete app
app_delete() {
    local username=""
    local force=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --force)
                force=true
                ;;
            *)
                if [ -z "$username" ]; then
                    username="$arg"
                fi
                ;;
        esac
    done
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app delete <username> [--force]"
        exit 1
    fi
    
    # Check if app exists (unless force mode)
    if [ "$force" = false ]; then
        check_app_exists "$username"
    else
        # In force mode, check if any resources exist
        local has_resources=false
        if id "$username" &>/dev/null 2>&1; then
            has_resources=true
        elif [ -d "/home/$username" ]; then
            has_resources=true
        elif [ -f "${NGINX_SITES_AVAILABLE}/${username}" ] || [ -f "${NGINX_SITES_ENABLED}/${username}" ]; then
            has_resources=true
        fi
        
        if [ "$has_resources" = false ]; then
            echo -e "${YELLOW}No resources found for user '$username'${NC}"
            exit 0
        fi
    fi
    
    # Confirm deletion (skip in force mode)
    if [ "$force" = false ]; then
        echo -e "${YELLOW}${BOLD}Warning: This will permanently delete the virtual host and all its data!${NC}"
        read -p "Type the username to confirm: " confirm
        
        if [ "$confirm" != "$username" ]; then
            echo "Deletion cancelled."
            exit 0
        fi
    else
        echo -e "${YELLOW}${BOLD}Force mode: Cleaning up orphaned resources for '$username'${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Deleting virtual host...${NC}"
    
    # Try to get PHP version from app data, or detect from pool configs
    local php_version=$(get_app_field "$username" "php_version")
    
    if [ -z "$php_version" ] || [ "$php_version" = "null" ]; then
        # Try to detect PHP version from pool config
        local php_versions=($(get_installed_php_versions))
        for version in "${php_versions[@]}"; do
            if [ -f "/etc/php/${version}/fpm/pool.d/${username}.conf" ]; then
                php_version="$version"
                break
            fi
        done
    fi
    
    # Delete associated domain
    echo "  → Deleting associated domain..."
    if [ "$force" = false ]; then
        delete_domain_by_app "$username"
    else
        # In force mode, try to find and delete domain manually
        local domains=$(json_keys "${DOMAINS_FILE}")
        for domain in $domains; do
            local domain_app=$(get_domain_field "$domain" "app")
            if [ "$domain_app" = "$username" ]; then
                local has_ssl=$(get_domain_field "$domain" "ssl")
                has_ssl=${has_ssl:-false}
                if [ "$has_ssl" = "true" ]; then
                    cleanup_ssl_certificate "$domain" 2>/dev/null || true
                fi
                json_delete "${DOMAINS_FILE}" "$domain" 2>/dev/null || true
                break
            fi
        done
    fi
    
    # Delete Nginx configuration
    echo "  → Deleting Nginx configuration..."
    delete_nginx_config "$username"
    
    # Delete PHP-FPM pool(s)
    echo "  → Deleting PHP-FPM pool(s)..."
    if [ -n "$php_version" ] && [ "$php_version" != "null" ]; then
        delete_php_pool "$username" "$php_version"
    else
        # If PHP version unknown, try all installed versions
        local php_versions=($(get_installed_php_versions))
        for version in "${php_versions[@]}"; do
            delete_php_pool "$username" "$version"
        done
    fi
    
    # Delete user crontab
    echo "  → Deleting crontab..."
    crontab -r -u "$username" 2>/dev/null || true
    
    # Delete system user and home directory
    echo "  → Deleting system user and files..."
    delete_system_user "$username"
    
    # Delete log rotation config
    echo "  → Deleting log rotation config..."
    rm -f "/etc/logrotate.d/faber-$username"
    
    # Delete GitHub webhook using app token
    local repository=$(get_app_field "$username" "repository")
    
    if [ -n "$repository" ] && [ "$repository" != "null" ]; then
        local owner_repo=$(github_parse_repo "$repository")
        
        if [ -n "$owner_repo" ] && github_app_is_configured; then
            echo "  → Removing GitHub webhook..."
            local access_token=$(github_app_get_token "$owner_repo")
            
            if [ -n "$access_token" ]; then
                local webhook_domain=$(get_config "webhook_domain")
                if [ -n "$webhook_domain" ]; then
                    local webhook_url="https://$webhook_domain/webhook/$username"
                    github_delete_webhook "$access_token" "$owner_repo" "$webhook_url" 2>&1 || true
                fi
            fi
        fi
    fi
    
    # Delete local webhook secret
    echo "  → Deleting webhook secret..."
    delete_webhook "$username" 2>/dev/null || true
    
    # Remove from storage (only if exists)
    if json_has_key "${APPS_FILE}" "$username"; then
        json_delete "${APPS_FILE}" "$username"
    fi
    
    # Reload nginx
    echo "  → Reloading Nginx..."
    nginx_reload
    
    echo ""
    echo -e "${GREEN}App deleted successfully!${NC}"
    echo ""
}

# Helper: Delete domain by app
delete_domain_by_app() {
    local username=$1
    local domain=$(get_domain_by_app "$username")
    
    if [ -n "$domain" ]; then
        # Get domain data to check for SSL
        local has_ssl=$(get_domain_field "$domain" "ssl")
        has_ssl=${has_ssl:-false}
        
        # Cleanup SSL certificate if exists
        if [ "$has_ssl" = "true" ]; then
            cleanup_ssl_certificate "$domain"
        fi
        
        json_delete "${DOMAINS_FILE}" "$domain"
    fi
}

# Helper: Create user crontab
create_user_crontab() {
    local username=$1
    local home_dir="/home/$username"
    
    # Create crontab for Laravel scheduler (if Laravel detected)
    # Uses current symlink for zero-downtime deployments
    if [ -f "$home_dir/current/artisan" ]; then
        # Only add if schedule:run entry doesn't already exist
        if ! crontab -u "$username" -l 2>/dev/null | grep -q "schedule:run"; then
            (crontab -u "$username" -l 2>/dev/null; echo "* * * * * cd $home_dir/current && php artisan schedule:run >> /dev/null 2>&1") | crontab -u "$username" -
        fi
    fi
}

# Helper: Create log rotation
create_log_rotation() {
    local username=$1
    local log_dir="/home/$username/logs"
    
    cat > "/etc/logrotate.d/faber-$username" <<EOF
$log_dir/*.log {
    daily
    rotate 30
    missingok
    notifempty
    compress
    delaycompress
    sharedscripts
    postrotate
        systemctl reload nginx > /dev/null 2>&1
    endscript
}
EOF
}

# Rollback to previous release
app_rollback() {
    local username=$1
    local target_release=$2
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app rollback <username> [release]"
        exit 1
    fi
    
    check_app_exists "$username"
    
    local home_dir=$(get_app_field "$username" "home_dir")
    local releases_dir="$home_dir/releases"
    local current_link="$home_dir/current"
    
    # Check if releases directory exists
    if [ ! -d "$releases_dir" ]; then
        echo -e "${RED}Error: No releases directory found${NC}"
        exit 1
    fi
    
    # Get list of available releases (sorted oldest first)
    local releases=($(ls -1d "$releases_dir"/*/ 2>/dev/null | xargs -n1 basename | sort))
    local release_count=${#releases[@]}
    
    if [ "$release_count" -eq 0 ]; then
        echo -e "${RED}Error: No releases available${NC}"
        exit 1
    fi
    
    # Get current release
    local current_release=""
    if [ -L "$current_link" ]; then
        current_release=$(basename "$(readlink -f "$current_link")")
    fi
    
    echo -e "${BOLD}Rollback: $username${NC}"
    echo "─────────────────────────────────────"
    echo -e "Current release: ${CYAN}$current_release${NC}"
    echo ""
    
    # If no target release specified, show available releases
    if [ -z "$target_release" ]; then
        echo -e "${BOLD}Available releases:${NC}"
        local i=1
        for release in "${releases[@]}"; do
            if [ "$release" = "$current_release" ]; then
                echo -e "  $i. ${GREEN}$release${NC} (current)"
            else
                echo -e "  $i. $release"
            fi
            ((i++))
        done
        echo ""
        
        # Find the previous release (one before current)
        local prev_release=""
        for ((i=${#releases[@]}-1; i>=0; i--)); do
            if [ "${releases[$i]}" = "$current_release" ] && [ $i -gt 0 ]; then
                prev_release="${releases[$((i-1))]}"
                break
            fi
        done
        
        if [ -z "$prev_release" ]; then
            echo -e "${YELLOW}No previous release available to rollback to.${NC}"
            echo ""
            read -p "Enter release name to rollback to (or Ctrl+C to cancel): " target_release
        else
            read -p "Rollback to $prev_release? (Y/n): " confirm
            if [ "$confirm" = "n" ] || [ "$confirm" = "N" ]; then
                read -p "Enter release name to rollback to: " target_release
            else
                target_release="$prev_release"
            fi
        fi
    fi
    
    # Validate target release exists
    if [ ! -d "$releases_dir/$target_release" ]; then
        echo -e "${RED}Error: Release '$target_release' not found${NC}"
        exit 1
    fi
    
    # Don't rollback to current release
    if [ "$target_release" = "$current_release" ]; then
        echo -e "${YELLOW}Already on release $target_release${NC}"
        exit 0
    fi
    
    echo ""
    echo -e "${CYAN}Rolling back to: $target_release${NC}"
    
    # Atomic symlink switch
    ln -sfn "$releases_dir/$target_release" "$current_link"
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to switch symlink${NC}"
        exit 1
    fi
    
    # Post-rollback tasks for Laravel
    if [ -f "$current_link/artisan" ]; then
        echo "→ Restarting queue workers..."
        sudo -u "$username" php "$current_link/artisan" queue:restart 2>/dev/null || true
        
        echo "→ Clearing config cache..."
        sudo -u "$username" php "$current_link/artisan" config:cache 2>/dev/null || true
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}Rollback successful!${NC}"
    echo "─────────────────────────────────────"
    echo -e "Previous: ${CYAN}$current_release${NC}"
    echo -e "Current:  ${CYAN}$target_release${NC}"
    echo ""
}

# List releases for an app
app_releases() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber app releases <username>"
        exit 1
    fi
    
    check_app_exists "$username"
    
    local home_dir=$(get_app_field "$username" "home_dir")
    local releases_dir="$home_dir/releases"
    local current_link="$home_dir/current"
    
    # Get current release
    local current_release=""
    if [ -L "$current_link" ]; then
        current_release=$(basename "$(readlink -f "$current_link")")
    fi
    
    echo -e "${BOLD}Releases: $username${NC}"
    echo "─────────────────────────────────────"
    
    if [ ! -d "$releases_dir" ]; then
        echo "No releases directory found."
        echo ""
        return
    fi
    
    local releases=($(ls -1d "$releases_dir"/*/ 2>/dev/null | xargs -n1 basename | sort -r))
    
    if [ ${#releases[@]} -eq 0 ]; then
        echo "No releases found."
        echo ""
        return
    fi
    
    printf "%-20s %-12s %s\n" "RELEASE" "STATUS" "SIZE"
    echo "───────────────────────────────────────────"
    
    for release in "${releases[@]}"; do
        local status=""
        if [ "$release" = "$current_release" ]; then
            status="${GREEN}active${NC}"
        else
            status="available"
        fi
        
        local size=$(du -sh "$releases_dir/$release" 2>/dev/null | awk '{print $1}')
        
        if [ "$release" = "$current_release" ]; then
            printf "${GREEN}%-20s${NC} ${GREEN}%-12s${NC} %s\n" "$release" "active" "$size"
        else
            printf "%-20s %-12s %s\n" "$release" "$status" "$size"
        fi
    done
    
    echo ""
    echo -e "Total releases: ${CYAN}${#releases[@]}${NC}"
    echo ""
    echo -e "${CYAN}Commands:${NC}"
    echo "  Rollback to previous: faber app rollback $username"
    echo "  Rollback to specific: faber app rollback $username <release>"
    echo ""
}

