#!/bin/bash

#############################################
# Release Management - Zero-Downtime Deployment Core
# This file is sourced by user's deploy.sh
#############################################

# Configuration
RELEASES_TO_KEEP=${RELEASES_TO_KEEP:-5}

# These are set when sourced from user's deploy.sh
RELEASE_HOME="${RELEASE_HOME:-$HOME}"
RELEASES_DIR="${RELEASES_DIR:-$RELEASE_HOME/releases}"
CURRENT_LINK="${CURRENT_LINK:-$RELEASE_HOME/current}"
SHARED_STORAGE="${SHARED_STORAGE:-$RELEASE_HOME/storage}"
SHARED_ENV="${SHARED_ENV:-$RELEASE_HOME/.env}"
LOG_FILE="${LOG_FILE:-$RELEASE_HOME/logs/deploy.log}"

# Release-specific variables (set during deployment)
RELEASE_NAME=""
RELEASE_DIR=""
PREVIOUS_RELEASE=""

# Deployment state
DEPLOY_FAILED=0

#############################################
# Default Hook Implementations
# Users override these in their deploy.sh
#############################################

# Default: do nothing (users override)
started() { :; }
linked() { :; }
activated() { :; }
finished() { :; }

#############################################
# Helper Functions
#############################################

# Print step with formatting
print_step() {
    echo "→ $1"
}

# Print section header
print_section() {
    echo ""
    echo "─── $1 ───"
}

# Run a command and track failures
run_step() {
    local description="$1"
    shift
    print_step "$description"
    if ! "$@" 2>&1; then
        echo "  ✗ Failed: $description"
        DEPLOY_FAILED=1
        return 1
    fi
    return 0
}

# Cleanup failed release
cleanup_failed_release() {
    if [ -d "$RELEASE_DIR" ] && [ -n "$RELEASE_DIR" ]; then
        echo "→ Cleaning up failed release..."
        rm -rf "$RELEASE_DIR"
    fi
}

#############################################
# Core Deployment Functions
#############################################

# Validate deployment configuration
# REPOSITORY and BRANCH should be defined in the user's deploy.sh
validate_deploy_config() {
    if [ -z "$REPOSITORY" ]; then
        echo "✗ Error: REPOSITORY is not set in deploy.sh"
        return 1
    fi
    
    if [ -z "$BRANCH" ]; then
        echo "✗ Error: BRANCH is not set in deploy.sh"
        return 1
    fi
    
    return 0
}

# Step 1: Create release directory
create_release() {
    RELEASE_NAME=$(date +%Y%m%d%H%M%S)
    RELEASE_DIR="$RELEASES_DIR/$RELEASE_NAME"
    
    print_section "Create Release Directory"
    mkdir -p "$RELEASE_DIR"
    print_step "Created: $RELEASE_DIR"
}

# Step 2: Clone repository
clone_repository() {
    print_section "Clone Repository"
    run_step "Cloning $BRANCH branch..." git clone -b "$BRANCH" --depth 1 "$REPOSITORY" "$RELEASE_DIR" || {
        echo "✗ Failed to clone repository"
        DEPLOY_FAILED=1
        return 1
    }
    
    cd "$RELEASE_DIR" || return 1
}

# Step 3: Link shared resources
link_shared_resources() {
    print_section "Link Shared Resources"
    
    # Remove storage from release (we'll symlink the shared one)
    if [ -d "$RELEASE_DIR/storage" ]; then
        rm -rf "$RELEASE_DIR/storage"
    fi
    
    # Symlink shared storage
    run_step "Linking shared storage..." ln -s "$SHARED_STORAGE" "$RELEASE_DIR/storage" || true
    
    # Remove .env from release and symlink shared
    if [ -f "$RELEASE_DIR/.env" ]; then
        rm -f "$RELEASE_DIR/.env"
    fi
    run_step "Linking shared .env..." ln -s "$SHARED_ENV" "$RELEASE_DIR/.env" || true
}

# Step 4: Activate release (atomic symlink switch)
activate_release() {
    print_section "Activate Release"
    
    # Get the current release for reference
    if [ -L "$CURRENT_LINK" ]; then
        PREVIOUS_RELEASE=$(readlink -f "$CURRENT_LINK")
    fi
    
    # Atomic symlink switch using ln -sfn
    run_step "Switching to new release..." ln -sfn "$RELEASE_DIR" "$CURRENT_LINK" || {
        echo "✗ Failed to switch symlink"
        DEPLOY_FAILED=1
        return 1
    }
    
    print_step "Active release: $RELEASE_NAME"
    if [ -n "$PREVIOUS_RELEASE" ]; then
        print_step "Previous release: $(basename "$PREVIOUS_RELEASE")"
    fi
}

