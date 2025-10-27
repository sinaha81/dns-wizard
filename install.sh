#!/bin/bash

# ==============================================================================
#
# Cloudflare DNS Worker - Unified Smart Installer & Updater
# Version: 2.1.0
#
# This script intelligently self-updates and then installs the DNS worker.
# It is fully self-contained and uses the Termux:API for a seamless,
# clipboard-based token acquisition flow, eliminating manual pasting.
#
# Author: Your Name/Alias & AI Thought Partner
#
# v2.1.0 Feature Update:
#   - Implemented a magical token acquisition flow using Termux:API's
#     clipboard-get feature. The script now polls the clipboard,
#     automating the token retrieval process after the user copies it.
#   - Added a dependency check and installation guide for 'termux-api'.
#
# ==============================================================================

# --- Bash Strict Mode ---
set -euo pipefail

# --- Script Configuration ---
readonly SCRIPT_VERSION="2.1.0"
readonly REPO_USER="sinaha81"
readonly REPO_NAME="dns-wizard"
readonly BRANCH_NAME="main"
readonly SCRIPT_FILENAME="install.sh"

# --- Read-only URLs and Paths ---
readonly REPO_RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH_NAME}"
readonly VERSION_FILE_URL="${REPO_RAW_URL}/VERSION"
readonly SELF_SCRIPT_URL="${REPO_RAW_URL}/${SCRIPT_FILENAME}"
readonly LOCAL_INSTALL_DIR="${HOME}/.dns-worker-installer"
readonly LOCAL_SCRIPT_PATH="${LOCAL_INSTALL_DIR}/${SCRIPT_FILENAME}"
readonly CF_API_BASE_URL="https://api.cloudflare.com/client/v4"
readonly WORKER_SOURCE_URL="https://raw.githubusercontent.com/sinaha81/dns/main/worker.js"
readonly CURL_TIMEOUT=20

# --- Color Codes ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_BLUE='\033[0;34m'; C_YELLOW='\033[1;33m';

# --- Utility Functions ---
info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }
warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }

# ==============================================================================
# SECTION 1: SELF-UPDATE LOGIC
# ==============================================================================
handle_self_update() {
    info "Checking for a new version of the installer..."
    local latest_version
    latest_version=$(curl --connect-timeout ${CURL_TIMEOUT} -fsSL "$VERSION_FILE_URL") || {
        warn "Could not fetch the latest version information. Continuing with the current version."
        return
    }

    if [[ "$SCRIPT_VERSION" != "$latest_version" ]]; then
        info "A new version (${C_GREEN}${latest_version}${C_RESET}) is available. Updating from version ${C_YELLOW}${SCRIPT_VERSION}${C_RESET}..."
        mkdir -p "$LOCAL_INSTALL_DIR"
        chmod 700 "$LOCAL_INSTALL_DIR"
        if curl --connect-timeout ${CURL_TIMEOUT} -fsSL -o "$LOCAL_SCRIPT_PATH" "$SELF_SCRIPT_URL"; then
            chmod +x "$LOCAL_SCRIPT_PATH"
            success "Installer updated successfully. Relaunching the new version..."
            echo "--------------------------------------------------------"
            exec "$LOCAL_SCRIPT_PATH" "$@"
        else
            error "Failed to download the new installer version."
        fi
    fi
    info "You are running the latest installer version (${C_GREEN}${SCRIPT_VERSION}${C_RESET})."
}

