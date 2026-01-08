#!/bin/bash

#############################################
# Shell Completion Functions
#############################################

# Generate bash completion script
generate_bash_completion() {
    cat <<'EOF'
# Cipi bash completion
_cipi() {
    local cur prev
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    
    COMPREPLY=()
    
    if [ $COMP_CWORD -eq 1 ]; then
        COMPREPLY=($(compgen -W "status version provision app domain database php service webhook reverb deploy logs update help completion" -- "$cur"))
    elif [ $COMP_CWORD -eq 2 ]; then
        case "$prev" in
            provision)
                COMPREPLY=($(compgen -W "create delete" -- "$cur"))
                ;;
            app)
                COMPREPLY=($(compgen -W "create list show edit env crontab password delete" -- "$cur"))
                ;;
            domain)
                COMPREPLY=($(compgen -W "create list delete" -- "$cur"))
                ;;
            database)
                COMPREPLY=($(compgen -W "create list password delete" -- "$cur"))
                ;;
            php)
                COMPREPLY=($(compgen -W "list install switch" -- "$cur"))
                ;;
            service)
                COMPREPLY=($(compgen -W "restart" -- "$cur"))
                ;;
            webhook)
                COMPREPLY=($(compgen -W "setup show regenerate delete logs" -- "$cur"))
                ;;
            reverb)
                COMPREPLY=($(compgen -W "setup show start stop restart delete" -- "$cur"))
                ;;
            completion)
                COMPREPLY=($(compgen -W "bash" -- "$cur"))
                ;;
            deploy)
                if [ -f /etc/cipi/apps.json ]; then
                    COMPREPLY=($(compgen -W "$(jq -r 'keys[]' /etc/cipi/apps.json 2>/dev/null)" -- "$cur"))
                fi
                ;;
        esac
    elif [ $COMP_CWORD -eq 3 ]; then
        case "${COMP_WORDS[1]}" in
            provision)
                case "${COMP_WORDS[2]}" in
                    delete)
                        if [ -f /etc/cipi/apps.json ]; then
                            COMPREPLY=($(compgen -W "$(jq -r 'keys[]' /etc/cipi/apps.json 2>/dev/null)" -- "$cur"))
                        fi
                        ;;
                esac
                ;;
            app)
                case "${COMP_WORDS[2]}" in
                    show|edit|env|crontab|password|delete)
                        if [ -f /etc/cipi/apps.json ]; then
                            COMPREPLY=($(compgen -W "$(jq -r 'keys[]' /etc/cipi/apps.json 2>/dev/null)" -- "$cur"))
                        fi
                        ;;
                esac
                ;;
            database)
                case "${COMP_WORDS[2]}" in
                    password|delete)
                        if [ -f /etc/cipi/databases.json ]; then
                            COMPREPLY=($(compgen -W "$(jq -r 'keys[]' /etc/cipi/databases.json 2>/dev/null)" -- "$cur"))
                        fi
                        ;;
                esac
                ;;
            php)
                case "${COMP_WORDS[2]}" in
                    install|switch)
                        if [ -d /etc/php ]; then
                            COMPREPLY=($(compgen -W "$(ls /etc/php | grep -E '^[0-9]+\.[0-9]+$' | sort -V)" -- "$cur"))
                        fi
                        ;;
                esac
                ;;
            service)
                if [ "${COMP_WORDS[2]}" = "restart" ]; then
                    COMPREPLY=($(compgen -W "nginx php mysql supervisor redis" -- "$cur"))
                fi
                ;;
            webhook)
                case "${COMP_WORDS[2]}" in
                    setup|show|regenerate|delete)
                        if [ -f /etc/cipi/apps.json ]; then
                            COMPREPLY=($(compgen -W "$(jq -r 'keys[]' /etc/cipi/apps.json 2>/dev/null)" -- "$cur"))
                        fi
                        ;;
                esac
                ;;
        esac
    fi
    
    return 0
}

complete -F _cipi cipi
EOF
}

# Generate completion script
generate_completion() {
    local shell="${1:-bash}"
    
    if [ "$shell" != "bash" ]; then
        echo -e "${RED}Error: Only bash completion is supported${NC}"
        echo "Usage: cipi completion [bash]"
        exit 1
    fi
    
    generate_bash_completion
}

