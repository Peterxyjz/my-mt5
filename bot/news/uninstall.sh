#!/bin/bash
# Gỡ cài đặt News Bot
# Chạy: sudo bash uninstall.sh

echo "=== Uninstall Telegram News Bot ==="

# 1. Stop & disable service
echo "Stopping service..."
systemctl stop news_bot 2>/dev/null || true
systemctl disable news_bot 2>/dev/null || true

# 2. Kill process còn chạy ngầm
echo "Killing remaining processes..."
pkill -f news_bot.py 2>/dev/null || true

# 3. Xóa service file
echo "Removing service file..."
rm -f /etc/systemd/system/news_bot.service
systemctl daemon-reload

# 4. Xóa deploy folder
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(eval echo "~$REAL_USER")
DEPLOY_DIR="$REAL_HOME/news-channel"

read -p "Xóa folder $DEPLOY_DIR? (y/n): " CONFIRM
if [ "$CONFIRM" = "y" ]; then
    rm -rf "$DEPLOY_DIR"
    echo "Deleted $DEPLOY_DIR"
else
    echo "Skipped folder deletion"
fi

echo ""
echo "=== DONE - News Bot đã được gỡ sạch ==="
