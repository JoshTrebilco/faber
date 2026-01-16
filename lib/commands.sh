#!/bin/bash

#############################################
# Main Command Functions
#############################################

# Check if help was requested
check_help_requested() {
    for arg in "$@"; do
        if [ "$arg" = "--help" ] || [ "$arg" = "-h" ]; then
            return 0
        fi
    done
    return 1
}

# Status command
cmd_status() {
    if check_help_requested "$@"; then
        show_help_command "status"
        exit 0
    fi
    show_logo
    echo -e "${BOLD}SERVER STATUS${NC}"
    echo "─────────────────────────────────────"
    local commit=$(get_version_commit)
    if [ -n "$commit" ]; then
        echo -e "FABER:     ${CYAN}v${FABER_VERSION} (${commit:0:7})${NC}"
    else
        echo -e "FABER:     ${CYAN}v${FABER_VERSION}${NC}"
    fi
    echo -e "IP:       ${CYAN}$(get_server_ip)${NC}"
    echo -e "HOSTNAME: ${CYAN}$(get_hostname)${NC}"
    echo -e "CPU:      ${CYAN}$(get_cpu_usage)${NC}"
    echo -e "RAM:      ${CYAN}$(get_memory_usage)${NC}"
    echo -e "HDD:      ${CYAN}$(get_disk_usage)${NC}"
    echo ""
    
    echo -e "${BOLD}SERVICES${NC}"
    echo "─────────────────────────────────────"
    echo -e "nginx:      $(get_service_status nginx)"
    echo -e "mysql:      $(get_service_status mysql)"
    echo -e "php8.4-fpm: $(get_service_status php8.4-fpm)"
    echo -e "supervisor: $(get_service_status supervisor)"
    echo -e "redis:      $(get_service_status redis-server)"
    echo ""
}

# Logs command
cmd_logs() {
    if check_help_requested "$@"; then
        show_help_command "logs"
        exit 0
    fi
    
    local lines=50
    
    # Parse arguments
    for arg in "$@"; do
        case $arg in
            --lines=*)
                lines="${arg#*=}"
                ;;
        esac
    done
    
    view_antivirus_logs "$lines"
}

# Config commands
cmd_config() {
    local subcmd=$1
    shift
    
    case $subcmd in
        set)
            set_config "$@"
            ;;
        *)
            echo -e "${RED}Unknown config command: $subcmd${NC}"
            echo "Usage: faber config {set}"
            exit 1
            ;;
    esac
}

# App commands
cmd_app() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "app"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "app" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        create)
            app_create "$@"
            ;;
        list)
            app_list "$@"
            ;;
        show)
            app_show "$@"
            ;;
        edit)
            app_edit "$@"
            ;;
        env)
            app_env "$@"
            ;;
        crontab)
            app_crontab "$@"
            ;;
        password)
            app_password "$@"
            ;;
        delete)
            app_delete "$@"
            ;;
        rollback)
            app_rollback "$@"
            ;;
        releases)
            app_releases "$@"
            ;;
        *)
            echo -e "${RED}Unknown app command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber app {create|list|show|edit|env|crontab|password|delete|rollback|releases}"
            echo "Run 'faber app --help' for more information"
            exit 1
            ;;
    esac
}

# Domain commands
cmd_domain() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "domain"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "domain" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        create)
            domain_create "$@"
            ;;
        list)
            domain_list "$@"
            ;;
        delete)
            domain_delete "$@"
            ;;
        *)
            echo -e "${RED}Unknown domain command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber domain {create|list|delete}"
            echo "Run 'faber domain --help' for more information"
            exit 1
            ;;
    esac
}

# Database commands
cmd_database() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "database"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "database" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        create)
            database_create "$@"
            ;;
        list)
            database_list "$@"
            ;;
        password)
            database_password "$@"
            ;;
        delete)
            database_delete "$@"
            ;;
        *)
            echo -e "${RED}Unknown database command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber database {create|list|password|delete}"
            echo "Run 'faber database --help' for more information"
            exit 1
            ;;
    esac
}

# PHP commands
cmd_php() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "php"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "php" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        list)
            php_list "$@"
            ;;
        install)
            php_install "$@"
            ;;
        switch)
            php_switch "$@"
            ;;
        *)
            echo -e "${RED}Unknown php command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber php {list|install|switch}"
            echo "Run 'faber php --help' for more information"
            exit 1
            ;;
    esac
}

