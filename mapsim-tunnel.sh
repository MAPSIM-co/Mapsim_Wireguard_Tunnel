#!/bin/bash

# تعریف رنگ‌های چاپ متن در ترمینال برای زیباتر کردن خروجی و تفکیک پیام‌ها
RED='\033[0;31m'      # رنگ قرمز برای پیام‌های خطا
GREEN='\033[0;32m'    # رنگ سبز برای پیام‌های موفقیت
YELLOW='\033[1;33m'   # رنگ زرد برای پیام‌های هشدار
BLUE='\033[0;34m'     # رنگ آبی برای پیام‌های اطلاعاتی
CYAN='\033[0;36m'     # رنگ فیروزه‌ای برای بخش‌های مختلف منو و جداول
MAGENTA='\033[0;35m'  # رنگ بنفش برای عنوان‌ها و خطوط جداکننده
NC='\033[0m'          # ریست رنگ به حالت عادی (No Color)

# ==============================================
# Configuration - تنظیمات اولیه و متغیرهای پایه اسکریپت
# ==============================================

WG_INTERFACE="wg1"                     # نام اینترفیس WireGuard که ساخته و مدیریت می‌شود (مثلاً wg1)
WG_PORT="21301"                        # پورتی که WireGuard روی آن گوش می‌دهد (UDP)
WG_NETWORK="10.100.100.0/24"          # رنج آی‌پی داخلی که تونل WireGuard استفاده می‌کند (شبکه خصوصی)
Main_IP="10.100.100.1"                # آی‌پی اختصاصی اینترفیس ایران داخل رنج بالا (آدرس سرور ایران در شبکه WireGuard)

PEERS_FILE="/etc/wireguard/peers.json"           # مسیر فایل JSON که اطلاعات سرورهای خارجی (همتاها) در آن ذخیره می‌شود
CONFIG_BACKUP_DIR="/etc/wireguard/backups"       # پوشه‌ای برای نگهداری نسخه‌های پشتیبان (بکاپ) فایل‌های کانفیگ WireGuard

MTU_SIZE="1420"                      # تنظیمات MTU (Maximum Transmission Unit) برای اینترفیس WireGuard - معمولاً برای بهینه‌سازی شبکه
PERSISTENT_KEEPALIVE="25"            # مدت زمان (ثانیه) برای ارسال پیام‌های keepalive به همتاها (برای حفظ اتصال حتی زمانی که بدون ترافیک هستند)

DEFAULT_SSH_PORT="22"                # پورت پیش‌فرض SSH برای اتصال به سرورهای خارجی
DEFAULT_SSH_USER="root"              # نام کاربری پیش‌فرض SSH برای اتصال به سرورهای خارجی

Main_PUBLIC_IP_FILE="/etc/wireguard/Main_public_ip.txt"  # فایلی که آی‌پی پابلیک (خارجی) سرور ایران را ذخیره می‌کند (برای استفاده در تنظیمات تونل)
IP="0.0.0.0" # مقدار پیش فرض
Main_PORT_FILE="/etc/wireguard/Main_port.txt"
# ==============================================
# Initialize system
# ==============================================

# تابع اصلی برای آماده‌سازی سیستم قبل از شروع کار اسکریپت
init() {
    check_root           # بررسی اینکه اسکریپت با دسترسی root اجرا شده باشد
    install_dependencies # نصب بسته‌ها و ابزارهای مورد نیاز برای اجرای تونل WireGuard
    init_filesystem      # آماده‌سازی پوشه‌ها و فایل‌های مورد نیاز (مثل فایل peers.json و پوشه بکاپ)
}

# بررسی اینکه کاربر فعلی root باشد
check_root() {
    # اگر شناسه کاربری فعلی (EUID) برابر ۰ نبود (یعنی root نیست)
    # پیغام خطا می‌دهد و اسکریپت را متوقف می‌کند
    [[ $EUID -ne 0 ]] && msg error "This script must be run as root!" && exit 1
}

# تابع کمکی برای چاپ پیام‌های رنگی با آیکون
msg() {
    local type="$1"; shift
    case "$type" in
        error)   echo -e "${RED}✗ ERROR: $*${NC}" >&2 ;;    # پیام خطا با رنگ قرمز و علامت ✗
        success) echo -e "${GREEN}✓ SUCCESS: $*${NC}" ;;    # پیام موفقیت با رنگ سبز و علامت ✓
        info)    echo -e "${BLUE}ℹ INFO: $*${NC}" ;;       # پیام اطلاع‌رسانی با رنگ آبی و علامت ℹ
        warn)    echo -e "${YELLOW}⚠ WARNING: $*${NC}" ;;   # پیام هشدار با رنگ زرد و علامت ⚠
    esac
}

