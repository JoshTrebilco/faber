# Cipi - Server Management CLI

<p align="center">
  <h1>Work in progress... this is not a stable version!</h1>
</p>

<p align="center">
  <strong>A powerful server management CLI for Laravel applications on Ubuntu</strong>
</p>

<p align="center">
  <a href="https://github.com/JoshTrebilco/cipi/blob/latest/LICENSE"><img src="https://img.shields.io/github/license/JoshTrebilco/cipi" alt="License"></a>
  <a href="https://github.com/JoshTrebilco/cipi/stargazers"><img src="https://img.shields.io/github/stars/JoshTrebilco/cipi?style=social" alt="Stars"></a>
</p>

---

## 🚀 What is Cipi?

Cipi is a **CLI-based server control panel** designed exclusively for **Laravel developers** who need a secure, production-ready hosting environment on Ubuntu VPS. With Cipi, you can:

- ✨ Create isolated virtual hosts with individual users and PHP versions
- 🔒 Automatic SSL certificates with Let's Encrypt
- 🗄️ Manage MySQL databases
- 🌐 Configure domains
- 🐘 Install and manage multiple PHP versions (5.6 - 8.5)
- 🔄 Deploy Laravel applications with Git
- 📊 Monitor server status
- 🛡️ Built-in fail2ban + ClamAV antivirus protection
- 🔐 Secure password management (never stored in plain text)

**No web interface needed** - everything is managed via SSH with the `cipi` command!

---

## 🎯 Who is Cipi For?

Cipi is **specifically designed for Laravel applications** and developers who:

- ✅ Want a **secure, production-ready** server without complex DevOps knowledge
- ✅ Need **isolated environments** for multiple Laravel projects on one VPS
- ✅ Prefer **CLI management** over web-based control panels
- ✅ Value **security hardening** with automatic updates and malware scanning
- ✅ Need **per-project PHP versions** (Laravel 8 on PHP 8.0, Laravel 11 on PHP 8.3, etc.)
- ✅ Are deploying on **Ubuntu 24.04 LTS** servers

### 🔒 Security Level: Production-Grade & Hardened

Cipi implements **production-ready security** with multiple layers of protection:

**System Security:**

- 🛡️ **Fail2ban** - Automatic SSH brute-force protection
- 🔥 **UFW Firewall** - Only ports 22, 80, 443 exposed
- 🦠 **ClamAV Antivirus** - Daily malware scans of all applications
- 🔐 **User Isolation** - Each app runs as a separate system user with strict permissions (chmod 750/640)
- 🔑 **Root-Only CLI** - Cipi commands require sudo for administrative control

**Application Security:**

- 🔒 **SSL Everywhere** - Free Let's Encrypt certificates with auto-renewal
- 🚫 **Nginx Hardening** - Server tokens hidden, rate limiting, security headers
- 🗝️ **SSH Keys** - Auto-generated for each app to access private Git repos
- 🔐 **Secure Passwords** - Complex passwords never stored in plain text, shown only once
- 🔄 **Automatic Updates** - Weekly system security patches via cron

**Laravel-Specific:**

- 📂 **Storage Permissions** - Optimized for Laravel's storage and cache directories
- ⚙️ **Supervisor Workers** - Process management for queues
- 📅 **Cron Scheduler** - Pre-configured for `php artisan schedule:run`

**Monitoring & Response:**

- 📊 **System Status** - Real-time monitoring of all services
- 📝 **Comprehensive Logs** - Nginx, PHP-FPM, application, and security logs
- 🚨 **Antivirus Logs** - Track malware scans and threats

**What Cipi is NOT:**

- ❌ Not for "enterprise" with compliance certifications (SOC2, PCI-DSS)
- ❌ Not a WAF (Web Application Firewall) like Cloudflare
- ❌ Not high-availability clustering or load balancing
- ❌ Not for non-PHP applications (only Laravel/PHP)

**Verdict:** Cipi provides **production-grade security** suitable for professional Laravel applications, side projects, and small-to-medium businesses. For highly regulated industries or applications requiring compliance certifications, additional security layers may be needed.

---

## 📋 Requirements

- **Ubuntu 24.04 LTS** (or higher)
- Fresh server installation recommended
- Minimum 512MB RAM, 1 CPU core
- Root access (sudo)
- Public IPv4 address

