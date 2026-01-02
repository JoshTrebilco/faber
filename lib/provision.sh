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
    local interactive=true
    
    # Default: everything enabled
    local skip_db=false
    local skip_domain=false
    local skip_env=false
    local skip_ssl=false
    local skip_deploy=false
    local ssl_email=""
    
    # Track which skip flags were explicitly set via command line
    local skip_db_set=false
    local skip_domain_set=false
    local skip_env_set=false
    local skip_ssl_set=false
    local skip_deploy_set=false
    
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
            --ssl-email=*)
                ssl_email="${arg#*=}"
                ;;
            --aliases=*)
                aliases="${arg#*=}"
                ;;
            --dbname=*)
                dbname="${arg#*=}"
                ;;
            --skip-db)
                skip_db=true
                skip_db_set=true
                ;;
            --skip-domain)
                skip_domain=true
                skip_domain_set=true
                ;;
            --skip-aliases)
                skip_aliases=true
                skip_aliases_set=true
                ;;
            --skip-env)
                skip_env=true
                skip_env_set=true
                ;;
            --skip-ssl)
                skip_ssl=true
                skip_ssl_set=true
                ;;
            --skip-deploy)
                skip_deploy=true
                skip_deploy_set=true
                ;;
        esac
    done
    
    # Determine interactive mode - if both user and repository provided, run non-interactive
    if [ -n "$username" ] && [ -n "$repository" ]; then
        interactive=false
    fi
    
    # Interactive prompts
    if [ $interactive = true ]; then
        echo -e "${BOLD}Provision New App${NC}"
        echo "─────────────────────────────────────"
        echo ""
        
        # Username prompt
        if [ -z "$username" ]; then
            default_username=$(generate_username)
            read -p "Username [$default_username]: " username
            username=${username:-$default_username}
        fi
        
        # Repository prompt
        if [ -z "$repository" ]; then
            read -p "Git repository URL: " repository
        fi
        
        # Branch prompt
        if [ -z "$branch" ]; then
            read -p "Git branch [main]: " branch
            branch=${branch:-main}
        fi
        
        # PHP version prompt
        echo ""
        echo "Select PHP version:"
        local php_versions=($(get_installed_php_versions))
        local i=1
        local default_php_index=1
        for version in "${php_versions[@]}"; do
            echo "  $i. PHP $version"
            if [ "$version" = "$php_version" ]; then
                default_php_index=$i
            fi
            ((i++))
        done
        read -p "Choice [$default_php_index]: " php_choice
        php_choice=${php_choice:-$default_php_index}
        php_version=${php_versions[$((php_choice-1))]}
        
        echo ""
        echo -e "${BOLD}Feature Configuration${NC}"
        echo "─────────────────────────────────────"
        
        # Skip domain prompt
        if [ "$skip_domain_set" = false ]; then
            read -p "Create domain? (Y/n): " create_domain
            if [ "$create_domain" = "n" ] || [ "$create_domain" = "N" ]; then
                skip_domain=true
            fi
        fi
        
        # Domain prompt (if not skipping)
        if [ "$skip_domain" = false ]; then
            if [ -z "$domain" ]; then
                read -p "Domain name: " domain
            fi

            # Skip aliases prompt
            if [ "$skip_aliases_set" = false ]; then
                read -p "Create aliases? (y/N): " create_aliases
                create_aliases=${create_aliases:-N}
                if [ "$create_aliases" = "N" ]; then
                    skip_aliases=true
                fi
            fi

            # Aliases prompt (if not skipping)
            if [ "$skip_aliases" = false ]; then
                if [ -z "$aliases" ]; then
                    read -p "Aliases (comma-separated, optional): " aliases
                fi
            fi
        fi
        
        # Skip database prompt
        if [ "$skip_db_set" = false ]; then
            read -p "Create database? (Y/n): " create_db
            if [ "$create_db" = "n" ] || [ "$create_db" = "N" ]; then
                skip_db=true
            fi
        fi
        
        # Database name prompt (if not skipping)
        if [ "$skip_db" = false ] && [ -z "$dbname" ]; then
            read -p "Database name [$username]: " dbname
            dbname=${dbname:-$username}
        fi
        
        # Skip env prompt
        if [ "$skip_env_set" = false ]; then
            read -p "Update .env file? (Y/n): " update_env
            if [ "$update_env" = "n" ] || [ "$update_env" = "N" ]; then
                skip_env=true
            fi
        fi
        
        # Skip SSL prompt (only if domain is being created)
        if [ "$skip_domain" = false ] && [ "$skip_ssl_set" = false ]; then
            read -p "Setup SSL certificate? (Y/n): " setup_ssl
            if [ "$setup_ssl" = "n" ] || [ "$setup_ssl" = "N" ]; then
                skip_ssl=true
            fi
        fi
        
        # SSL email prompt (if setting up SSL)
        if [ "$skip_ssl" = false ] && [ "$skip_domain" = false ] && [ -z "$ssl_email" ]; then
            local default_ssl_email=$(get_config "ssl_email")
            if [ -n "$default_ssl_email" ]; then
                read -p "SSL email [$default_ssl_email]: " ssl_email
                ssl_email=${ssl_email:-$default_ssl_email}
            else
                read -p "SSL email: " ssl_email
            fi
        fi
        
        # Skip deploy prompt
        if [ "$skip_deploy_set" = false ]; then
            read -p "Run initial deployment? (Y/n): " run_deploy
            if [ "$run_deploy" = "n" ] || [ "$run_deploy" = "N" ]; then
                skip_deploy=true
            fi
        fi
        
        echo ""
    fi
    
    # Set default branch if still empty
    if [ -z "$branch" ]; then
        branch="main"
    fi
    
    # Set default dbname to username if not skipping and not set
    if [ "$skip_db" = false ] && [ -z "$dbname" ]; then
        dbname="$username"
    fi
    
    # Set default SSL email from config if not provided
    if [ "$skip_ssl" = false ] && [ "$skip_domain" = false ] && [ -z "$ssl_email" ]; then
        ssl_email=$(get_config "ssl_email")
    fi
    
    # Validate required parameters
    if [ -z "$username" ] || [ -z "$repository" ]; then
        echo -e "${RED}Error: Username and repository are required${NC}"
        echo ""
        echo "Usage: cipi provision create [options]"
        echo ""
        echo "Run without arguments for interactive mode, or provide options:"
        echo ""
        echo "Options:"
        echo "  --user=USERNAME          App username (auto-generated if not provided)"
        echo "  --repository=REPO_URL    Git repository URL"
        echo "  --domain=DOMAIN          Domain name"
        echo "  --branch=BRANCH          Git branch (default: main)"
        echo "  --php=VERSION            PHP version (default: 8.4)"
        echo "  --aliases=ALIASES        Comma-separated domain aliases"
        echo "  --dbname=DBNAME          Database name (defaults to username)"
        echo "  --ssl-email=EMAIL        Email for Let's Encrypt certificate"
        echo ""
        echo "Skip flags (all features enabled by default):"
        echo "  --skip-db                Skip database creation"
        echo "  --skip-domain            Skip domain creation"
        echo "  --skip-env               Skip .env file updates"
        echo "  --skip-ssl               Skip SSL certificate setup"
        echo "  --skip-deploy            Skip initial deployment"
        echo ""
        echo "Non-interactive mode requires at least --user and --repository."
        echo ""
        exit 1
    fi
    
    # Validate domain if not skipped
    if [ "$skip_domain" = false ] && [ -z "$domain" ]; then
        echo -e "${RED}Error: Domain is required unless domain creation is skipped${NC}"
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
    
    # Extract app password from output (strip ANSI color codes)
    app_password=$(grep "Password:" "$app_output" | sed 's/\x1b\[[0-9;]*m//g' | head -n 1 | awk '{print $2}')
    rm -f "$app_output"
    
    ((step++))
    
    # Get app home directory
    local home_dir=$(get_app_field "$username" "home_dir")
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
        
        # Extract database name and password from output (strip ANSI color codes)
        dbname_final=$(grep "Database:" "$db_output" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}')
        db_password=$(grep "Password:" "$db_output" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}')
        db_username=$(grep "Username:" "$db_output" | sed 's/\x1b\[[0-9;]*m//g' | awk '{print $2}')
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
        update_env_file "$env_file" "$username" "$domain" "$dbname_final" "$db_username" "$db_password" "$skip_domain"
        ((step++))
    fi
    
    # Step 5: Setup SSL
    if [ "$skip_ssl" = false ] && [ "$skip_domain" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Setting up SSL certificate...${NC}"
        
        # Run SSL script (run directly since we're already root)
        echo "  → Requesting Let's Encrypt certificate..."
        if [ -f "$home_dir/ssl.sh" ]; then
            "$home_dir/ssl.sh" 2>&1 | grep -v "^$" | head -10
            
            if [ ${PIPESTATUS[0]} -eq 0 ]; then
                # Check if certificate was actually obtained
                if [ -d "/etc/letsencrypt/live/$domain" ]; then
                    echo "  → Updating Nginx configuration with SSL..."
                    
                    # Get aliases from domain storage
                    local aliases_str=$(get_domain_aliases "$domain" | tr '\n' ' ')
                    
                    # Update nginx config with SSL
                    if add_ssl_to_nginx "$username" "$domain" "$aliases_str" "$php_version"; then
                        # Reload nginx
                        nginx_reload
                        echo "  → SSL certificate installed and configured"
                    else
                        echo -e "  → ${YELLOW}Failed to update Nginx SSL configuration${NC}"
                        echo -e "  → ${YELLOW}Run manually: sudo cipi domain create --domain=$domain --app=$username${NC}"
                    fi
                else
                    echo -e "  → ${YELLOW}Certificate directory not found, SSL may need manual configuration${NC}"
                    echo -e "  → ${YELLOW}Run manually: $home_dir/ssl.sh${NC}"
                fi
            else
                echo -e "  → ${YELLOW}SSL setup may require DNS configuration${NC}"
                echo -e "  → ${YELLOW}Run manually: $home_dir/ssl.sh${NC}"
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
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --dbname=*)
                dbname="${arg#*=}"
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
        echo "Usage: cipi provision delete <username> [--dbname=DBNAME]"
        exit 1
    fi
    
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
    echo -e "${BOLD}Provision Delete${NC}"
    echo "─────────────────────────────────────"
    echo -e "The following resources will be deleted:"
    echo -e "  • App: ${CYAN}$username${NC}"
    echo -e "  • Home directory: ${CYAN}/home/$username${NC}"
    [ -n "$domain" ] && echo -e "  • Domain: ${CYAN}$domain${NC}"
    [ -n "$dbname" ] && echo -e "  • Database: ${CYAN}$dbname${NC}"
    echo ""
    
    # Delete app (has its own confirmation)
    app_delete "$username"
    
    # Delete database if specified (has its own confirmation)
    if [ -n "$dbname" ]; then
        echo ""
        database_delete "$dbname"
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}Provision deleted successfully!${NC}"
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
    local skip_domain=$7
    
    # Function to set or update an env variable
    set_env_var() {
        local file=$1
        local key=$2
        local value=$3
        
        # Check if key exists (uncommented)
        if grep -q "^${key}=" "$file" 2>/dev/null; then
            # Update existing value using | as delimiter to handle special chars
            sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        # Check if key exists but is commented out (# KEY= or #KEY=)
        elif grep -q "^#[[:space:]]*${key}=" "$file" 2>/dev/null; then
            # Uncomment and set the value
            sed -i "s|^#[[:space:]]*${key}=.*|${key}=${value}|" "$file"
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
    
    # Update app settings (always production)
    set_env_var "$env_file" "APP_ENV" "production"
    set_env_var "$env_file" "APP_DEBUG" "false"
    echo "  → Set APP_ENV=production, APP_DEBUG=false"
    
    if [ "$skip_domain" = false ] && [ -n "$domain" ]; then
        set_env_var "$env_file" "APP_URL" "https://${domain}"
        echo "  → Updated APP_URL in .env"
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