# آماده‌سازی ساختار پوشه و فایل‌ها قبل از اجرا
init_filesystem() {
    mkdir -p "$CONFIG_BACKUP_DIR"   # ساخت پوشه برای نگهداری بکاپ‌های کانفیگ WireGuard (اگر وجود نداشته باشد)
    # اگر فایل peers.json وجود نداشت، یک آرایه JSON خالی در آن ایجاد کن
    [[ ! -f "$PEERS_FILE" ]] && echo '[]' > "$PEERS_FILE"
}

# ==============================================
# Status checking functions - توابع بررسی وضعیت سیستم و کانکشن‌ها
# ==============================================

# بررسی وجود کانفیگ اینترفیس WireGuard ایران (یعنی آیا ایران نصب شده یا نه)
is_Main_installed() {
    # اگر فایل کانفیگ WireGuard (wg1.conf) وجود داشته باشد، خروجی موفق (true) خواهد بود
    [[ -f "/etc/wireguard/$WG_INTERFACE.conf" ]]
}

# بررسی وضعیت سرویس WireGuard روی اینترفیس ایران (wg1)
get_service_status() {
    # اگر سرویس wg-quick@wg1 فعال باشد، "Active" سبز چاپ می‌شود
    if systemctl is-active --quiet wg-quick@$WG_INTERFACE; then
        echo -e "${GREEN}Active${NC}"
    else
        # در غیر اینصورت "Inactive" قرمز چاپ می‌شود
        echo -e "${RED}Inactive${NC}"
    fi
}

# گرفتن تعداد سرورهای خارجی (peers) ثبت‌شده در فایل peers.json
get_peer_count() {
    if [[ -f "$PEERS_FILE" ]]; then
        # با دستور jq طول آرایه JSON را نشان می‌دهد (تعداد آیتم‌ها)
        jq length "$PEERS_FILE"
    else
        # اگر فایل وجود نداشت ۰ را نمایش می‌دهد
        echo "0"
    fi
}

# گرفتن تعداد سرورهای متصل به اینترفیس WireGuard (peers فعلی که در handshake وجود دارند)
get_connected_peers() {
    # دستور wg show اطلاعات peers را نمایش می‌دهد، خط‌هایی که با peer: شروع می‌شوند شمرده می‌شود
    # در صورت خطا یا عدم وجود peer عدد ۰ برگردانده می‌شود
    wg show $WG_INTERFACE 2>/dev/null | grep -E '^peer:' | wc -l || echo "0"
}

# بررسی وضعیت اتصال یک peer مشخص (بر اساس آی‌پی داخلی و کلید عمومی)
check_peer_connection() {
    local peer_ip=$1        # آی‌پی خصوصی سرور خارجی در تونل
    local peer_pubkey=$2    # کلید عمومی آن سرور خارجی

    # تلاش برای ping به آی‌پی خصوصی peer با یک بسته و timeout ۲ ثانیه
    if ping -c 1 -W 2 "$peer_ip" >/dev/null 2>&1; then
        # اگر پاسخ داد، یعنی اتصال زنده و سبز رنگ نمایش داده می‌شود
        echo -e "${GREEN}Connected${NC}"
    # اگر ping موفق نبود ولی آخرین handshake بین دو سرور انجام شده بود (بدون پاسخ ping)
    elif wg show $WG_INTERFACE | grep -A 5 "$peer_pubkey" | grep -q "latest handshake"; then
        # وضعیت handshake برقرار ولی پینگ موفق نیست (زرد)
        echo -e "${YELLOW}Handshake only${NC}"
    else
        # در غیر اینصورت اتصال قطع شده (قرمز)
        echo -e "${RED}Disconnected${NC}"
    fi
}

# نصب بسته‌ها و پیش‌نیازهای لازم برای اجرای تونل WireGuard و کار با اسکریپت
install_dependencies() {
    msg info "Installing required dependencies..."   # اطلاع‌رسانی شروع نصب
    apt-get update -y                               # بروزرسانی لیست بسته‌ها
    # نصب بسته‌های wireguard و ابزارهای جانبی برای مدیریت کلید، json، ssh، و فایروال
    apt-get install -y wireguard wireguard-tools jq sshpass resolvconf iptables
}

