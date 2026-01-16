#!/bin/bash

#############################################
# Storage Functions - JSON Data Management
#############################################

STORAGE_DIR="${FABER_DATA_DIR}"
APPS_FILE="${STORAGE_DIR}/apps.json"
DOMAINS_FILE="${STORAGE_DIR}/domains.json"
DATABASES_FILE="${STORAGE_DIR}/databases.json"
CONFIG_FILE="${STORAGE_DIR}/config.json"
WEBHOOKS_FILE="${STORAGE_DIR}/webhooks.json"
VERSION_FILE="${STORAGE_DIR}/version.json"
REVERB_FILE="${STORAGE_DIR}/reverb.json"
GITHUB_FILE="${STORAGE_DIR}/github.json"

# Initialize storage
init_storage() {
    mkdir -p "${STORAGE_DIR}"
    # Allow www-data to traverse for webhook handler
    chmod 751 "${STORAGE_DIR}" 
    
    # Files readable by www-data for webhook handler
    for file in "${APPS_FILE}" "${DOMAINS_FILE}" "${VERSION_FILE}"; do
        if [ ! -f "$file" ]; then
            echo "{}" > "$file"
        fi
        chmod 640 "$file"
        chown root:www-data "$file"
    done
    
    # Webhooks file needs www-data read access for signature validation
    if [ ! -f "${WEBHOOKS_FILE}" ]; then
        echo "{}" > "${WEBHOOKS_FILE}"
    fi
    chmod 640 "${WEBHOOKS_FILE}"
    chown root:www-data "${WEBHOOKS_FILE}"
    
    # GitHub App config needs www-data read access for deploy scripts
    if [ ! -f "${GITHUB_FILE}" ]; then
        echo "{}" > "${GITHUB_FILE}"
    fi
    chmod 640 "${GITHUB_FILE}"
    chown root:www-data "${GITHUB_FILE}"
    
    # Sensitive files - keep restricted (passwords, secrets)
    for file in "${DATABASES_FILE}" "${CONFIG_FILE}"; do
        if [ ! -f "$file" ]; then
            echo "{}" > "$file"
        fi
        chmod 600 "$file"
    done
}

# Read JSON file
json_read() {
    local file=$1
    cat "$file" 2>/dev/null || echo "{}"
}

# Write JSON file
json_write() {
    local file=$1
    local content=$2
    echo "$content" | jq '.' > "$file"
    chmod 600 "$file"
}

# Get value from JSON
json_get() {
    local file=$1
    local key=$2
    jq -r ".[\"$key\"]" "$file" 2>/dev/null
}

# Set value in JSON
json_set() {
    local file=$1
    local key=$2
    local value=$3
    local tmp=$(mktemp)
    
    jq ".[\"$key\"] = $value" "$file" > "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
}

# Delete key from JSON
json_delete() {
    local file=$1
    local key=$2
    local tmp=$(mktemp)
    
    jq "del(.[\"$key\"])" "$file" > "$tmp"
    mv "$tmp" "$file"
    chmod 600 "$file"
}

# Get all keys from JSON
json_keys() {
    local file=$1
    jq -r 'keys[]' "$file" 2>/dev/null
}

# Check if key exists
json_has_key() {
    local file=$1
    local key=$2
    jq -e ".[\"$key\"]" "$file" >/dev/null 2>&1
}

# Get config value
get_config() {
    local key=$1
    local default=$2
    local value=$(json_get "${CONFIG_FILE}" "$key")
    
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo "$default"
    else
        echo "$value"
    fi
}

# Set config value
set_config() {
    local key=$1
    local value=$2
    json_set "${CONFIG_FILE}" "$key" "\"$value\""
}

#############################################
# GitHub App Config Helpers
#############################################

# Get GitHub App config value
get_github_config() {
    local key=$1
    local value=$(json_get "${GITHUB_FILE}" "$key")
    
    if [ "$value" = "null" ] || [ -z "$value" ]; then
        echo ""
    else
        echo "$value"
    fi
}

# Set GitHub App config value
set_github_config() {
    local key=$1
    local value=$2
    json_set "${GITHUB_FILE}" "$key" "\"$value\""
    # Ensure permissions are maintained
    chmod 640 "${GITHUB_FILE}"
    chown root:www-data "${GITHUB_FILE}"
}

#############################################
# Stack Helpers
#############################################

# Generate unique username
generate_username() {
    while true; do
        username="u$(shuf -i 100000-999999 -n 1)"
        if ! json_has_key "${APPS_FILE}" "$username"; then
            echo "$username"
            break
        fi
    done
}

# Generate secure password
# Only includes characters that are safe everywhere:
# - Alphanumeric: A-Z, a-z, 0-9
# - Safe special chars: @ % + - _ = (no shell/sed/env conflicts)
#
# Excluded problematic characters:
# - # $ " ' ` \ (shell/env special chars)
# - | / (sed delimiters)
# - & ; < > (shell operators)
# - ( ) [ ] { } (shell grouping/expansion)
# - * ? ! ~ ^ : (shell wildcards/expansion)
# - spaces and whitespace
generate_password() {
    local length=${1:-24}
    tr -dc 'A-Za-z0-9@%+_=-' < /dev/urandom | head -c "$length"
}

