#!/bin/bash

#############################################
# Faber Installer
# Version: 1.0.0
# Author: Josh Trebilco
# License: MIT
#############################################

set -e

# Configuration
BUILD="1.0.0"
REPO="JoshTrebilco/faber"
BRANCH="${1:-latest}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

# Helper: Update config.json with key-value pair
update_config_json() {
    local key=$1
    local value=$2
    local config_file="/etc/faber/config.json"
    
    # Ensure directory exists
    mkdir -p /etc/faber
    # 751 so www-data can traverse to read apps.json, but can't list contents
    chmod 751 /etc/faber
    
    if [ -f "$config_file" ]; then
        # Update existing config
        local tmp=$(mktemp)
        jq --arg key "$key" --arg value "$value" '.[$key] = $value' "$config_file" > "$tmp"
        mv "$tmp" "$config_file"
    else
        # Create new config
        echo "{\"$key\": \"$value\"}" > "$config_file"
    fi
    
    chmod 600 "$config_file"
    chown root:root "$config_file"
}

# Logo
show_logo() {
    clear
    echo -e "${GREEN}${BOLD}"
    echo " _______ _______ ______  _______ ______  "
    echo "(_______|_______|____  \(_______|_____ \ "
    echo " _____   _______ ____)  )_____   _____) )"
    echo "|  ___) |  ___  |  __  (|  ___) |  __  / "
    echo "| |     | |   | | |__)  ) |_____| |  \ \ "
    echo "|_|     |_|   |_|______/|_______)_|   |_|"
    echo ""
    echo "Installation started..."
    echo -e "${NC}"
    sleep 2
}

# Check Ubuntu version
check_os() {
    clear
    echo -e "${GREEN}${BOLD}OS Check...${NC}"
    sleep 1
    
    if [ ! -f /etc/os-release ]; then
        echo -e "${RED}Error: Cannot detect OS${NC}"
        exit 1
    fi
    
    . /etc/os-release
    
    if [ "$ID" != "ubuntu" ]; then
        echo -e "${RED}Error: Faber requires Ubuntu${NC}"
        exit 1
    fi
    
    # Check version (24.04 or higher)
    version_check=$(echo "$VERSION_ID >= 24.04" | bc)
    if [ "$version_check" -ne 1 ]; then
        echo -e "${RED}Error: Faber requires Ubuntu 24.04 LTS or higher${NC}"
        echo "Current version: $VERSION_ID"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Ubuntu $VERSION_ID detected${NC}"
}

# Check root
check_root() {
    clear
    echo -e "${GREEN}${BOLD}Permission Check...${NC}"
    sleep 1
    
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}Error: Faber must be run as root${NC}"
        echo "Please run: sudo bash install.sh"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Running as root${NC}"
}

# Wait for apt locks to be released
wait_for_apt() {
    local max_wait=300  # Maximum wait time in seconds (5 minutes)
    local wait_time=0
    
    while fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || \
          fuser /var/lib/apt/lists/lock >/dev/null 2>&1 || \
          fuser /var/cache/apt/archives/lock >/dev/null 2>&1; do
        if [ $wait_time -eq 0 ]; then
            echo -e "${YELLOW}Waiting for other package managers to finish...${NC}"
        fi
        sleep 5
        wait_time=$((wait_time + 5))
        if [ $wait_time -ge $max_wait ]; then
            echo -e "${RED}Error: Timeout waiting for apt locks after ${max_wait} seconds${NC}"
            echo -e "${YELLOW}Try running: sudo killall unattended-upgr${NC}"
            exit 1
        fi
    done
    
    if [ $wait_time -gt 0 ]; then
        echo -e "${GREEN}✓ Package manager is now available${NC}"
    fi
}

# Install basic packages
install_basics() {
    clear
    echo -e "${GREEN}${BOLD}Installing Basic Packages...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get update
    apt-get install -y software-properties-common curl wget nano vim git \
        sed zip unzip openssl expect apt-transport-https \
        ca-certificates gnupg lsb-release jq bc python3-pip
    
    # Install AWS CLI v2
    cd /tmp
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip -q -o awscliv2.zip
    if [ -d "/usr/local/aws-cli" ]; then
        ./aws/install --update
    else
        ./aws/install
    fi
    rm -rf awscliv2.zip aws
    cd -
    
    echo -e "${GREEN}✓ Basic packages installed${NC}"
}

