#!/bin/bash

#############################################
# Reverb Management Functions
#############################################

# Configure an app as a Reverb client (adds env vars to app's .env)
configure_app_for_reverb() {
    local username=$1
    local home_dir="/home/$username"
    local env_file="$home_dir/wwwroot/.env"
    
    if [ ! -f "$env_file" ]; then
        echo -e "  ${YELLOW}Warning: .env file not found, skipping Reverb config${NC}"
        return 1
    fi
    
    local reverb_domain=$(get_reverb_field "domain")
    local reverb_app_id=$(get_reverb_field "app_id")
    local reverb_app_key=$(get_reverb_field "app_key")
    local reverb_app_secret=$(get_reverb_field "app_secret")
    
    # Helper to set env var
    set_env_var() {
        local file=$1
        local key=$2
        local value=$3
        
        if grep -q "^${key}=" "$file" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        elif grep -q "^#[[:space:]]*${key}=" "$file" 2>/dev/null; then
            sed -i "s|^#[[:space:]]*${key}=.*|${key}=${value}|" "$file"
        else
            echo "${key}=${value}" >> "$file"
        fi
    }
    
    set_env_var "$env_file" "BROADCAST_CONNECTION" "reverb"
    set_env_var "$env_file" "REVERB_APP_ID" "$reverb_app_id"
    set_env_var "$env_file" "REVERB_APP_KEY" "$reverb_app_key"
    set_env_var "$env_file" "REVERB_APP_SECRET" "$reverb_app_secret"
    set_env_var "$env_file" "REVERB_HOST" "$reverb_domain"
    set_env_var "$env_file" "REVERB_PORT" "443"
    set_env_var "$env_file" "REVERB_SCHEME" "https"
    
    chown "$username:$username" "$env_file"
}

# Create supervisor config for Reverb worker
create_reverb_supervisor_config() {
    local username=$1
    local home_dir="/home/$username"
    local project_dir="${home_dir}/wwwroot"
    local log_file="${home_dir}/reverb-worker.log"
    local log_dir="${home_dir}/logs"
    
    # Ensure log directory exists with correct ownership
    mkdir -p "$log_dir"
    chown "$username:$username" "$log_dir"
    
    # Fix log file ownership if it exists
    if [ -f "$log_file" ]; then
        chown "$username:$username" "$log_file"
    fi
    
    cat > "/etc/supervisor/conf.d/reverb-worker.conf" <<EOF
[program:reverb-worker]
process_name=%(program_name)s_%(process_num)02d
command=php artisan reverb:start
directory=${project_dir}
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${username}
numprocs=1
redirect_stderr=true
stdout_logfile=${log_file}
stderr_logfile=${log_dir}/reverb-worker-error.log
stopwaitsecs=3600
startsecs=3
environment=HOME="${home_dir}",PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
EOF
}

# Reload supervisor config for Reverb
supervisor_reload_reverb() {
    supervisorctl reread
    supervisorctl update
}

# Validate that artisan command is ready to run
# Returns 0 if valid, 1 if invalid
validate_reverb_artisan() {
    local username=$1
    local home_dir="/home/$username"
    local project_dir="${home_dir}/wwwroot"
    local artisan_file="${project_dir}/artisan"
    local vendor_dir="${project_dir}/vendor"
    
    # Check if artisan file exists
    if [ ! -f "$artisan_file" ]; then
        echo -e "  ${RED}✗ Artisan file not found: $artisan_file${NC}"
        return 1
    fi
    
    # Check if vendor directory exists (composer deps installed)
    if [ ! -d "$vendor_dir" ]; then
        echo -e "  ${RED}✗ Composer dependencies not installed (vendor/ missing)${NC}"
        echo -e "  ${YELLOW}  Run: sudo -u $username $home_dir/deploy.sh${NC}"
        return 1
    fi
    
    # Test that php artisan command works (doesn't crash immediately)
    if ! sudo -u "$username" php "$artisan_file" --version >/dev/null 2>&1; then
        echo -e "  ${RED}✗ Artisan command failed to execute${NC}"
        echo -e "  ${YELLOW}  Check PHP errors or missing dependencies${NC}"
        return 1
    fi
    
    return 0
}

