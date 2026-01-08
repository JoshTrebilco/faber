#!/bin/bash

#############################################
# Webhook Management Functions
#############################################

WEBHOOK_HANDLER="/opt/cipi/webhook.php"
WEBHOOK_LOG="/var/log/cipi/webhook.log"

# Generate webhook secret for an app
generate_webhook_secret() {
    openssl rand -hex 32
}

# Regenerate webhook secret for an app
webhook_regenerate_secret() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: cipi webhook regenerate <username>"
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
        echo -e "Run: ${CYAN}cipi webhook regenerate $username${NC}"
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
        echo "Usage: cipi webhook delete <username> [repository]"
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
    local owner_repo=$(extract_github_owner_repo "$repository")
    
    if [ -z "$owner_repo" ]; then
        echo -e "${RED}Error: Could not extract owner/repo from: $repository${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Deleting webhook for ${BOLD}$owner_repo${NC}"
    echo ""
    
    # Get access token via device flow
    local access_token=$(github_device_flow "admin:repo_hook")
    
    if [ -z "$access_token" ]; then
        echo -e "${RED}Error: Failed to get GitHub access token${NC}"
        exit 1
    fi
    
    # Delete the webhook
    github_delete_webhook "$owner_repo" "$access_token" "$webhook_url"
    
    echo ""
}

# Automatically setup webhook on GitHub using Device Flow
webhook_setup() {
    local username=$1
    local repository=$2  # Optional: can be passed to avoid requiring app JSON
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: cipi webhook setup <username> [repository]"
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
    
    # Use shared function from git.sh to setup the webhook
    if ! github_setup_webhook "$repository" "$webhook_url" "$webhook_secret"; then
        echo "Please try again: ${CYAN}cipi webhook setup $username${NC}"
        exit 1
    fi
    
    echo ""
}