# ==============================================================================
# SECTION 2: SHELL-BASED JSON PARSING UTILITIES
# ==============================================================================
parse_json_value() {
    local json=$1; local key=$2
    echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\(.[^\"]*\)\".*/\1/p"
}
is_success() {
    echo "$1" | grep -q '"success"[[:space:]]*:[[:space:]]*true'
}
parse_json_array() {
    local json=$1; local key1=$2; local key2=$3
    echo "$json" | tr -d '\n' | tr '{' '\n' | sed 's/\[\|\]//g' | grep "\"${key1}\"" |
    awk -F'"' -v k1="$key1" -v k2="$key2" '{
        id=""; name="";
        for(i=1; i<=NF; i++) {
            if ($(i) == k1) id = $(i+2);
            if ($(i) == k2) name = $(i+2);
        }
        if (id != "" && name != "") print id, name;
    }'
}

# ==============================================================================
# SECTION 3: CORE INSTALLER LOGIC FUNCTIONS
# ==============================================================================

# Checks for dependencies, including the special Termux:API.
ensure_dependencies() {
    info "Checking for required dependencies..."
    command -v curl >/dev/null || error "'curl' is not installed. Please install it first."
    
    # Check if we are in Termux before checking for termux-api
    if [[ -n "${PREFIX-}" ]] && [[ "$PREFIX" == *"/com.termux"* ]]; then
        if ! command -v termux-clipboard-get >/dev/null; then
            warn "'termux-api' package is not installed. It is required for the seamless token experience."
            read -p "Would you like to install it now? (y/N): " choice
            if [[ "$choice" =~ ^[yY]([eE][sS])?$ ]]; then
                pkg install -y termux-api
                # Also check if the Termux:API app is installed
                if ! termux-toast -h &>/dev/null; then
                   warn "Please also install the 'Termux:API' app from F-Droid or the Play Store."
                fi
            else
                error "Please install 'termux-api' (pkg install termux-api) and the Termux:API app, then run this script again."
            fi
        fi
    fi
    success "All dependencies are met."
}

# Guides the user through token creation using their browser and clipboard polling.
prompt_and_verify_token() {
    local api_token=""
    local token_url="https://dash.cloudflare.com/profile/api-tokens/new?name=DNS-Worker-Wizard-$(date +%s)&description=API%20Token%20for%20DNS%20Worker%20Deployment&scope=com.cloudflare.api.account.zone.list&scope=com.cloudflare.api.account.user.read&scope=com.cloudflare.api.account.account.read&scope=com.cloudflare.api.account.workers.subdomain.update&scope=com.cloudflare.api.account.workers.script.update"

    info "The script will now open a browser for you to create a secure API token."
    read -p "Press [ENTER] to open your browser..."

    if command -v termux-open-url >/dev/null; then
        termux-open-url "$token_url"
    else
        warn "Could not find 'termux-open-url'. Please open this link manually:"
        echo -e "${C_YELLOW}${token_url}${C_RESET}"
    fi

    echo
    info "IN YOUR BROWSER:"
    echo "1. Scroll to the bottom and click 'Continue to summary'."
    echo "2. Click 'Create Token'."
    echo -e "3. ${C_YELLOW}Click the 'Copy' button to copy your new API token.${C_RESET}"
    echo
    
    # --- Clipboard Polling Magic ---
    info "Waiting for you to copy the API token to your clipboard..."
    local clipboard_content=""
    local timeout=120 # 2 minutes timeout
    local start_time=$(date +%s)

    while true; do
        if command -v termux-clipboard-get >/dev/null; then
            clipboard_content=$(termux-clipboard-get)
        else
            # Fallback for non-Termux environments
            read -sp "Please paste the copied API token here: " clipboard_content
            break
        fi

        # A Cloudflare API token is typically a 40-char alphanumeric string
        if [[ "${clipboard_content}" =~ ^[a-zA-Z0-9_-]{40}$ ]]; then
            api_token="${clipboard_content}"
            # Clear clipboard for security
            if command -v termux-clipboard-set >/dev/null; then
                termux-clipboard-set ""
            fi
            break
        fi

        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        if [[ $elapsed -ge $timeout ]]; then
            error "Timed out waiting for API token. Please run the script again."
        fi
        
        # Print a waiting indicator without spamming
        echo -n "."
        sleep 2
    done
    echo # Newline after the dots
    
    [[ -z "$api_token" ]] && error "API token was not obtained."
    success "API Token successfully and securely retrieved from clipboard!"
    
    info "Verifying the retrieved API token..."
    local verify_response
    verify_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/user/tokens/verify" -H "Authorization: Bearer ${api_token}")
    
    if ! is_success "$verify_response"; then
        error "The retrieved API token is invalid. Please try again."
    fi
    success "API token verified successfully."
    API_TOKEN="${api_token}"
}

# (The rest of the functions: select_cf_account, ensure_worker_subdomain, deploy_worker remain the same as v2.0.0)
select_cf_account() {
    info "Fetching your Cloudflare accounts..."
    local accounts_response accounts_list account_count
    accounts_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/accounts" -H "Authorization: Bearer ${API_TOKEN}")
    accounts_list=$(parse_json_array "$accounts_response" "id" "name")
    [[ -z "$accounts_list" ]] && error "No accounts found for this API token."
    account_count=$(echo "$accounts_list" | wc -l)
    
    local account_id account_name
    if [[ "$account_count" -eq 1 ]]; then
        account_id=$(echo "$accounts_list" | awk '{print $1}')
        account_name=$(echo "$accounts_list" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
        info "Account '${account_name}' selected automatically."
    else
        info "Multiple accounts found. Please choose one:"
        echo "$accounts_list" | nl -w2 -s'. '
        local choice selection
        read -p "Enter the number of the account you want to use: " choice
        selection=$(echo "$accounts_list" | sed -n "${choice}p")
        [[ -z "$selection" ]] && error "Invalid selection."
        account_id=$(echo "$selection" | awk '{print $1}')
        account_name=$(echo "$selection" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
        success "Account '${account_name}' selected."
    fi
    ACCOUNT_ID="${account_id}"
}

ensure_worker_subdomain() {
    info "Checking for a workers.dev subdomain..."
    local subdomain_response worker_subdomain
    subdomain_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/subdomain" -H "Authorization: Bearer ${API_TOKEN}")
    worker_subdomain=$(parse_json_value "$subdomain_response" "subdomain")

    if [[ -n "$worker_subdomain" && "$worker_subdomain" != "null" ]]; then
        success "Your subdomain is '${worker_subdomain}'."
    else
        warn "You have not set up a workers.dev subdomain yet."
        local new_subdomain
        read -p "Enter a name for your new subdomain (e.g., my-space): " new_subdomain
        [[ -z "$new_subdomain" ]] && error "Subdomain name cannot be empty."
        
        info "Creating subdomain '${new_subdomain}.workers.dev'..."
        local create_response
        create_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X PUT "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/subdomain" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"subdomain\": \"$new_subdomain\"}")
        if is_success "$create_response"; then
            worker_subdomain=$(parse_json_value "$create_response" "subdomain")
            success "Subdomain '${worker_subdomain}' created successfully."
        else
            error "Failed to create subdomain: $(parse_json_value "$create_response" "message")"
        fi
    fi
    WORKER_SUBDOMAIN="${worker_subdomain}"
}

deploy_worker() {
    local worker_name=$1
    info "Downloading worker script and preparing for deployment..."
    local worker_code
    worker_code=$(curl --connect-timeout ${CURL_TIMEOUT} -sL "$WORKER_SOURCE_URL")
    [[ -z "$worker_code" ]] && error "Failed to download worker code from ${WORKER_SOURCE_URL}."
    
    info "Deploying worker '${worker_name}'..."
    local deploy_response http_code response_body
    deploy_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -w "\n%{http_code}" -X PUT "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/scripts/${worker_name}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/javascript" \
        --data-binary "$worker_code")
    
    http_code=$(echo "$deploy_response" | tail -n1)
    response_body=$(echo "$deploy_response" | sed '$d')

    if [[ "$http_code" -eq 200 ]] && is_success "$response_body"; then
        success "Worker '${worker_name}' deployed successfully."
    else
        local error_msg
        error_msg=$(parse_json_value "$response_body" "message")
        [[ -z "$error_msg" ]] && error_msg="Unknown API error"
        error "Worker deployment failed (HTTP code: ${http_code}). Message: ${error_msg}"
    fi
}

# ==============================================================================
# SECTION 4: MAIN INSTALLER WORKFLOW
# ==============================================================================
run_installer_workflow() {
    clear
    echo -e "${C_YELLOW}=======================================================${C_RESET}"
    echo -e "${C_YELLOW}  Cloudflare DNS Worker Installer (v${SCRIPT_VERSION})      ${C_RESET}"
    echo -e "${C_YELLOW}=======================================================${C_RESET}"
    echo
    
    ensure_dependencies
    echo
    prompt_and_verify_token
    echo
    select_cf_account
    echo
    
    local worker_name
    read -p "Enter a name for your new worker (e.g., my-dns-worker): " worker_name
    [[ -z "$worker_name" ]] && error "Worker name cannot be empty."
    worker_name=$(echo "$worker_name" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
    info "Worker name set to '${worker_name}'."
    echo
    
    ensure_worker_subdomain
    echo

    warn "You are about to deploy a worker with the following details:"
    echo -e "  Worker Name:  ${C_GREEN}${worker_name}${C_RESET}"
    echo -e "  Final URL:    ${C_GREEN}https://${worker_name}.${WORKER_SUBDOMAIN}${C_RESET}"
    read -p "Are you sure you want to proceed? (y/N): " confirmation
    if [[ ! "$confirmation" =~ ^[yY]([eE][sS])?$ ]]; then
        info "Operation cancelled by user."
        exit 0
    fi
    echo

    deploy_worker "${worker_name}"
    
    unset API_TOKEN

    local worker_url="https://${worker_name}.${WORKER_SUBDOMAIN}"
    echo
    success "======================================================="
    success "  Deployment Completed Successfully!                   "
    success "======================================================="
    echo
    info "Your DNS worker is now active and available."
    echo -e "Your Worker URL: ${C_YELLOW}${worker_url}${C_RESET}"
    echo
    info "You can use this URL for your DNS-over-HTTPS (DoH) settings."
    echo
}

# ==============================================================================
# SECTION 5: SCRIPT ENTRY POINT
# ==============================================================================
main() {
    trap 'echo -e "\n\n${C_RED}Operation aborted by user.${C_RESET}"; exit 130' INT

    if [[ "${1-}" == "--version" ]]; then
        echo "$SCRIPT_VERSION"
        exit 0
    fi
    
    API_TOKEN=""
    ACCOUNT_ID=""
    WORKER_SUBDOMAIN=""

    handle_self_update "$@"
    run_installer_workflow "$@"
}

main "$@"
