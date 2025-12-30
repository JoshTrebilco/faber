#!/bin/bash

#############################################
# Provision Functions - Full App Setup
#############################################

# Provision create - full app setup (app + domain + database + .env + SSL + deploy)
provision_create() {
    local username=""
    local repository=""
    local branch=""
    local php_version="8.4"
    local domain=""
    local aliases=""
    local dbname=""
    local app_env="production"
    
    # Default: everything enabled
    local skip_db=false
    local skip_domain=false
    local skip_env=false
    local skip_ssl=false
    local skip_deploy=false
    local ssl_email=""
    
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
            --domain=*)
                domain="${arg#*=}"
                ;;
            --aliases=*)
                aliases="${arg#*=}"
                ;;
            --dbname=*)
                dbname="${arg#*=}"
                ;;
            --env=*)
                app_env="${arg#*=}"
                ;;
            --skip-db)
                skip_db=true
                ;;
            --skip-domain)
                skip_domain=true
                ;;
            --skip-env)
                skip_env=true
                ;;
            --skip-ssl)
                skip_ssl=true
                ;;
            --skip-deploy)
                skip_deploy=true
                ;;
            --ssl-email=*)
                ssl_email="${arg#*=}"
                ;;
        esac
    done
    
    # Validate required parameters
    if [ -z "$username" ] || [ -z "$repository" ]; then
        echo -e "${RED}Error: --user and --repository are required${NC}"
        echo ""
        echo "Usage: cipi provision create --user=USERNAME --repository=REPO_URL [options]"
        echo ""
        echo "Required:"
        echo "  --user=USERNAME          App username"
        echo "  --repository=REPO_URL    Git repository URL"
        echo ""
        echo "Optional:"
        echo "  --domain=DOMAIN          Domain name (required unless --skip-domain)"
        echo "  --branch=BRANCH          Git branch (default: main)"
        echo "  --php=VERSION            PHP version (default: 8.4)"
        echo "  --aliases=ALIASES        Comma-separated domain aliases"
        echo "  --dbname=DBNAME          Database name (auto-generated if not provided)"
        echo "  --env=ENV                APP_ENV value (default: production)"
        echo "  --ssl-email=EMAIL        Email for Let's Encrypt certificate"
        echo ""
        echo "Skip flags (all features enabled by default):"
        echo "  --skip-db                Skip database creation"
        echo "  --skip-domain            Skip domain creation"
        echo "  --skip-env               Skip .env file updates"
        echo "  --skip-ssl               Skip SSL certificate setup"
        echo "  --skip-deploy            Skip initial deployment"
        echo ""
        exit 1
    fi
    
    # Validate domain if not skipped
    if [ "$skip_domain" = false ] && [ -z "$domain" ]; then
        echo -e "${RED}Error: --domain is required unless --skip-domain is used${NC}"
        exit 1
    fi
    
    echo -e "${BOLD}Provision App${NC}"
    echo "─────────────────────────────────────"
    echo -e "User:       ${CYAN}$username${NC}"
    echo -e "Repository: ${CYAN}$repository${NC}"
    echo -e "Branch:     ${CYAN}$branch${NC}"
    echo -e "PHP:        ${CYAN}$php_version${NC}"
    [ "$skip_domain" = false ] && echo -e "Domain:     ${CYAN}$domain${NC}"
    [ -n "$aliases" ] && echo -e "Aliases:    ${CYAN}$aliases${NC}"
    echo ""
    
    # Calculate total steps
    local step=1
    local total_steps=1
    [ "$skip_domain" = false ] && ((total_steps++))
    [ "$skip_db" = false ] && ((total_steps++))
    [ "$skip_env" = false ] && ((total_steps++))
    [ "$skip_ssl" = false ] && [ "$skip_domain" = false ] && ((total_steps++))
    [ "$skip_deploy" = false ] && ((total_steps++))
    
    # Store app password for summary
    local app_password=""
    
    # Step 1: Create app
    echo -e "${CYAN}Step ${step}/${total_steps}: Creating app...${NC}"
    
    # Capture app_create output to get the password
    local app_output=$(mktemp)
    app_create --user="$username" --repository="$repository" --branch="$branch" --php="$php_version" 2>&1 | tee "$app_output"
    
    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo -e "${RED}Error: Failed to create app${NC}"
        rm -f "$app_output"
        exit 1
    fi
    
    # Extract app password from output
    app_password=$(grep "Password:" "$app_output" | head -n 1 | awk '{print $2}')
    rm -f "$app_output"
    
    ((step++))
    
    # Get app home directory
    init_storage
    local vhost=$(json_get "${APPS_FILE}" "$username")
    local home_dir=$(echo "$vhost" | jq -r '.home_dir')
    local env_file="$home_dir/wwwroot/.env"
    
    # Step 2: Create domain
    if [ "$skip_domain" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Creating domain...${NC}"
        if [ -n "$aliases" ]; then
            domain_create --domain="$domain" --aliases="$aliases" --app="$username"
        else
            domain_create --domain="$domain" --app="$username"
        fi
        
        if [ $? -ne 0 ]; then
            echo -e "${RED}Error: Failed to create domain${NC}"
            exit 1
        fi
        ((step++))
    fi
    
    # Step 3: Create database
    local dbname_final=""
    local db_username=""
    local db_password=""
    
    if [ "$skip_db" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Creating database...${NC}"
        
        # Create a temp file to capture database output
        local db_output=$(mktemp)
        if [ -n "$dbname" ]; then
            database_create --name="$dbname" 2>&1 | tee "$db_output"
        else
            database_create --name="$username" 2>&1 | tee "$db_output"
        fi
        
        # Extract database name and password from output
        dbname_final=$(grep "Database:" "$db_output" | awk '{print $2}')
        db_password=$(grep "Password:" "$db_output" | awk '{print $2}')
        db_username=$(grep "Username:" "$db_output" | awk '{print $2}')
        rm -f "$db_output"
        
        ((step++))
    fi
    
    # Step 4: Update .env file
    if [ "$skip_env" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Updating .env file...${NC}"
        
        # Ensure .env exists
        if [ ! -f "$env_file" ]; then
            if [ -f "$home_dir/wwwroot/.env.example" ]; then
                sudo -u "$username" cp "$home_dir/wwwroot/.env.example" "$env_file"
                chown "$username:$username" "$env_file"
                chmod 644 "$env_file"
                echo "  → Created .env from .env.example"
            else
                # Create minimal .env file
                sudo -u "$username" touch "$env_file"
                chown "$username:$username" "$env_file"
                chmod 644 "$env_file"
                echo "  → Created empty .env file"
            fi
        fi
        
        # Update .env with settings
        update_env_file "$env_file" "$username" "$domain" "$dbname_final" "$db_username" "$db_password" "$app_env" "$skip_domain"
        ((step++))
    fi
    
    # Step 5: Setup SSL
    if [ "$skip_ssl" = false ] && [ "$skip_domain" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Setting up SSL certificate...${NC}"
        
        # Run SSL script
        echo "  → Requesting Let's Encrypt certificate..."
        if [ -f "$home_dir/ssl.sh" ]; then
            sudo -u "$username" "$home_dir/ssl.sh" 2>&1 | grep -v "^$" | head -10
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                echo "  → SSL certificate installed"
            else
                echo -e "  → ${YELLOW}SSL setup may require DNS configuration${NC}"
                echo -e "  → ${YELLOW}Run manually: sudo -u $username $home_dir/ssl.sh${NC}"
            fi
        else
            echo -e "  → ${YELLOW}SSL script not found${NC}"
        fi
        ((step++))
    fi
    
    # Step 6: Run deployment
    if [ "$skip_deploy" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Running initial deployment...${NC}"
        
        if [ -f "$home_dir/deploy.sh" ]; then
            cd "$home_dir"
            sudo -u "$username" "$home_dir/deploy.sh" 2>&1 | grep -E "^(→|─|Deployment)" | head -20
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                echo "  → Deployment completed"
            else
                echo -e "  → ${YELLOW}Deployment had issues, check logs${NC}"
            fi
        else
            echo -e "  → ${YELLOW}Deploy script not found${NC}"
        fi
        ((step++))
    fi
    
    # Display summary
    echo ""
    echo -e "${GREEN}${BOLD}Provision completed successfully!${NC}"
    echo "─────────────────────────────────────"
    echo ""
    echo -e "${BOLD}App Credentials${NC}"
    echo -e "Username:   ${CYAN}$username${NC}"
    echo -e "Password:   ${CYAN}$app_password${NC}"
    echo -e "Path:       ${CYAN}$home_dir${NC}"
    echo -e "PHP:        ${CYAN}$php_version${NC}"
    echo ""
    
    if [ "$skip_domain" = false ]; then
        echo -e "${BOLD}Domain${NC}"
        echo -e "Domain:     ${CYAN}$domain${NC}"
        [ -n "$aliases" ] && echo -e "Aliases:    ${CYAN}$aliases${NC}"
        echo ""
    fi
    
    if [ "$skip_db" = false ]; then
        echo -e "${BOLD}Database Credentials${NC}"
        echo -e "Database:   ${CYAN}$dbname_final${NC}"
        echo -e "Username:   ${CYAN}$db_username${NC}"
        echo -e "Password:   ${CYAN}$db_password${NC}"
        echo ""
    fi
    
    echo -e "${YELLOW}${BOLD}IMPORTANT: Save these credentials!${NC}"
    echo ""
    
    echo -e "${BOLD}Git SSH Public Key${NC}"
    if [ -f "$home_dir/gitkey.pub" ]; then
        cat "$home_dir/gitkey.pub"
        echo ""
    fi
    
    echo ""
    echo -e "${BOLD}Next Steps${NC}"
    [ "$skip_ssl" = false ] && [ "$skip_domain" = false ] && echo -e "• SSL (if needed): ${CYAN}sudo -u $username $home_dir/ssl.sh${NC}"
    echo -e "• Edit .env: ${CYAN}cipi app env $username${NC}"
    echo -e "• View app: ${CYAN}cipi app show $username${NC}"
    echo -e "• Deploy: ${CYAN}sudo -u $username $home_dir/deploy.sh${NC}"
    echo ""
}

# Provision delete - delete app and optionally database
provision_delete() {
    local username=""
    local dbname=""
    local force=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --dbname=*)
                dbname="${arg#*=}"
                ;;
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
        echo "Usage: cipi provision delete <username> [--dbname=DBNAME] [--force]"
        exit 1
    fi
    
    init_storage
    
    # Check if app exists
    if ! json_has_key "${APPS_FILE}" "$username"; then
        echo -e "${RED}Error: App '$username' not found${NC}"
        exit 1
    fi
    
    # Check if database exists (if provided)
    if [ -n "$dbname" ]; then
        if ! json_has_key "${DATABASES_FILE}" "$dbname"; then
            echo -e "${RED}Error: Database '$dbname' not found${NC}"
            exit 1
        fi
    fi
    
    # Get domain info for display
    local domain=$(get_domain_by_app "$username")
    
    # Show what will be deleted
    echo -e "${YELLOW}${BOLD}Warning: This will permanently delete:${NC}"
    echo -e "  • App: ${CYAN}$username${NC}"
    echo -e "  • Home directory: ${CYAN}/home/$username${NC}"
    [ -n "$domain" ] && echo -e "  • Domain: ${CYAN}$domain${NC}"
    [ -n "$dbname" ] && echo -e "  • Database: ${CYAN}$dbname${NC}"
    echo ""
    
    # Confirm deletion
    if [ "$force" != "true" ]; then
        read -p "Type the username to confirm deletion: " confirm
        
        if [ "$confirm" != "$username" ]; then
            echo "Deletion cancelled."
            exit 0
        fi
    fi
    
    echo ""
    echo -e "${CYAN}Deleting resources...${NC}"
    
    # Delete database first (if specified)
    if [ -n "$dbname" ]; then
        echo ""
        echo -e "  → Deleting database '$dbname'..."
        
        # Get database data
        local db_data=$(json_get "${DATABASES_FILE}" "$dbname")
        local db_username=$(echo "$db_data" | jq -r '.username')
        local root_password=$(get_mysql_root_password)
        
        # Delete database and user
        mysql -u root -p"${root_password}" <<EOF 2>/dev/null
DROP DATABASE IF EXISTS \`${dbname}\`;
DROP USER IF EXISTS '${db_username}'@'localhost';
FLUSH PRIVILEGES;
EOF
        
        # Remove from storage
        json_delete "${DATABASES_FILE}" "$dbname"
        echo -e "  → Database deleted"
    fi
    
    # Delete app (this handles domains, nginx, php pool, system user)
    echo ""
    echo -e "  → Deleting app '$username'..."
    
    local vhost=$(json_get "${APPS_FILE}" "$username")
    local php_version=$(echo "$vhost" | jq -r '.php_version')
    
    # Delete associated domains
    delete_domains_by_app "$username"
    
    # Delete Nginx configuration
    delete_nginx_config "$username"
    
    # Delete PHP-FPM pool
    delete_php_pool "$username" "$php_version"
    
    # Delete system user and home directory
    delete_system_user "$username"
    
    # Remove from storage
    json_delete "${APPS_FILE}" "$username"
    
    # Reload nginx
    nginx_reload
    
    echo ""
    echo -e "${GREEN}${BOLD}Provision deleted successfully!${NC}"
    echo -e "  • App '$username' deleted"
    [ -n "$dbname" ] && echo -e "  • Database '$dbname' deleted"
    echo ""
}

# Helper: Update .env file with database and app settings
update_env_file() {
    local env_file=$1
    local username=$2
    local domain=$3
    local dbname=$4
    local db_username=$5
    local db_password=$6
    local app_env=$7
    local skip_domain=$8
    
    # Function to set or update an env variable
    set_env_var() {
        local file=$1
        local key=$2
        local value=$3
        
        # Check if key exists
        if grep -q "^${key}=" "$file" 2>/dev/null; then
            # Update existing value using | as delimiter to handle special chars
            sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        else
            # Append new value
            echo "${key}=${value}" >> "$file"
        fi
    }
    
    # Update database settings
    if [ -n "$dbname" ] && [ -n "$db_username" ]; then
        set_env_var "$env_file" "DB_CONNECTION" "mysql"
        set_env_var "$env_file" "DB_HOST" "127.0.0.1"
        set_env_var "$env_file" "DB_PORT" "3306"
        set_env_var "$env_file" "DB_DATABASE" "$dbname"
        set_env_var "$env_file" "DB_USERNAME" "$db_username"
        
        if [ -n "$db_password" ]; then
            set_env_var "$env_file" "DB_PASSWORD" "$db_password"
        fi
        echo "  → Updated database settings in .env"
    fi
    
    # Update app settings
    set_env_var "$env_file" "APP_ENV" "$app_env"
    
    if [ "$skip_domain" = false ] && [ -n "$domain" ]; then
        set_env_var "$env_file" "APP_URL" "https://${domain}"
        echo "  → Updated APP_URL in .env"
    fi
    
    # Set production defaults
    if [ "$app_env" = "production" ]; then
        set_env_var "$env_file" "APP_DEBUG" "false"
        echo "  → Set APP_DEBUG=false for production"
    fi
    
    # Configure Redis if available
    if systemctl is-active --quiet redis-server 2>/dev/null; then
        set_env_var "$env_file" "CACHE_DRIVER" "redis"
        set_env_var "$env_file" "SESSION_DRIVER" "redis"
        set_env_var "$env_file" "REDIS_HOST" "127.0.0.1"
        set_env_var "$env_file" "REDIS_PASSWORD" "null"
        set_env_var "$env_file" "REDIS_PORT" "6379"
        echo "  → Configured Redis for cache and sessions"
    fi
    
    # Configure queue
    set_env_var "$env_file" "QUEUE_CONNECTION" "database"
    
    # Set proper ownership
    chown "$username:$username" "$env_file"
    chmod 644 "$env_file"
}