# Step 5: Cleanup old releases
cleanup_old_releases() {
    print_section "Cleanup Old Releases"
    
    cd "$RELEASES_DIR" || return 1
    
    # Count releases
    local release_count=$(ls -1d */ 2>/dev/null | wc -l)
    print_step "Total releases: $release_count (keeping last $RELEASES_TO_KEEP)"
    
    if [ "$release_count" -gt "$RELEASES_TO_KEEP" ]; then
        # Get releases to delete (oldest first, excluding newest N)
        local releases_to_delete=$(ls -1d */ | head -n -$RELEASES_TO_KEEP)
        
        for release in $releases_to_delete; do
            local release_path="$RELEASES_DIR/$release"
            # Don't delete the current release
            if [ "$release_path" != "$RELEASE_DIR/" ] && [ "$release_path" != "$RELEASE_DIR" ]; then
                print_step "Removing old release: $release"
                rm -rf "$RELEASES_DIR/$release"
            fi
        done
    fi
}

#############################################
# Main Deployment Runner
#############################################

run_deployment() {
    # Trap to cleanup on failure
    trap 'if [ $DEPLOY_FAILED -eq 1 ]; then cleanup_failed_release; fi' EXIT
    
    echo "═══════════════════════════════════════"
    echo "Zero-Downtime Deployment"
    echo "Started at $(date)"
    echo "═══════════════════════════════════════"
    
    # Set umask for secure permissions
    umask 027
    
    # Validate configuration (REPOSITORY and BRANCH should be set in deploy.sh)
    if ! validate_deploy_config; then
        DEPLOY_FAILED=1
        exit 1
    fi
    
    # Step 1: Create release directory
    create_release
    
    # Step 2: Clone repository
    if ! clone_repository; then
        exit 1
    fi
    
    # Hook: started (after clone, before linking)
    print_section "Hook: started"
    cd "$RELEASE_DIR" || exit 1
    started
    
    # Step 3: Link shared resources
    link_shared_resources
    
    # Hook: linked (after symlinks, before activation)
    # This is where users run composer, npm, migrations, etc.
    print_section "Hook: linked"
    cd "$RELEASE_DIR" || exit 1
    linked
    
    # Check if linked hook failed
    if [ $DEPLOY_FAILED -eq 1 ]; then
        echo ""
        echo "✗ Deployment failed during 'linked' hook"
        exit 1
    fi
    
    # Fix permissions on bootstrap/cache
    if [ -d "$RELEASE_DIR/bootstrap/cache" ]; then
        chmod -R 775 "$RELEASE_DIR/bootstrap/cache" 2>/dev/null || true
    fi
    
    # Step 4: Activate release (atomic symlink switch)
    if ! activate_release; then
        exit 1
    fi
    
    # Hook: activated (after symlink switch, app is live)
    print_section "Hook: activated"
    cd "$CURRENT_LINK" || exit 1
    activated
    
    # Step 5: Cleanup old releases
    cleanup_old_releases
    
    # Hook: finished (final cleanup)
    print_section "Hook: finished"
    cd "$CURRENT_LINK" || exit 1
    finished
    
    # Final status
    echo ""
    echo "═══════════════════════════════════════"
    if [ $DEPLOY_FAILED -eq 1 ]; then
        echo "Deployment completed with errors"
        echo "Finished at $(date)"
        echo "═══════════════════════════════════════"
        exit 1
    else
        echo "✓ Deployment successful!"
        echo "Release: $RELEASE_NAME"
        echo "Finished at $(date)"
        echo "═══════════════════════════════════════"
    fi
}

#############################################
# Utility Functions (can be used in hooks)
#############################################

# Check if current project is Laravel
is_laravel() {
    [ -f "$RELEASE_DIR/artisan" ] || [ -f "$CURRENT_LINK/artisan" ]
}

# Run artisan command in release directory
artisan() {
    php artisan "$@"
}

# Mark deployment as failed (can be called from hooks)
fail_deployment() {
    local message="${1:-Deployment failed}"
    echo "✗ $message"
    DEPLOY_FAILED=1
}

