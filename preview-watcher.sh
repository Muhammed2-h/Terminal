#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Enhanced Live Preview Watcher
# ─────────────────────────────────────────────────────────────────────────────
# Writes /usr/share/nginx/html/preview/status.json polled by preview.html
# Updates nginx's /preview/proxy/ → the detected/configured port
#
# Modes:
#   PREVIEW_PORT=<N>  → static pin; waits for that port to become active
#   (unset)           → auto-discover lowest non-system listening TCP port
#
# App Name detection order:
#   PREVIEW_APP_NAME env var > process name from /proc > binary guess
# ─────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────────────
STATUS_DIR="/usr/share/nginx/html/preview"
STATUS_FILE="$STATUS_DIR/status.json"
PROXY_CONF="/etc/nginx/conf.d/preview.conf"
POLL_INTERVAL=2

# Ports always excluded from auto-discovery (add your system ports here)
# Reads the main PORT env var so auto-discovery doesn't steal the main port
EXCL_PORTS="^(${PORT:-8080}|443|8081|8082|2375|22|53)$"

CURRENT_PORT=""
CURRENT_APP=""

mkdir -p "$STATUS_DIR" /etc/nginx/conf.d
echo "🔍 Preview Watcher starting..."

# ── Helpers ───────────────────────────────────────────────────────────────────

write_status() {
    local port="$1" app="$2" extra="${3:-}"
    printf '{"port":%s,"app":"%s"%s}\n' \
        "${port:-null}" "$app" "$extra" > "$STATUS_FILE"
}

write_status_waiting() {
    local mode="$1" val="${2:-}"
    if [ "$mode" = "scan" ]; then
        printf '{"port":null,"app":"","scanning":true}\n' > "$STATUS_FILE"
    else
        printf '{"port":null,"app":"","waiting_for":%s}\n' "$val" > "$STATUS_FILE"
    fi
}

# Look up the process name that's listening on a port
detect_app_name() {
    local port="$1"
    # Use env override first
    if [ -n "${PREVIEW_APP_NAME:-}" ]; then
        echo "$PREVIEW_APP_NAME"; return
    fi
    # Try ss → get PID → look up /proc/<pid>/comm
    local pid
    pid=$(ss -tlnpH "sport = :$port" 2>/dev/null \
        | grep -oP 'pid=\K[0-9]+' | head -n 1 || true)
    if [ -n "$pid" ] && [ -f "/proc/$pid/comm" ]; then
        local comm
        comm=$(cat "/proc/$pid/comm" 2>/dev/null | tr -d '\n')
        # Map common runtimes to friendly names
        case "$comm" in
            node)
                # Try to get the script name from cmdline
                local script
                script=$(cat "/proc/$pid/cmdline" 2>/dev/null \
                    | tr '\0' ' ' | grep -oP '(?<=node )\S+' | head -n 1 || true)
                if echo "$script" | grep -qi "vite";   then echo "Vite";   return; fi
                if echo "$script" | grep -qi "next";   then echo "Next.js"; return; fi
                if echo "$script" | grep -qi "nuxt";   then echo "Nuxt";   return; fi
                if echo "$script" | grep -qi "server"; then echo "Node Server"; return; fi
                echo "Node.js"
                ;;
            python*|python)
                local pycmd
                pycmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ' | head -c 120)
                if echo "$pycmd" | grep -qi "uvicorn";  then echo "FastAPI/Uvicorn"; return; fi
                if echo "$pycmd" | grep -qi "gunicorn"; then echo "Gunicorn"; return; fi
                if echo "$pycmd" | grep -qi "flask";    then echo "Flask"; return; fi
                if echo "$pycmd" | grep -qi "django";   then echo "Django"; return; fi
                if echo "$pycmd" | grep -qi "http.server"; then echo "Python HTTP"; return; fi
                echo "Python"
                ;;
            ruby)   echo "Ruby" ;;
            php*)   echo "PHP" ;;
            nginx)  echo "" ;; # skip nginx itself
            *)      echo "$comm" ;;
        esac
    else
        echo "App"
    fi
}