# ==============================================
# نمایش هدر اصلی و وضعیت tunnel و peerها
# ==============================================
show_header() {
    width=81
    export LC_ALL=C.UTF-8
    echo -e '\n\n'

    # هدر اصلی
    echo -e "${CYAN}┌$(printf '─%.0s' $(seq 1 $((width - 2))))┐${NC}"
    printf "${CYAN}│%*s%s%*s│${NC}\n" $(( (width - 2 - 33) / 2 )) "" "Mapsim Tunnel Status Manager     " $(( (width - 2 - 33 + 1) / 2 )) ""
    echo -e "${CYAN}├$(printf '─%.0s' $(seq 1 $((width - 2))))┤${NC}"

    # IP سرور و موقعیت آن
    INFO=$(curl -s https://ipinfo.io/json)
    if ! echo "$INFO" | jq -e .ip >/dev/null 2>&1; then
        INFO=$(curl -s http://ip-api.com/json/)
        IP=$(echo "$INFO" | jq -r .query)
        CITY=$(echo "$INFO" | jq -r .city)
        COUNTRY=$(echo "$INFO" | jq -r .country)
    else
        IP=$(echo "$INFO" | jq -r .ip)
        CITY=$(echo "$INFO" | jq -r .city)
        COUNTRY=$(echo "$INFO" | jq -r .country)
    fi

    IP="${IP:-Not found}"
    CITY="${CITY:-Unknown}"
    COUNTRY="${COUNTRY:-Unknown}"

    LINE1="Your IP Address = 🌐 $IP"
    LINE2="Location        = 📍 $CITY, $COUNTRY"

    printf "${CYAN}│ ${YELLOW}%-79s │\n" "$LINE1"
    printf "${CYAN}│ ${GREEN}%-79s │\n" "$LINE2"




    # اطلاعات سرویس
    local service_status=$(get_service_status)
    local peer_count=$(get_peer_count)
    local connected_count=$(get_connected_peers)
    WG_PORT=$(get_wg_port)

    printf "${CYAN}│ %-77s            │\n" "Service: $service_status"
    printf "${CYAN}│ %-77s │\n" "Peers: $peer_count     Connected: $connected_count"

    # فقط اگر ایران نصب شده باشد
    if is_Main_installed; then
        local private_key=$(grep -m1 -oP '(?<=PrivateKey = ).*' "/etc/wireguard/$WG_INTERFACE.conf")
        if [[ -n "$private_key" ]]; then
            local Main_pubkey=$(echo "$private_key" | wg pubkey | cut -c 1-16)
            printf "${CYAN}│ %-77s │\n" "Main Public Key: $Main_pubkey..."
        else
            printf "${CYAN}│ %-77s │\n" "Main Public Key: [Not Found]"
        fi
        printf "${CYAN}│ %-77s │\n" "IP: $Main_IP     Port: $WG_PORT"
    fi

    echo -e "${CYAN}└$(printf '─%.0s' $(seq 1 $((width - 2))))┘${NC}"

    # جدول کانکشن‌ها (در صورت وجود peer)
    if [[ -f "$PEERS_FILE" && $(jq length "$PEERS_FILE") -gt 0 ]]; then
        echo -e "\n${CYAN}Active Peer Connections:${NC}"
        echo -e "${CYAN}┌────────────────────┬────────────────────┬────────────────────────────┐${NC}"
        echo -e "${CYAN}│     Private IP     │     Public IP      │          Status            │${NC}"
        echo -e "${CYAN}├────────────────────┼────────────────────┼────────────────────────────┤${NC}"

        jq -r '.[] | "\(.ip)|\(.public_ip)|\(.pubkey)"' "$PEERS_FILE" | while IFS='|' read -r ip public_ip pubkey; do
            status_raw=$(check_peer_connection "$ip" "$pubkey")
            status_plain=$(echo -e "$status_raw" | sed 's/\x1B\[[0-9;]*[mK]//g')
            status_padded=$(printf "%-26s" "$status_plain")
            status_colored=$(echo "$status_padded" | sed "s|$status_plain|$status_raw|")

            printf "${CYAN}│ %-18s │ %-18s │ %s │\n" "$ip" "$public_ip" "$status_colored"
        done

        echo -e "${CYAN}└────────────────────┴────────────────────┴────────────────────────────┘${NC}"
    fi

    echo ""
}





# ==============================================
# Core functionality (working menu options)
# ==============================================

install_main_server() {
    # بررسی اینکه قبلاً اینترفیس ایران نصب شده یا نه
    if is_Main_installed; then
        msg info "Main server is already installed!"
        return
    fi

    msg info "Configuring Main server..."

    while true; do
        read -p "Enter Mapsim Tunnel port [$WG_PORT]: " input_port
        input_port=${input_port:-$WG_PORT}

        # بررسی اینکه فقط عدد باشه
        if ! [[ "$input_port" =~ ^[0-9]+$ ]]; then
            echo "❌ Invalid input. Please enter a number."
            continue
        fi

        # بررسی اینکه در بازه مجاز باشه
        if (( input_port < 1024 || input_port > 65535 )); then
            echo "❌ Port must be between 1024 and 65535."
            continue
        fi

        # اگر همه چیز درست بود، مقدار رو ست کن و break بزن
        WG_PORT="$input_port"
        # ذخیره در فایل
        echo "$WG_PORT" > "$Main_PORT_FILE"
        break
    done

    msg info "Configuring Main server on port $WG_PORT..."

    # تشخیص خودکار اینترفیس شبکه خارجی (برای NAT کردن ترافیک WireGuard)
    # معمولاً eth0 یا ens3 یا ...
    DEFAULT_IFACE=$(ip route get 1 | awk '{print $5; exit}')
    if [[ -z "$DEFAULT_IFACE" ]]; then
        msg error "Could not detect default network interface!"
        exit 1
    fi

    # حذف تنظیمات باقی‌مانده قبلی (در صورتی که کانفیگ قبلی وجود داشته)
    systemctl stop wg-quick@$WG_INTERFACE 2>/dev/null || true
    ip link del $WG_INTERFACE 2>/dev/null || true

    # تولید کلید خصوصی و سپس کلید عمومی معادل آن برای سرور ایران
    PRIVATE_KEY=$(wg genkey)
    PUBLIC_KEY=$(echo "$PRIVATE_KEY" | wg pubkey)

    # ایجاد فایل کانفیگ WireGuard برای سرور ایران
    cat > "/etc/wireguard/$WG_INTERFACE.conf" <<EOF
[Interface]
Address = $Main_IP/24                 
ListenPort = $WG_PORT                 
PrivateKey = $PRIVATE_KEY            
MTU = $MTU_SIZE                       
DNS = 8.8.8.8                         
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -t nat -A POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT; iptables -t nat -D POSTROUTING -o $DEFAULT_IFACE -j MASQUERADE
EOF

    # ایمن‌سازی فایل کانفیگ (عدم دسترسی دیگر کاربران به کلیدها)
    chmod 600 /etc/wireguard/$WG_INTERFACE.conf

    # فعال‌سازی سرویس WireGuard به‌صورت دائم و اجرای اولیه
    systemctl enable --now wg-quick@$WG_INTERFACE >/dev/null 2>&1

    # بررسی اینکه آیا رابط با موفقیت بالا آمده یا نه
    if systemctl is-active --quiet wg-quick@$WG_INTERFACE; then
        msg success "Main Mapsim Tunnel interface started successfully on $Main_IP"
    else
        msg error "Failed to start Main Mapsim Tunnel interface"
        exit 1
    fi

    # افزودن قانون فایروال برای باز کردن پورت WireGuard فقط اگر وجود نداشته باشد
    if ! iptables -C INPUT -p udp --dport $WG_PORT -j ACCEPT 2>/dev/null; then
        iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT
    fi

    # گرفتن IP عمومی (پیش‌فرض از $IP که قبلاً با curl گرفته شده)
    read -p "Enter the public IP of this Main server [$IP]: " Main_PUBLIC_IP
    Main_PUBLIC_IP=${Main_PUBLIC_IP:-$IP}

    # ذخیره در فایل
    echo "$Main_PUBLIC_IP" > "$Main_PUBLIC_IP_FILE"

}

add_Distance_server() {
    # اگر سرور ایران هنوز نصب نشده باشد، امکان افزودن کلاینت وجود ندارد
    if ! is_Main_installed; then
        msg error "Main server must be installed first!"
        return 1
    fi

    # تولید آدرس IP داخلی برای کلاینت خارجی (بر اساس شمارنده‌ی قبلی)
    local NEXT_ID=$(jq length "$PEERS_FILE")
    local Distance_IP="10.100.100.$((NEXT_ID + 2))"

    # گرفتن اطلاعات اتصال SSH به سرور خارجی
    read -p "Enter Distance server public IP: " FIP
    read -p "Enter SSH port [$DEFAULT_SSH_PORT]: " SPORT
    SPORT=${SPORT:-$DEFAULT_SSH_PORT}  # اگر چیزی وارد نشد، از مقدار پیش‌فرض استفاده کن
    read -p "Enter SSH username [$DEFAULT_SSH_USER]: " SUSER
    SUSER=${SUSER:-$DEFAULT_SSH_USER}
    read -s -p "Enter SSH password: " SPASS; echo ""

    # تولید کلید خصوصی و عمومی و preshared key برای این کلاینت
    local PKEY=$(wg genkey)
    local PUBKEY=$(echo "$PKEY" | wg pubkey)
    local PSK=$(wg genpsk)

    # گرفتن کلید عمومی سرور ایران و IP عمومی‌اش (که قبلاً ذخیره شده)
    local Main_PUB=$(wg show $WG_INTERFACE public-key)
    local Main_PUBLIC_IP=$(cat "$Main_PUBLIC_IP_FILE")

    # تشخیص اینترفیس خروجی برای NAT در صورت نیاز (در این تابع استفاده نشده، ولی آماده است)
    local DEFAULT_IFACE=$(ip route get 1 | awk '{print $5; exit}')

    # ذخیره مشخصات این کلاینت جدید در فایل peers.json
    jq ". += [{
        \"ip\": \"$Distance_IP\",                   
        \"public_ip\": \"$FIP\",                   
        \"ssh_port\": \"$SPORT\",                  
        \"ssh_user\": \"$SUSER\",                  
        \"pubkey\": \"$PUBKEY\",                   
        \"psk\": \"$PSK\",                         
        \"added_at\": \"$(date +%Y-%m-%dT%H:%M:%S)\" 
    }]" "$PEERS_FILE" > tmp.json && mv tmp.json "$PEERS_FILE"

    wg set $WG_INTERFACE peer "$PUBKEY" allowed-ips "$Distance_IP/32" persistent-keepalive $PERSISTENT_KEEPALIVE preshared-key <(echo "$PSK")

    # ساخت فایل کانفیگ کامل برای کلاینت خارجی
    local REMOTE_CFG="[Interface]
Address = $Distance_IP/24              
PrivateKey = $PKEY                    
ListenPort = $WG_PORT                 
MTU = $MTU_SIZE
DNS = 8.8.8.8

[Peer]
PublicKey = $Main_PUB                 
PresharedKey = $PSK                   
AllowedIPs = $Main_IP/32              
Endpoint = $Main_PUBLIC_IP:$WG_PORT   
PersistentKeepalive = $PERSISTENT_KEEPALIVE"

    # اجرای دستورات از راه دور برای نصب و پیکربندی WireGuard در سرور خارجی
    sshpass -p "$SPASS" ssh -o StrictHostKeyChecking=no -p "$SPORT" "$SUSER@$FIP" "
        sudo apt-get update
        sudo apt-get install -y wireguard wireguard-tools jq sshpass resolvconf iptables

        # اگر از قبل کانفیگ یا رابطی وجود دارد، حذفش کن
        sudo systemctl stop wg-quick@wg2 2>/dev/null || true
        sudo ip link del wg2 2>/dev/null || true

        # نوشتن فایل پیکربندی و فعال‌سازی رابط WireGuard
        sudo mkdir -p /etc/wireguard
        echo '$REMOTE_CFG' | sudo tee /etc/wireguard/wg2.conf >/dev/null
        sudo chmod 600 /etc/wireguard/wg2.conf
        sudo systemctl enable wg-quick@wg2
        sudo wg-quick up wg2
    " && msg success "Distance server configured successfully" || msg error "Failed to configure Distance server"
}

