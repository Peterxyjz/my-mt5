#!/bin/bash
# Setup News Bot trên VPS
# Upload folder news-channel lên VPS rồi chạy: sudo bash setup_vps.sh

set -e

REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
DEPLOY_DIR="$REAL_HOME/news-channel"
VENV_DIR="$DEPLOY_DIR/venv"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=== Setup Telegram News Bot ==="
echo "User: $REAL_USER"
echo "Deploy: $DEPLOY_DIR"

# 1. Copy files nếu chạy từ folder khác
if [ "$SCRIPT_DIR" != "$DEPLOY_DIR" ]; then
    mkdir -p "$DEPLOY_DIR"
    cp "$SCRIPT_DIR/news_bot.py" "$DEPLOY_DIR/"
    cp "$SCRIPT_DIR/requirements.txt" "$DEPLOY_DIR/"
    cp "$SCRIPT_DIR/setup_vps.sh" "$DEPLOY_DIR/"
    cp "$SCRIPT_DIR/uninstall.sh" "$DEPLOY_DIR/"
fi
chown -R "$REAL_USER:$REAL_USER" "$DEPLOY_DIR"

# 2. Tạo venv & cài dependencies
echo "Tạo venv & cài packages..."
sudo -u "$REAL_USER" python3 -m venv "$VENV_DIR"
sudo -u "$REAL_USER" "$VENV_DIR/bin/pip" install --quiet -r "$DEPLOY_DIR/requirements.txt"

# 3. Nhập token
read -p "Nhập Bot Token (@BotFather): " BOT_TOKEN
read -p "Nhập Chat ID (channel/group): " CHAT_ID

# 4. Tạo service file
cat > /etc/systemd/system/news_bot.service <<EOF
[Unit]
Description=Telegram News Bot - fxtin.com important news
After=network.target

[Service]
Type=simple
User=$REAL_USER
WorkingDirectory=$DEPLOY_DIR
ExecStart=$VENV_DIR/bin/python $DEPLOY_DIR/news_bot.py
Restart=always
RestartSec=10
Environment=TELEGRAM_BOT_TOKEN=$BOT_TOKEN
Environment=TELEGRAM_CHAT_ID=$CHAT_ID
Environment=POLL_INTERVAL=30

[Install]
WantedBy=multi-user.target
EOF

# 5. Kill process cũ nếu có
pkill -f news_bot.py 2>/dev/null || true

# 6. Start service
systemctl daemon-reload
systemctl enable news_bot
systemctl start news_bot

echo ""
echo "=== DONE ==="
echo "Kiểm tra status:  systemctl status news_bot"
echo "Xem log live:     journalctl -u news_bot -f"
echo "Restart:          sudo systemctl restart news_bot"
echo "Stop:             sudo systemctl stop news_bot"