# Setup MOTD
setup_motd() {
    clear
    echo -e "${GREEN}${BOLD}Setting up MOTD...${NC}"
    sleep 1
    
    cat > /etc/motd <<'EOF'

 _______ _______ ______  _______ ______  
(_______|_______|____  \(_______|_____ \ 
 _____   _______ ____)  )_____   _____) )
|  ___) |  ___  |  __  (|  ___) |  __  / 
| |     | |   | | |__)  ) |_____| |  \ \ 
|_|     |_|   |_|______/|_______)_|   |_|

Welcome to Faber!
Type 'faber help' for available commands.

EOF
    
    echo -e "${GREEN}✓ MOTD configured${NC}"
}

# Setup swap
setup_swap() {
    clear
    echo -e "${GREEN}${BOLD}Setting up SWAP...${NC}"
    sleep 1
    
    if [ ! -f /var/swap.1 ]; then
        dd if=/dev/zero of=/var/swap.1 bs=1M count=2048
        mkswap /var/swap.1
        swapon /var/swap.1
        echo '/var/swap.1 none swap sw 0 0' >> /etc/fstab
    fi
    
    echo -e "${GREEN}✓ SWAP configured${NC}"
}

# Setup editor
setup_editor() {
    clear
    echo -e "${GREEN}${BOLD}Configuring default editor...${NC}"
    sleep 1
    
    # Set nano as default editor system-wide (only if registered)
    if update-alternatives --list editor | grep -q nano; then
        update-alternatives --set editor /usr/bin/nano 2>/dev/null || true
    fi
    
    # Add to profile for all users
    cat > /etc/profile.d/faber-editor.sh <<'EOF'
export EDITOR=nano
export VISUAL=nano
EOF
    chmod +x /etc/profile.d/faber-editor.sh
    
    # Export for current session
    export EDITOR=nano
    export VISUAL=nano
    
    echo -e "${GREEN}✓ Nano configured as default editor${NC}"
}

