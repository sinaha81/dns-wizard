#!/bin/bash

# ==============================================================================
#
# Cloudflare DNS Worker - Unified Smart Installer & Updater
# Version: 1.4.0
#
# This script intelligently self-updates and then installs the DNS worker.
# Author: Your Name/Alias & AI Thought Partner
#
# v1.4.0 Changes:
#   - Added smart dependency handler to auto-install 'jq' if missing.
#   - Full translation of all prompts, messages, and comments to English.
#
# ==============================================================================

# --- Bash Strict Mode ---
# -e: exit immediately if a command exits with a non-zero status.
# -u: treat unset variables as an error when substituting.
# -o pipefail: the return value of a pipeline is the status of the last command to exit with a non-zero status.
set -euo pipefail

# --- Script Configuration ---
readonly SCRIPT_VERSION="1.4.0"
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
readonly CURL_TIMEOUT=15 # 15-second timeout for network requests

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
# SECTION 2: CORE INSTALLER LOGIC FUNCTIONS
# ==============================================================================

# Checks for dependencies and offers to install 'jq' if missing.
ensure_dependencies() {
    info "Checking for required dependencies..."
    command -v curl >/dev/null || error "'curl' is not installed. Please install it first."

    if command -v jq >/dev/null; then
        success "'curl' and 'jq' are installed."
        return
    fi

    warn "'jq' is not installed, but it is required to continue."
    read -p "Would you like to attempt an automatic installation? (y/N): " choice
    if [[ ! "$choice" =~ ^[yY]([eE][sS])?$ ]]; then
        error "Please install 'jq' manually and run this script again."
    fi

    info "Attempting to install 'jq'..."
    if command -v apt-get >/dev/null; then
        sudo apt-get update && sudo apt-get install -y jq
    elif command -v yum >/dev/null; then
        sudo yum install -y jq
    elif command -v dnf >/dev/null; then
        sudo dnf install -y jq
    elif command -v pacman >/dev/null; then
        sudo pacman -S --noconfirm jq
    elif command -v apk >/dev/null; then
        sudo apk add jq
    elif command -v brew >/dev/null; then
        brew install jq
    else
        error "Could not detect a supported package manager (apt, yum, dnf, pacman, apk, brew). Please install 'jq' manually."
    fi

    command -v jq >/dev/null || error "Automatic installation of 'jq' failed. Please install it manually."
    success "'jq' has been successfully installed."
}

# Prompts for and validates the Cloudflare API token.
prompt_and_verify_token() {
    local api_token=""
    info "A Cloudflare API token with 'Workers Scripts:Edit' permission is required."
    info "Create one here: ${C_YELLOW}https://dash.cloudflare.com/profile/api-tokens${C_RESET}"
    read -sp "Please enter your Cloudflare API token: " api_token
    echo # Newline after silent input
    [[ -z "$api_token" ]] && error "API token cannot be empty."
    
    info "Verifying API token..."
    local verify_response
    verify_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/user/tokens/verify" -H "Authorization: Bearer ${api_token}")
    if ! echo "$verify_response" | jq -e '.success' &>/dev/null; then
        local error_msg
        error_msg=$(echo "$verify_response" | jq -r '.errors[0].message' 2>/dev/null || echo "Invalid API response")
        error "API token is invalid. Cloudflare message: ${error_msg}"
    fi
    success "API token verified successfully."
    API_TOKEN="${api_token}"
}

# Selects a Cloudflare account.
select_cf_account() {
    info "Fetching your Cloudflare accounts..."
    local accounts_response account_count
    accounts_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/accounts" -H "Authorization: Bearer ${API_TOKEN}")
    account_count=$(echo "$accounts_response" | jq '.result | length')

    [[ "$account_count" -eq 0 ]] && error "No accounts found for this API token."
    
    local account_id account_name
    if [[ "$account_count" -eq 1 ]]; then
        account_id=$(echo "$accounts_response" | jq -r '.result[0].id')
        account_name=$(echo "$accounts_response" | jq -r '.result[0].name')
        info "Account '${account_name}' selected automatically."
    else
        info "Multiple accounts found. Please choose one:"
        echo "$accounts_response" | jq -r '.result[] | "\(.id) \(.name)"' | nl -w2 -s'. '
        local choice
        read -p "Enter the number of the account you want to use: " choice
        account_id=$(echo "$accounts_response" | jq -r ".result[$((choice-1))].id")
        account_name=$(echo "$accounts_response" | jq -r ".result[$((choice-1))].name")
        [[ "$account_id" == "null" || -z "$account_id" ]] && error "Invalid selection."
        success "Account '${account_name}' selected."
    fi
    ACCOUNT_ID="${account_id}"
}

# Ensures a workers.dev subdomain is available.
ensure_worker_subdomain() {
    info "Checking for a workers.dev subdomain..."
    local subdomain_response worker_subdomain
    subdomain_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X GET "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/subdomain" -H "Authorization: Bearer ${API_TOKEN}")
    worker_subdomain=$(echo "$subdomain_response" | jq -r '.result.subdomain')

    if [[ "$worker_subdomain" != "null" && -n "$worker_subdomain" ]]; then
        success "Your subdomain is '${worker_subdomain}'."
    else
        warn "You have not set up a workers.dev subdomain yet."
        local new_subdomain
        read -p "Enter a name for your new subdomain (e.g., my-space): " new_subdomain
        [[ -z "$new_subdomain" ]] && error "Subdomain name cannot be empty."
        
        info "Creating subdomain '${new_subdomain}.workers.dev'..."
        local create_response
        create_response=$(curl --connect-timeout ${CURL_TIMEOUT} -s -X PUT "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/subdomain" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"subdomain\": \"$new_subdomain\"}")
        if echo "$create_response" | jq -e '.success' &>/dev/null; then
            worker_subdomain=$(echo "$create_response" | jq -r '.result.subdomain')
            success "Subdomain '${worker_subdomain}' created successfully."
        else
            error "Failed to create subdomain: $(echo "$create_response" | jq -r '.errors[0].message')"
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

    if [[ "$http_code" -eq 200 ]] && echo "$response_body" | jq -e '.success' &>/dev/null; then
        success "Worker '${worker_name}' deployed successfully."
    else
        local error_msg
        error_msg=$(echo "$response_body" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown API error")
        error "Worker deployment failed (HTTP code: ${http_code}). Message: ${error_msg}"
    fi
}

# ==============================================================================
# SECTION 3: MAIN INSTALLER WORKFLOW
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

    # --- Final Confirmation Step ---
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
    
    # Unset the sensitive variable
    unset API_TOKEN

    # --- Final Success Message ---
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
# SECTION 4: SCRIPT ENTRY POINT
# ==============================================================================
main() {
    # Handle Ctrl+C gracefully
    trap 'echo -e "\n\n${C_RED}Operation aborted by user.${C_RESET}"; exit 130' INT

    if [[ "${1-}" == "--version" ]]; then
        echo "$SCRIPT_VERSION"
        exit 0
    fi
    
    # Global variables to be populated by functions
    API_TOKEN=""
    ACCOUNT_ID=""
    WORKER_SUBDOMAIN=""

    handle_self_update "$@"
    run_installer_workflow "$@"
}

main "$@"