# Service commands
cmd_service() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "service"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "service" "$subcmd"
        exit 0
    fi
    
    if [ "$subcmd" != "restart" ]; then
        echo -e "${RED}Unknown service command: $subcmd${NC}"
        local suggestion=$(suggest_command "$subcmd")
        if [ -n "$suggestion" ]; then
            echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
            echo ""
        fi
        echo "Usage: faber service restart <service>"
        echo "Run 'faber service --help' for more information"
        exit 1
    fi
    
    service_restart "$@"
}

# Stack commands
cmd_stack() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "stack"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "stack" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        create)
            stack_create "$@"
            ;;
        delete)
            stack_delete "$@"
            ;;
        *)
            echo -e "${RED}Unknown stack command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber stack {create|delete}"
            echo "Run 'faber stack --help' for more information"
            exit 1
            ;;
    esac
}

# Webhook commands
cmd_webhook() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "webhook"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "webhook" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        create)
            webhook_create "$@"
            ;;
        show)
            webhook_show "$@"
            ;;
        regenerate)
            webhook_regenerate_secret "$@"
            ;;
        delete)
            webhook_delete "$@"
            ;;
        logs)
            webhook_logs "$@"
            ;;
        *)
            echo -e "${RED}Unknown webhook command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber webhook {create|show|regenerate|delete|logs} <username>"
            echo "Run 'faber webhook --help' for more information"
            exit 1
            ;;
    esac
}

# Reverb commands
cmd_reverb() {
    # Check for --help before subcommand
    if [ -z "$1" ] || check_help_requested "$@"; then
        show_help_command "reverb"
        exit 0
    fi
    
    local subcmd=$1
    shift
    
    # Check for --help after subcommand
    if check_help_requested "$@"; then
        show_help_subcommand "reverb" "$subcmd"
        exit 0
    fi
    
    case $subcmd in
        create)
            reverb_create "$@"
            ;;
        show)
            reverb_show "$@"
            ;;
        start)
            reverb_start "$@"
            ;;
        stop)
            reverb_stop "$@"
            ;;
        restart)
            reverb_restart "$@"
            ;;
        delete)
            reverb_delete "$@"
            ;;
        *)
            echo -e "${RED}Unknown reverb command: $subcmd${NC}"
            local suggestion=$(suggest_command "$subcmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo "Usage: faber reverb {create|show|start|stop|restart|delete}"
            echo "Run 'faber reverb --help' for more information"
            exit 1
            ;;
    esac
}

# Deploy command
cmd_deploy() {
    if check_help_requested "$@"; then
        show_help_command "deploy"
        exit 0
    fi
    
    local username=$1
    
    if [ -z "$username" ]; then
        echo -e "${RED}Error: Username required${NC}"
        echo "Usage: faber deploy <username>"
        exit 1
    fi
    
    check_app_exists "$username"
    
    local home_dir="/home/$username"
    local deploy_script="$home_dir/deploy.sh"
    
    if [ ! -f "$deploy_script" ]; then
        echo -e "${RED}Error: Deploy script not found: $deploy_script${NC}"
        exit 1
    fi
    
    echo -e "${CYAN}Triggering deployment for: $username${NC}"
    echo ""
    
    # Run deployment script
    sudo -u "$username" bash -c "cd $home_dir && ./deploy.sh"
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo ""
        echo -e "${GREEN}Deployment completed successfully${NC}"
    else
        echo ""
        echo -e "${RED}Deployment failed (exit code: $exit_code)${NC}"
        exit $exit_code
    fi
}

# GitHub App commands
cmd_github() {
    local subcmd=$1
    shift

    case $subcmd in
        set)
            local key=$1
            local value=$2
            if [ -z "$key" ] || [ -z "$value" ]; then
                echo -e "${RED}Error: Key and value required${NC}"
                echo "Usage: faber github set <key> <value>"
                echo "Keys: app_id, private_key, slug"
                exit 1
            fi
            set_github_config "github_app_$key" "$value"
            echo -e "${GREEN}Set github_app_$key${NC}"
            ;;
        show)
            echo -e "${BOLD}GitHub App Configuration${NC}"
            echo "─────────────────────────────────────"
            local app_id=$(get_github_config "github_app_id")
            local slug=$(get_github_config "github_app_slug")
            local has_key=$(get_github_config "github_app_private_key")
            echo -e "App ID:      ${CYAN}${app_id:-(not set)}${NC}"
            echo -e "Slug:        ${CYAN}${slug:-(not set)}${NC}"
            echo -e "Private Key: ${CYAN}${has_key:+configured}${has_key:-not set}${NC}"
            ;;
        *)
            echo "Usage: faber github <set|show>"
            exit 1
            ;;
    esac
}

# Update command
cmd_update() {
    if check_help_requested "$@"; then
        show_help_command "update"
        exit 0
    fi
    
    update_faber "$@"
}

