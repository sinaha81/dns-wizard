#!/bin/bash

# ==============================================================================
#
# Cloudflare DNS Worker - Unified Smart Installer & Updater
#
# این اسکریپت به صورت هوشمند خود را به‌روزرسانی کرده و سپس ورکر DNS را نصب می‌کند.
# Author: Your Name/Alias
#
# ==============================================================================

# --- پیکربندی اسکریپت ---
# این شماره نسخه باید با محتوای فایل VERSION در ریپازیتوری برای هر آپدیت جدید، یکسان شود.
SCRIPT_VERSION="1.2.0"

# اطلاعات ریپازیتوری شما در گیت‌هاب
REPO_USER="sinaha81"
REPO_NAME="dns-installer" # نام ریپازیتوری که این اسکریپت‌ها را در آن قرار می‌دهید
BRANCH_NAME="main"
SCRIPT_FILENAME="install.sh" # نام همین فایل در ریپازیتوری

# آدرس‌های کامل فایل‌ها
REPO_RAW_URL="https://raw.githubusercontent.com/${REPO_USER}/${REPO_NAME}/${BRANCH_NAME}"
VERSION_FILE_URL="${REPO_RAW_URL}/VERSION"
SELF_SCRIPT_URL="${REPO_RAW_URL}/${SCRIPT_FILENAME}"

# مسیر نصب محلی اسکریپت برای به‌روزرسانی‌های آینده
LOCAL_INSTALL_DIR="${HOME}/.dns-worker-installer"
LOCAL_SCRIPT_PATH="${LOCAL_INSTALL_DIR}/${SCRIPT_FILENAME}"

# --- متغیرهای سراسری برای نصب ---
CF_API_BASE_URL="https://api.cloudflare.com/client/v4"
WORKER_SOURCE_URL="https://raw.githubusercontent.com/sinaha81/dns/main/worker.js"
API_TOKEN=""
ACCOUNT_ID=""
WORKER_NAME=""
WORKER_SUBDOMAIN=""

# --- رنگ‌ها برای خروجی بهتر ---
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_BLUE='\033[0;34m'
C_YELLOW='\033[1;33m'
C_CYAN='\033[0;36m'

# --- توابع ابزاری ---
info() { echo -e "${C_BLUE}[INFO]${C_RESET} $1"; }
success() { echo -e "${C_GREEN}[SUCCESS]${C_RESET} $1"; }
error() { echo -e "${C_RED}[ERROR]${C_RESET} $1"; exit 1; }
warn() { echo -e "${C_YELLOW}[WARNING]${C_RESET} $1"; }

# ==============================================================================
# بخش ۱: منطق به‌روزرسانی خودکار
# ==============================================================================
handle_self_update() {
    info "بررسی برای نسخه جدید نصب‌کننده..."
    LATEST_VERSION=$(curl -fsSL "$VERSION_FILE_URL")
    if [ -z "$LATEST_VERSION" ]; then
        warn "دریافت اطلاعات آخرین نسخه با مشکل مواجه شد. با نسخه فعلی ادامه می‌دهیم."
        return
    fi

    # اگر نسخه فعلی با آخرین نسخه متفاوت است، خود را آپدیت کن
    if [ "$SCRIPT_VERSION" != "$LATEST_VERSION" ]; then
        info "نسخه جدیدی (${C_GREEN}${LATEST_VERSION}${C_RESET}) موجود است. در حال به‌روزرسانی از نسخه ${C_YELLOW}${SCRIPT_VERSION}${C_RESET}..."
        
        mkdir -p "$LOCAL_INSTALL_DIR"
        
        # دانلود آخرین نسخه از خود اسکریپت
        if curl -fsSL -o "$LOCAL_SCRIPT_PATH" "$SELF_SCRIPT_URL"; then
            chmod +x "$LOCAL_SCRIPT_PATH"
            success "نصب‌کننده با موفقیت به‌روزرسانی شد. در حال اجرای نسخه جدید..."
            echo "--------------------------------------------------------"
            # اجرای نسخه جدید و خروج از اسکریپت فعلی
            exec "$LOCAL_SCRIPT_PATH" "$@"
        else
            error "دانلود نسخه جدید نصب‌کننده با شکست مواجه شد."
        fi
    fi
    info "شما در حال حاضر آخرین نسخه (${C_GREEN}${SCRIPT_VERSION}${C_RESET}) را در اختیار دارید."
}

