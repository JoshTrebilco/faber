#!/bin/bash

#############################################
# Help System Functions
#############################################

# Levenshtein distance calculation for typo suggestions
levenshtein_distance() {
    local s1="$1"
    local s2="$2"
    local len1=${#s1}
    local len2=${#s2}
    
    # Create distance matrix
    local i j cost
    local -a d
    
    # Initialize first row and column
    for ((i=0; i<=len1; i++)); do
        d[$((i*(len2+1)))]=$i
    done
    for ((j=0; j<=len2; j++)); do
        d[$j]=$j
    done
    
    # Fill the matrix
    for ((i=1; i<=len1; i++)); do
        for ((j=1; j<=len2; j++)); do
            if [ "${s1:$((i-1)):1}" = "${s2:$((j-1)):1}" ]; then
                cost=0
            else
                cost=1
            fi
            local del=$((d[$(((i-1)*(len2+1)+j))]+1))
            local ins=$((d[$((i*(len2+1)+j-1))]+1))
            local sub=$((d[$(((i-1)*(len2+1)+j-1))]+cost))
            
            local min=$del
            [ $ins -lt $min ] && min=$ins
            [ $sub -lt $min ] && min=$sub
            d[$((i*(len2+1)+j))]=$min
        done
    done
    
    echo ${d[$((len1*(len2+1)+len2))]}
}

# Suggest closest command match
suggest_command() {
    local input="$1"
    local commands=("status" "stack" "app" "domain" "database" "php" "service" "webhook" "reverb" "deploy" "update" "help" "logs" "version")
    local best_match=""
    local min_distance=999
    local distance
    
    for cmd in "${commands[@]}"; do
        distance=$(levenshtein_distance "$input" "$cmd")
        if [ $distance -lt $min_distance ] && [ $distance -le 2 ]; then
            min_distance=$distance
            best_match="$cmd"
        fi
    done
    
    echo "$best_match"
}

# Help data structures
declare -A HELP_SYNOPSIS=(
    ["status"]="faber status"
    ["version"]="faber version"
    ["stack"]="faber stack <command> [options]"
    ["stack:create"]="faber stack create [options]"
    ["stack:delete"]="faber stack delete <user> [options]"
    ["app"]="faber app <command> [options]"
    ["app:create"]="faber app create [options]"
    ["app:list"]="faber app list"
    ["app:show"]="faber app show <user>"
    ["app:edit"]="faber app edit <user> [options]"
    ["app:env"]="faber app env <user>"
    ["app:crontab"]="faber app crontab <user>"
    ["app:password"]="faber app password <user>"
    ["app:delete"]="faber app delete <user>"
    ["app:rollback"]="faber app rollback <user> [release]"
    ["app:releases"]="faber app releases <user>"
    ["domain"]="faber domain <command> [options]"
    ["domain:create"]="faber domain create [options]"
    ["domain:list"]="faber domain list"
    ["domain:delete"]="faber domain delete <domain>"
    ["database"]="faber database <command> [options]"
    ["database:create"]="faber database create [options]"
    ["database:list"]="faber database list"
    ["database:password"]="faber database password <name>"
    ["database:delete"]="faber database delete <name>"
    ["php"]="faber php <command> [options]"
    ["php:list"]="faber php list"
    ["php:install"]="faber php install <version>"
    ["php:switch"]="faber php switch <version>"
    ["service"]="faber service <command> [options]"
    ["service:restart"]="faber service restart <service>"
    ["webhook"]="faber webhook <command> [options]"
    ["webhook:create"]="faber webhook create <user>"
    ["webhook:show"]="faber webhook show <user>"
    ["webhook:regenerate"]="faber webhook regenerate <user>"
    ["webhook:delete"]="faber webhook delete <user>"
    ["webhook:logs"]="faber webhook logs"
    ["reverb"]="faber reverb <command> [options]"
    ["reverb:create"]="faber reverb create"
    ["reverb:show"]="faber reverb show"
    ["reverb:start"]="faber reverb start"
    ["reverb:stop"]="faber reverb stop"
    ["reverb:restart"]="faber reverb restart"
    ["reverb:delete"]="faber reverb delete"
    ["logs"]="faber logs [--lines=N]"
    ["deploy"]="faber deploy <user>"
    ["update"]="faber update [--force]"
)

declare -A HELP_DESCRIPTION=(
    ["status"]="Show server status and service information"
    ["version"]="Show Faber version and commit information"
    ["stack"]="Full stack creation: app + domain + database + SSL + .env"
    ["stack:create"]="Create a complete application stack (app + domain + database + SSL + .env)"
    ["stack:delete"]="Delete a stack and optionally its database"
    ["app"]="Manage applications"
    ["app:create"]="Create a new application"
    ["app:list"]="List all applications"
    ["app:show"]="Show detailed information about an application"
    ["app:edit"]="Modify application settings (PHP version, etc.)"
    ["app:env"]="Edit the .env file for an application"
    ["app:crontab"]="Edit the crontab for an application"
    ["app:password"]="Change the SSH password for an application user"
    ["app:delete"]="Delete an application"
    ["app:rollback"]="Roll back to a previous release"
    ["app:releases"]="List all releases for an application"
    ["domain"]="Manage domains"
    ["domain:create"]="Create or assign a domain to an application"
    ["domain:list"]="List all domains"
    ["domain:delete"]="Delete a domain"
    ["database"]="Manage databases"
    ["database:create"]="Create a new database"
    ["database:list"]="List all databases"
    ["database:password"]="Change database password"
    ["database:delete"]="Delete a database"
    ["php"]="Manage PHP versions"
    ["php:list"]="List installed PHP versions"
    ["php:install"]="Install a PHP version (5.6-8.5)"
    ["php:switch"]="Switch CLI PHP version"
    ["service"]="Control system services"
    ["service:restart"]="Restart a service (nginx|php|mysql|supervisor|redis)"
    ["webhook"]="Manage webhook configuration"
    ["webhook:create"]="Create webhook on GitHub"
    ["webhook:show"]="Show webhook configuration for an application"
    ["webhook:regenerate"]="Regenerate webhook secret for an application"
    ["webhook:delete"]="Delete webhook from GitHub"
    ["webhook:logs"]="View webhook logs"
    ["deploy"]="Trigger a deployment for an application"
    ["reverb"]="Manage Reverb WebSocket server"
    ["reverb:create"]="Create dedicated Reverb WebSocket server"
    ["reverb:show"]="Show Reverb server configuration"
    ["reverb:start"]="Start Reverb server"
    ["reverb:stop"]="Stop Reverb server"
    ["reverb:restart"]="Restart Reverb server"
    ["reverb:delete"]="Delete Reverb server"
    ["logs"]="View ClamAV antivirus scan logs"
    ["update"]="Update Faber to latest version"
)

# Compact help screen (default)
show_help_compact() {
    show_logo
    local commit=$(get_version_commit)
    if [ -n "$commit" ]; then
        echo -e "Faber v${FABER_VERSION} (${commit:0:7}) - Server Management CLI"
    else
        echo -e "Faber v${FABER_VERSION} - Server Management CLI"
    fi
    echo ""
    echo -e "${BOLD}COMMANDS:${NC}"
    echo ""
    echo -e "  ${CYAN}status${NC}      Show server status"
    echo -e "  ${CYAN}stack${NC}       Full stack: app + domain + database + SSL"
    echo -e "  ${CYAN}app${NC}         Manage applications"
    echo -e "  ${CYAN}domain${NC}      Manage domains"
    echo -e "  ${CYAN}database${NC}    Manage databases"
    echo -e "  ${CYAN}php${NC}         Manage PHP versions"
    echo -e "  ${CYAN}service${NC}     Control services"
    echo -e "  ${CYAN}webhook${NC}     Webhook configuration"
    echo -e "  ${CYAN}reverb${NC}      WebSocket server management"
    echo -e "  ${CYAN}deploy${NC}      Trigger deployment for an app"
    echo -e "  ${CYAN}logs${NC}        View antivirus logs"
    echo -e "  ${CYAN}update${NC}      Update Faber"
    echo ""
    echo -e "Run ${CYAN}faber help${NC} for full documentation"
    echo -e "Run ${CYAN}faber <command> --help${NC} for command details"
    echo -e "Run ${CYAN}faber help -i${NC} for interactive mode"
    echo ""
    echo -e "${YELLOW}Tip:${NC} You can use ${CYAN}fab${NC} as a shorthand for ${CYAN}faber${NC}"
    echo ""
}

# Full help screen
show_help_full() {
    show_logo
    echo -e "${BOLD}Usage:${NC} ${CYAN}faber [command] [options]${NC}"
    echo -e "${BOLD}   or:${NC} ${CYAN}fab   [command] [options]${NC}"
    echo ""
    echo -e "${BOLD}Commands:${NC}"
    echo ""
    echo -e "  ${CYAN}status${NC}                          Show server status"
    echo -e "  ${CYAN}version${NC}                         Show Faber version"
    echo ""
    echo -e "${BOLD}Stack (Full Stack Creation):${NC}"
    echo -e "  ${CYAN}stack create${NC}                    Create app, domain, database, SSL, and configure .env"
    echo -e "  ${CYAN}stack delete <user>${NC}             Delete stack and optionally database"
    echo ""
    echo -e "${BOLD}App Management:${NC}"
    echo -e "  ${CYAN}app create${NC}                      Create a new app"
    echo -e "  ${CYAN}app list${NC}                        List all apps"
    echo -e "  ${CYAN}app show <user>${NC}                 Show app details"
    echo -e "  ${CYAN}app edit <user> --php=X.X${NC}       Change PHP version for app"
    echo -e "  ${CYAN}app env <user>${NC}                  Edit .env file for app"
    echo -e "  ${CYAN}app crontab <user>${NC}              Edit crontab for app"
    echo -e "  ${CYAN}app password <user>${NC}             Change app SSH password"
    echo -e "  ${CYAN}app delete <user>${NC}               Delete an app"
    echo -e "  ${CYAN}app rollback <user>${NC}             Roll back to previous release"
    echo -e "  ${CYAN}app releases <user>${NC}             List all releases"
    echo ""
    echo -e "${BOLD}Domain Management:${NC}"
    echo -e "  ${CYAN}domain create${NC}                   Create/assign a domain"
    echo -e "  ${CYAN}domain list${NC}                     List all domains"
    echo -e "  ${CYAN}domain delete <domain>${NC}          Delete a domain"
    echo ""
    echo -e "${BOLD}Database Management:${NC}"
    echo -e "  ${CYAN}database create${NC}                 Create a new database"
    echo -e "  ${CYAN}database list${NC}                   List all databases"
    echo -e "  ${CYAN}database password <name>${NC}        Change database password"
    echo -e "  ${CYAN}database delete <name>${NC}          Delete a database"
    echo ""
    echo -e "${BOLD}PHP Management:${NC}"
    echo -e "  ${CYAN}php list${NC}                        List installed PHP versions"
    echo -e "  ${CYAN}php install <version>${NC}           Install PHP version (5.6-8.5)"
    echo -e "  ${CYAN}php switch <version>${NC}            Switch CLI PHP version"
    echo ""
    echo -e "${BOLD}Service Management:${NC}"
    echo -e "  ${CYAN}service restart <service>${NC}       Restart service (nginx|php|mysql|supervisor|redis)"
    echo ""
    echo -e "${BOLD}Webhook Management:${NC}"
    echo -e "  ${CYAN}webhook create <user>${NC}           Create webhook on GitHub"
    echo -e "  ${CYAN}webhook show <user>${NC}             Show webhook configuration for app"
    echo -e "  ${CYAN}webhook regenerate <user>${NC}       Regenerate webhook secret"
    echo -e "  ${CYAN}webhook delete <user>${NC}           Delete webhook from GitHub"
    echo -e "  ${CYAN}webhook logs${NC}                    View webhook logs"
    echo ""
    echo -e "${BOLD}Reverb (WebSocket Server):${NC}"
    echo -e "  ${CYAN}reverb create${NC}                   Create dedicated Reverb WebSocket server"
    echo -e "  ${CYAN}reverb show${NC}                     Show Reverb server configuration"
    echo -e "  ${CYAN}reverb start${NC}                    Start Reverb server"
    echo -e "  ${CYAN}reverb stop${NC}                     Stop Reverb server"
    echo -e "  ${CYAN}reverb restart${NC}                  Restart Reverb server"
    echo -e "  ${CYAN}reverb delete${NC}                   Delete Reverb server"
    echo ""
    echo -e "${BOLD}Deployment:${NC}"
    echo -e "  ${CYAN}deploy <user>${NC}                   Trigger deployment for an app"
    echo ""
    echo -e "${BOLD}System Management:${NC}"
    echo -e "  ${CYAN}logs [--lines=N]${NC}                View ClamAV antivirus scan logs"
    echo -e "  ${CYAN}update${NC}                          Update Faber to latest version"
    echo ""
    echo -e "${BOLD}Examples:${NC}"
    echo -e "  faber status"
    echo -e "  faber stack create --user=myapp --repository=https://github.com/user/repo.git --domain=example.com"
    echo -e "  faber stack delete myapp --dbname=mydb"
    echo -e "  faber app create --user=myapp --repository=https://github.com/user/repo.git --php=8.4"
    echo -e "  faber app edit myapp --php=8.3"
    echo -e "  faber app env myapp"
    echo -e "  faber app crontab myapp"
    echo -e "  faber app password myapp"
    echo -e "  faber database create --name=mydb"
    echo -e "  faber database password mydb"
    echo -e "  faber domain create --domain=example.com --app=myapp"
    echo -e "  faber logs --lines=100"
    echo ""
}

# Show help for a specific command
show_help_command() {
    local cmd="$1"
    
    case "$cmd" in
        status)
            echo -e "${BOLD}STATUS${NC} - Show server status"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber status${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays server information including IP, hostname, CPU, RAM, disk usage,"
            echo -e "  and the status of all services (nginx, mysql, php, supervisor, redis)."
            echo ""
            ;;
        version)
            echo -e "${BOLD}VERSION${NC} - Show Faber version"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber version${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays the current Faber version and commit hash (if available)."
            echo ""
            ;;
        stack)
            echo -e "${BOLD}STACK${NC} - Full Stack Creation"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber stack <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}create${NC}    Create app, domain, database, SSL, and configure .env"
            echo -e "  ${CYAN}delete${NC}    Delete stack and optionally database"
            echo ""
            echo -e "Run ${CYAN}faber stack <command> --help${NC} for command options"
            echo ""
            ;;
        app)
            echo -e "${BOLD}APP${NC} - Application Management"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}create${NC}     Create a new application"
            echo -e "  ${CYAN}list${NC}       List all applications"
            echo -e "  ${CYAN}show${NC}       Show app details"
            echo -e "  ${CYAN}edit${NC}       Modify app settings"
            echo -e "  ${CYAN}env${NC}        Edit .env file"
            echo -e "  ${CYAN}crontab${NC}    Edit crontab"
            echo -e "  ${CYAN}password${NC}   Change SSH password"
            echo -e "  ${CYAN}delete${NC}     Remove an application"
            echo -e "  ${CYAN}rollback${NC}   Roll back to a previous release"
            echo -e "  ${CYAN}releases${NC}   List all releases"
            echo ""
            echo -e "Run ${CYAN}faber app <command> --help${NC} for command options"
            echo ""
            ;;
        domain)
            echo -e "${BOLD}DOMAIN${NC} - Domain Management"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber domain <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}create${NC}     Create/assign a domain"
            echo -e "  ${CYAN}list${NC}       List all domains"
            echo -e "  ${CYAN}delete${NC}     Delete a domain"
            echo ""
            echo -e "Run ${CYAN}faber domain <command> --help${NC} for command options"
            echo ""
            ;;
        database)
            echo -e "${BOLD}DATABASE${NC} - Database Management"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber database <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}create${NC}     Create a new database"
            echo -e "  ${CYAN}list${NC}       List all databases"
            echo -e "  ${CYAN}password${NC}   Change database password"
            echo -e "  ${CYAN}delete${NC}     Delete a database"
            echo ""
            echo -e "Run ${CYAN}faber database <command> --help${NC} for command options"
            echo ""
            ;;
        php)
            echo -e "${BOLD}PHP${NC} - PHP Version Management"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber php <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}list${NC}       List installed PHP versions"
            echo -e "  ${CYAN}install${NC}    Install PHP version (5.6-8.5)"
            echo -e "  ${CYAN}switch${NC}     Switch CLI PHP version"
            echo ""
            echo -e "Run ${CYAN}faber php <command> --help${NC} for command options"
            echo ""
            ;;
        service)
            echo -e "${BOLD}SERVICE${NC} - Service Control"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber service <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}restart${NC}    Restart a service"
            echo ""
            echo -e "Run ${CYAN}faber service restart --help${NC} for details"
            echo ""
            ;;
        webhook)
            echo -e "${BOLD}WEBHOOK${NC} - Webhook Configuration"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber webhook <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}create${NC}      Create webhook on GitHub"
            echo -e "  ${CYAN}show${NC}        Show webhook configuration"
            echo -e "  ${CYAN}regenerate${NC}  Regenerate webhook secret"
            echo -e "  ${CYAN}delete${NC}      Delete webhook from GitHub"
            echo -e "  ${CYAN}logs${NC}        View webhook logs"
            echo ""
            echo -e "Run ${CYAN}faber webhook <command> --help${NC} for command options"
            echo ""
            ;;
        reverb)
            echo -e "${BOLD}REVERB${NC} - WebSocket Server Management"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb <command> [options]${NC}"
            echo ""
            echo -e "${BOLD}COMMANDS:${NC}"
            echo -e "  ${CYAN}create${NC}     Create dedicated Reverb server"
            echo -e "  ${CYAN}show${NC}       Show Reverb configuration"
            echo -e "  ${CYAN}start${NC}      Start Reverb server"
            echo -e "  ${CYAN}stop${NC}       Stop Reverb server"
            echo -e "  ${CYAN}restart${NC}    Restart Reverb server"
            echo -e "  ${CYAN}delete${NC}     Delete Reverb server"
            echo ""
            echo -e "Run ${CYAN}faber reverb <command> --help${NC} for command options"
            echo ""
            ;;
        deploy)
            echo -e "${BOLD}DEPLOY${NC} - Trigger deployment for an application"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber deploy <username>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<username>${NC}    The application username to deploy"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Triggers a zero-downtime deployment for the specified application."
            echo -e "  This runs the same deployment process as the webhook trigger:"
            echo -e "    • Clones fresh code into a new release directory"
            echo -e "    • Runs deployment hooks (composer install, npm build, migrations)"
            echo -e "    • Atomically switches the 'current' symlink"
            echo -e "    • Cleans up old releases"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber deploy myapp"
            echo ""
            ;;
        logs)
            echo -e "${BOLD}LOGS${NC} - View Antivirus Logs"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber logs [--lines=N]${NC}"
            echo ""
            echo -e "${BOLD}OPTIONS:${NC}"
            echo -e "  ${CYAN}--lines=N${NC}    Number of lines to display (default: 50)"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber logs"
            echo -e "  faber logs --lines=100"
            echo ""
            ;;
        update)
            echo -e "${BOLD}UPDATE${NC} - Update Faber"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber update [--force]${NC}"
            echo ""
            echo -e "${BOLD}OPTIONS:${NC}"
            echo -e "  ${CYAN}--force, -f${NC}    Force reinstall even if already up to date"
            echo -e "                 Useful for reinstalling the current version"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Updates Faber to the latest version from the repository."
            echo ""
            ;;
        *)
            echo -e "${RED}Unknown command: $cmd${NC}"
            echo ""
            local suggestion=$(suggest_command "$cmd")
            if [ -n "$suggestion" ]; then
                echo -e "Did you mean: ${CYAN}$suggestion${NC}?"
                echo ""
            fi
            echo -e "Run ${CYAN}faber help${NC} for available commands."
            echo ""
            return 1
            ;;
    esac
}