get_wg_port() {
    if [[ -f "$Main_PORT_FILE" ]]; then
        port=$(<"$Main_PORT_FILE")
        if [[ "$port" =~ ^[0-9]+$ ]]; then
            echo "$port"
            return
        fi
    fi
    echo "21301"
}


#تست داخلی
# add_Distance_server() {
#     # اگر سرور ایران هنوز نصب نشده باشد، امکان افزودن کلاینت وجود ندارد
#     if ! is_Main_installed; then
#         msg error "Main server must be installed first!"
#         return 1
#     fi

#     # تولید آدرس IP داخلی برای کلاینت خارجی (بر اساس شمارنده‌ی قبلی)
#     local NEXT_ID=$(jq length "$PEERS_FILE")
#     local Distance_IP="10.100.100.$((NEXT_ID + 2))"

#     # گرفتن اطلاعات ظاهری برای سازگاری با ساختار اولیه (بدون استفاده واقعی)
#     read -p "Enter Distance server public IP: " FIP
#     read -p "Enter SSH port [$DEFAULT_SSH_PORT]: " SPORT
#     SPORT=${SPORT:-$DEFAULT_SSH_PORT}
#     read -p "Enter SSH username [$DEFAULT_SSH_USER]: " SUSER
#     SUSER=${SUSER:-$DEFAULT_SSH_USER}
#     read -s -p "Enter SSH password (not used in local mode): " SPASS; echo ""

