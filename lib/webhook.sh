#!/bin/bash

#############################################
# Webhook Management Functions
#############################################

WEBHOOKS_FILE="${CIPI_DATA_DIR}/webhooks.json"
WEBHOOK_HANDLER="/opt/cipi/webhook.php"
WEBHOOK_LOG="/var/log/cipi/webhook.log"

# Generate webhook secret for an app
generate_webhook_secret() {
    openssl rand -hex 32
}

# Store webhook secret for an app
store_webhook_secret() {
    local username=$1
    local secret=$2
    
    init_storage
    
    local tmp=$(mktemp)
    jq --arg user "$username" --arg secret "$secret" \
        '.[$user] = {"secret": $secret, "created_at": (now | todate)}' \
        "$WEBHOOKS_FILE" > "$tmp"
    mv "$tmp" "$WEBHOOKS_FILE"
    chmod 600 "$WEBHOOKS_FILE"
    chown root:root "$WEBHOOKS_FILE"
}

# Get webhook secret for an app
get_webhook_secret() {
    local username=$1
    
    if [ -f "$WEBHOOKS_FILE" ]; then
        jq -r --arg user "$username" '.[$user].secret // empty' "$WEBHOOKS_FILE"
    fi
}

# Delete webhook secret for an app
delete_webhook_secret() {
    local username=$1
    
    if [ -f "$WEBHOOKS_FILE" ]; then
        local tmp=$(mktemp)
        jq --arg user "$username" 'del(.[$user])' "$WEBHOOKS_FILE" > "$tmp"
        mv "$tmp" "$WEBHOOKS_FILE"
        chmod 600 "$WEBHOOKS_FILE"
        chown root:root "$WEBHOOKS_FILE"
    fi
}

# Regenerate webhook secret for an app
webhook_regenerate_secret() {
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: cipi webhook regenerate <username>"
        exit 1
    fi
    
    init_storage
    
    if ! json_has_key "${APPS_FILE}" "$username"; then
        echo -e "${RED}Error: App '$username' not found${NC}"
        exit 1
    fi
    
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
    local server_ip=$(get_server_ip)
    local secret=$(get_webhook_secret "$username")
    
    if [ -z "$secret" ]; then
        echo -e "${YELLOW}No webhook secret configured for this app.${NC}"
        echo -e "Run: ${CYAN}cipi webhook regenerate $username${NC}"
        return
    fi
    
    echo ""
    echo -e "${BOLD}GitHub Webhook Configuration:${NC}"
    echo "─────────────────────────────────────"
    echo -e "Payload URL:   ${CYAN}http://$server_ip/webhook/$username${NC}"
    echo -e "Content type:  ${CYAN}application/json${NC}"
    echo -e "Secret:        ${CYAN}$secret${NC}"
    echo -e "Events:        ${CYAN}Just the push event${NC}"
    echo ""
}

# Webhook logs
webhook_logs() {
    tail -f "$WEBHOOK_LOG"
}

