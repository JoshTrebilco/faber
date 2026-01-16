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
# Only defined if user hasn't defined them
#############################################

# Define defaults only if not already defined by user's deploy.sh
type started &>/dev/null || started() { :; }
type linked &>/dev/null || linked() { :; }
type activated &>/dev/null || activated() { :; }
type finished &>/dev/null || finished() { :; }

#############################################
# Helper Functions
#############################################

# Print step with formatting
print_step() {
    echo "→ $1"
}

# Run a command with output
run_cmd() {
    if ! "$@" 2>&1; then
        DEPLOY_FAILED=1
        return 1
    fi
    return 0
}

#############################################
# GitHub App Authentication (Inline)
#############################################

# GitHub App config file
GITHUB_FILE="${FABER_DATA_DIR:-/etc/faber}/github.json"

# Parse owner/repo from REPOSITORY URL
github_parse_repo_inline() {
    local url=$1
    if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
}

# Generate JWT for GitHub App (inline version for deploy scripts)
github_generate_jwt_inline() {
    local app_id=$(jq -r '.github_app_id // empty' "$GITHUB_FILE" 2>/dev/null)
    local private_key=$(jq -r '.github_app_private_key // empty' "$GITHUB_FILE" 2>/dev/null)

    if [ -z "$app_id" ] || [ -z "$private_key" ]; then
        return 1
    fi

    local header='{"alg":"RS256","typ":"JWT"}'
    local now=$(date +%s)
    local iat=$((now - 60))
    local exp=$((now + 600))
    local payload="{\"iat\":$iat,\"exp\":$exp,\"iss\":\"$app_id\"}"

    local header_b64=$(echo -n "$header" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
    local payload_b64=$(echo -n "$payload" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
    local signature=$(echo -n "${header_b64}.${payload_b64}" | \
        openssl dgst -sha256 -sign <(echo "$private_key") | \
        openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

    echo "${header_b64}.${payload_b64}.${signature}"
}

# Get installation token (inline version for deploy scripts)
github_get_token_inline() {
    local owner_repo=$1
    local jwt=$(github_generate_jwt_inline)

    if [ -z "$jwt" ]; then
        return 1
    fi

    local install_response=$(curl -s \
        "https://api.github.com/repos/$owner_repo/installation" \
        -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json")

    local installation_id=$(echo "$install_response" | jq -r '.id // empty')
    if [ -z "$installation_id" ]; then
        return 1
    fi

    local token_response=$(curl -s -X POST \
        "https://api.github.com/app/installations/$installation_id/access_tokens" \
        -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json")

    echo "$token_response" | jq -r '.token // empty'
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
    echo ""
    
    # Set umask for secure permissions
    umask 027
    
    # Validate configuration
    if ! validate_deploy_config; then
        DEPLOY_FAILED=1
        exit 1
    fi
    
    # Step 1: Create release directory
    RELEASE_NAME=$(date +%Y%m%d%H%M%S)
    RELEASE_DIR="$RELEASES_DIR/$RELEASE_NAME"
    mkdir -p "$RELEASE_DIR"
    print_step "Release: $RELEASE_NAME"
    
    # Step 2: Clone repository with GitHub App token
    local owner_repo=$(github_parse_repo_inline "$REPOSITORY")
    if [ -z "$owner_repo" ]; then
        echo "✗ Could not parse GitHub repository from: $REPOSITORY"
        exit 1
    fi
    
    print_step "Getting deployment token..."
    local token=$(github_get_token_inline "$owner_repo")
    if [ -z "$token" ]; then
        echo "✗ Failed to get GitHub token"
        exit 1
    fi
    
    local auth_url="https://x-access-token:${token}@github.com/${owner_repo}.git"
    
    print_step "Cloning $BRANCH branch..."
    if ! run_cmd git clone -b "$BRANCH" --depth 1 "$auth_url" "$RELEASE_DIR"; then
        echo "✗ Failed to clone repository"
        exit 1
    fi
    
    # Reset remote to plain HTTPS (no token stored)
    git -C "$RELEASE_DIR" remote set-url origin "$REPOSITORY"
    
    cd "$RELEASE_DIR" || exit 1
    
    # Hook: started (after clone, before linking)
    started
    
    # Step 3: Link shared resources
    print_step "Linking storage and .env..."
    [ -d "$RELEASE_DIR/storage" ] && rm -rf "$RELEASE_DIR/storage"
    ln -s "$SHARED_STORAGE" "$RELEASE_DIR/storage"
    [ -f "$RELEASE_DIR/.env" ] && rm -f "$RELEASE_DIR/.env"
    ln -s "$SHARED_ENV" "$RELEASE_DIR/.env"
    
    # Hook: linked (composer, npm, migrations, etc.)
    cd "$RELEASE_DIR" || exit 1
    linked
    
    # Check if linked hook failed
    if [ $DEPLOY_FAILED -eq 1 ]; then
        echo "✗ Deployment failed during build"
        exit 1
    fi
    
    # Fix permissions on bootstrap/cache
    [ -d "$RELEASE_DIR/bootstrap/cache" ] && chmod -R 775 "$RELEASE_DIR/bootstrap/cache" 2>/dev/null || true
    
    # Step 4: Get previous release reference
    if [ -L "$CURRENT_LINK" ]; then
        PREVIOUS_RELEASE=$(readlink -f "$CURRENT_LINK")
    fi
    
    # Atomic symlink switch
    print_step "Activating release..."
    if ! ln -sfn "$RELEASE_DIR" "$CURRENT_LINK"; then
        echo "✗ Failed to switch symlink"
        DEPLOY_FAILED=1
        exit 1
    fi
    
    # Hook: activated (queue restart, notifications)
    cd "$CURRENT_LINK" || exit 1
    activated
    
    # Step 5: Cleanup old releases
    cd "$RELEASES_DIR" || exit 1
    local release_count=$(ls -1d */ 2>/dev/null | wc -l)
    
    if [ "$release_count" -gt "$RELEASES_TO_KEEP" ]; then
        local releases_to_delete=$(ls -1d */ | head -n -$RELEASES_TO_KEEP)
        for release in $releases_to_delete; do
            [ "$RELEASES_DIR/$release" != "$RELEASE_DIR/" ] && rm -rf "$RELEASES_DIR/$release"
        done
        print_step "Cleaned up old releases (kept last $RELEASES_TO_KEEP)"
    fi
    
    # Hook: finished (monitoring pings, cleanup)
    cd "$CURRENT_LINK" || exit 1
    finished
    
    # Final status
    echo ""
    echo "═══════════════════════════════════════"
    if [ $DEPLOY_FAILED -eq 1 ]; then
        echo "Deployment completed with errors"
    else
        echo "✓ Deployment successful!"
        echo "Release: $RELEASE_NAME"
    fi
    echo "Finished at $(date)"
    echo "═══════════════════════════════════════"
    
    exit $DEPLOY_FAILED
}

#############################################
# Utility Functions (can be used in hooks)
#############################################

# Mark deployment as failed (can be called from hooks)
fail_deployment() {
    local message="${1:-Deployment failed}"
    echo "✗ $message"
    DEPLOY_FAILED=1
}