#############################################
# App Helpers
#############################################

# Get app data
get_app() {
    local username=$1
    json_get "${APPS_FILE}" "$username"
}

# Get specific field from app
get_app_field() {
    local username=$1
    local field=$2
    local app=$(get_app "$username")
    if [ -n "$app" ] && [ "$app" != "null" ]; then
        echo "$app" | jq -r ".$field // empty"
    fi
}

# Set specific field in app
set_app_field() {
    local username=$1
    local field=$2
    local value=$3
    local app=$(get_app "$username")
    if [ -n "$app" ] && [ "$app" != "null" ]; then
        local tmp=$(mktemp)
        echo "$app" | jq ".$field = \"$value\"" > "$tmp"
        local updated_app=$(cat "$tmp")
        rm "$tmp"
        json_set "${APPS_FILE}" "$username" "$updated_app"
    fi
}

# Check if app exists, exit with error if not
check_app_exists() {
    local username=$1
    if ! json_has_key "${APPS_FILE}" "$username"; then
        echo -e "${RED}Error: App '$username' not found${NC}"
        exit 1
    fi
}

#############################################
# Domain Helpers
#############################################

# Get domain data
get_domain() {
    local domain=$1
    json_get "${DOMAINS_FILE}" "$domain"
}

# Check if domain exists
domain_exists() {
    local domain=$1
    local domains=$(json_read "${DOMAINS_FILE}")
    
    # Check if it's a primary domain
    if echo "$domains" | jq -e ".[\"$domain\"]" >/dev/null 2>&1; then
        return 0
    fi
    
    return 1
}

# Get specific field from domain
get_domain_field() {
    local domain=$1
    local field=$2
    local data=$(get_domain "$domain")
    if [ -n "$data" ] && [ "$data" != "null" ]; then
        echo "$data" | jq -r ".$field // empty"
    fi
}

# Get app by domain
get_app_by_domain() {
    local domain=$1
    get_domain_field "$domain" "app"
}

# Get domain by app
get_domain_by_app() {
    local username=$1
    local domains=$(json_keys "${DOMAINS_FILE}")
    
    for domain in $domains; do
        local app=$(get_domain_field "$domain" "app")
        if [ "$app" = "$username" ]; then
            echo "$domain"
            return 0
        fi
    done
    
    return 1
}

#############################################
# Database Helpers
#############################################

# Get database data
get_db() {
    local dbname=$1
    json_get "${DATABASES_FILE}" "$dbname"
}

# Get specific field from database
get_db_field() {
    local dbname=$1
    local field=$2
    local data=$(get_db "$dbname")
    if [ -n "$data" ] && [ "$data" != "null" ]; then
        echo "$data" | jq -r ".$field // empty"
    fi
}

# Generate database name
generate_dbname() {
    while true; do
        dbname="db$(shuf -i 100000-999999 -n 1)"
        if ! json_has_key "${DATABASES_FILE}" "$dbname"; then
            echo "$dbname"
            break
        fi
    done
}

# Generate database username
generate_db_username() {
    echo "db$(shuf -i 100000-999999 -n 1)"
}

#############################################
# Webhook Helpers
#############################################

# Get webhook secret for user
get_webhook_secret() {
    local username=$1
    local data=$(json_get "${WEBHOOKS_FILE}" "$username")
    if [ -n "$data" ] && [ "$data" != "null" ]; then
        echo "$data" | jq -r '.secret // empty'
    fi
}

# Set webhook for user
set_webhook() {
    local username=$1
    local secret=$2
    local webhook_data="{\"secret\": \"$secret\", \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    json_set "${WEBHOOKS_FILE}" "$username" "$webhook_data"
}

# Delete webhook for user
delete_webhook() {
    local username=$1
    json_delete "${WEBHOOKS_FILE}" "$username"
}

#############################################
# Version Helpers
#############################################

# Get current version commit
get_version_commit() {
    local value=$(json_get "${VERSION_FILE}" "commit")
    if [ "$value" != "null" ]; then
        echo "$value"
    fi
}

# Set version info
set_version() {
    local commit=$1
    local branch=$2
    local version_data="{\"commit\": \"$commit\", \"branch\": \"$branch\", \"installed_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}"
    json_write "${VERSION_FILE}" "$version_data"
}

#############################################
# Reverb Helpers
#############################################

# Check if Reverb is configured
reverb_is_configured() {
    [ -f "${REVERB_FILE}" ] && [ "$(get_reverb_field 'app')" != "" ]
}

# Get Reverb field
get_reverb_field() {
    local field=$1
    if [ -f "${REVERB_FILE}" ]; then
        jq -r ".$field // empty" "${REVERB_FILE}" 2>/dev/null
    fi
}

# Save all Reverb config at once
save_reverb_config() {
    local app=$1
    local domain=$2
    local app_id=$3
    local app_key=$4
    local app_secret=$5
    
    cat > "${REVERB_FILE}" <<EOF
{
    "app": "$app",
    "domain": "$domain",
    "app_id": "$app_id",
    "app_key": "$app_key",
    "app_secret": "$app_secret",
    "created_at": "$(date -Iseconds)"
}
EOF
    chmod 600 "${REVERB_FILE}"
}
