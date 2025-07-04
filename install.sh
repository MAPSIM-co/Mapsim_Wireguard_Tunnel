#!/bin/bash

set -e

CYAN="\033[0;36m"
GREEN="\033[0;32m"
RED="\033[0;31m"
NC="\033[0m"

echo -e "${CYAN}[*] Installing Mapsim Tunnel...${NC}"

# 1. Check root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}[ERROR] This script must be run as root${NC}"
   exit 1
fi

# 2. Install dependencies
echo -e "${CYAN}[*] Installing required packages...${NC}"
apt update && apt install -y wireguard curl qrencode resolvconf net-tools

# 3. Download latest mapsim-tunnel.sh from GitHub
INSTALL_DIR="/opt/mapsim"
mkdir -p "$INSTALL_DIR"

echo -e "${CYAN}[*] Downloading mapsim-tunnel.sh...${NC}"
curl -fsSL https://raw.githubusercontent.com/MAPSIM-co/Mapsim_Wireguard_Tunnel/main/mapsim-tunnel.sh -o "$INSTALL_DIR/mapsim-tunnel.sh"
chmod +x "$INSTALL_DIR/mapsim-tunnel.sh"

# 4. Add global command
ln -sf "$INSTALL_DIR/mapsim-tunnel.sh" /usr/local/bin/mapsim

# 5. Create systemd service
SERVICE_FILE="/etc/systemd/system/mapsim-tunnel.service"
cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Mapsim WireGuard Tunnel
After=network.target

[Service]
Type=simple
ExecStart=/opt/mapsim/mapsim-tunnel.sh
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

# 6. Enable and start the service
systemctl daemon-reload
systemctl enable mapsim-tunnel
systemctl start mapsim-tunnel

# 7. Done
echo -e "${GREEN}[✓] Mapsim Tunnel installed successfully!${NC}"
echo -e "${GREEN}[→] You can now run it manually with: mapsim${NC}"