#     # تولید کلید خصوصی و عمومی و PSK برای این کلاینت
#     local PKEY=$(wg genkey)
#     local PUBKEY=$(echo "$PKEY" | wg pubkey)
#     local PSK=$(wg genpsk)
#     # گرفتن کلید عمومی سرور و IP عمومی
#     local Main_PUB=$(wg show "$WG_INTERFACE" public-key)
#     local Main_PUBLIC_IP=$(cat "$Main_PUBLIC_IP_FILE")
#     local Main_IP="10.100.100.1"  # IP سرور اصلی - باید با سیستم شما هماهنگ باشد

#     # ذخیره مشخصات کلاینت در peers.json
#     jq ". += [{
#         \"ip\": \"$Distance_IP\",
#         \"public_ip\": \"$FIP\",
#         \"ssh_port\": \"$SPORT\",
#         \"ssh_user\": \"$SUSER\",
#         \"pubkey\": \"$PUBKEY\",
#         \"psk\": \"$PSK\",
#         \"added_at\": \"$(date +%Y-%m-%dT%H:%M:%S)\"
#     }]" "$PEERS_FILE" > tmp.json && mv tmp.json "$PEERS_FILE"

#     # اضافه‌کردن این peer به سرور ایران (wg0)
#     wg set "$WG_INTERFACE" peer "$PUBKEY" allowed-ips "$Distance_IP/32" persistent-keepalive $PERSISTENT_KEEPALIVE preshared-key <(echo "$PSK")