### VPS Providers Tested

- ✅ DigitalOcean
- ✅ AWS EC2
- ✅ Vultr
- ✅ Linode
- ✅ Hetzner
- ✅ Google Cloud

---

## ⚡ Quick Installation

```bash
wget -O - https://raw.githubusercontent.com/JoshTrebilco/cipi/refs/heads/latest/install.sh | bash
```

Installation takes approximately **10-15 minutes** depending on your server's internet speed.
You will be prompted for:

- **Webhook domain** - A domain for webhook endpoints (e.g., `webhooks.yourdomain.com`)
- **SSL email** - Email address for Let's Encrypt SSL certificates

### AWS Installation

AWS disables root login by default. Use this method:

```bash
ssh ubuntu@<your-server-ip>
sudo -s
wget -O - https://raw.githubusercontent.com/JoshTrebilco/cipi/refs/heads/latest/install.sh | bash
```

**Important:**

- Open ports 22, 80, and 443 in your VPS firewall!
- **Save the MySQL root password** shown during installation!
- App and database passwords are **never stored** in config files for security. Save them when displayed!
- Webhook domain cannot be changed after installation, but SSL email can be changed with `cipi config set ssl_email <email>`

---

## 📚 Usage

### Quick Start Example

The fastest way to deploy a Laravel application:

```bash
# 1. Create your stack (app + domain + database + SSL in one command)
cipi stack create \
  --user=myapp \
  --repository=https://github.com/user/repo.git \
  --domain=example.com \
  --php=8.4

# 2. View webhook configuration for auto-deployment
cipi webhook show myapp
# Copy the webhook URL and secret to GitHub repository settings
# Note: Webhook domain and SSL email are set during installation

# 5. Deploy updates manually (or let webhook handle it)
cipi deploy myapp
```

### Basic Commands

```bash
# Show server status
cipi status

# Show all available commands
cipi help

# Show Cipi version
cipi version
```

### Stack (Full Stack Creation)

The `stack` command is the **recommended way** to set up a complete Laravel application. It creates the app, domain, database, configures SSL, updates `.env`, and runs the initial deployment in one command.

```bash
# Create a new stack (interactive)
cipi stack create

# Create a new stack (non-interactive)
cipi stack create \
  --user=myapp \
  --repository=https://github.com/user/repo.git \
  --domain=example.com \
  --branch=main \
  --php=8.4 \
  --dbname=mydb

# Skip optional steps
cipi stack create \
  --user=myapp \
  --repository=https://github.com/user/repo.git \
  --domain=example.com \
  --skip-db \
  --skip-env \
  --skip-deploy

# Delete stack and optionally database
cipi stack delete myapp

# Delete stack and database together
cipi stack delete myapp --dbname=mydb
```

**What Stack Create Does:**

1. **Creates the app** - Sets up virtual host, user, Git repository, PHP-FPM pool, Nginx config, webhook secret
2. **Assigns domain** - Configures domain and attempts automatic SSL certificate setup
3. **Creates database** - Generates database with secure credentials
4. **Updates .env** - Automatically configures:
   - Database connection (DB_HOST, DB_DATABASE, DB_USERNAME, DB_PASSWORD)
   - APP_URL (if domain provided)
   - APP_ENV=production, APP_DEBUG=false
   - Redis configuration (CACHE_DRIVER, SESSION_DRIVER, REDIS_HOST, etc.)
   - Queue connection (QUEUE_CONNECTION=database)
5. **Runs deployment** - Executes initial deployment script (composer install, migrations, cache optimization, etc.)

**Skip Flags:**

- `--skip-db` - Don't create a database
- `--skip-domain` - Don't assign a domain
- `--skip-env` - Don't update the .env file
- `--skip-deploy` - Don't run the initial deployment

### App Management

