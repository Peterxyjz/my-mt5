"""
Telegram News Bot - Tự động gửi tin tức quan trọng từ fxtin.com
Chạy 24/7 trên VPS với systemd

Cài đặt:
    pip install requests python-telegram-bot

Chạy:
    python news_bot.py
"""

import os
import time
import json
import logging
import requests
from datetime import datetime

# ===================== CẤU HÌNH =====================
BOT_TOKEN = os.getenv("TELEGRAM_BOT_TOKEN", "YOUR_BOT_TOKEN_HERE")
CHAT_ID = os.getenv("TELEGRAM_CHAT_ID", "YOUR_CHAT_ID_HERE")  # Channel: @channel hoặc -100xxxx
POLL_INTERVAL = int(os.getenv("POLL_INTERVAL", "30"))  # Giây
API_URL = "https://www.fxtin.com/page/finance/information"
SEEN_FILE = "seen_news.json"
# =====================================================

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
log = logging.getLogger("news_bot")

HEADERS = {
    "accept": "application/json, text/plain, */*",
    "content-type": "application/json;charset=UTF-8",
    "origin": "https://fxtin.com",
    "referer": "https://fxtin.com/",
    "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
}


def load_seen() -> set:
    """Load danh sách ID tin đã gửi."""
    if os.path.exists(SEEN_FILE):
        with open(SEEN_FILE, "r") as f:
            return set(json.load(f))
    return set()


def save_seen(seen: set):
    """Lưu danh sách ID tin đã gửi. Giữ tối đa 5000 ID gần nhất."""
    trimmed = sorted(seen)[-5000:]
    with open(SEEN_FILE, "w") as f:
        json.dump(trimmed, f)


def fetch_news() -> list:
    """Gọi API lấy tin tức."""
    try:
        resp = requests.post(API_URL, headers=HEADERS, json={"limit": 10, "page": 1}, timeout=15)
        resp.raise_for_status()
        data = resp.json()
        if data.get("code") == 200:
            return data["data"]["list"]
    except Exception as e:
        log.error(f"Fetch error: {e}")
    return []


def format_message(item: dict) -> str:
    """Format tin tức thành message Telegram."""
    time_str = item.get("pub_time", item.get("time", ""))
    text = item.get("translate", "") or item.get("content", "")

    # Chỉ lấy HH:MM
    if time_str and len(time_str) >= 5:
        time_str = time_str[:5]

    msg = f"🔴 <b>TIN NÓNG</b> | {time_str}\n{text}"
    return msg


def send_telegram(text: str) -> bool:
    """Gửi tin nhắn lên Telegram."""
    url = f"https://api.telegram.org/bot{BOT_TOKEN}/sendMessage"
    payload = {
        "chat_id": CHAT_ID,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": True,
    }
    try:
        resp = requests.post(url, json=payload, timeout=10)
        if resp.status_code == 200:
            return True
        # Rate limit
        if resp.status_code == 429:
            retry_after = resp.json().get("parameters", {}).get("retry_after", 5)
            log.warning(f"Rate limited, waiting {retry_after}s")
            time.sleep(retry_after)
            return send_telegram(text)
        log.error(f"Telegram error {resp.status_code}: {resp.text}")
    except Exception as e:
        log.error(f"Send error: {e}")
    return False


def run():
    """Main loop chạy 24/7."""
    log.info("=== News Bot started ===")
    log.info(f"Chat ID: {CHAT_ID}")
    log.info(f"Poll interval: {POLL_INTERVAL}s")

    if BOT_TOKEN == "YOUR_BOT_TOKEN_HERE":
        log.error("Chưa cấu hình BOT_TOKEN! Set env TELEGRAM_BOT_TOKEN hoặc sửa trong file.")
        return

    seen = load_seen()
    log.info(f"Loaded {len(seen)} seen news IDs")

    while True:
        try:
            news = fetch_news()
            important_news = [n for n in news if n.get("important") == "1"]

            new_items = [n for n in important_news if n["id"] not in seen]

            if new_items:
                # Gửi từ cũ -> mới
                new_items.sort(key=lambda x: x["id"])
                log.info(f"Found {len(new_items)} new important news")

                for item in new_items:
                    msg = format_message(item)
                    if send_telegram(msg):
                        seen.add(item["id"])
                        log.info(f"Sent: {item['id']} - {item['pub_time_tz']}")
                    time.sleep(1)  # Tránh rate limit

                save_seen(seen)

        except Exception as e:
            log.error(f"Loop error: {e}")

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    run()
