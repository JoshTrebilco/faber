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
    
    cat > "/etc/supervisor/conf.d/reverb-worker.conf" <<EOF
[program:reverb-worker]
process_name=%(program_name)s_%(process_num)02d
command=php ${home_dir}/wwwroot/artisan reverb:start
autostart=true
autorestart=true
stopasgroup=true
killasgroup=true
user=${username}
numprocs=1
redirect_stderr=true
stdout_logfile=${home_dir}/reverb-worker.log
stopwaitsecs=3600
EOF
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

# Create nginx WebSocket proxy config (serves Laravel app + WebSocket proxy at /app)
create_reverb_nginx_config() {
    local username=$1
    local domain=$2
    local php_version=$3
    local root_path="/home/${username}/wwwroot/public"
    local php_socket="/var/run/php/php${php_version}-fpm-${username}.sock"
    
    cat > "${NGINX_SITES_AVAILABLE}/${username}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${domain};
    root ${root_path};
    
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    
    index index.php;
    charset utf-8;
    
    access_log /home/${username}/logs/access.log;
    error_log /home/${username}/logs/error.log;
    
    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }
    
    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }
    
    error_page 404 /index.php;
    
    location ~ \.php\$ {
        fastcgi_pass unix:${php_socket};
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
    
    # Reverb WebSocket proxy at /app
    location /app {
        proxy_http_version 1.1;
        proxy_set_header Host \$http_host;
        proxy_set_header Scheme \$scheme;
        proxy_set_header SERVER_PORT \$server_port;
        proxy_set_header REMOTE_ADDR \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";
        proxy_pass http://0.0.0.0:8080;
    }
}
EOF
    
    # Enable site
    ln -sf "${NGINX_SITES_AVAILABLE}/${username}" "${NGINX_SITES_ENABLED}/${username}"
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
    echo -e "${CYAN}Step 5/6: Creating supervisor config...${NC}"
    create_reverb_supervisor_config "$username"
    supervisorctl reread >/dev/null 2>&1
    supervisorctl update >/dev/null 2>&1
    echo "  → Supervisor config created and loaded"
    
    # Start the worker
    echo "  → Starting Reverb worker..."
    supervisorctl start reverb-worker >/dev/null 2>&1
    sleep 1
    if supervisorctl status reverb-worker 2>/dev/null | grep -q "RUNNING"; then
        echo "  → Worker started successfully"
    else
        echo -e "  ${YELLOW}⚠ Worker may need manual start: cipi reverb start${NC}"
    fi
    
    echo ""
    echo -e "${CYAN}Step 6/6: Configuring nginx...${NC}"
    create_reverb_nginx_config "$username" "$domain" "$php_version"
    nginx_reload
    echo "  → Nginx configured (app + WebSocket proxy)"
    
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
        supervisorctl reread >/dev/null 2>&1
        supervisorctl update >/dev/null 2>&1
    fi
    
    # Start the worker
    supervisorctl start reverb-worker 2>/dev/null
    
    if [ $? -eq 0 ]; then
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
    supervisorctl stop reverb-worker 2>/dev/null
    
    if [ $? -eq 0 ]; then
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
        supervisorctl reread >/dev/null 2>&1
        supervisorctl update >/dev/null 2>&1
    fi
    
    supervisorctl restart reverb-worker 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Worker restarted successfully${NC}"
        echo ""
        supervisorctl status reverb-worker
    else
        echo -e "${YELLOW}Worker may not be running, attempting to start...${NC}"
        supervisorctl start reverb-worker 2>/dev/null
        if [ $? -eq 0 ]; then
            echo -e "${GREEN}Worker started successfully${NC}"
            echo ""
            supervisorctl status reverb-worker
        else
            echo -e "${RED}Failed to start worker${NC}"
            exit 1
        fi
    fi
    echo ""
}

