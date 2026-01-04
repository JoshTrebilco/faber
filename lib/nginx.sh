#!/bin/bash

#############################################
# Nginx Management Functions
#############################################

NGINX_SITES_AVAILABLE="/etc/nginx/sites-available"
NGINX_SITES_ENABLED="/etc/nginx/sites-enabled"

# Generate SSL certificate block
nginx_ssl_block() {
    local domain=$1
    cat <<EOF
    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
EOF
}

# Generate security headers
nginx_security_headers() {
    cat <<EOF
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
EOF
}

# Generate client settings
nginx_client_settings() {
    cat <<EOF
    client_body_timeout 10s;
    client_header_timeout 10s;
    client_max_body_size 256M;
EOF
}

# Generate Laravel PHP locations
nginx_laravel_locations() {
    local php_socket=$1
    local hide_powered_by=${2:-false}
    local fastcgi_hide=""
    if [ "$hide_powered_by" = "true" ]; then
        fastcgi_hide="        fastcgi_hide_header X-Powered-By;"
    fi
    cat <<EOF
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
${fastcgi_hide}
    }
    
    location ~ /\.(?!well-known).* {
        deny all;
    }
EOF
}

# Generate WebSocket proxy location (for Reverb)
nginx_websocket_proxy() {
    local port=${1:-8080}
    cat <<EOF
    
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
        proxy_pass http://0.0.0.0:${port};
    }
EOF
}

# Create Nginx configuration
create_nginx_config() {
    local username=$1
    local domain=$2
    local php_version=$3
    local extra_locations=${4:-""}
    
    local server_name="${domain:-$username}"
    local root_path="/home/$username/wwwroot/public"
    local log_path="/home/$username/logs"
    local php_socket="/var/run/php/php${php_version}-fpm-${username}.sock"
    
    local security_headers=$(nginx_security_headers)
    local client_settings=$(nginx_client_settings)
    local laravel_locations=$(nginx_laravel_locations "$php_socket" "false")
    
    cat > "${NGINX_SITES_AVAILABLE}/${username}" <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${server_name};
    root ${root_path};
    
${security_headers}
${client_settings}
    
    index index.php;
    charset utf-8;
    server_tokens off;
    
    access_log ${log_path}/access.log;
    error_log ${log_path}/error.log;
    
${laravel_locations}
${extra_locations}
}
EOF
    
    # Enable site
    ln -sf "${NGINX_SITES_AVAILABLE}/${username}" "${NGINX_SITES_ENABLED}/${username}"
}

# Update Nginx configuration with domain
update_nginx_domain() {
    local username=$1
    local domain=$2
    
    local config_file="${NGINX_SITES_AVAILABLE}/${username}"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Replace server_name line
    sed -i "s/server_name .*/server_name $domain;/" "$config_file"
}

# Add SSL to Nginx configuration
add_ssl_to_nginx() {
    local username=$1
    local domain=$2
    local php_version=$3
    local extra_locations=${4:-""}
    local hide_powered_by=${5:-false}
    
    local root_path="/home/$username/wwwroot/public"
    local log_path="/home/$username/logs"
    local php_socket="/var/run/php/php${php_version}-fpm-${username}.sock"
    
    local ssl_block=$(nginx_ssl_block "$domain")
    local security_headers=$(nginx_security_headers)
    local client_settings=$(nginx_client_settings)
    local laravel_locations=$(nginx_laravel_locations "$php_socket" "$hide_powered_by")
    
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
    
${ssl_block}
${security_headers}
${client_settings}
    
    index index.php;
    charset utf-8;
    server_tokens off;
    
    access_log ${log_path}/access.log;
    error_log ${log_path}/error.log;
    
${laravel_locations}
${extra_locations}
}
EOF
}

# Add WebSocket proxy location to existing nginx config
add_websocket_proxy_to_nginx() {
    local username=$1
    local domain=$2
    local php_version=$3
    local port=${4:-8080}
    
    local config_file="${NGINX_SITES_AVAILABLE}/${username}"
    
    if [ ! -f "$config_file" ]; then
        echo -e "${RED}Error: Nginx config not found for $username${NC}" >&2
        return 1
    fi
    
    # Check if WebSocket proxy already exists (prevent duplicates)
    if grep -q "location /app" "$config_file" 2>/dev/null; then
        echo -e "${YELLOW}WebSocket proxy location already exists in config${NC}" >&2
        return 0
    fi
    
    # Get the websocket proxy location block
    local websocket_proxy=$(nginx_websocket_proxy "$port")
    
    # Regenerate SSL config with websocket proxy included (same pattern as add_ssl_to_nginx)
    add_ssl_to_nginx "$username" "$domain" "$php_version" "$websocket_proxy" "true"
}

# Delete Nginx configuration
delete_nginx_config() {
    local username=$1
    
    rm -f "${NGINX_SITES_ENABLED}/${username}"
    rm -f "${NGINX_SITES_AVAILABLE}/${username}"
}

# Test Nginx configuration
nginx_test() {
    nginx -t 2>&1
}

# Reload Nginx
nginx_reload() {
    if nginx_test > /dev/null 2>&1; then
        systemctl reload nginx
        return $?
    else
        echo -e "${RED}Error: Nginx configuration test failed${NC}"
        nginx_test
        return 1
    fi
}

# Restart Nginx
nginx_restart() {
    systemctl restart nginx
    return $?
}

