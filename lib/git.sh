#!/bin/bash

#############################################
# Git Helper Functions
#############################################

# Helper: Convert HTTPS Git URL to SSH format
git_url_to_ssh() {
    local url=$1
    
    # If already SSH format, return as-is
    if [[ "$url" =~ ^git@ ]] || [[ "$url" =~ ^ssh:// ]]; then
        echo "$url"
        return
    fi
    
    # Convert HTTPS to SSH format
    # https://github.com/user/repo.git -> git@github.com:user/repo.git
    # https://gitlab.com/user/repo.git -> git@gitlab.com:user/repo.git
    if [[ "$url" =~ ^https://([^/]+)/(.+)/(.+)(\.git)?$ ]]; then
        local host="${BASH_REMATCH[1]}"
        local user="${BASH_REMATCH[2]}"
        local repo="${BASH_REMATCH[3]}"
        # Remove .git suffix if present
        repo="${repo%.git}"
        echo "git@${host}:${user}/${repo}.git"
    else
        # If pattern doesn't match, return original
        echo "$url"
    fi
}

# Helper: Create SSH config for git operations (known hosts + config file)
# This should be called before cloning private repos
git_create_ssh_config() {
    local username=$1
    local home_dir=$2
    
    # Configure SSH for Git (accept known hosts automatically for common providers)
    # This allows automated deployments without manual host key verification
    cat > "$home_dir/.ssh/config" <<'SSHCONFIG'
Host github.com
    StrictHostKeyChecking accept-new
    LogLevel ERROR

Host gitlab.com
    StrictHostKeyChecking accept-new
    LogLevel ERROR

Host bitbucket.org
    StrictHostKeyChecking accept-new
    LogLevel ERROR
SSHCONFIG
    chown "$username:$username" "$home_dir/.ssh/config"
    chmod 600 "$home_dir/.ssh/config"
    
    # Pre-add known hosts for common Git providers (prevents first-connection prompts)
    # GitHub
    if ! sudo -u "$username" ssh-keygen -F github.com >/dev/null 2>&1; then
        ssh-keyscan -t rsa github.com 2>/dev/null | sudo -u "$username" tee -a "$home_dir/.ssh/known_hosts" >/dev/null 2>&1
    fi
    # GitLab
    if ! sudo -u "$username" ssh-keygen -F gitlab.com >/dev/null 2>&1; then
        ssh-keyscan -t rsa gitlab.com 2>/dev/null | sudo -u "$username" tee -a "$home_dir/.ssh/known_hosts" >/dev/null 2>&1
    fi
    # Bitbucket
    if ! sudo -u "$username" ssh-keygen -F bitbucket.org >/dev/null 2>&1; then
        ssh-keyscan -t rsa bitbucket.org 2>/dev/null | sudo -u "$username" tee -a "$home_dir/.ssh/known_hosts" >/dev/null 2>&1
    fi
    chown "$username:$username" "$home_dir/.ssh/known_hosts" 2>/dev/null || true
    chmod 600 "$home_dir/.ssh/known_hosts" 2>/dev/null || true
}

# Helper: Configure Git to use SSH (full creation + remote URL conversion)
# Call this after cloning to convert remote URL from HTTPS to SSH
git_configure_ssh() {
    local username=$1
    local home_dir=$2
    local current_dir="$home_dir/current"
    
    # Create SSH config if not already done
    git_create_ssh_config "$username" "$home_dir"
    
    # Get current remote URL and convert HTTPS to SSH if needed
    local current_url=$(sudo -u "$username" git -C "$current_dir" config --get remote.origin.url 2>/dev/null)
    
    if [ -z "$current_url" ]; then
        return 0
    fi
    
    # If already SSH format, nothing to do
    if [[ "$current_url" =~ ^git@ ]] || [[ "$current_url" =~ ^ssh:// ]]; then
        return 0
    fi
    
    # Convert HTTPS to SSH
    if [[ "$current_url" =~ ^https:// ]]; then
        local ssh_url=$(git_url_to_ssh "$current_url")
        echo "  → Converting Git remote from HTTPS to SSH..."
        sudo -u "$username" git -C "$current_dir" remote set-url origin "$ssh_url" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "  → Git remote configured to use SSH"
        else
            echo -e "  ${YELLOW}⚠ Warning: Failed to update Git remote URL${NC}"
        fi
    fi
}

# Helper: Parse GitHub owner/repo from a git URL
# Returns owner/repo if GitHub URL, empty if not
github_parse_repo() {
    local repository=$1
    
    if [[ "$repository" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
}

# Helper: Check if a GitHub repo is private
# Returns: "private", "public", or "unknown" (if not GitHub or API error)
github_is_repo_private() {
    local repository=$1
    local owner_repo=$(github_parse_repo "$repository")
    
    # Not a GitHub URL
    if [ -z "$owner_repo" ]; then
        echo "unknown"
        return
    fi
    
    # Try unauthenticated API call
    local response=$(curl -s -w "\n%{http_code}" \
        "https://api.github.com/repos/$owner_repo" \
        -H "Accept: application/vnd.github+json")
    
    local http_code=$(echo "$response" | tail -n1)
    local body=$(echo "$response" | sed '$d')
    
    if [ "$http_code" = "200" ]; then
        local is_private=$(echo "$body" | jq -r '.private // false')
        if [ "$is_private" = "true" ]; then
            echo "private"
        else
            echo "public"
        fi
    elif [ "$http_code" = "404" ]; then
        # 404 means private repo (or doesn't exist, but we'll find out during clone)
        echo "private"
    else
        echo "unknown"
    fi
}

# Helper: GitHub Device Flow OAuth - prompts user to authorize and returns access token
# Usage: local token=$(github_device_flow_auth "scope")
# Returns: access token on success, empty on failure
# Note: Caller should check if result is empty and handle accordingly
github_device_flow_auth() {
    local scope=$1
    
    # Get GitHub Client ID from config
    local github_client_id=$(get_config "github_client_id")
    
    if [ -z "$github_client_id" ]; then
        echo ""
        return 1
    fi
    
    # Step 1: Request device code
    local device_response=$(curl -s -X POST \
        "https://github.com/login/device/code" \
        -H "Accept: application/json" \
        -d "client_id=$github_client_id&scope=$scope")
    
    local device_code=$(echo "$device_response" | jq -r '.device_code // empty')
    local user_code=$(echo "$device_response" | jq -r '.user_code // empty')
    local verification_uri=$(echo "$device_response" | jq -r '.verification_uri // empty')
    local interval=$(echo "$device_response" | jq -r '.interval // 5')
    local expires_in=$(echo "$device_response" | jq -r '.expires_in // 900')
    
    if [ -z "$device_code" ] || [ "$device_code" = "null" ]; then
        echo "" >&2
        return 1
    fi
    
    # Step 2: Prompt user to authorize (output to stderr so it doesn't interfere with token return)
    echo "" >&2
    echo "─────────────────────────────────────" >&2
    echo -e "${YELLOW}${BOLD}GitHub Authorization Required${NC}" >&2
    echo "" >&2
    echo -e "  1. Open: ${CYAN}${BOLD}$verification_uri${NC}" >&2
    echo -e "  2. Enter code: ${GREEN}${BOLD}$user_code${NC}" >&2
    echo "" >&2
    echo "Waiting for authorization..." >&2
    echo "─────────────────────────────────────" >&2
    
    # Step 3: Poll for authorization
    local access_token=""
    local elapsed=0
    local poll_count=0
    
    while [ $elapsed -lt $expires_in ]; do
        sleep "$interval"
        elapsed=$((elapsed + interval))
        poll_count=$((poll_count + 1))
        
        # Show progress every 5 polls
        if [ $((poll_count % 5)) -eq 0 ]; then
            printf "." >&2
        fi
        
        local token_response=$(curl -s -X POST \
            "https://github.com/login/oauth/access_token" \
            -H "Accept: application/json" \
            -d "client_id=$github_client_id&device_code=$device_code&grant_type=urn:ietf:params:oauth:grant-type:device_code")
        
        local error=$(echo "$token_response" | jq -r '.error // empty')
        
        if [ "$error" = "authorization_pending" ]; then
            continue
        elif [ "$error" = "slow_down" ]; then
            interval=$((interval + 5))
            continue
        elif [ -n "$error" ] && [ "$error" != "null" ]; then
            echo "" >&2
            echo -e "${RED}Error: Authorization failed - $error${NC}" >&2
            echo ""
            return 1
        fi
        
        access_token=$(echo "$token_response" | jq -r '.access_token // empty')
        if [ -n "$access_token" ] && [ "$access_token" != "null" ]; then
            break
        fi
    done
    
    if [ -z "$access_token" ] || [ "$access_token" = "null" ]; then
        echo "" >&2
        echo -e "${RED}Error: Authorization timed out${NC}" >&2
        echo ""
        return 1
    fi
    
    echo "" >&2
    echo -e "${GREEN}✓ Authorized!${NC}" >&2
    
    # Return the token (to stdout)
    echo "$access_token"
}

# Helper: Add deploy key to GitHub repo
# Usage: github_add_deploy_key "access_token" "owner/repo" "key_title" "public_key"
github_add_deploy_key() {
    local access_token=$1
    local owner_repo=$2
    local key_title=$3
    local public_key=$4
    
    echo -e "  ${CYAN}Adding deploy key to $owner_repo...${NC}"
    
    local key_response=$(curl -s -X POST \
        "https://api.github.com/repos/$owner_repo/keys" \
        -H "Authorization: Bearer $access_token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "{
            \"title\": \"$key_title\",
            \"key\": \"$public_key\",
            \"read_only\": true
        }")
    
    local key_id=$(echo "$key_response" | jq -r '.id // empty')
    local error_msg=$(echo "$key_response" | jq -r '.message // empty')
    
    if [ -z "$key_id" ] || [ "$key_id" = "null" ]; then
        # Check if key already exists (common error)
        if [[ "$error_msg" == *"key is already in use"* ]]; then
            echo -e "  ${GREEN}✓ Deploy key already exists on repository${NC}"
            return 0
        fi
        echo -e "  ${RED}Error: Failed to add deploy key: $error_msg${NC}"
        return 1
    fi
    
    echo -e "  ${GREEN}✓ Deploy key added successfully (ID: $key_id)${NC}"
    echo ""
    return 0
}

# Helper: Delete deploy key from GitHub repo
# Usage: github_delete_deploy_key "access_token" "owner/repo" "key_title"
# Returns: 0 on success, 1 on failure
github_delete_deploy_key() {
    local access_token=$1
    local owner_repo=$2
    local key_title=$3
    
    # List all deploy keys for the repo
    local keys_response=$(curl -s -X GET \
        "https://api.github.com/repos/$owner_repo/keys" \
        -H "Authorization: Bearer $access_token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28")
    
    # Find key ID by matching title
    local key_id=$(echo "$keys_response" | jq -r ".[] | select(.title == \"$key_title\") | .id")
    
    if [ -z "$key_id" ] || [ "$key_id" = "null" ]; then
        echo -e "  ${YELLOW}No deploy key found matching title: $key_title${NC}"
        return 0
    fi
    
    # Delete the deploy key
    local delete_response=$(curl -s -X DELETE \
        "https://api.github.com/repos/$owner_repo/keys/$key_id" \
        -H "Authorization: Bearer $access_token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -w "%{http_code}" \
        -o /dev/null)
    
    if [ "$delete_response" = "204" ]; then
        echo -e "  ${GREEN}✓ Deploy key deleted successfully${NC}"
        return 0
    else
        echo -e "  ${RED}Error: Failed to delete deploy key (HTTP $delete_response)${NC}"
        return 1
    fi
}

# Helper: Create GitHub webhook
# Usage: github_create_webhook "access_token" "owner/repo" "webhook_url" "webhook_secret"
# Returns: 0 on success, 1 on failure
github_create_webhook() {
    local access_token=$1
    local owner_repo=$2
    local webhook_url=$3
    local webhook_secret=$4
    
    if [ -z "$access_token" ] || [ -z "$owner_repo" ] || [ -z "$webhook_url" ] || [ -z "$webhook_secret" ]; then
        echo -e "${RED}Error: Missing required parameters for webhook creation${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Creating webhook on GitHub...${NC}"
    
    local webhook_response=$(curl -s -X POST \
        "https://api.github.com/repos/$owner_repo/hooks" \
        -H "Authorization: Bearer $access_token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d "{
            \"name\": \"web\",
            \"active\": true,
            \"events\": [\"push\"],
            \"config\": {
                \"url\": \"$webhook_url\",
                \"content_type\": \"json\",
                \"secret\": \"$webhook_secret\",
                \"insecure_ssl\": \"0\"
            }
        }")
    
    local webhook_id=$(echo "$webhook_response" | jq -r '.id // empty')
    local error_msg=$(echo "$webhook_response" | jq -r '.message // empty')
    
    if [ -z "$webhook_id" ] || [ "$webhook_id" = "null" ]; then
        # Check for common errors
        if [[ "$error_msg" == *"Hook already exists"* ]]; then
            echo -e "${GREEN}✓ Webhook already exists on repository${NC}"
            return 0
        fi
        if [ -n "$error_msg" ] && [ "$error_msg" != "null" ]; then
            echo -e "${RED}Error: Failed to create webhook: $error_msg${NC}"
        else
            echo -e "${RED}Error: Failed to create webhook${NC}"
        fi
        return 1
    fi
    
    echo ""
    echo -e "${GREEN}${BOLD}✓ Webhook created successfully!${NC}"
    echo "─────────────────────────────────────"
    echo -e "Webhook ID: ${CYAN}$webhook_id${NC}"
    echo -e "URL:        ${CYAN}$webhook_url${NC}"
    echo ""
    echo -e "${GREEN}Pushes to $owner_repo will now auto-deploy!${NC}"
    return 0
}

# Helper: Delete GitHub webhook by finding it via URL
# Usage: github_delete_webhook "access_token" "owner/repo" "webhook_url"
# Returns: 0 on success, 1 on failure
github_delete_webhook() {
    local access_token=$1
    local owner_repo=$2
    local webhook_url=$3
    
    if [ -z "$access_token" ] || [ -z "$owner_repo" ] || [ -z "$webhook_url" ]; then
        echo -e "${RED}Error: Missing required parameters for webhook deletion${NC}"
        return 1
    fi
    
    echo -e "${CYAN}Finding webhook on GitHub...${NC}"
    
    # List all webhooks for the repo
    local hooks_response=$(curl -s -X GET \
        "https://api.github.com/repos/$owner_repo/hooks" \
        -H "Authorization: Bearer $access_token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28")
    
    # Find webhook ID by matching URL
    local webhook_id=$(echo "$hooks_response" | jq -r ".[] | select(.config.url == \"$webhook_url\") | .id")
    
    if [ -z "$webhook_id" ] || [ "$webhook_id" = "null" ]; then
        echo -e "${YELLOW}No webhook found matching URL: $webhook_url${NC}"
        return 0
    fi
    
    echo -e "${CYAN}Deleting webhook ID: $webhook_id...${NC}"
    
    # Delete the webhook
    local delete_response=$(curl -s -X DELETE \
        "https://api.github.com/repos/$owner_repo/hooks/$webhook_id" \
        -H "Authorization: Bearer $access_token" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -w "%{http_code}" \
        -o /dev/null)
    
    if [ "$delete_response" = "204" ]; then
        echo -e "${GREEN}✓ Webhook deleted successfully${NC}"
        return 0
    else
        echo -e "${RED}Error: Failed to delete webhook (HTTP $delete_response)${NC}"
        return 1
    fi
}
