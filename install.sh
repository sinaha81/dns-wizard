#!/bin/bash

# ==============================================================================
#
# DNS Worker Wizard - Launcher Script
# Version: 3.0.0
#
# This script detects the user's OS and architecture, downloads the
# appropriate compiled binary from GitHub Releases, and executes it.
#
# ==============================================================================

set -e

# --- Configuration ---
readonly REPO_USER="sinaha81"
# نام ریپازیتوری که برنامه Go و Release را در آن قرار دادید
readonly REPO_NAME="dns-wizard" 
readonly BINARY_NAME="dns-wizard"

# --- Color Codes ---
C_RESET='\033[0m'; C_RED='\033[0;31m'; C_GREEN='\033[0;32m'; C_BLUE='\033[0;34m';

info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $1" >&2; exit 1; }

# --- Main Logic ---
main() {
    # 1. Detect OS and Architecture
    local os_name
    os_name=$(uname -s | tr '[:upper:]' '[:lower:]')

    local arch_name
    case "$(uname -m)" in
        aarch64|arm64) arch_name="arm64" ;;
        x86_64|amd64)  arch_name="amd64" ;;
        armv7*)        arch_name="arm" ;;
        *)             error "Unsupported architecture: $(uname -m)" ;;
    esac
    
    # Check for Linux (required for Termux and most servers)
    if [[ "$os_name" != "linux" ]]; then
        error "This installation method is currently only supported on Linux-based systems."
    fi

    # 2. Determine Asset URL from GitHub Releases
    info "Detecting latest version..."
    # از API گیت‌هاب برای پیدا کردن آخرین نسخه استفاده می‌کنیم
    local latest_version
    latest_version=$(curl -s "https://api.github.com/repos/${REPO_USER}/${REPO_NAME}/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    
    if [[ -z "$latest_version" ]]; then
        error "Could not determine the latest version. Please check the repository."
    fi
    info "Latest version is ${latest_version}"

    local asset_filename="${BINARY_NAME}-${os_name}-${arch_name}"
    local download_url="https://github.com/${REPO_USER}/${REPO_NAME}/releases/download/${latest_version}/${asset_filename}"
    local install_path="/data/data/com.termux/files/usr/bin/${BINARY_NAME}"

    # 3. Download and Install
    info "Downloading ${asset_filename} from GitHub..."
    # از curl برای دانلود مستقیم به مسیر نصب استفاده می‌کنیم
    if curl -L -o "${install_path}" "${download_url}"; then
        info "Download complete."
    else
        error "Download failed. Please check your connection or the release assets."
    fi

    # 4. Make it executable
    chmod +x "${install_path}"
    info "Installation complete. The wizard is now installed as '${BINARY_NAME}' command."
    
    # 5. Execute the wizard
    info "Launching the wizard..."
    echo "--------------------------------------------------------"
    exec "${BINARY_NAME}"
}

main "$@"
