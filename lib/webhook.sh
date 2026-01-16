#!/bin/bash

#############################################
# Webhook Management Functions
#############################################

WEBHOOK_HANDLER="/opt/faber/web/webhook.php"
WEBHOOK_LOG="/var/log/faber/webhook.log"

# Generate webhook secret for an app
generate_webhook_secret() {
    openssl rand -hex 32
}

# Regenerate webhook secret for an app
webhook_regenerate_secret() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber webhook regenerate <username>"
        exit 1
    fi
    
    check_app_exists "$username"
    
    echo -e "${YELLOW}${BOLD}Warning: This will invalidate the current webhook secret!${NC}"
    read -p "Type the username to confirm: " confirm
    
    if [ "$confirm" != "$username" ]; then
        echo "Regeneration cancelled."
        exit 0
    fi
    
    echo ""
    echo -e "${CYAN}Regenerating webhook secret...${NC}"
    
    local new_secret=$(generate_webhook_secret)
    set_webhook "$username" "$new_secret"
    echo ""
    echo -e "${GREEN}${BOLD}Webhook secret regenerated!${NC}"
    echo "─────────────────────────────────────"
    echo -e "New webhook secret: ${CYAN}$new_secret${NC}"
    echo ""
}

# Show webhook information for an app
webhook_show() {
    local username=$1
    local webhook_domain=$(get_config "webhook_domain")
    local secret=$(get_webhook_secret "$username")
    
    if [ -z "$secret" ]; then
        echo -e "${YELLOW}No webhook secret configured for this app.${NC}"
        echo -e "Run: ${CYAN}faber webhook regenerate $username${NC}"
        return
    fi
    
    echo ""
    echo -e "${BOLD}GitHub Webhook Configuration:${NC}"
    echo "─────────────────────────────────────"
    if [ -n "$webhook_domain" ]; then
        echo -e "Payload URL:   ${CYAN}https://$webhook_domain/webhook/$username${NC}"
    else
        echo -e "${YELLOW}Warning: Webhook domain not configured${NC}"
        echo -e "Payload URL:   ${CYAN}(webhook domain required)${NC}"
    fi
    echo -e "Content type:  ${CYAN}application/json${NC}"
    echo -e "Secret:        ${CYAN}$secret${NC}"
    echo -e "Events:        ${CYAN}Just the push event${NC}"
    echo ""
}

# Webhook logs
webhook_logs() {
    tail -f "$WEBHOOK_LOG"
}

# Delete webhook from GitHub
webhook_delete() {
    local username=$1
    local repository=$2  # Optional: can be passed to avoid requiring app JSON
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber webhook delete <username> [repository]"
        exit 1
    fi
    
    # Only check app exists if repository not provided (standalone call)
    if [ -z "$repository" ]; then
        check_app_exists "$username"
        repository=$(get_app_field "$username" "repository")
        
        if [ -z "$repository" ]; then
            echo -e "${RED}Error: Repository not found for app '$username'${NC}"
            exit 1
        fi
    fi
    
    # Get webhook configuration
    local webhook_domain=$(get_config "webhook_domain")
    
    if [ -z "$webhook_domain" ]; then
        echo -e "${RED}Error: Webhook domain not configured${NC}"
        exit 1
    fi
    
    local webhook_url="https://$webhook_domain/webhook/$username"
    
    # Extract owner/repo from repository URL
    local owner_repo=$(github_parse_repo "$repository")
    
    if [ -z "$owner_repo" ]; then
        echo -e "${RED}Error: Could not extract owner/repo from: $repository${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Deleting webhook for ${BOLD}$owner_repo${NC}"
    echo ""
    
    # Get access token via GitHub App
    local access_token=$(github_app_get_token "$owner_repo")
    
    if [ -z "$access_token" ]; then
        echo -e "${RED}Error: Failed to get GitHub access token${NC}"
        exit 1
    fi
    
    # Delete the webhook from GitHub
    github_delete_webhook "$access_token" "$owner_repo" "$webhook_url"
    
    # Clear token
    unset access_token
    
    # Delete the webhook secret from local storage
    delete_webhook "$username"
    
    echo ""
}

# Automatically create webhook on GitHub using Device Flow
webhook_create() {
    local username=$1
    local repository=$2  # Optional: can be passed to avoid requiring app JSON
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber webhook create <username> [repository]"
        exit 1
    fi
    
    # Only check app exists if repository not provided (standalone call)
    if [ -z "$repository" ]; then
        check_app_exists "$username"
        # Get repository info from app JSON
        repository=$(get_app_field "$username" "repository")
        
        if [ -z "$repository" ]; then
            echo -e "${RED}Error: Repository not found for app '$username'${NC}"
            exit 1
        fi
    fi
    
    # Get webhook configuration
    local webhook_domain=$(get_config "webhook_domain")
    
    if [ -z "$webhook_domain" ]; then
        echo -e "${RED}Error: Webhook domain not configured${NC}"
        echo "Please configure the webhook domain first."
        exit 1
    fi
    
    # Get or generate webhook secret
    local webhook_secret=$(get_webhook_secret "$username")
    
    if [ -z "$webhook_secret" ]; then
        echo -e "${YELLOW}No webhook secret found, generating one...${NC}"
        webhook_secret=$(generate_webhook_secret)
        set_webhook "$username" "$webhook_secret"
    fi
    
    local webhook_url="https://$webhook_domain/webhook/$username"
    
    # Parse repository URL
    local owner_repo=$(github_parse_repo "$repository")
    
    if [ -z "$owner_repo" ]; then
        echo -e "${RED}Error: Could not parse GitHub repository from: $repository${NC}"
        echo "Repository must be a GitHub URL (e.g., https://github.com/owner/repo or git@github.com:owner/repo.git)"
        exit 1
    fi
    
    echo ""
    echo -e "${CYAN}Creating GitHub webhook for ${BOLD}$owner_repo${NC}"
    
    # Get access token via GitHub App
    local access_token=$(github_app_get_token "$owner_repo")
    
    if [ -z "$access_token" ]; then
        echo -e "${RED}Error: Failed to authenticate with GitHub${NC}"
        exit 1
    fi
    
    # Create the webhook
    if ! github_create_webhook "$access_token" "$owner_repo" "$webhook_url" "$webhook_secret"; then
        echo "Please try again: ${CYAN}faber webhook create $username${NC}"
        unset access_token
        exit 1
    fi
    
    # Clear token
    unset access_token
    
    echo ""
}

