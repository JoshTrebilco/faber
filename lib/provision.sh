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
    local dbname=""
    local interactive=true
    
    # Default: everything enabled
    local skip_db=false
    local skip_domain=false
    local skip_env=false
    local skip_deploy=false
    local skip_reverb=false
    
    # Track which skip flags were explicitly set via command line
    local skip_db_set=false
    local skip_domain_set=false
    local skip_env_set=false
    local skip_deploy_set=false
    local skip_reverb_set=false
    
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
            --skip-env)
                skip_env=true
                skip_env_set=true
                ;;
            --skip-deploy)
                skip_deploy=true
                skip_deploy_set=true
                ;;
            --skip-reverb)
                skip_reverb=true
                skip_reverb_set=true
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
        
        # Skip deploy prompt
        if [ "$skip_deploy_set" = false ]; then
            read -p "Run initial deployment? (Y/n): " run_deploy
            if [ "$run_deploy" = "n" ] || [ "$run_deploy" = "N" ]; then
                skip_deploy=true
            fi
        fi
        
        # Skip reverb prompt
        if [ "$skip_reverb_set" = false ] && reverb_is_configured; then
            read -p "Connect to Reverb WebSocket server? (Y/n): " enable_reverb
            if [ "$enable_reverb" = "n" ] || [ "$enable_reverb" = "N" ]; then
                skip_reverb=true
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
        echo "  --dbname=DBNAME          Database name (defaults to username)"
        echo ""
        echo "Skip flags (all features enabled by default):"
        echo "  --skip-db                Skip database creation"
        echo "  --skip-domain            Skip domain creation"
        echo "  --skip-env               Skip .env file updates"
        echo "  --skip-deploy            Skip initial deployment"
        echo "  --skip-reverb            Skip Reverb WebSocket server connection"
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
    echo ""
    
    # Calculate total steps
    local step=1
    local total_steps=1
    [ "$skip_domain" = false ] && ((total_steps++))
    [ "$skip_db" = false ] && ((total_steps++))
    [ "$skip_env" = false ] && ((total_steps++))
    [ "$skip_deploy" = false ] && ((total_steps++))
    
    # Store app password for summary
    local app_password=""
    
    # Step 1: Create app
    echo -e "${CYAN}Step ${step}/${total_steps}: Creating app...${NC}"
    
    # Capture app_create output to get the password
    local app_output=$(mktemp)
    local app_create_args="--user=$username --repository=$repository --branch=$branch --php=$php_version"
    if [ "$skip_reverb" = true ]; then
        app_create_args="$app_create_args --skip-reverb"
    fi
    app_create $app_create_args 2>&1 | tee "$app_output"
    
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
    local env_file="$home_dir/.env"
    
    # Step 2: Create domain
    if [ "$skip_domain" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Creating domain...${NC}"
        domain_create --domain="$domain" --app="$username"
        
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
        
        # Ensure .env exists (shared .env is in home directory)
        if [ ! -f "$env_file" ]; then
            if [ -f "$home_dir/current/.env.example" ]; then
                sudo -u "$username" cp "$home_dir/current/.env.example" "$env_file"
                chown "$username:$username" "$env_file"
                chmod 640 "$env_file"
                echo "  → Created .env from .env.example"
            else
                # Create minimal .env file
                sudo -u "$username" touch "$env_file"
                chown "$username:$username" "$env_file"
                chmod 640 "$env_file"
                echo "  → Created empty .env file"
            fi
        fi
        
        # Update .env with settings
        update_env_file "$env_file" "$username" "$domain" "$dbname_final" "$db_username" "$db_password" "$skip_domain"
        ((step++))
    fi
    
    # Step 5: Run deployment
    if [ "$skip_deploy" = false ]; then
        echo ""
        echo -e "${CYAN}Step ${step}/${total_steps}: Running initial deployment...${NC}"
        
        if [ -f "$home_dir/deploy.sh" ]; then
            cd "$home_dir"
            
            # Run deployment with live output and save to log file
            local deploy_log="$home_dir/logs/deploy.log"
            sudo -u "$username" "$home_dir/deploy.sh" 2>&1 | tee "$deploy_log"
            local deploy_exit=${PIPESTATUS[0]}
            
            if [ $deploy_exit -eq 0 ]; then
                echo "  → Deployment completed"
            else
                echo -e "  → ${YELLOW}Deployment had issues (exit code: $deploy_exit)${NC}"
                echo -e "  ${YELLOW}Full log: cat $deploy_log${NC}"
                echo -e "  ${YELLOW}Re-run:   cipi deploy $username${NC}"
            fi
            
            # Fix log ownership
            chown "$username:$username" "$deploy_log" 2>/dev/null || true
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
    echo -e "• Edit .env: ${CYAN}cipi app env $username${NC}"
    echo -e "• View app: ${CYAN}cipi app show $username${NC}"
    echo -e "• Deploy: ${CYAN}cipi deploy $username${NC}"
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
    
    # Check if app exists (unless force mode)
    if [ "$force" = false ]; then
        check_app_exists "$username"
    fi
    
    # Check if database exists (if provided and not force mode)
    if [ -n "$dbname" ] && [ "$force" = false ]; then
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
    
    # Delete app (pass --force if enabled)
    if [ "$force" = true ]; then
        app_delete "$username" --force
    else
        app_delete "$username"
    fi
    
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
    
    # Update app settings (always production)
    set_env_var "$env_file" "APP_NAME" "$username"
    set_env_var "$env_file" "APP_ENV" "production"
    set_env_var "$env_file" "APP_DEBUG" "false"
    echo "  → Set APP_NAME=$username, APP_ENV=production, APP_DEBUG=false"
    
    # Generate APP_KEY
    local app_key="base64:$(openssl rand -base64 32)"
    set_env_var "$env_file" "APP_KEY" "$app_key"
    echo "  → Generated application key"
    
    if [ "$skip_domain" = false ] && [ -n "$domain" ]; then
        set_env_var "$env_file" "APP_URL" "https://${domain}"
        echo "  → Updated APP_URL in .env"
    fi
    
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