write_proxy_conf() {
    local port="$1"
    cat > "$PROXY_CONF" <<EOF
    # preview-watcher: auto-generated — do not edit
    # Routes /preview/proxy/ → http://127.0.0.1:$port/
    location /preview/proxy/ {
        proxy_pass          http://127.0.0.1:$port/;
        proxy_http_version  1.1;
        proxy_set_header    Upgrade \$http_upgrade;
        proxy_set_header    Connection "upgrade";
        proxy_set_header    Host \$host;
        proxy_set_header    X-Real-IP \$remote_addr;
        proxy_set_header    X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header    X-Forwarded-Proto \$scheme;
        # Strip /preview/proxy prefix so the app sees /
        proxy_read_timeout  86400;
        proxy_send_timeout  86400;
        proxy_buffering     off;
        # Rewrite absolute redirects from the upstream
        proxy_redirect      http://127.0.0.1:$port/ /preview/proxy/;
        # Fix sub-resource paths
        sub_filter_once     off;
    }
EOF
    nginx -s reload 2>/dev/null && echo "✅ Nginx reloaded → port $port" \
        || echo "⚠️  Nginx reload failed (will retry)"
}

remove_proxy_conf() {
    rm -f "$PROXY_CONF"
    nginx -s reload 2>/dev/null || true
    echo "🛑 Preview proxy removed."
}

on_port_up() {
    local port="$1"
    local app
    app=$(detect_app_name "$port")
    echo "🔥 Preview online: port=$port app='$app'"
    write_proxy_conf "$port"
    write_status "\"$port\"" "$app"
    CURRENT_PORT="$port"
    CURRENT_APP="$app"
}

on_port_down() {
    echo "⏳ Port $CURRENT_PORT went offline."
    remove_proxy_conf
    write_status "null" ""
    CURRENT_PORT=""
    CURRENT_APP=""
}

port_is_listening() {
    local port="$1"
    ss -tlnH 2>/dev/null | awk '{print $4}' | awk -F':' '{print $NF}' \
        | grep -qxF "$port"
}

# ── STATIC MODE ───────────────────────────────────────────────────────────────
if [ -n "${PREVIEW_PORT:-}" ]; then
    echo "📌 Static preview port: PREVIEW_PORT=$PREVIEW_PORT"
    write_status_waiting "wait" "\"$PREVIEW_PORT\""

    while true; do
        if port_is_listening "$PREVIEW_PORT"; then
            if [ "$CURRENT_PORT" != "$PREVIEW_PORT" ]; then
                on_port_up "$PREVIEW_PORT"
            fi
        else
            if [ -n "$CURRENT_PORT" ]; then
                on_port_down
            fi
            write_status_waiting "wait" "\"$PREVIEW_PORT\""
        fi
        sleep "$POLL_INTERVAL"
    done

# ── AUTO-DISCOVERY MODE ───────────────────────────────────────────────────────
else
    echo "🔍 Auto-discovery mode active (set PREVIEW_PORT to pin a port)"
    write_status_waiting "scan"

    while true; do
        NEW_PORT=$(ss -tlnH 2>/dev/null \
            | awk '{print $4}' \
            | awk -F':' '{print $NF}' \
            | grep -E '^[0-9]+$' \
            | grep -vE "$EXCL_PORTS" \
            | sort -n \
            | head -n 1 || true)

        if [ -n "$NEW_PORT" ] && [ "$NEW_PORT" != "$CURRENT_PORT" ]; then
            # New port appeared
            [ -n "$CURRENT_PORT" ] && echo "♻️  Port changed: $CURRENT_PORT → $NEW_PORT"
            on_port_up "$NEW_PORT"
        elif [ -z "$NEW_PORT" ] && [ -n "$CURRENT_PORT" ]; then
            # Port disappeared
            on_port_down
            write_status_waiting "scan"
        elif [ -z "$NEW_PORT" ]; then
            write_status_waiting "scan"
        fi

        sleep "$POLL_INTERVAL"
    done
fi
