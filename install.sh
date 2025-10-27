#!/bin/bash

# ==============================================================================
#
# Cloudflare DNS Worker - Unified Smart Installer & Updater
# Version: 2.0.0
#
# This script intelligently self-updates and then installs the DNS worker.
# It is fully self-contained with no external dependencies like 'jq'.
# It features a semi-automated, browser-based token acquisition flow for Termux.
#
# Author: Your Name/Alias & AI Thought Partner
#
# v2.0.0 Major Changes:
#   - Removed 'jq' dependency entirely. JSON parsing is now handled by internal
#     shell functions using grep, sed, and awk for maximum portability.
#   - Implemented a semi-automated token flow that opens the Cloudflare token
#     creation page directly in the user's browser (optimized for Termux).
#
# ==============================================================================

# --- Bash Strict Mode ---
set -euo pipefail

# --- Script Configuration ---
readonly SCRIPT_VERSION="2.0.0"
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

    if [[ "$SCRIPT_VERSION" != "$latest_version" ]];
    then
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
# SECTION 2: SHELL-BASED JSON PARSING UTILITIES (jq REPLACEMENT)
# ==============================================================================

# Parses a simple key-value from a JSON string.
# Usage: parse_json_value <json_string> <key>
parse_json_value() {
    local json=$1
    local key=$2
    # This regex looks for the key, then captures the value inside the quotes.
    # It handles potential whitespace and colons.
    echo "$json" | sed -n "s/.*\"${key}\"[[:space:]]*:[[:space:]]*\"\(.[^\"]*\)\".*/\1/p"
}

# Checks if the "success" field in a JSON response is true.
# Usage: is_success <json_string>
is_success() {
    local json=$1
    # Grep for "success":true, ignoring whitespace.
    echo "$json" | grep -q '"success"[[:space:]]*:[[:space:]]*true'
}

# Parses an array of objects and returns a formatted list of two specified keys.
# Usage: parse_json_array <json_string> <key1> <key2>
parse_json_array() {
    local json=$1
    local key1=$2
    local key2=$3
    # Use awk to process the JSON line by line.
    # This is a robust way to handle multi-line formatted JSON.
    echo "$json" | tr -d '\n' | tr '{' '\n' | \
    sed 's/\[//g; s/\]//g' | \
    grep "\"${key1}\"" | \
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

# Checks for dependencies.
ensure_dependencies() {
    info "Checking for required dependencies..."
    command -v curl >/dev/null || error "'curl' is not installed. Please install it first."
    # No jq check needed anymore!
    success "All dependencies are met."
}

# Guides the user through token creation using their browser.
prompt_and_verify_token() {
    local api_token=""
    # This URL pre-fills the token creation form with the exact permissions needed.
    local token_url="https://dash.cloudflare.com/profile/api-tokens/new?name=DNS-Worker-Wizard&description=API%20Token%20for%20DNS%20Worker%20Deployment&scope=com.cloudflare.api.account.zone.list&scope=com.cloudflare.api.account.user.read&scope=com.cloudflare.api.account.account.read&scope=com.cloudflare.api.account.workers.subdomain.update&scope=com.cloudflare.api.account.workers.script.update"

    info "The script will now open a browser for you to create a secure API token."
    warn "If the browser does not open, please manually copy the URL below."
    echo -e "${C_YELLOW}${token_url}${C_RESET}"
    echo
    read -p "Press [ENTER] to continue..."

    # Use termux-open-url if available, otherwise suggest manual opening.
    if command -v termux-open-url >/dev/null; then
        termux-open-url "$token_url"
    else
        warn "Could not find 'termux-open-url'. Please open the link manually."
    fi

    echo
    info "IN YOUR BROWSER:"
    echo "1. Scroll to the bottom of the Cloudflare page."
    echo "2. Click the 'Continue to summary' button."
    echo "3. Click the 'Create Token' button."
    echo "4. Click the 'Copy' button to copy your new API token."
    echo
    
    read -sp "Please paste the copied API token here: " api_token
    echo
    [[ -z "$api_token" ]] && error "API token cannot be empty."
    
    info "Verifying API token..."
    local verify_response
    verify_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/user/tokens/verify" -H "Authorization: Bearer ${api_token}")
    
    if ! is_success "$verify_response"; then
        local error_msg
        error_msg=$(parse_json_value "$verify_response" "message")
        [[ -z "$error_msg" ]] && error_msg="Invalid API response"
        error "API token is invalid. Cloudflare message: ${error_msg}"
    fi
    success "API token verified successfully."
    API_TOKEN="${api_token}"
}

# Selects a Cloudflare account.
select_cf_account() {
    info "Fetching your Cloudflare accounts..."
    local accounts_response
    accounts_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/accounts" -H "Authorization: Bearer ${API_TOKEN}")
    
    local accounts_list
    accounts_list=$(parse_json_array "$accounts_response" "id" "name")
    [[ -z "$accounts_list" ]] && error "No accounts found for this API token."

    local account_count
    account_count=$(echo "$accounts_list" | wc -l)
    
    local account_id account_name
    if [[ "$account_count" -eq 1 ]]; then
        account_id=$(echo "$accounts_list" | awk '{print $1}')
        account_name=$(echo "$accounts_list" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
        info "Account '${account_name}' selected automatically."
    else
        info "Multiple accounts found. Please choose one:"
        echo "$accounts_list" | nl -w2 -s'. '
        local choice
        read -p "Enter the number of the account you want to use: " choice
        
        local selection
        selection=$(echo "$accounts_list" | sed -n "${choice}p")
        [[ -z "$selection" ]] && error "Invalid selection."

        account_id=$(echo "$selection" | awk '{print $1}')
        account_name=$(echo "$selection" | awk '{$1=""; print $0}' | sed 's/^[ \t]*//')
        success "Account '${account_name}' selected."
    fi
    ACCOUNT_ID="${account_id}"
}

# Ensures a workers.dev subdomain is available.
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

# Deploys the worker script.
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