```bash
# Create a new virtual host (interactive)
cipi app create

# Create virtual host (non-interactive)
cipi app create \
  --user=myapp \
  --repository=https://github.com/laravel/laravel.git \
  --branch=main \
  --php=8.4

# List all virtual hosts
cipi app list

# Show virtual host details (includes disk space, Git key, webhook info)
cipi app show myapp

# Change PHP version for a virtual host
cipi app edit myapp --php=8.3

# Edit .env file
cipi app env myapp

# Edit crontab (for Laravel scheduler, backups, etc.)
cipi app crontab myapp

# Change virtual host password
cipi app password myapp

# Change virtual host password (custom)
cipi app password myapp --password=MySecurePass123!

# Delete virtual host
cipi app delete myapp
```

### Domain Management

```bash
# Assign a domain (interactive)
cipi domain create

# Assign a domain (non-interactive)
cipi domain create \
  --domain=example.com \
  --app=myapp

# List all domains
cipi domain list

# Delete a domain
cipi domain delete example.com

# Delete a domain (skip confirmation)
cipi domain delete example.com --force
```

**Note:** Deleting a domain will revoke and remove the SSL certificate if one exists. The app will still be accessible via its username.

### Database Management

```bash
# Create a new database (interactive)
cipi database create

# Create database (non-interactive)
cipi database create --name=mydb

# List all databases
cipi database list

# Change database password
cipi database password mydb

# Change database password (custom)
cipi database password mydb --password=MyDbPass123!

# Delete a database
cipi database delete mydb
```

**Database Output:**

When creating or changing a database password, Cipi displays:

- Database credentials (name, username, password)
- Laravel `.env` configuration format
- SSH tunnel connection string for remote database access

### PHP Management

```bash
# List installed PHP versions
cipi php list

# Install a PHP version
cipi php install 8.3

# Switch CLI PHP version
cipi php switch 8.4
```

### Service Management

```bash
# Restart nginx
cipi service restart nginx

# Restart all PHP-FPM services
cipi service restart php

# Restart MySQL
cipi service restart mysql

# Restart Supervisor
cipi service restart supervisor

# Restart Redis
cipi service restart redis
```

### System Management

```bash
# View ClamAV antivirus scan logs
cipi logs

# View last N lines of antivirus logs
cipi logs --lines=100

# Update Cipi to latest version
cipi update
```

### Webhook Management

Each app automatically gets a webhook secret for GitHub/GitLab auto-deployment. The webhook domain is configured during installation and cannot be changed afterward.

**To view your webhook configuration, always run:**

```bash
cipi webhook show myapp
```

This command displays:

- Payload URL (webhook endpoint)
- Secret (for GitHub/GitLab authentication)
- Content type and event settings

**Other webhook commands:**

```bash
# Regenerate webhook secret (invalidates old one)
cipi webhook regenerate myapp

# View webhook logs (live tail)
cipi webhook logs
```

**Setting Up GitHub Webhook:**

1. View your configured webhook: `cipi webhook show myapp`
   - This shows the Payload URL, Secret, and all configuration details
   - The webhook domain is set during installation and cannot be changed
2. In GitHub: Repository → Settings → Webhooks → Add webhook
3. Use the Payload URL from the command output
4. Set Content type to `application/json`
5. Add the Secret from the command output
6. Select "Just the push event"
7. Save webhook

### Configuration Management

Configure global Cipi settings that affect SSL certificates.

```bash
# Change SSL email (set during installation, can be changed)
cipi config set ssl_email your@email.com
```

**Configuration Notes:**

- **SSL Email** - Set during installation and used for all Let's Encrypt SSL certificate requests. Let's Encrypt uses this for certificate expiration notifications. Can be changed at any time using `cipi config set ssl_email <email>`.
- **Webhook Domain** - Set during installation and cannot be changed afterward. To view the configured webhook domain and URL for an app, run `cipi webhook show <username>`.

---

## 🏗️ App Structure

Cipi uses **zero-downtime deployments** with an Envoyer-style release structure:

```
/home/<username>/
├── current -> releases/20260106123456/   # Symlink to active release
├── releases/                              # Timestamped release directories
│   ├── 20260106123456/                   # Each deployment creates a new release
│   └── 20260106100000/
├── storage/                               # Shared persistent storage
│   ├── app/
│   ├── framework/
│   └── logs/
├── .env                                   # Shared environment file
├── logs/                                  # Nginx access & error logs
├── .ssh/                                  # SSH keys for Git
├── deploy.sh                              # Deployment hooks (editable)
└── gitkey.pub                             # SSH public key for GitHub/GitLab
```

