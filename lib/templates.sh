#!/bin/bash

#############################################
# Template Functions
# Generates user-customizable deploy.sh
#############################################

# Create user-customizable deployment hooks script
create_deploy_script() {
    local username=$1
    local repository=$2
    local branch=$3
    local home_dir="/home/$username"
    local deploy_script="$home_dir/deploy.sh"
    
    # Repository URL is already validated as HTTPS
    local clone_url="$repository"
    
    # Generate the user's deploy.sh with hooks
    cat > "$deploy_script" <<DEPLOYEOF
#!/bin/bash

#############################################
# Deployment Hooks
# Customize your deployment by editing the functions below
#
# Hook Phases (Envoyer-style):
#   started()   - After clone, before linking shared resources
#   linked()    - After storage/.env linked, before activation
#   activated() - After symlink switch (app is live)
#   finished()  - Final cleanup
#
# Available variables:
#   \$RELEASE_DIR  - Path to the new release being deployed
#   \$CURRENT_LINK - Path to the 'current' symlink
#   \$RELEASE_NAME - Timestamp of the release (e.g., 20260106123456)
#
# Available functions:
#   fail_deployment "message" - Mark deployment as failed
#############################################

# Deployment Configuration
REPOSITORY="$clone_url"
BRANCH="$branch"

# After clone, before linking shared resources
# Use for: environment checks, custom setup
started() {
    : # Add custom steps here
}

# After storage/.env linked, before activation
# Use for: composer, npm, migrations, caching
linked() {
    # Install PHP dependencies
    composer install --no-interaction --prefer-dist --optimize-autoloader --no-dev
    
    # Install and build frontend assets
    if [ -f "package.json" ]; then
        npm ci
        if grep -q '"build"' package.json; then
            npm run build
        fi
    fi
    
    # Run database migrations
    php artisan migrate --force
    
    # Optimize for production
    php artisan config:cache
    php artisan route:cache
    php artisan view:cache
    php artisan event:cache
}

# After symlink switch (app is live)
# Use for: queue restart, notifications, health checks
activated() {
    # Restart queue workers to pick up new code
    php artisan queue:restart
}

# Final cleanup
# Use for: monitoring pings, cleanup tasks
finished() {
    : # Add custom cleanup here
}

#############################################
# DO NOT EDIT BELOW THIS LINE
# Core deployment logic is handled by release.sh
#############################################
FABER_LIB="\${FABER_LIB:-/opt/faber/lib}"
if [ -f "\$FABER_LIB/release.sh" ]; then
    source "\$FABER_LIB/release.sh"
    run_deployment
else
    echo "Error: release.sh not found at \$FABER_LIB/release.sh"
    echo "Please ensure Faber is properly installed."
    exit 1
fi
DEPLOYEOF
    
    # Set ownership and permissions
    chown "$username:$username" "$deploy_script"
    chmod 755 "$deploy_script"
}