# ==============================================================================
# بخش ۲: منطق اصلی نصب ورکر
# ==============================================================================
run_installer() {
    trap 'echo -e "\n${C_RED}عملیات توسط کاربر لغو شد.${C_RESET}"; exit 1' INT
    
    clear
    echo -e "${C_CYAN}=======================================================${C_RESET}"
    echo -e "${C_CYAN}  Cloudflare DNS Worker Installer (v${SCRIPT_VERSION})      ${C_RESET}"
    echo -e "${C_CYAN}=======================================================${C_RESET}"
    echo
    info "این اسکریپت به شما کمک می‌کند تا ورکر DNS را بر روی حساب Cloudflare خود نصب کنید."
    info "لطفاً مراحل را با دقت دنبال کنید."
    echo

    # --- بررسی ابزارهای مورد نیاز ---
    info "در حال بررسی ابزارهای مورد نیاز (curl و jq)..."
    if ! command -v curl &> /dev/null; then error "ابزار 'curl' یافت نشد. لطفاً آن را نصب کنید. در Termux: pkg install curl"; fi
    if ! command -v jq &> /dev/null; then error "ابزار 'jq' یافت نشد. لطفاً آن را نصب کنید. در Termux: pkg install jq"; fi
    success "تمام ابزارهای مورد نیاز نصب هستند."
    echo

    # --- دریافت و اعتبارسنجی توکن API ---
    info "برای ادامه، به یک توکن API از Cloudflare با دسترسی ویرایش 'Workers Scripts' نیاز داریم."
    info "لینک ساخت توکن: ${C_YELLOW}https://dash.cloudflare.com/profile/api-tokens${C_RESET}"
    read -p "لطفاً توکن API خود را وارد کنید: " API_TOKEN
    [ -z "$API_TOKEN" ] && error "توکن API نمی‌تواند خالی باشد."
    
    info "در حال اعتبارسنجی توکن API..."
    local verify_response
    verify_response=$(curl -s -X GET "${CF_API_BASE_URL}/user/tokens/verify" -H "Authorization: Bearer ${API_TOKEN}")
    if ! echo "$verify_response" | jq -e '.success' &> /dev/null; then
        local error_msg=$(echo "$verify_response" | jq -r '.errors[0].message' 2>/dev/null || echo "Unknown error")
        error "توکن API نامعتبر است. پیام کلادفلر: ${error_msg}"
    fi
    success "توکن API با موفقیت اعتبارسنجی شد."
    echo

    # --- انتخاب حساب کاربری ---
    info "در حال دریافت لیست حساب‌های Cloudflare..."
    local accounts_response
    accounts_response=$(curl -s -X GET "${CF_API_BASE_URL}/accounts" -H "Authorization: Bearer ${API_TOKEN}")
    local account_count=$(echo "$accounts_response" | jq '.result | length')

    if [ "$account_count" -eq 0 ]; then error "هیچ حسابی در این توکن یافت نشد."; fi
    if [ "$account_count" -eq 1 ]; then
        ACCOUNT_ID=$(echo "$accounts_response" | jq -r '.result[0].id')
        info "حساب '$(echo "$accounts_response" | jq -r '.result[0].name')' به صورت خودکار انتخاب شد."
    else
        info "چندین حساب یافت شد. لطفاً یکی را انتخاب کنید:"
        echo "$accounts_response" | jq -r '.result[] | "\(.id) \(.name)"' | nl -w2 -s'. '
        read -p "شماره حساب مورد نظر را وارد کنید: " choice
        ACCOUNT_ID=$(echo "$accounts_response" | jq -r ".result[${choice}-1].id")
        [ "$ACCOUNT_ID" == "null" ] || [ -z "$ACCOUNT_ID" ] && error "انتخاب نامعتبر."
        success "حساب '$(echo "$accounts_response" | jq -r ".result[${choice}-1].name")' انتخاب شد."
    fi
    echo

    # --- دریافت نام ورکر ---
    read -p "یک نام برای ورکر جدید خود وارد کنید (مثال: my-dns-worker): " WORKER_NAME
    [ -z "$WORKER_NAME" ] && error "نام ورکر نمی‌تواند خالی باشد."
    WORKER_NAME=$(echo "$WORKER_NAME" | tr '[:upper:]' '[:lower:]' | tr -s ' ' '-' | sed 's/[^a-z0-9-]//g')
    info "نام ورکر به '${WORKER_NAME}' تنظیم شد."
    echo

    # --- بررسی و ایجاد زیردامنه ---
    info "در حال بررسی زیردامنه workers.dev..."
    local subdomain_response
    subdomain_response=$(curl -s -X GET "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/subdomain" -H "Authorization: Bearer ${API_TOKEN}")
    WORKER_SUBDOMAIN=$(echo "$subdomain_response" | jq -r '.result.subdomain')

    if [ "$WORKER_SUBDOMAIN" != "null" ] && [ -n "$WORKER_SUBDOMAIN" ]; then
        success "زیردامنه شما '${WORKER_SUBDOMAIN}' است."
    else
        warn "شما هنوز زیردامنه workers.dev را تنظیم نکرده‌اید."
        read -p "یک نام برای زیردامنه خود وارد کنید (مثال: my-space): " new_subdomain
        [ -z "$new_subdomain" ] && error "نام زیردامنه نمی‌تواند خالی باشد."
        
        info "در حال ایجاد زیردامنه '${new_subdomain}.workers.dev'..."
        local create_response
        create_response=$(curl -s -X PUT "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/subdomain" -H "Authorization: Bearer ${API_TOKEN}" -H "Content-Type: application/json" --data "{\"subdomain\": \"$new_subdomain\"}")
        if echo "$create_response" | jq -e '.success' &> /dev/null; then
            WORKER_SUBDOMAIN=$(echo "$create_response" | jq -r '.result.subdomain')
            success "زیردامنه '${WORKER_SUBDOMAIN}' با موفقیت ایجاد شد."
        else
            error "خطا در ایجاد زیردامنه: $(echo "$create_response" | jq -r '.errors[0].message')"
        fi
    fi
    echo

    # --- استقرار ورکر ---
    info "در حال دانلود کد ورکر و استقرار آن..."
    local worker_code
    worker_code=$(curl -sL "$WORKER_SOURCE_URL")
    [ -z "$worker_code" ] && error "دانلود کد ورکر از ${WORKER_SOURCE_URL} با شکست مواجه شد."
    
    local deploy_response
    deploy_response=$(curl -s -w "\n%{http_code}" -X PUT "${CF_API_BASE_URL}/accounts/${ACCOUNT_ID}/workers/scripts/${WORKER_NAME}" \
        -H "Authorization: Bearer ${API_TOKEN}" \
        -H "Content-Type: application/javascript" \
        --data-binary "$worker_code")
    
    local http_code=$(echo "$deploy_response" | tail -n1)
    local response_body=$(echo "$deploy_response" | sed '$d')

    if [ "$http_code" -eq 200 ] && echo "$response_body" | jq -e '.success' &> /dev/null; then
        success "ورکر '${WORKER_NAME}' با موفقیت استقرار یافت."
    else
        error "استقرار ورکر با شکست مواجه شد: $(echo "$response_body" | jq -r '.errors[0].message')"
    fi
    echo

    # --- نمایش پیام پایانی ---
    local worker_url="https://${WORKER_NAME}.${WORKER_SUBDOMAIN}"
    echo -e "${C_GREEN}=======================================================${C_RESET}"
    echo -e "${C_GREEN}  نصب با موفقیت انجام شد!                             ${C_RESET}"
    echo -e "${C_GREEN}=======================================================${C_RESET}"
    echo
    info "ورکر DNS شما اکنون فعال و در دسترس است."
    echo -e "آدرس ورکر شما: ${C_YELLOW}${worker_url}${C_RESET}"
    echo
    info "می‌توانید از این آدرس برای تنظیمات DNS-over-HTTPS (DoH) استفاده کنید."
    echo
}

# ==============================================================================
# بخش ۳: نقطه شروع اصلی برنامه
# ==============================================================================
main() {
    # مدیریت آرگومان‌های ورودی مانند --version یا --help
    if [[ "$1" == "--version" ]]; then
        echo "$SCRIPT_VERSION"
        exit 0
    elif [[ "$1" == "--help" ]]; then
        echo "Cloudflare DNS Worker Installer v${SCRIPT_VERSION}"
        echo "Usage: bash <(curl -fsSL <URL_TO_THIS_SCRIPT>)"
        echo "This script interactively helps you deploy a DNS worker to your Cloudflare account."
        exit 0
    fi

    # ابتدا خود را آپدیت کن
    handle_self_update
    
    # سپس منطق اصلی نصب را اجرا کن
    run_installer
}

# اجرای برنامه با تمام آرگومان‌های ارسال شده
main "$@"
