#!/bin/bash
CURRENT_PORT=""
mkdir -p /etc/nginx/conf.d

echo "Starting Dynamic Live Preview Watcher..."

while true; do
    # Find listening TCP ports inside the container.
    # We exclude our known system ports (main, ttyd, dockerd).
    NEW_PORT=$(ss -tlnH | awk '{print $4}' | awk -F':' '{print $NF}' | grep -vE '^(80|443|8080|8081|2375)$' | sort -n | head -n 1)

    if [ "$NEW_PORT" != "$CURRENT_PORT" ]; then
        if [ -n "$NEW_PORT" ]; then
            echo "🔥 Live Preview detected on port $NEW_PORT. Routing /preview/ to it..."
            cat <<EOF > /etc/nginx/conf.d/preview.conf
    location /preview/ {
        proxy_pass http://127.0.0.1:$NEW_PORT/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
    }
EOF
            nginx -s reload
            CURRENT_PORT="$NEW_PORT"
        else
            echo "🛑 Live Preview port closed. Removing /preview/ route."
            rm -f /etc/nginx/conf.d/preview.conf
            nginx -s reload
            CURRENT_PORT=""
        fi
    fi
    sleep 3
done
