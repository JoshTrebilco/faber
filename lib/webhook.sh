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

# Store webhook secret for an app (wrapper for storage function)
store_webhook_secret() {
    local username=$1
    local secret=$2
    set_webhook "$username" "$secret"
}

# Delete webhook secret for an app (wrapper for storage function)
delete_webhook_secret() {
    local username=$1
    delete_webhook "$username"
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
    store_webhook_secret "$username" "$new_secret"
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