# Wait for Reverb worker to reach a state (default: RUNNING)
# Returns 0 if reached, 1 if timeout
wait_for_reverb_worker() {
    local target_state="${1:-RUNNING}"
    local timeout="${2:-10}"
    local wait_time=0
    
    while [ $wait_time -lt $timeout ]; do
        local status_output=$(supervisorctl status reverb-worker 2>/dev/null)
        # Check for target state (RUNNING, STOPPED, etc.) or process name pattern
        if echo "$status_output" | grep -qE "$target_state|reverb-worker:reverb-worker"; then
            # If looking for RUNNING, make sure it's actually running
            if [ "$target_state" = "RUNNING" ]; then
                if echo "$status_output" | grep -q "RUNNING"; then
                    return 0
                fi
            else
                return 0
            fi
        fi
        sleep 1
        ((wait_time++))
    done
    return 1
}

# Set file limits for Reverb user (production optimization)
set_reverb_file_limits() {
    local username=$1
    
    if ! grep -q "^${username}" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf <<EOF
${username}        soft  nofile  10000
${username}        hard  nofile  10000
EOF
        echo "  → Set file limits (nofile 10000) for $username"
    fi
}


# Main setup function
reverb_setup() {
    local username="reverb"
    local repository=""
    local domain=""
    local branch="main"
    local php_version="8.4"
    local interactive=true
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --user=*)
                username="${arg#*=}"
                ;;
            --repository=*)
                repository="${arg#*=}"
                ;;
            --domain=*)
                domain="${arg#*=}"
                ;;
            --branch=*)
                branch="${arg#*=}"
                ;;
            --php=*)
                php_version="${arg#*=}"
                ;;
        esac
    done
    
    # Check if already configured
    if reverb_is_configured; then
        echo -e "${YELLOW}Reverb is already configured${NC}"
        echo -e "Run ${CYAN}cipi reverb show${NC} to see configuration"
        exit 1
    fi
    
    # Interactive prompts
    if [ -z "$repository" ] || [ -z "$domain" ]; then
        interactive=true
        echo -e "${BOLD}Reverb WebSocket Server Setup${NC}"
        echo "─────────────────────────────────────"
        echo ""
        
        read -p "Username [$username]: " input_username
        username=${input_username:-$username}
        
        if [ -z "$repository" ]; then
            read -p "Git repository URL: " repository
        fi
        
        if [ -z "$domain" ]; then
            read -p "Reverb domain (e.g., reverb.example.com): " domain
        fi
        
        read -p "Git branch [$branch]: " input_branch
        branch=${input_branch:-$branch}
        
        # PHP version selection
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
    fi
    
    # Validate
    if [ -z "$repository" ] || [ -z "$domain" ]; then
        echo -e "${RED}Error: Repository and domain are required${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${CYAN}Step 1/6: Provisioning Reverb app...${NC}"
    
    # Provision the app (skip database and reverb client config)
    # Domain + SSL will be set up automatically by provision_create
    provision_create \
        --user="$username" \
        --repository="$repository" \
        --domain="$domain" \
        --branch="$branch" \
        --php="$php_version" \
        --skip-db \
        --skip-reverb
    
    local home_dir="/home/$username"
    
    echo ""
    echo -e "${CYAN}Step 2/6: Generating Reverb credentials...${NC}"
    
    # Generate credentials
    local app_id=$(shuf -i 100000-999999 -n 1)
    local app_key=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 20)
    local app_secret=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 32)
    
    # Save to reverb.json
    save_reverb_config "$username" "$domain" "$app_id" "$app_key" "$app_secret"
    echo "  → Credentials saved to reverb.json"
    
    echo ""
    echo -e "${CYAN}Step 3/6: Configuring Reverb server .env...${NC}"
    
    local env_file="$home_dir/wwwroot/.env"
    
    # Helper to set env var
    set_env_var() {
        local file=$1
        local key=$2
        local value=$3
        
        if grep -q "^${key}=" "$file" 2>/dev/null; then
            sed -i "s|^${key}=.*|${key}=${value}|" "$file"
        elif grep -q "^#[[:space:]]*${key}=" "$file" 2>/dev/null; then
            sed -i "s|^#[[:space:]]*${key}=.*|${key}=${value}|" "$file"
        else
            echo "${key}=${value}" >> "$file"
        fi
    }
    
    # Configure Reverb server env vars
    set_env_var "$env_file" "REVERB_SERVER_HOST" "0.0.0.0"
    set_env_var "$env_file" "REVERB_SERVER_PORT" "8080"
    set_env_var "$env_file" "REVERB_HOST" "$domain"
    set_env_var "$env_file" "REVERB_PORT" "443"
    set_env_var "$env_file" "REVERB_SCHEME" "https"
    set_env_var "$env_file" "REVERB_APP_ID" "$app_id"
    set_env_var "$env_file" "REVERB_APP_KEY" "$app_key"
    set_env_var "$env_file" "REVERB_APP_SECRET" "$app_secret"
    
    chown "$username:$username" "$env_file"
    echo "  → Reverb server .env configured"
    
    echo ""
    echo -e "${CYAN}Step 4/6: Setting production file limits...${NC}"
    set_reverb_file_limits "$username"
    
    echo ""
    echo -e "${CYAN}Step 5/6: Adding WebSocket proxy to nginx...${NC}"
    
    # Domain + SSL are already set up by provision_create
    # Regenerate SSL config with websocket proxy included
    if ! add_websocket_proxy_to_nginx "$username" "$domain" "$php_version" 8080; then
        echo -e "${RED}Error: Failed to add WebSocket proxy to nginx${NC}"
        exit 1
    fi
    
    if ! nginx_reload; then
        echo -e "${RED}Error: Failed to reload nginx${NC}"
        exit 1
    fi
    echo "  → WebSocket proxy added to nginx config"
    
    echo ""
    echo -e "${CYAN}Step 6/6: Creating supervisor config...${NC}"
    
    # Validate artisan is ready before setting up supervisor
    echo "  → Validating artisan command..."
    if ! validate_reverb_artisan "$username"; then
        echo -e "  ${RED}✗ Validation failed${NC}"
        echo ""
        echo -e "  ${YELLOW}Please ensure:${NC}"
        echo -e "    1. Composer dependencies are installed (run deploy.sh)"
        echo -e "    2. .env file is properly configured"
        echo -e "    3. Artisan file exists and is executable"
        echo ""
        exit 1
    fi
    
    create_reverb_supervisor_config "$username"
    supervisor_reload_reverb
    echo "  → Supervisor config created and loaded"
    
    # Wait for autostart to kick in (config has autostart=true)
    echo "  → Starting Reverb worker..."
    if wait_for_reverb_worker "RUNNING" 10; then
        echo "  → Worker started successfully"
    else
        echo -e "  ${YELLOW}⚠ Worker failed to start automatically${NC}"
        echo ""
        echo -e "  ${CYAN}Diagnostics:${NC}"
        supervisorctl status reverb-worker
        echo ""
        
        # Show recent logs if available
        local log_file="/home/$username/reverb-worker.log"
        local error_log="/home/$username/logs/reverb-worker-error.log"
        if [ -f "$error_log" ] && [ -s "$error_log" ]; then
            echo -e "  ${CYAN}Recent error log:${NC}"
            tail -10 "$error_log" | sed 's/^/    /'
            echo ""
        elif [ -f "$log_file" ] && [ -s "$log_file" ]; then
            echo -e "  ${CYAN}Recent log output:${NC}"
            tail -10 "$log_file" | sed 's/^/    /'
            echo ""
        fi
        
        echo -e "  ${YELLOW}Troubleshooting:${NC}"
        echo -e "    • Check logs: tail -f $log_file"
        echo -e "    • Check errors: tail -f $error_log"
        echo -e "    • Manual start: cipi reverb start"
        echo -e "    • Supervisor status: supervisorctl status reverb-worker"
        echo ""
    fi
    
    # Display summary
    echo ""
    echo -e "${GREEN}${BOLD}Reverb setup complete!${NC}"
    echo "─────────────────────────────────────"
    echo -e "App:        ${CYAN}$username${NC}"
    echo -e "Domain:     ${CYAN}https://$domain${NC}"
    echo -e "App ID:     ${CYAN}$app_id${NC}"
    echo -e "App Key:    ${CYAN}$app_key${NC}"
    echo -e "App Secret: ${CYAN}$app_secret${NC}"
    echo ""
    echo -e "New apps will automatically connect to this Reverb server."
    echo -e "Use ${CYAN}--skip-reverb${NC} flag to opt out."
    echo ""
}