#     # ساخت کانفیگ WireGuard برای کلاینت خارجی (wg2) روی همین سیستم
#     local REMOTE_CFG="[Interface]
# Address = $Distance_IP/32
# PrivateKey = $PKEY
# ListenPort = $WG_PORT
# MTU = $MTU_SIZE
# DNS = 8.8.8.8

# [Peer]
# PublicKey = $Main_PUB
# PresharedKey = $PSK
# AllowedIPs = $Main_IP/32
# Endpoint = $Main_PUBLIC_IP:$WG_PORT
# PersistentKeepalive = $PERSISTENT_KEEPALIVE"

#     # نوشتن فایل کانفیگ
#     echo "$REMOTE_CFG" | sudo tee /etc/wireguard/wg2.conf >/dev/null
#     sudo chmod 600 /etc/wireguard/wg2.conf

#     # فعال‌سازی رابط wg2
#     sudo systemctl stop wg-quick@wg2 2>/dev/null || true
#     sudo ip link del wg2 2>/dev/null || true
#     sudo systemctl enable wg-quick@wg2
#     if sudo wg-quick up wg2; then
#         msg success "Distance server (wg2) interface brought up successfully."
#     else
#         msg error "Failed to bring up wg2 interface"
#     fi
# }

list_Distance_servers() {
    # بررسی فایل
    if [[ ! -f "$PEERS_FILE" ]] || [[ $(jq length "$PEERS_FILE") -eq 0 ]]; then
        msg info "No Distance servers configured"
        return
    fi

    echo -e "\n${GREEN}Configured Distance Servers:${NC}"

    # هدر جدول با 5 ستون: شماره، IP خصوصی، IP عمومی، SSH، زمان
    echo -e "${CYAN}┌────┬────────────────────┬────────────────────┬────────────────────────────┬────────────────────────────┐${NC}"
    echo -e "${CYAN}│ #  │ Private IP         │ Public IP          │ SSH Info                   │ Added At                   │${NC}"
    echo -e "${CYAN}├────┼────────────────────┼────────────────────┼────────────────────────────┼────────────────────────────┤${NC}"

    local idx=0
    jq -r '.[] | "\(.ip)|\(.public_ip)|\(.ssh_user)@\(.public_ip):\(.ssh_port)|\(.added_at)"' "$PEERS_FILE" | while IFS='|' read -r ip public_ip ssh_info added_at; do
        idx=$((idx+1))
        printf "${CYAN}│ %-2s │ %-18s │ %-18s │ %-26s │ %-26s │\n" "$idx" "$ip" "$public_ip" "$ssh_info" "$added_at"
    done

    echo -e "${CYAN}└────┴────────────────────┴────────────────────┴────────────────────────────┴────────────────────────────┘${NC}"

    # وضعیت اتصال‌ها
    echo -e "\n${YELLOW}Connection Status:${NC}"
    jq -r '.[] | "\(.ip) \(.pubkey)"' "$PEERS_FILE" | while read -r ip pubkey; do
        status=$(check_peer_connection "$ip" "$pubkey")
        echo -e "${CYAN}$ip:${NC} $status"
    done
}