# Install nginx
install_nginx() {
    clear
    echo -e "${GREEN}${BOLD}Installing Nginx...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get install -y nginx
    systemctl start nginx
    systemctl enable nginx
    
    # Configure nginx - Hide version and optimize
    sed -i 's/# server_names_hash_bucket_size.*/server_names_hash_bucket_size 64;/' /etc/nginx/nginx.conf
    sed -i 's/# server_tokens off;/server_tokens off;/' /etc/nginx/nginx.conf
    
    # Add optimizations to http block if not present
    if ! grep -q "client_max_body_size" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \    client_max_body_size 100M;' /etc/nginx/nginx.conf
    fi
    
    if ! grep -q "fastcgi_read_timeout" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \    fastcgi_read_timeout 300;' /etc/nginx/nginx.conf
    fi
    
    if ! grep -q "limit_req_zone" /etc/nginx/nginx.conf; then
        sed -i '/http {/a \    limit_req_zone $binary_remote_addr zone=one:10m rate=1r/s;' /etc/nginx/nginx.conf
    fi
    
    # Optimize worker processes
    CPU_CORES=$(nproc)
    sed -i "s/worker_processes.*/worker_processes $CPU_CORES;/" /etc/nginx/nginx.conf
    
    # Optimize worker connections
    sed -i 's/worker_connections.*/worker_connections 2048;/' /etc/nginx/nginx.conf
    
    # Enable gzip compression if not already enabled
    if ! grep -q "gzip_vary on;" /etc/nginx/nginx.conf; then
        sed -i '/gzip on;/a \    gzip_vary on;' /etc/nginx/nginx.conf
        sed -i '/gzip_vary on;/a \    gzip_proxied any;' /etc/nginx/nginx.conf
        sed -i '/gzip_proxied any;/a \    gzip_comp_level 6;' /etc/nginx/nginx.conf
        sed -i '/gzip_comp_level 6;/a \    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml font/truetype font/opentype application/vnd.ms-fontobject image/svg+xml;' /etc/nginx/nginx.conf
    fi
    
    # Create default config
    cat > /etc/nginx/sites-available/default <<'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    root /var/www/html;
    index index.html index.php;
    server_name _;
    server_tokens off;
    
    client_max_body_size 100M;
    
    location / {
        try_files $uri $uri/ =404;
    }
}
EOF
    
    # Create landing page
    cat > /var/www/html/index.html <<'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>It Works</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }

        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Inter', 'Helvetica Neue', Arial, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
            color: #1a1a1a;
        }

        .container {
            background: #ffffff;
            border-radius: 24px;
            padding: 60px 40px;
            max-width: 600px;
            width: 100%;
            box-shadow: 0 20px 60px rgba(0, 0, 0, 0.15);
            text-align: center;
        }

        .logo {
            width: 80px;
            height: 80px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border-radius: 20px;
            margin: 0 auto 30px;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 36px;
            font-weight: 700;
            color: #ffffff;
            letter-spacing: 2px;
            box-shadow: 0 10px 30px rgba(102, 126, 234, 0.3);
        }

        h1 {
            font-size: 42px;
            font-weight: 700;
            color: #1a1a1a;
            margin-bottom: 16px;
            letter-spacing: -0.5px;
        }

        .subtitle {
            font-size: 18px;
            color: #6b7280;
            line-height: 1.6;
        }

        @media (max-width: 640px) {
            .container {
                padding: 40px 24px;
            }

            h1 {
                font-size: 32px;
            }

            .subtitle {
                font-size: 16px;
            }

            .logo {
                width: 60px;
                height: 60px;
                font-size: 28px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="logo">✓</div>
        
        <h1>It Works</h1>
        <p class="subtitle">
            Your server is up and running.
        </p>
    </div>
</body>
</html>
HTMLEOF
    
    chmod 644 /var/www/html/index.html
    
    systemctl reload nginx
    
    echo -e "${GREEN}✓ Nginx installed${NC}"
}

# Install fail2ban and firewall
install_firewall() {
    clear
    echo -e "${GREEN}${BOLD}Installing Fail2ban & Firewall...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get install -y fail2ban
    
    cat > /etc/fail2ban/jail.local <<'EOF'
[DEFAULT]
bantime = 3600
banaction = iptables-multiport
maxretry = 5

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 5
EOF
    
    systemctl restart fail2ban
    systemctl enable fail2ban
    
    # UFW
    ufw --force enable
    ufw allow 22/tcp
    ufw allow 80/tcp
    ufw allow 443/tcp
    ufw reload
    
    echo -e "${GREEN}✓ Firewall configured${NC}"
}

# Install PHP 8.4
install_php() {
    clear
    echo -e "${GREEN}${BOLD}Installing PHP 8.4...${NC}"
    sleep 1
    
    wait_for_apt
    add-apt-repository -y ppa:ondrej/php
    apt-get update
    
    # Install PHP 8.4 and extensions
    apt-get install -y php8.4-fpm php8.4-common php8.4-cli php8.4-curl \
        php8.4-bcmath php8.4-mbstring php8.4-mysql php8.4-sqlite3 \
        php8.4-pgsql php8.4-redis php8.4-memcached php8.4-zip \
        php8.4-xml php8.4-soap php8.4-gd php8.4-imagick php8.4-intl
    
    # Configure PHP
    cat > /etc/php/8.4/fpm/conf.d/faber.ini <<'EOF'
memory_limit = 256M
upload_max_filesize = 256M
post_max_size = 256M
max_execution_time = 300
max_input_time = 300
EOF
    
    systemctl restart php8.4-fpm
    systemctl enable php8.4-fpm
    
    # Set PHP 8.4 as default CLI
    update-alternatives --set php /usr/bin/php8.4
    
    echo -e "${GREEN}✓ PHP 8.4 installed${NC}"
}

# Install Composer
install_composer() {
    clear
    echo -e "${GREEN}${BOLD}Installing Composer...${NC}"
    sleep 1
    
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    php composer-setup.php --no-interaction --install-dir=/usr/local/bin --filename=composer
    php -r "unlink('composer-setup.php');"
    
    echo -e "${GREEN}✓ Composer installed${NC}"
}

# Install MySQL
install_mysql() {
    clear
    echo -e "${GREEN}${BOLD}Installing MySQL...${NC}"
    sleep 1
    
    # Check if MySQL is already configured
    local existing_password=""
    if [ -f "/etc/faber/config.json" ]; then
        existing_password=$(jq -r '.mysql_root_password // empty' /etc/faber/config.json 2>/dev/null)
    fi
    
    if [ -n "$existing_password" ]; then
        echo -e "${YELLOW}MySQL already configured, skipping password setup${NC}"
        # Just ensure MySQL is installed and running
        wait_for_apt
        apt-get install -y mysql-server
        systemctl enable mysql
        echo -e "${GREEN}✓ MySQL installed${NC}"
        return
    fi
    
    # Generate root password (only on first install)
    MYSQL_ROOT_PASSWORD=$(openssl rand -base64 24 | sha256sum | base64 | head -c 32)
    
    # Install MySQL
    wait_for_apt
    apt-get install -y mysql-server
    
    # Secure MySQL installation
    mysql <<EOF
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PASSWORD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
EOF
    
    systemctl enable mysql
    
    # Save root password
    update_config_json "mysql_root_password" "$MYSQL_ROOT_PASSWORD"
    
    echo -e "${GREEN}✓ MySQL installed${NC}"
}

# Install Redis
install_redis() {
    clear
    echo -e "${GREEN}${BOLD}Installing Redis...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get install -y redis-server
    
    # Configure Redis
    sed -i 's/^supervised no/supervised systemd/' /etc/redis/redis.conf
    
    systemctl restart redis-server
    systemctl enable redis-server
    
    echo -e "${GREEN}✓ Redis installed${NC}"
}

# Install ClamAV
install_clamav() {
    clear
    echo -e "${GREEN}${BOLD}Installing ClamAV Antivirus...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get install -y clamav clamav-daemon clamav-freshclam
    
    # Stop services to update
    systemctl stop clamav-daemon
    systemctl stop clamav-freshclam
    
    # Update virus definitions
    echo -e "${CYAN}Updating virus definitions (this may take a few minutes)...${NC}"
    freshclam
    
    # Start services
    systemctl start clamav-freshclam
    systemctl start clamav-daemon
    systemctl enable clamav-daemon
    systemctl enable clamav-freshclam
    
    # Create scan script
    cat > /usr/local/bin/faber-scan <<'SCANEOF'
#!/bin/bash

#############################################
# ClamAV Daily Scan Script
# Auto-generated by Faber
#############################################

LOG_DIR="/var/log/faber"
SCAN_LOG="$LOG_DIR/clamav-scan.log"
REPORT_LOG="$LOG_DIR/clamav-report.log"

mkdir -p "$LOG_DIR"

echo "================================================" >> "$SCAN_LOG"
echo "ClamAV Scan Report - $(date)" >> "$SCAN_LOG"
echo "================================================" >> "$SCAN_LOG"
echo "" >> "$SCAN_LOG"

# Scan all app directories (uses 'current' symlink for zero-downtime deployments)
for app_dir in /home/*/current; do
    if [ -d "$app_dir" ]; then
        username=$(basename $(dirname "$app_dir"))
        echo "Scanning: $username ($app_dir)" >> "$SCAN_LOG"
        
        # Run scan (exclude some Laravel directories for performance)
        clamscan -r "$app_dir" \
            --exclude-dir="$app_dir/vendor" \
            --exclude-dir="$app_dir/node_modules" \
            --exclude-dir="$app_dir/storage" \
            --infected \
            --log="$REPORT_LOG" \
            2>&1 | grep -E "Infected files:|FOUND" >> "$SCAN_LOG"
        
        if [ $? -eq 1 ]; then
            echo "✓ Clean" >> "$SCAN_LOG"
        elif [ $? -eq 0 ]; then
            echo "⚠ THREATS DETECTED!" >> "$SCAN_LOG"
            # Send alert (you can customize this)
            echo "ALERT: Malware detected in $username" | mail -s "ClamAV Alert: $username" root
        fi
        echo "" >> "$SCAN_LOG"
    fi
done

echo "================================================" >> "$SCAN_LOG"
echo "Scan completed at $(date)" >> "$SCAN_LOG"
echo "================================================" >> "$SCAN_LOG"
echo "" >> "$SCAN_LOG"

# Keep only last 30 days of logs
find "$LOG_DIR" -name "clamav-*.log" -mtime +30 -delete
SCANEOF
    
    chmod +x /usr/local/bin/faber-scan
    
    # Note: ClamAV scan cron job will be added in setup_cron()
    
    echo -e "${GREEN}✓ ClamAV installed and configured${NC}"
}

# Install Supervisor
install_supervisor() {
    clear
    echo -e "${GREEN}${BOLD}Installing Supervisor...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get install -y supervisor
    systemctl enable supervisor
    systemctl start supervisor
    
    echo -e "${GREEN}✓ Supervisor installed${NC}"
}

# Install Let's Encrypt
install_letsencrypt() {
    clear
    echo -e "${GREEN}${BOLD}Installing Let's Encrypt...${NC}"
    sleep 1
    
    wait_for_apt
    apt-get install -y certbot python3-certbot-nginx
    
    echo -e "${GREEN}✓ Let's Encrypt installed${NC}"
}

# Install Node.js
install_nodejs() {
    clear
    echo -e "${GREEN}${BOLD}Installing Node.js...${NC}"
    sleep 1
    
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    wait_for_apt
    apt-get install -y nodejs
    
    echo -e "${GREEN}✓ Node.js installed${NC}"
}

# Install Faber
install_faber() {
    clear
    echo -e "${GREEN}${BOLD}Installing Faber CLI...${NC}"
    sleep 1
    
    # Create directories
    mkdir -p /opt/faber/lib
    mkdir -p /etc/faber
    # 751 so www-data can traverse to read apps.json, but can't list contents
    chmod 751 /etc/faber
    
    # Download Faber
    cd /tmp
    git clone -b "$BRANCH" "https://github.com/${REPO}.git" faber-install
    
    # Get commit hash
    cd faber-install
    INSTALLED_COMMIT=$(git rev-parse HEAD)
    cd /tmp
    
    # Copy files
    cp faber-install/faber /usr/local/bin/faber
    ln -sf /usr/local/bin/faber /usr/local/bin/fab
    cp -r faber-install/lib/* /opt/faber/lib/

    # Copy web files (webhook.php, etc.)
    mkdir -p /opt/faber/web
    cp -r faber-install/web/* /opt/faber/web/

    # Set secure permissions (only root can read and execute)
    chmod 700 /usr/local/bin/faber
    chmod 700 /opt/faber/lib/*.sh
    chmod 755 /opt/faber/lib/release.sh  # Must be readable by app users for deploy.sh
    chmod 644 /opt/faber/web/*.php       # Readable by www-data for nginx/php-fpm
    chmod 711 /opt/faber /opt/faber/lib /opt/faber/web  # Traversable but not listable
    chown -R root:root /usr/local/bin/faber /opt/faber
    
    # Initialize storage
    # apps.json and domains.json are 644 (readable by www-data for webhooks)
    # databases.json stays 600 (contains sensitive info)
    for file in apps.json domains.json; do
        if [ ! -f "/etc/faber/$file" ]; then
            echo "{}" > "/etc/faber/$file"
            chmod 644 "/etc/faber/$file"
        fi
    done
    
    if [ ! -f "/etc/faber/databases.json" ]; then
        echo "{}" > "/etc/faber/databases.json"
        chmod 600 "/etc/faber/databases.json"
    fi
    
    # Create version file with commit hash
    cat > /etc/faber/version.json <<EOF
{
  "commit": "${INSTALLED_COMMIT}",
  "branch": "${BRANCH}",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
    chmod 600 /etc/faber/version.json
    
    # Cleanup
    rm -rf /tmp/faber-install
    
    echo -e "${GREEN}✓ Faber installed${NC}"
}

# Install Webhook Endpoint
install_webhook() {
    clear
    echo -e "${GREEN}${BOLD}Installing Webhook Endpoint...${NC}"
    sleep 1
    
    # Prompt for webhook domain (required)
    echo ""
    echo -e "${CYAN}Webhook Domain Configuration${NC}"
    echo "─────────────────────────────────────"
    echo "A domain with SSL is required for webhook endpoints."
    echo "Enter a domain name for the webhook endpoint (e.g., webhooks.yourdomain.com)"
    echo ""
    
    while [ -z "$WEBHOOK_DOMAIN" ]; do
        read -p "Webhook domain (required): " WEBHOOK_DOMAIN < /dev/tty
        if [ -z "$WEBHOOK_DOMAIN" ]; then
            echo -e "${RED}Error: Domain is required for webhook endpoint${NC}"
        fi
    done
    
    # Prompt for SSL email (required)
    echo ""
    echo "Enter an email address for Let's Encrypt SSL certificates."
    echo "This email will also be used as the default for app SSL certificates."
    echo ""
    
    while [ -z "$WEBHOOK_SSL_EMAIL" ]; do
        read -p "SSL email (required): " WEBHOOK_SSL_EMAIL < /dev/tty
        if [ -z "$WEBHOOK_SSL_EMAIL" ]; then
            echo -e "${RED}Error: SSL email is required${NC}"
        fi
    done
    
    # GitHub OAuth App setup tutorial
    echo ""
    echo -e "${CYAN}GitHub OAuth App Setup (Optional)${NC}"
    echo "─────────────────────────────────────"
    echo "To enable automatic webhook creation, you need a GitHub OAuth App."
    echo ""
    echo "1. Go to: https://github.com/settings/applications/new"
    echo "2. Fill in:"
    echo "   - Application name: Faber Server Manager (or whatever you want)"
    echo "   - Homepage URL: Your project url"
    echo "   - Authorization callback URL: http://localhost (not used for device flow, but required)"
    echo "3. Check 'Enable Device Flow'"
    echo "4. Click 'Register application'"
    echo "5. Copy the 'Client ID' (NOT the secret)"
    echo ""
    read -p "GitHub OAuth Client ID (or press Enter to skip): " GITHUB_CLIENT_ID < /dev/tty
    
    if [ -n "$GITHUB_CLIENT_ID" ]; then
        update_config_json "github_client_id" "$GITHUB_CLIENT_ID"
        echo -e "${GREEN}✓ GitHub OAuth Client ID saved${NC}"
    fi
    
    # Get server IP for DNS example
    local SERVER_IP=$(curl -s https://checkip.amazonaws.com)
    
    echo ""
    echo -e "${YELLOW}${BOLD}DNS Configuration Required${NC}"
    echo -e "${YELLOW}─────────────────────────────────────${NC}"
    echo -e "${YELLOW}Create an A record pointing to this server:${NC}"
    echo ""
    echo -e "  ${CYAN}${WEBHOOK_DOMAIN}${NC}  →  ${CYAN}${SERVER_IP}${NC}"
    echo ""
    echo -e "${YELLOW}Press Enter when DNS is ready...${NC}"
    read -p "" < /dev/tty

    # webhook.php is installed by install_faber() from the web/ directory

    # Initialize webhooks storage
    if [ ! -f "/etc/faber/webhooks.json" ]; then
        echo "{}" > /etc/faber/webhooks.json
        # 640 with www-data group so PHP can read secrets
        chmod 640 /etc/faber/webhooks.json
        chown root:www-data /etc/faber/webhooks.json
    fi
    
    # Create webhook log directory and file with proper permissions
    mkdir -p /var/log/faber
    touch /var/log/faber/webhook.log
    chown www-data:www-data /var/log/faber/webhook.log
    chmod 644 /var/log/faber/webhook.log
    
    # Allow www-data to run bash as any user (needed for deploy.sh execution)
    echo 'www-data ALL=(ALL) NOPASSWD: /usr/bin/bash' > /etc/sudoers.d/faber-webhook
    chmod 440 /etc/sudoers.d/faber-webhook
    
    # Step 1: Create temporary HTTP-only config for certbot validation
    cat > /etc/nginx/sites-available/webhook <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${WEBHOOK_DOMAIN};
    
    location / {
        return 200 'Faber webhook endpoint - awaiting SSL setup';
        add_header Content-Type text/plain;
    }
}
EOF
    
    # Remove old symlink if exists
    rm -f /etc/nginx/sites-enabled/webhook
    
    # Enable the webhook site
    ln -sf /etc/nginx/sites-available/webhook /etc/nginx/sites-enabled/webhook
    
    # Test and reload nginx with HTTP-only config
    nginx -t
    systemctl reload nginx
    
    # Step 2: Request SSL certificate
    echo ""
    echo -e "${CYAN}Requesting SSL certificate for ${WEBHOOK_DOMAIN}...${NC}"
    CERTBOT_OUTPUT=$(certbot certonly --nginx -d "$WEBHOOK_DOMAIN" --non-interactive --agree-tos --email "$WEBHOOK_SSL_EMAIL" 2>&1)
    CERTBOT_EXIT=$?
    
    # Filter out verbose output but show important messages
    echo "$CERTBOT_OUTPUT" | grep -v "^Saving debug log" | grep -v "^$" || true
    
    if [ $CERTBOT_EXIT -ne 0 ] || [ ! -d "/etc/letsencrypt/live/${WEBHOOK_DOMAIN}" ]; then
        echo -e "${RED}Error: SSL certificate request failed${NC}"
        echo -e "${YELLOW}SSL is required for webhook endpoints.${NC}"
        echo -e "${YELLOW}Please ensure:${NC}"
        echo -e "  1. DNS is configured to point ${WEBHOOK_DOMAIN} to this server"
        echo -e "  2. Port 80 is accessible from the internet"
        echo -e "  3. The domain is not already using Let's Encrypt"
        echo ""
        echo -e "${YELLOW}After fixing DNS, run:${NC}"
        echo -e "  ${CYAN}certbot certonly --nginx -d ${WEBHOOK_DOMAIN}${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ SSL certificate obtained${NC}"
    
    # Step 3: Now create the full SSL config (certs exist now)
    cat > /etc/nginx/sites-available/webhook <<EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${WEBHOOK_DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name ${WEBHOOK_DOMAIN};
    server_tokens off;
    
    ssl_certificate /etc/letsencrypt/live/${WEBHOOK_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${WEBHOOK_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-XSS-Protection "1; mode=block";
    add_header X-Content-Type-Options "nosniff";
    
    client_max_body_size 100M;
    
    # Faber Webhook Endpoint
    location ~ ^/webhook/([a-zA-Z0-9_-]+)/?$ {
        # Only allow POST requests
        if (\$request_method != POST) {
            return 405;
        }
        
        # Rate limiting
        limit_req zone=one burst=10 nodelay;
        
        # Pass to PHP-FPM
        fastcgi_pass unix:/var/run/php/php8.4-fpm.sock;
        fastcgi_param SCRIPT_FILENAME /opt/faber/web/webhook.php;
        fastcgi_param REQUEST_URI \$request_uri;
        include fastcgi_params;
    }
    
    # Deny all other requests
    location / {
        return 404;
    }
}
EOF
    
    # Test and reload nginx with SSL config
    nginx -t
    systemctl reload nginx
    echo -e "${GREEN}✓ Webhook endpoint installed with SSL${NC}"
    
    # Store webhook domain and SSL email in config
    update_config_json "webhook_domain" "$WEBHOOK_DOMAIN"
    update_config_json "ssl_email" "$WEBHOOK_SSL_EMAIL"
    
    # Final summary with webhook URL
    echo ""
    echo -e "${CYAN}${BOLD}Webhook Configuration Summary:${NC}"
    echo "─────────────────────────────────────"
    echo -e "${GREEN}✓ Domain: ${WEBHOOK_DOMAIN}${NC}"
    echo -e "${GREEN}✓ SSL: Enabled${NC}"
    echo -e "${CYAN}Webhook URL: https://${WEBHOOK_DOMAIN}/webhook/<username>${NC}"
    echo ""
}

# Setup cron jobs
setup_cron() {
    clear
    echo -e "${GREEN}${BOLD}Setting up Cron Jobs...${NC}"
    sleep 1
    
    # Create log directory
    mkdir -p /var/log/faber
    
    cat > /etc/cron.d/faber <<'CRONEOF'
# ============================================
# FABER AUTOMATIC CRON JOBS
# Managed by Faber - do not edit manually
# ============================================

SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# Update ClamAV Virus Definitions (Daily 2 AM)
0 2 * * * root /usr/bin/freshclam >> /var/log/faber/clamav-update.log 2>&1

# ClamAV Daily Scan (3 AM)
0 3 * * * root /usr/local/bin/faber-scan >> /var/log/faber/clamav-scan.log 2>&1

# SSL Certificate Renewal (Weekly Sunday 4:10 AM)
10 4 * * 0 root certbot renew --nginx --non-interactive --post-hook "systemctl restart nginx.service" >> /var/log/faber/certbot.log 2>&1

# System Updates (Weekly Sunday 4:20 AM)
20 4 * * 0 root apt-get -y update >> /var/log/faber/updates.log 2>&1

# System Upgrade (Weekly Sunday 4:40 AM)
40 4 * * 0 root DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical apt-get -q -y -o "Dpkg::Options::=--force-confdef" -o "Dpkg::Options::=--force-confold" dist-upgrade >> /var/log/faber/updates.log 2>&1

# Clean APT Cache (Weekly Sunday 5:20 AM)
20 5 * * 0 root apt-get clean && apt-get autoclean >> /var/log/faber/updates.log 2>&1

# Clear RAM Cache and Swap (Daily 5:50 AM)
50 5 * * * root echo 3 > /proc/sys/vm/drop_caches && swapoff -a && swapon -a
CRONEOF
    
    # Set proper permissions for cron.d file
    chmod 644 /etc/cron.d/faber
    
    echo -e "${GREEN}✓ Cron jobs configured${NC}"
}

# Final steps
final_steps() {
    clear
    echo -e "${GREEN}${BOLD}Final Steps...${NC}"
    sleep 1
    
    # Disable password authentication for root (optional)
    # sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    # systemctl restart sshd
    
    # Get server info
    SERVER_IP=$(curl -s https://checkip.amazonaws.com)
    MYSQL_ROOT_PASSWORD=$(jq -r '.mysql_root_password' /etc/faber/config.json)
    
    clear
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo -e "  ${GREEN}${BOLD}FABER INSTALLATION COMPLETED!${NC}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo -e "  ${BOLD}Server Information:${NC}"
    echo "  ────────────────────────────────────────────────"
    echo -e "  IP Address:    ${CYAN}$SERVER_IP${NC}"
    echo -e "  Faber Version:  ${CYAN}$BUILD${NC}"
    echo ""
    echo -e "  ${BOLD}MySQL Root Credentials:${NC}"
    echo "  ────────────────────────────────────────────────"
    echo -e "  Username:      ${CYAN}root${NC}"
    echo -e "  Password:      ${CYAN}$MYSQL_ROOT_PASSWORD${NC}"
    echo ""
    echo -e "  ${YELLOW}${BOLD}⚠ IMPORTANT: Save these credentials!${NC}"
    echo ""
    echo -e "  ${BOLD}Getting Started:${NC}"
    echo "  ────────────────────────────────────────────────"
    echo -e "  Check server status:    ${CYAN}faber status${NC}"
    echo -e "  View all commands:      ${CYAN}faber help${NC}"
    echo -e "  Create app:             ${CYAN}faber app create${NC}"
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Main installation
main() {
    show_logo
    check_os
    check_root
    install_basics
    setup_motd
    setup_swap
    setup_editor
    install_nginx
    install_firewall
    install_php
    install_composer
    install_mysql
    install_redis
    install_clamav
    install_supervisor
    install_letsencrypt
    install_nodejs
    install_faber
    install_webhook
    setup_cron
    final_steps
}

# Run installation
main