# Show Reverb configuration
reverb_show() {
    if ! reverb_is_configured; then
        echo -e "${YELLOW}Reverb is not configured${NC}"
        echo ""
        echo "Run: cipi reverb setup"
        return 1
    fi
    
    echo -e "${BOLD}Reverb WebSocket Server${NC}"
    echo "─────────────────────────────────────"
    echo -e "App:        ${CYAN}$(get_reverb_field 'app')${NC}"
    echo -e "Domain:     ${CYAN}https://$(get_reverb_field 'domain')${NC}"
    echo -e "App ID:     ${CYAN}$(get_reverb_field 'app_id')${NC}"
    echo -e "App Key:    ${CYAN}$(get_reverb_field 'app_key')${NC}"
    echo -e "App Secret: ${CYAN}$(get_reverb_field 'app_secret')${NC}"
    echo -e "Created:    ${CYAN}$(get_reverb_field 'created_at')${NC}"
    echo ""
    
    # Show supervisor status
    echo -e "${BOLD}Worker Status${NC}"
    echo "─────────────────────────────────────"
    supervisorctl status reverb-worker 2>/dev/null || echo "Worker not running"
    echo ""
}

# Start Reverb worker
reverb_start() {
    if ! reverb_is_configured; then
        echo -e "${RED}Error: Reverb is not configured${NC}"
        echo ""
        echo "Run: cipi reverb setup"
        exit 1
    fi
    
    echo -e "${CYAN}Starting Reverb worker...${NC}"
    
    # Ensure supervisor config exists and is loaded
    local username=$(get_reverb_field "app")
    if [ -n "$username" ]; then
        create_reverb_supervisor_config "$username"
        supervisor_reload_reverb
    fi
    
    # Wait for autostart, or try explicit start
    if wait_for_reverb_worker "RUNNING" 10; then
        echo -e "${GREEN}Worker started successfully${NC}"
        echo ""
        supervisorctl status reverb-worker
    elif supervisorctl start reverb-worker; then
        echo -e "${GREEN}Worker started successfully${NC}"
        echo ""
        supervisorctl status reverb-worker
    else
        echo -e "${RED}Failed to start worker${NC}"
        echo ""
        echo "Try: sudo supervisorctl start reverb-worker"
        exit 1
    fi
    echo ""
}

