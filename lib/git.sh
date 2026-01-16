#!/bin/bash

#############################################
# Git Helper Functions
#############################################

# Helper: Parse GitHub owner/repo from a git URL
# Returns owner/repo if GitHub URL, empty if not
github_parse_repo() {
    local repository=$1
    
    if [[ "$repository" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    fi
}

# Validate that a repository URL is HTTPS format
# Returns: 0 if valid HTTPS, 1 if SSH or invalid
github_validate_https_url() {
    local url=$1

    if [[ "$url" =~ ^https://github\.com/ ]]; then
        return 0
    fi

    if [[ "$url" =~ ^git@ ]] || [[ "$url" =~ ^ssh:// ]]; then
        echo -e "${RED}Error: SSH URLs are not supported${NC}"
        echo ""
        echo "Please use HTTPS format:"
        echo -e "  ${CYAN}https://github.com/owner/repo.git${NC}"
        echo ""
        echo "Instead of:"
        echo -e "  ${YELLOW}git@github.com:owner/repo.git${NC}"
        return 1
    fi

    echo -e "${RED}Error: Invalid repository URL${NC}"
    echo "Please use HTTPS format: https://github.com/owner/repo.git"
    return 1
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

#############################################
# GitHub App Authentication Functions
#############################################

# Generate JWT for GitHub App authentication
# Requires: openssl
# Returns: JWT string on stdout, empty on failure
github_app_generate_jwt() {
    local app_id=$(get_github_config "github_app_id")
    local private_key=$(get_github_config "github_app_private_key")

    if [ -z "$app_id" ] || [ -z "$private_key" ]; then
        return 1
    fi

    # JWT header and payload
    local header='{"alg":"RS256","typ":"JWT"}'
    local now=$(date +%s)
    local iat=$((now - 60))  # 1 min in past for clock skew
    local exp=$((now + 600))  # 10 min max
    local payload="{\"iat\":$iat,\"exp\":$exp,\"iss\":\"$app_id\"}"

    # Base64url encode (replace + with -, / with _, remove =)
    local header_b64=$(echo -n "$header" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')
    local payload_b64=$(echo -n "$payload" | openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

    # Sign with RS256
    local signature=$(echo -n "${header_b64}.${payload_b64}" | \
        openssl dgst -sha256 -sign <(echo "$private_key") | \
        openssl base64 -e -A | tr '+/' '-_' | tr -d '=')

    echo "${header_b64}.${payload_b64}.${signature}"
}

# Get installation access token for a specific repo
# Usage: github_app_get_token "owner/repo"
# Returns: access_token on stdout, empty on failure
github_app_get_token() {
    local owner_repo=$1
    local jwt=$(github_app_generate_jwt)

    if [ -z "$jwt" ]; then
        echo -e "${RED}Error: Failed to generate JWT${NC}" >&2
        return 1
    fi

    # Get installation ID for this repo
    local install_response=$(curl -s \
        "https://api.github.com/repos/$owner_repo/installation" \
        -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json")

    local installation_id=$(echo "$install_response" | jq -r '.id // empty')

    if [ -z "$installation_id" ]; then
        echo -e "${RED}Error: GitHub App not installed on $owner_repo${NC}" >&2
        return 1
    fi

    # Get installation access token
    local token_response=$(curl -s -X POST \
        "https://api.github.com/app/installations/$installation_id/access_tokens" \
        -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json")

    local token=$(echo "$token_response" | jq -r '.token // empty')

    if [ -z "$token" ]; then
        echo -e "${RED}Error: Failed to get installation token${NC}" >&2
        return 1
    fi

    echo "$token"
}

# Check if GitHub App is installed on a repository
# Returns: 0 if installed, 1 if not installed or error
github_app_check_installation() {
    local owner_repo=$1
    local jwt=$(github_app_generate_jwt)

    if [ -z "$jwt" ]; then
        return 1
    fi

    local response=$(curl -s -w "%{http_code}" -o /dev/null \
        "https://api.github.com/repos/$owner_repo/installation" \
        -H "Authorization: Bearer $jwt" \
        -H "Accept: application/vnd.github+json")

    [ "$response" = "200" ]
}

# Check if GitHub App is configured
github_app_is_configured() {
    local app_id=$(get_github_config "github_app_id")
    local private_key=$(get_github_config "github_app_private_key")
    [ -n "$app_id" ] && [ -n "$private_key" ]
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