# Show help for a specific subcommand
show_help_subcommand() {
    local cmd="$1"
    local subcmd="$2"
    
    case "$cmd:$subcmd" in
        stack:create)
            echo -e "${BOLD}STACK CREATE${NC} - Create Full Application Stack"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber stack create [options]${NC}"
            echo ""
            echo -e "${BOLD}REQUIRED:${NC}"
            echo -e "  ${CYAN}--user=<name>${NC}          System username (lowercase, alphanumeric)"
            echo -e "  ${CYAN}--repository=<url>${NC}     Git repository URL (HTTPS or SSH)"
            echo ""
            echo -e "${BOLD}OPTIONAL:${NC}"
            echo -e "  ${CYAN}--php=<version>${NC}        PHP version (default: 8.4)"
            echo -e "  ${CYAN}--branch=<name>${NC}        Git branch (default: main)"
            echo -e "  ${CYAN}--domain=<domain>${NC}      Domain name"
            echo -e "  ${CYAN}--dbname=<name>${NC}        Database name"
            echo -e "  ${CYAN}--skip-db${NC}              Skip database creation"
            echo -e "  ${CYAN}--skip-domain${NC}          Skip domain creation"
            echo -e "  ${CYAN}--skip-env${NC}             Skip .env configuration"
            echo -e "  ${CYAN}--skip-deploy${NC}          Skip initial deployment"
            echo -e "  ${CYAN}--skip-reverb${NC}          Skip Reverb connection"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber stack create"
            echo -e "  faber stack create --user=mysite --repository=https://github.com/user/repo.git --domain=example.com"
            echo -e "  faber stack create --user=mysite --repository=git@github.com:user/repo.git --php=8.3 --branch=develop"
            echo ""
            ;;
        stack:delete)
            echo -e "${BOLD}STACK DELETE${NC} - Delete Application Stack"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber stack delete <user> [options]${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                 Application username"
            echo ""
            echo -e "${BOLD}OPTIONAL:${NC}"
            echo -e "  ${CYAN}--dbname=<name>${NC}        Database name to delete"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber stack delete myapp"
            echo -e "  faber stack delete myapp --dbname=mydb"
            echo ""
            ;;
        app:create)
            echo -e "${BOLD}APP CREATE${NC} - Create a new application"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app create [options]${NC}"
            echo ""
            echo -e "${BOLD}REQUIRED:${NC}"
            echo -e "  ${CYAN}--user=<name>${NC}           System username (lowercase, alphanumeric)"
            echo -e "  ${CYAN}--repository=<url>${NC}      Git repository URL (HTTPS or SSH)"
            echo ""
            echo -e "${BOLD}OPTIONAL:${NC}"
            echo -e "  ${CYAN}--php=<version>${NC}         PHP version (default: 8.4)"
            echo -e "  ${CYAN}--branch=<name>${NC}         Git branch (default: main)"
            echo -e "  ${CYAN}--skip-reverb${NC}           Don't connect to Reverb WebSocket server"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app create"
            echo -e "  faber app create --user=mysite --repository=https://github.com/user/repo.git"
            echo -e "  faber app create --user=mysite --repository=git@github.com:user/repo.git --php=8.3 --branch=develop"
            echo ""
            ;;
        app:list)
            echo -e "${BOLD}APP LIST${NC} - List all applications"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app list${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays a list of all applications with their details."
            echo ""
            ;;
        app:show)
            echo -e "${BOLD}APP SHOW${NC} - Show app details"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app show <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app show myapp"
            echo ""
            ;;
        app:edit)
            echo -e "${BOLD}APP EDIT${NC} - Modify app settings"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app edit <user> [options]${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}OPTIONS:${NC}"
            echo -e "  ${CYAN}--php=<version>${NC}         PHP version to switch to"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app edit myapp --php=8.3"
            echo ""
            ;;
        app:env)
            echo -e "${BOLD}APP ENV${NC} - Edit .env file"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app env <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Opens the .env file for the application in your default editor."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app env myapp"
            echo ""
            ;;
        app:crontab)
            echo -e "${BOLD}APP CRONTAB${NC} - Edit crontab"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app crontab <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Opens the crontab for the application in your default editor."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app crontab myapp"
            echo ""
            ;;
        app:password)
            echo -e "${BOLD}APP PASSWORD${NC} - Change SSH password"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app password <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Changes the SSH password for the application user."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app password myapp"
            echo ""
            ;;
        app:delete)
            echo -e "${BOLD}APP DELETE${NC} - Delete an application"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app delete <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Permanently deletes an application and all its files."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app delete myapp"
            echo ""
            ;;
        app:rollback)
            echo -e "${BOLD}APP ROLLBACK${NC} - Roll back to a previous release"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app rollback <user> [release]${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo -e "  ${CYAN}[release]${NC}               Release name (timestamp) - optional"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Rolls back the application to a previous release by switching the"
            echo -e "  'current' symlink. If no release is specified, rolls back to the"
            echo -e "  previous release."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app rollback myapp"
            echo -e "  faber app rollback myapp 20260105120000"
            echo ""
            ;;
        app:releases)
            echo -e "${BOLD}APP RELEASES${NC} - List all releases"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber app releases <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Lists all available releases for an application, showing the active"
            echo -e "  release and available rollback targets."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber app releases myapp"
            echo ""
            ;;
        domain:create)
            echo -e "${BOLD}DOMAIN CREATE${NC} - Create or assign a domain"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber domain create [options]${NC}"
            echo ""
            echo -e "${BOLD}REQUIRED:${NC}"
            echo -e "  ${CYAN}--domain=<domain>${NC}        Domain name"
            echo -e "  ${CYAN}--app=<user>${NC}             Application username"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber domain create --domain=example.com --app=myapp"
            echo ""
            ;;
        domain:list)
            echo -e "${BOLD}DOMAIN LIST${NC} - List all domains"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber domain list${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays a list of all domains with their associated applications."
            echo ""
            ;;
        domain:delete)
            echo -e "${BOLD}DOMAIN DELETE${NC} - Delete a domain"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber domain delete <domain>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<domain>${NC}                Domain name to delete"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber domain delete example.com"
            echo ""
            ;;
        database:create)
            echo -e "${BOLD}DATABASE CREATE${NC} - Create a new database"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber database create [options]${NC}"
            echo ""
            echo -e "${BOLD}OPTIONAL:${NC}"
            echo -e "  ${CYAN}--name=<name>${NC}           Database name (auto-generated if not provided)"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber database create"
            echo -e "  faber database create --name=mydb"
            echo ""
            ;;
        database:list)
            echo -e "${BOLD}DATABASE LIST${NC} - List all databases"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber database list${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays a list of all databases."
            echo ""
            ;;
        database:password)
            echo -e "${BOLD}DATABASE PASSWORD${NC} - Change database password"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber database password <name>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<name>${NC}                  Database name"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber database password mydb"
            echo ""
            ;;
        database:delete)
            echo -e "${BOLD}DATABASE DELETE${NC} - Delete a database"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber database delete <name>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<name>${NC}                  Database name"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber database delete mydb"
            echo ""
            ;;
        php:list)
            echo -e "${BOLD}PHP LIST${NC} - List installed PHP versions"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber php list${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays all installed PHP versions on the system."
            echo ""
            ;;
        php:install)
            echo -e "${BOLD}PHP INSTALL${NC} - Install PHP version"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber php install <version>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<version>${NC}               PHP version (5.6-8.5)"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber php install 8.3"
            echo -e "  faber php install 8.4"
            echo ""
            ;;
        php:switch)
            echo -e "${BOLD}PHP SWITCH${NC} - Switch CLI PHP version"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber php switch <version>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<version>${NC}               PHP version to switch to"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber php switch 8.3"
            echo ""
            ;;
        service:restart)
            echo -e "${BOLD}SERVICE RESTART${NC} - Restart a service"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber service restart <service>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<service>${NC}               Service name (nginx|php|mysql|supervisor|redis)"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber service restart nginx"
            echo -e "  faber service restart mysql"
            echo ""
            ;;
        webhook:create)
            echo -e "${BOLD}WEBHOOK CREATE${NC} - Create webhook on GitHub"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber webhook create <user>${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Creates a webhook on the GitHub repository. Requires GitHub"
            echo -e "  authorization via device flow."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber webhook create myapp"
            echo ""
            ;;
        webhook:show)
            echo -e "${BOLD}WEBHOOK SHOW${NC} - Show webhook configuration"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber webhook show <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber webhook show myapp"
            echo ""
            ;;
        webhook:regenerate)
            echo -e "${BOLD}WEBHOOK REGENERATE${NC} - Regenerate webhook secret"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber webhook regenerate <user>${NC}"
            echo ""
            echo -e "${BOLD}ARGUMENTS:${NC}"
            echo -e "  ${CYAN}<user>${NC}                  Application username"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Generates a new webhook secret for the application. The old secret"
            echo -e "  will be invalidated."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber webhook regenerate myapp"
            echo ""
            ;;
        webhook:delete)
            echo -e "${BOLD}WEBHOOK DELETE${NC} - Delete webhook from GitHub"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber webhook delete <user>${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Deletes the webhook from the GitHub repository. Requires GitHub"
            echo -e "  authorization via device flow."
            echo ""
            echo -e "${BOLD}EXAMPLES:${NC}"
            echo -e "  faber webhook delete myapp"
            echo ""
            ;;
        webhook:logs)
            echo -e "${BOLD}WEBHOOK LOGS${NC} - View webhook logs"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber webhook logs${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays webhook execution logs."
            echo ""
            ;;
        reverb:create)
            echo -e "${BOLD}REVERB CREATE${NC} - Create Reverb WebSocket server"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb create${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Creates a dedicated Reverb WebSocket server for Laravel applications."
            echo ""
            ;;
        reverb:show)
            echo -e "${BOLD}REVERB SHOW${NC} - Show Reverb configuration"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb show${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Displays the current Reverb server configuration."
            echo ""
            ;;
        reverb:start)
            echo -e "${BOLD}REVERB START${NC} - Start Reverb server"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb start${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Starts the Reverb WebSocket server."
            echo ""
            ;;
        reverb:stop)
            echo -e "${BOLD}REVERB STOP${NC} - Stop Reverb server"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb stop${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Stops the Reverb WebSocket server."
            echo ""
            ;;
        reverb:restart)
            echo -e "${BOLD}REVERB RESTART${NC} - Restart Reverb server"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb restart${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Restarts the Reverb WebSocket server."
            echo ""
            ;;
        reverb:delete)
            echo -e "${BOLD}REVERB DELETE${NC} - Delete Reverb server"
            echo ""
            echo -e "${BOLD}USAGE:${NC}"
            echo -e "  ${CYAN}faber reverb delete${NC}"
            echo ""
            echo -e "${BOLD}DESCRIPTION:${NC}"
            echo -e "  Removes the Reverb WebSocket server configuration."
            echo ""
            ;;
        *)
            echo -e "${RED}Unknown subcommand: $cmd $subcmd${NC}"
            echo ""
            echo -e "Run ${CYAN}faber $cmd --help${NC} for available subcommands."
            echo ""
            return 1
            ;;
    esac
}