**How Zero-Downtime Works:**

1. Each deployment clones fresh code into a new timestamped `releases/` directory
2. Shared resources (`storage/` and `.env`) are symlinked into the release
3. Build steps run (composer, npm, migrations)
4. The `current` symlink is atomically switched to the new release
5. Old releases are cleaned up (keeps last 5)

**Additional System Files:**

- **Log Rotation:** `/etc/logrotate.d/cipi-<username>` - Automatic log rotation (30 days retention)
- **PHP-FPM Pool:** `/etc/php/<version>/fpm/pool.d/<username>.conf` - PHP-FPM configuration
- **Nginx Config:** `/etc/nginx/sites-available/<username>` - Nginx virtual host configuration
- **Webhook Secret:** Stored securely in `/etc/cipi/webhooks.json` (not in user directory)

### Deployment Hooks

Each app has a customizable `deploy.sh` with Envoyer-style hooks:

```bash
cd /home/<username>
./deploy.sh
```

**Hook Phases:**

| Hook          | When                      | Typical Use                        |
| ------------- | ------------------------- | ---------------------------------- |
| `started()`   | After clone               | Environment checks, custom setup   |
| `linked()`    | After storage/.env linked | Composer, npm, migrations, caching |
| `activated()` | After symlink switch      | Queue restart, notifications       |
| `finished()`  | End of deployment         | Monitoring pings, cleanup          |

**Default `linked()` hook:**

```bash
linked() {
    composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev

    if [ -f "package.json" ]; then
        npm ci && npm run build
    fi

    php artisan migrate --force
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
}
```

### Rollback

Instantly rollback to a previous release:

```bash
# List available releases
cipi app releases <username>

# Rollback to previous release
cipi app rollback <username>

# Rollback to specific release
cipi app rollback <username> 20260105120000
```

### SSL Certificates

SSL certificates are **automatically configured** when you create a domain. Cipi uses Let's Encrypt to obtain and configure SSL certificates automatically. Certificates are automatically renewed via cron job.

**Note:** For automatic SSL to work, ensure:

- DNS is configured to point your domain to the server
- Port 80 is accessible from the internet
- SSL email is set (configured during installation, can be changed with `cipi config set ssl_email <email>`)

### Private Git Repositories

Each virtual host has its own SSH key pair for accessing private Git repositories:

```bash
# View the public key
cat /home/<username>/gitkey.pub

# Or show it with the app details
cipi app show <username>
```

Copy the public key and add it to your Git provider:

- **GitHub:** Settings → SSH and GPG keys → New SSH key
- **GitLab:** Settings → SSH Keys → Add new key
- **Bitbucket:** Personal settings → SSH keys → Add key

---

## 🔒 Security Features

- 🛡️ **Fail2ban** - Automatic IP banning after failed SSH attempts
- 🔥 **UFW Firewall** - Only ports 22, 80, 443 are open
- 👤 **Isolated Users** - Each virtual host runs under its own system user
- 🔐 **Secure Permissions** - Proper file and directory permissions
- 🚫 **No FTP** - Only secure SFTP access
- 🔑 **SSL Everywhere** - Free Let's Encrypt certificates

---

## 📦 What's Installed

### Core Software

| Software   | Version       | Purpose                |
| ---------- | ------------- | ---------------------- |
| nginx      | Latest        | Web server             |
| PHP        | 8.4 (default) | PHP interpreter        |
| MySQL      | 8.0+          | Database server        |
| Redis      | Latest        | Caching & sessions     |
| Supervisor | Latest        | Process manager        |
| Composer   | 2.x           | PHP dependency manager |
| Node.js    | 20.x          | JavaScript runtime     |
| npm        | Latest        | Node package manager   |
| Certbot    | Latest        | SSL certificates       |

### Additional PHP Versions

You can install any PHP version from **5.6 to 8.5** (beta):

```bash
cipi php install 8.3
cipi php install 8.2
cipi php install 7.4
```

---

## 🔄 Auto-Updates

Cipi automatically checks for updates via cron job (daily at 5:00 AM). You can also manually update:

```bash
cipi update
```

Updates are pulled from GitHub latest branch.

---

## 📊 Monitoring

### Server Status

```bash
cipi status
```

