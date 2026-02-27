#!/bin/bash
echo "Starting PM2 Error Watcher..."

# Create a place for the error log that Nginx can serve publicly
LOG_FILE="/usr/share/nginx/html/pm2-error.log"
touch "$LOG_FILE"
chmod 777 "$LOG_FILE"

while true; do
    if command -v pm2 &> /dev/null; then
        pm2 logs --err --nostream --lines 50 > "$LOG_FILE" 2>/dev/null || true
    fi
    sleep 3
done