# Interactive help mode
show_help_interactive() {
    local commands=(
        "status:Show server status"
        "stack:Full stack creation"
        "app:Manage applications"
        "domain:Manage domains"
        "database:Manage databases"
        "php:Manage PHP versions"
        "service:Control services"
        "webhook:Webhook configuration"
        "reverb:WebSocket server"
        "logs:View antivirus logs"
        "update:Update Faber"
    )
    
    local selected=0
    local total=${#commands[@]}
    local key
    local box_width=50
    
    # Hide cursor
    echo -ne "\033[?25l"
    
    while true; do
        # Clear screen and show menu
        clear
        echo -e "${GREEN}${BOLD}"
        echo " _______ _______ ______  _______ ______  "
        echo "(_______|_______|____  \(_______|_____ \ "
        echo " _____   _______ ____)  )_____   _____) )"
        echo "|  ___) |  ___  |  __  (|  ___) |  __  / "
        echo "| |     | |   | | |__)  ) |_____| |  \ \ "
        echo "|_|     |_|   |_|______/|_______)_|   |_|"
        echo -e "${NC}"
        echo -e "${BOLD}┌─ Faber Help ────────────────────────────────────┐${NC}"
        echo -e "${BOLD}│${NC}                                                ${BOLD}│${NC}"
        
        for ((i=0; i<total; i++)); do
            local cmd_name=$(echo "${commands[$i]}" | cut -d: -f1)
            local cmd_desc=$(echo "${commands[$i]}" | cut -d: -f2)
            
            if [ $i -eq $selected ]; then
                printf "${BOLD}│${NC}  ${GREEN}${BOLD}>${NC} ${CYAN}${BOLD}%-12s${NC} %-30s ${BOLD}│${NC}\n" "$cmd_name" "$cmd_desc"
            else
                printf "${BOLD}│${NC}    %-12s %-30s ${BOLD}│${NC}\n" "$cmd_name" "$cmd_desc"
            fi
        done
        
        echo -e "${BOLD}│${NC}                                                ${BOLD}│${NC}"
        echo -e "${BOLD}│${NC}  ↑/↓ Navigate  Enter Select  q Quit            ${BOLD}│${NC}"
        echo -e "${BOLD}└────────────────────────────────────────────────┘${NC}"
        
        # Read key
        read -rsn1 key
        case "$key" in
            $'\x1b')
                read -rsn1 -t 0.1 tmp
                if [[ "$tmp" == "[" ]]; then
                    read -rsn1 -t 0.1 tmp
                    case "$tmp" in
                        "A") # Up arrow
                            selected=$((selected - 1))
                            [ $selected -lt 0 ] && selected=$((total - 1))
                            ;;
                        "B") # Down arrow
                            selected=$((selected + 1))
                            [ $selected -ge $total ] && selected=0
                            ;;
                    esac
                fi
                ;;
            "")
                # Enter key
                local cmd_name=$(echo "${commands[$selected]}" | cut -d: -f1)
                clear
                echo -ne "\033[?25h"  # Show cursor
                show_help_command "$cmd_name"
                echo ""
                read -p "Press Enter to return to menu..."
                ;;
            "q"|"Q")
                clear
                echo -ne "\033[?25h"  # Show cursor
                return 0
                ;;
        esac
    done
}