remove_Distance_peer() {
    # نمایش لیست سرورهای خارجی فعلی برای انتخاب حذف
    list_Distance_servers
    
    # دریافت تعداد کل سرورها از فایل peers.json
    local count=$(jq length "$PEERS_FILE")
    
    # اگر هیچ سروری وجود نداشت، خروج از تابع
    [[ $count -eq 0 ]] && return
    
    # گرفتن شماره سروری که کاربر می‌خواهد حذف کند
    read -p "Please Select Distance Server For uninstall (Choice number): " IDX
    
    # اعتبارسنجی ورودی: باید عدد صحیح در بازه درست باشد
    [[ ! "$IDX" =~ ^[0-9]+$ ]] || [[ $IDX -lt 1 ]] || [[ $IDX -gt $count ]] && msg error "Invalid selection" && return
    
    # تبدیل شماره به اندیس مناسب برای jq (از ۰ شروع می‌شود)
    IDX=$((IDX - 1))
    
    # استخراج IP و کلید عمومی peer مورد نظر از فایل peers.json
    local IP=$(jq -r ".[$IDX].ip" "$PEERS_FILE")
    local PUB=$(jq -r ".[$IDX].pubkey" "$PEERS_FILE")
    local FIP=$(jq -r ".[$IDX].public_ip" "$PEERS_FILE")
    local SUSER=$(jq -r ".[$IDX].ssh_user" "$PEERS_FILE")
    local SPORT=$(jq -r ".[$IDX].ssh_port" "$PEERS_FILE")

    read -s -p "Enter SSH password for $SUSER@$FIP: " SPASS; echo ""
    msg info "Removing peer from local Mapsim Tunnel config..."

    sshpass -p "$SPASS" ssh -o StrictHostKeyChecking=no -p "$SPORT" "$SUSER@$FIP" "
        sudo systemctl stop wg-quick@wg2 2>/dev/null || true
        sudo systemctl disable wg-quick@wg2 2>/dev/null || true
        sudo ip link del wg2 2>/dev/null || true
        sudo rm -f /etc/wireguard/wg2.conf
        sudo rm -rf /etc/wireguard
        sudo rm -f /etc/systemd/system/wg-quick@wg2.service 2>/dev/null || true
        sudo systemctl daemon-reload
    " && msg success "Remote Mapsim Tunnel Distance from $FIP" || msg warn "Failed to clean Distance server"

    # حذف peer از تنظیمات WireGuard
    wg set $WG_INTERFACE peer "$PUB" remove
    
    # حذف peer از فایل JSON و جایگزینی فایل
    jq "del(.[$IDX])" "$PEERS_FILE" > tmp.json && mv tmp.json "$PEERS_FILE"
    
    # پیام موفقیت
    msg success "Removed peer $IP"
    msg success "Remote Mapsim Tunnel Distance Finished $FIP  . . ."
    
}


uninstall_main_server() {
    # تایید از کاربر برای حذف تونل ایران
    read -p "Are you sure you want to uninstall the Main tunnel? [y/N] " confirm
    
    # خروج در صورت انصراف کاربر
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return

    # توقف و غیرفعال‌سازی سرویس WireGuard
    sudo systemctl stop wg-quick@"$WG_INTERFACE" 2>/dev/null || true
    sudo systemctl disable wg-quick@"$WG_INTERFACE" 2>/dev/null || true

    # حذف اینترفیس اگر هنوز فعال باشد
    sudo ip link del "$WG_INTERFACE" 2>/dev/null || true

    # حذف فایل پیکربندی
    sudo rm -f "/etc/wireguard/$WG_INTERFACE.conf"

    # بررسی موفقیت حذف
    if ip link show "$WG_INTERFACE" &>/dev/null; then
        echo "⚠️  Interface $WG_INTERFACE still exists!"
        msg error "❌ Main tunnel has NOT been uninstalled."
    else
        echo "✅ Interface $WG_INTERFACE removed successfully."
        msg success "✅ Main tunnel has been uninstalled."
    fi
}