# Stop Reverb worker
reverb_stop() {
    if ! reverb_is_configured; then
        echo -e "${RED}Error: Reverb is not configured${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Stopping Reverb worker...${NC}"
    if supervisorctl stop reverb-worker; then
        echo -e "${GREEN}Worker stopped successfully${NC}"
    else
        echo -e "${YELLOW}Worker may not be running${NC}"
    fi
    echo ""
}

# Restart Reverb worker
reverb_restart() {
    if ! reverb_is_configured; then
        echo -e "${RED}Error: Reverb is not configured${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Restarting Reverb worker...${NC}"
    
    # Ensure supervisor config exists and is loaded
    local username=$(get_reverb_field "app")
    if [ -n "$username" ]; then
        create_reverb_supervisor_config "$username"
        supervisor_reload_reverb
    fi
    
    # Wait for process to be registered
    wait_for_reverb_worker "RUNNING|STOPPED" 10
    
    # Check if running and restart, otherwise start
    if supervisorctl status reverb-worker 2>/dev/null | grep -q "RUNNING"; then
        if supervisorctl restart reverb-worker; then
            echo -e "${GREEN}Worker restarted successfully${NC}"
            echo ""
            supervisorctl status reverb-worker
        else
            echo -e "${RED}Failed to restart worker${NC}"
            exit 1
        fi
    elif supervisorctl start reverb-worker; then
        echo -e "${GREEN}Worker started successfully${NC}"
        echo ""
        supervisorctl status reverb-worker
    else
        echo -e "${RED}Failed to start worker${NC}"
        exit 1
    fi
    echo ""
}

# Delete Reverb configuration and app
reverb_delete() {
    # Get username from config, or default to "reverb"
    local default_username=$(get_reverb_field "app")
    default_username=${default_username:-reverb}
    
    echo -e "${BOLD}Delete Reverb${NC}"
    echo "─────────────────────────────────────"
    echo ""
    
    read -p "Username [$default_username]: " input_username
    local username=${input_username:-$default_username}
    
    echo ""
    echo -e "This will delete:"
    echo -e "  • Reverb app: ${CYAN}$username${NC}"
    echo -e "  • Supervisor worker config"
    echo -e "  • Reverb configuration (reverb.json)"
    echo ""
    
    read -p "Type 'delete' to confirm: " confirm
    if [ "$confirm" != "delete" ]; then
        echo "Cancelled."
        exit 0
    fi
    
    echo ""
    echo -e "${CYAN}Stopping Reverb worker...${NC}"
    supervisorctl stop reverb-worker || true
    
    echo -e "${CYAN}Removing supervisor config...${NC}"
    rm -f /etc/supervisor/conf.d/reverb-worker.conf
    supervisor_reload_reverb
    
    echo -e "${CYAN}Deleting Reverb app...${NC}"
    provision_delete "$username" --force
    
    echo -e "${CYAN}Removing reverb.json...${NC}"
    rm -f "${REVERB_FILE}"
    
    echo ""
    echo -e "${GREEN}Reverb deleted successfully${NC}"
    echo ""
}

