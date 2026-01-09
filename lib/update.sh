#!/bin/bash

#############################################
# Auto-Update Functions
#############################################

GITHUB_REPO="JoshTrebilco/cipi"
GITHUB_API="https://api.github.com/repos/${GITHUB_REPO}"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_REPO}"
BRANCH="latest"

# Get latest commit from GitHub branch
get_latest_commit() {
    curl -s "${GITHUB_API}/branches/${BRANCH}" | jq -r '.commit.sha' 2>/dev/null
}

# Count commits behind latest
count_commits_behind() {
    local current_commit=$1
    local latest_commit=$2
    
    if [ -z "$current_commit" ] || [ "$current_commit" = "null" ] || [ -z "$latest_commit" ]; then
        echo "unknown"
        return
    fi
    
    # If commits are the same, return 0
    if [ "$current_commit" = "$latest_commit" ]; then
        echo "0"
        return
    fi
    
    # Use GitHub compare API to count commits
    # Format: base...head compares base to head, ahead_by tells us how many commits head is ahead of base
    local compare_result=$(curl -s "${GITHUB_API}/compare/${current_commit}...${latest_commit}" 2>/dev/null)
    local ahead=$(echo "$compare_result" | jq -r '.ahead_by // 0' 2>/dev/null)
    
    if [ "$ahead" = "null" ] || [ -z "$ahead" ]; then
        echo "unknown"
    else
        echo "$ahead"
    fi
}