# نمایش منوی اصلی برنامه با گزینه‌های قابل انتخاب
# منو به صورت زیبا با رنگ‌ها و طرح با حاشیه چاپ می‌شود
# گزینه‌ها:
# 1 - نصب سرور اصلی ایران
# 2 - افزودن سرور خارجی (Peer)
# 3 - نمایش سرورهای خارجی ثبت شده
# 4 - حذف یک سرور خارجی
# 5 - حذف کامل تونل ایران
# 0 - خروج از برنامه
show_menu() {
    clear
    width=81
    export LC_ALL=C.UTF-8

    echo -e "${MAGENTA}"
    echo "       ▄▄▄▄███▄▄▄▄      ▄████████    ▄███████▄    ▄████████  ▄█    ▄▄▄▄███▄▄▄▄         "
    echo "      ▄██▀▀▀███▀▀▀██▄   ███    ███   ███    ███   ███    ███ ███  ▄██▀▀▀███▀▀▀██▄      "
    echo "      ███   ███   ███   ███    ███   ███    ███   ███    █▀  ███▌ ███   ███   ███      "
    echo "      ███   ███   ███   ███    ███   ███    ███   ███        ███▌ ███   ███   ███      "
    echo "      ███   ███   ███ ▀███████████ ▀█████████▀  ▀███████████ ███▌ ███   ███   ███      "
    echo "      ███   ███   ███   ███    ███   ███                 ███ ███  ███   ███   ███      "
    echo "      ███   ███   ███   ███    ███   ███           ▄█    ███ ███  ███   ███   ███      "
    echo "       ▀█   ███   █▀    ███    █▀   ▄████▀       ▄████████▀  █▀    ▀█   ███   █▀       "
    echo "                                                                                       "
    echo "                     ███    █▄  ███▄▄▄▄   ███▄▄▄▄      ▄████████  ▄█                   "
    echo "         ▀█████████▄ ███    ███ ███▀▀▀██▄ ███▀▀▀██▄   ███    ███ ███                   "
    echo "            ▀███▀▀██ ███    ███ ███   ███ ███   ███   ███    █▀  ███                   "
    echo "             ███   ▀ ███    ███ ███   ███ ███   ███   ███▄▄▄     ███                   "
    echo "             ███     ███    ███ ███   ███ ███   ███ ▀▀███▀▀▀     ███                   "
    echo "             ███     ███    ███ ███   ███ ███   ███   ███    █▄  ███                   "
    echo "             ███     ███    ███ ███   ███ ███   ███   ███    ███ ███▌    ▄             "
    echo "            ▄████▀   ████████▀   ▀█   █▀   ▀█   █▀    ██████████ █████▄▄██             "
}

show_menu_item() 
{
    echo -e '\n\n'  # اینجا منوی جدید پایین‌تر چاپ میشه
    echo -e "${CYAN}┌$(printf '─%.0s' $(seq 1 $((width - 2))))┐${NC}"
    printf "${CYAN}│%*s%s%*s│${NC}\n" $(( (width - 2 - 27) / 2 )) "" "Mapsim Tunnel - Main Menu  " $(( (width - 2 - 27 + 1) / 2 )) ""
    echo -e "${CYAN}├$(printf '─%.0s' $(seq 1 $((width - 2))))┤${NC}"

    menu_item() {
        local num="$1"
        local text="$2"
        local color_num="$3"
        local line=" $num - $text"
        local spaces=$((width - 2 - ${#line}))
        # شماره رنگی، متن به رنگ سیان، فاصله و کادر
        printf "│${color_num}%s${CYAN}%*s${NC}│\n" "$line" "$spaces" ""
    }

    menu_item "1" "Install Main Service Tunnel" "${GREEN}"
    menu_item "2" "Add Distance Server" "${GREEN}"
    menu_item "3" "List Distance Servers" "${GREEN}"
    menu_item "4" "Remove a Distance Server" "${GREEN}"
    menu_item "5" "Uninstall Main Service Tunnel" "${GREEN}"
    menu_item "0" "Exit" "${RED}"

    echo -e "${CYAN}└$(printf '─%.0s' $(seq 1 $((width - 2))))┘${NC}"
}



# ==============================================
# اجرای اصلی برنامه: حلقه منوی تعاملی
# ==============================================

main() {
    init  # آماده‌سازی اولیه (مثل بارگذاری تنظیمات، چک کردن نیازمندی‌ها و متغیرها)

    # حلقه بی‌نهایت که منو و وضعیت را نمایش می‌دهد و از کاربر گزینه می‌گیرد
    while true; do
        show_menu
        show_header    # نمایش وضعیت فعلی سرویس و اتصالات
        show_menu_item
        #show_menu      # نمایش منوی اصلی برای انتخاب عملیات
        read -p $'\nEnter Number Of List: ' opt  # گرفتن ورودی از کاربر

        case $opt in
            1) install_main_server ;;    # نصب سرور ایران
            2) add_Distance_server ;;     # افزودن سرور خارجی جدید
            3) list_Distance_servers ;;   # نمایش سرورهای خارجی ثبت‌شده
            4) remove_Distance_peer ;;    # حذف یک سرور خارجی
            5) uninstall_main_server ;;         # حذف کامل تونل ایران
            0) exit 0 ;;                 # خروج از برنامه
            *) msg error "Invalid Choice" ;;  # گزینه نامعتبر، پیام خطا می‌دهد
        esac

        # اگر گزینه خروج نبود، منتظر می‌ماند تا کاربر اینتر بزند و دوباره منو نمایش داده شود
        [[ $opt -ne 0 ]] && read -p $'\nPress Enter to continue...'
    done
}

# اجرای تابع main و شروع برنامه
main