Output:

```
 ██████ ██ ██████  ██
██      ██ ██   ██ ██
██      ██ ██████  ██
██      ██ ██      ██
 ██████ ██ ██      ██

SERVER STATUS
─────────────────────────────────────
IP:       123.456.789.0
HOSTNAME: my-server
CPU:      25%
RAM:      45%
HDD:      30%

SERVICES
─────────────────────────────────────
nginx:      ● running
mysql:      ● running
php8.4-fpm: ● running
supervisor: ● running
redis:      ● running
```

---

## 🗑️ Uninstall

To uninstall Cipi from your server while **keeping all virtual hosts, databases, and websites running**:

```bash
# Stop and remove Cipi system cron jobs
sudo crontab -l | grep -v "cipi\|certbot\|freshclam\|apt-get" | sudo crontab -

# Remove Cipi executable and scripts
sudo rm -f /usr/local/bin/cipi
sudo rm -rf /opt/cipi

# Optional: Remove Cipi configuration data
# WARNING: This removes all domain/app metadata but keeps actual files
sudo rm -rf /etc/cipi

# Optional: Remove Cipi log directory
sudo rm -rf /var/log/cipi
```

### What Gets Removed

✅ Cipi CLI tool (`/usr/local/bin/cipi`)  
✅ Cipi library scripts (`/opt/cipi/`)  
✅ Cipi configuration data (`/etc/cipi/`)  
✅ Cipi cron jobs (SSL renewal, updates, scans)  
✅ Cipi logs (`/var/log/cipi/`)

### What Stays Intact

✅ All virtual host users (e.g., `/home/myapp/`)  
✅ All websites and Laravel applications  
✅ All databases and MySQL users  
✅ Nginx configurations (`/etc/nginx/sites-available/`)  
✅ PHP-FPM pools (`/etc/php/*/fpm/pool.d/`)  
✅ SSL certificates (`/etc/letsencrypt/`)  
✅ All system packages (Nginx, MySQL, PHP, Redis, etc.)  
✅ Supervisor workers  
✅ Fail2ban and UFW configurations

### After Uninstall

Your websites will **continue to work normally**. You'll need to manage:

- **SSL Renewal**: Setup your own certbot cron job

  ```bash
  sudo crontab -e
  # Add: 10 4 * * 7 certbot renew --nginx --non-interactive
  ```

- **System Updates**: Setup your own update schedule

  ```bash
  sudo crontab -e
  # Add: 20 4 * * 7 apt-get -y update
  # Add: 40 4 * * 7 DEBIAN_FRONTEND=noninteractive apt-get -q -y dist-upgrade
  ```

- **Antivirus Scans**: Setup your own ClamAV scan schedule

  ```bash
  sudo crontab -e
  # Add: 0 3 * * * /usr/local/bin/cipi-scan
  ```

- **Manual Management**: Use standard Linux tools
  ```bash
  sudo nginx -t                          # Test Nginx
  sudo systemctl reload nginx            # Reload Nginx
  sudo systemctl restart php8.4-fpm      # Restart PHP-FPM
  mysql -u root -p                       # Manage databases
  ```

### Reinstallation

You can reinstall Cipi at any time without affecting existing sites:

```bash
wget -O - https://raw.githubusercontent.com/JoshTrebilco/cipi/refs/heads/latest/install.sh | bash
```

Cipi will detect existing virtual hosts and continue managing them.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

---

## 📝 License

Cipi is open-source software licensed under the [MIT license](LICENSE).

---

## 💬 Support

- 🐛 **Bug Reports:** [GitHub Issues](https://github.com/JoshTrebilco/cipi/issues)
- 💡 **Feature Requests:** [GitHub Issues](https://github.com/JoshTrebilco/cipi/issues)

---

## ⭐ Star History

If you find Cipi useful, please consider giving it a star on GitHub!

---

## 🙏 Acknowledgments

- Built by [Josh Trebilco](https://github.com/JoshTrebilco)
- Forked from Cipi. Built by [Andrea Pollastri](https://github.com/andreapollastri/cipi)
- Inspired by server management tools like Forge, RunCloud, and Ploi

---

<p align="center">
  <strong>Made with ❤️ for the Laravel community</strong>
</p>