# Update Cipi
update_cipi() {
    local force=false
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --force|-f)
                force=true
                ;;
        esac
    done
    
    echo -e "${BOLD}Cipi Update${NC}"
    echo "─────────────────────────────────────"
    echo ""
    
    echo -e "${CYAN}Checking for updates...${NC}"
    local latest_commit=$(get_latest_commit)
    
    if [ -z "$latest_commit" ] || [ "$latest_commit" = "null" ]; then
        echo -e "${RED}Error: Could not fetch latest commit${NC}"
        exit 1
    fi
    
    local current_commit=$(get_version_commit)
    
    # Display current status
    if [ -n "$current_commit" ] && [ "$current_commit" != "null" ]; then
        local commits_behind=$(count_commits_behind "$current_commit" "$latest_commit")
        echo -e "Current commit: ${CYAN}${current_commit:0:7}${NC}"
        if [ "$commits_behind" != "unknown" ] && [ "$commits_behind" != "0" ]; then
            echo -e "Commits behind: ${YELLOW}${commits_behind}${NC}"
        fi
    else
        echo -e "Current commit: ${YELLOW}Unknown${NC}"
    fi
    
    echo -e "Latest commit:  ${GREEN}${latest_commit:0:7}${NC}"
    echo ""
    
    # Check if update is needed (skip if --force)
    if [ "$force" = false ] && [ -n "$current_commit" ] && [ "$current_commit" != "null" ] && [ "$current_commit" = "$latest_commit" ]; then
        echo -e "${GREEN}Cipi is already up to date!${NC}"
        echo -e "${YELLOW}Tip:${NC} Use ${CYAN}--force${NC} to reinstall the current version"
        exit 0
    fi
    
    if [ "$force" = true ]; then
        echo -e "${YELLOW}Force reinstalling...${NC}"
    else
        local commits_behind=$(count_commits_behind "$current_commit" "$latest_commit")
        if [ "$commits_behind" != "unknown" ] && [ "$commits_behind" != "0" ]; then
            echo -e "${YELLOW}A new version is available! (${commits_behind} commit(s) behind)${NC}"
        else
            echo -e "${YELLOW}A new version is available!${NC}"
        fi
        
        read -p "Do you want to update? (y/N): " confirm
        
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Update cancelled."
            exit 0
        fi
    fi
    
    echo ""
    echo -e "${CYAN}Updating Cipi...${NC}"
    
    # Create temporary directory
    local tmp_dir=$(mktemp -d)
    
    # Download latest branch archive
    echo "  → Downloading latest version..."
    cd "$tmp_dir"
    curl -sL "https://github.com/${GITHUB_REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar xz
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to download update${NC}"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    # Find extracted directory
    local extract_dir=$(ls -d cipi-*/ | head -n 1)
    
    if [ -z "$extract_dir" ]; then
        echo -e "${RED}Error: Could not find extracted files${NC}"
        rm -rf "$tmp_dir"
        exit 1
    fi
    
    # Backup current installation
    echo "  → Creating backup..."
    if [ -f "${CIPI_BIN}" ]; then
        cp "${CIPI_BIN}" "${CIPI_BIN}.backup"
    fi
    if [ -d "${CIPI_LIB_DIR}" ]; then
        cp -r "${CIPI_LIB_DIR}" "${CIPI_LIB_DIR}.backup"
    fi
    
    # Install new version
    echo "  → Installing new version..."
    
    # Copy main script
    if [ -f "${tmp_dir}/${extract_dir}/cipi" ]; then
        cp "${tmp_dir}/${extract_dir}/cipi" "${CIPI_BIN}"
        chmod 700 "${CIPI_BIN}"
        chown root:root "${CIPI_BIN}"
    fi
    
    # Copy library files
    if [ -d "${tmp_dir}/${extract_dir}/lib" ]; then
        mkdir -p "${CIPI_LIB_DIR}"
        cp -r "${tmp_dir}/${extract_dir}/lib"/* "${CIPI_LIB_DIR}/"
        chmod 700 "${CIPI_LIB_DIR}"/*.sh
        chmod 755 "${CIPI_LIB_DIR}/release.sh"  # Must be readable by app users for deploy.sh
        chmod 711 /opt/cipi "${CIPI_LIB_DIR}"   # Traversable but not listable
        chown -R root:root "${CIPI_LIB_DIR}"
    fi

    # Copy web files (webhook.php, etc.)
    if [ -d "${tmp_dir}/${extract_dir}/web" ]; then
        mkdir -p /opt/cipi/web
        cp -r "${tmp_dir}/${extract_dir}/web"/* /opt/cipi/web/
        chmod 644 /opt/cipi/web/*.php           # Readable by www-data for nginx/php-fpm
        chmod 711 /opt/cipi/web                 # Traversable but not listable
        chown -R root:root /opt/cipi/web
    fi
    
    # Update version file with new commit
    echo "  → Updating version information..."
    set_version "$latest_commit" "$BRANCH"
    
    # Install bash completion
    echo "  → Installing bash completion..."
    if [ -f "${CIPI_LIB_DIR}/completion.sh" ]; then
        # Source the completion functions
        source "${CIPI_LIB_DIR}/completion.sh" 2>/dev/null || true
        if type generate_bash_completion >/dev/null 2>&1; then
            local completion_file="/etc/bash_completion.d/cipi"
            mkdir -p /etc/bash_completion.d
            generate_bash_completion > "$completion_file" 2>/dev/null || true
            if [ -f "$completion_file" ]; then
                chmod 644 "$completion_file"
                chown root:root "$completion_file"
            fi
        fi
    fi
    
    # Cleanup
    echo "  → Cleaning up..."
    rm -rf "$tmp_dir"
    
    echo ""
    if [ "$force" = true ] && [ "$current_commit" = "$latest_commit" ]; then
        echo -e "${GREEN}${BOLD}Cipi reinstalled successfully!${NC}"
        echo -e "Commit: ${CYAN}${latest_commit:0:7}${NC}"
    else
        echo -e "${GREEN}${BOLD}Cipi updated successfully!${NC}"
        echo -e "New commit: ${CYAN}${latest_commit:0:7}${NC}"
    fi
    echo ""
    if [ -f "${CIPI_BIN}.backup" ]; then
        echo "Backup saved at: ${CIPI_BIN}.backup"
    fi
    if [ -d "${CIPI_LIB_DIR}.backup" ]; then
        echo "Backup saved at: ${CIPI_LIB_DIR}.backup"
    fi
    echo ""
    echo -e "${YELLOW}Tip:${NC} Open a new terminal for tab completion, or run:"
    echo -e "     ${CYAN}source /etc/bash_completion.d/cipi${NC}"
    echo ""
    
    # Exit after successful update to prevent any further execution
    exit 0
}

# Check for updates (used by cron)
check_updates() {
    local current_commit=$(get_version_commit)
    local latest_commit=$(get_latest_commit)
    
    if [ -z "$latest_commit" ] || [ "$latest_commit" = "null" ]; then
        echo "Error: Could not fetch latest commit"
        return 1
    fi
    
    if [ -z "$current_commit" ] || [ "$current_commit" = "null" ]; then
        echo "Update available: Unknown -> ${latest_commit:0:7}"
        return 0
    fi
    
    if [ "$current_commit" != "$latest_commit" ]; then
        local commits_behind=$(count_commits_behind "$current_commit" "$latest_commit")
        if [ "$commits_behind" != "unknown" ] && [ "$commits_behind" != "0" ]; then
            echo "Update available: ${current_commit:0:7} -> ${latest_commit:0:7} (${commits_behind} commit(s) behind)"
        else
            echo "Update available: ${current_commit:0:7} -> ${latest_commit:0:7}"
        fi
        return 0
    else
        echo "Cipi is up to date (${current_commit:0:7})"
        return 1
    fi
}

