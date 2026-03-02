#!/bin/bash
set -e
# NOTE: Keep this script fast. Services (nginx, ttyd) must start within seconds.
# Any slow I/O here delays the terminal becoming available.

echo "Starting Persistence Engine..."

# GPU Detection
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA GPU Detected! Ollama will use hardware acceleration."
    export OLLAMA_GPU=true
else
    echo "ℹ️ No GPU detected or drivers missing. Falling back to CPU mode."
    export OLLAMA_GPU=false
fi

# NOTE: apt-get upgrade is intentionally NOT run here.
# Running it on every boot blocks startup for 30-120 seconds.
# Bake updated packages into a new Docker image instead.

# Ensure /data exists (this should be the mounted volume)
mkdir -p /data/root /data/home

# ── Persistence via symlinks ──────────────────────────────────────────────────
# IMPORTANT: The initial cp (first-run only) is run in the BACKGROUND so it
# does NOT block supervisord/ttyd from starting. The terminal is usable within
# seconds even while the volume is being seeded for the first time.
persist_dir() {
    local target_dir=$1
    local storage_dir=$2

    mkdir -p "$storage_dir"

    if [ ! -L "$target_dir" ]; then
        echo "Persisting $target_dir → $storage_dir (background copy)..."
        # Move the real dir aside and immediately create the symlink so the
        # rest of the entrypoint and supervisord can proceed without waiting.
        mv "$target_dir" "${target_dir}_bak"
        ln -s "$storage_dir" "$target_dir"
        # Seed the volume in background — terminal stays responsive while this runs
        ( cp -an "${target_dir}_bak"/. "$storage_dir"/ 2>/dev/null || true
          rm -rf "${target_dir}_bak"
          echo "  ✅ Background seed of $storage_dir complete." ) &
    else
        echo "  ✅ $target_dir already persisted."
    fi
}

mkdir -p /data/root /data/home
persist_dir "/root" "/data/root"
persist_dir "/home" "/data/home"

# Smart-merge .zshrc: overwrite the system portion from the template but preserve
# anything the user has added between # BEGIN USER CONFIG / # END USER CONFIG markers.
#
# CRITICAL: We read from /etc/cloud-terminal/zshrc.template (baked fresh into every
# Docker image, outside of /root so it is NEVER persisted to /data).
# Reading from /root/.zshrc.template would silently use the OLD stale version from
# the volume — that was why every previous .zshrc fix was invisible.
echo "Applying latest terminal configs from image templates..."
TEMPLATE_DIR="/etc/cloud-terminal"

if [ -f "/root/.zshrc" ]; then
    USER_BLOCK=$(awk '/# BEGIN USER CONFIG/{found=1} found{print} /# END USER CONFIG/{found=0}' /root/.zshrc 2>/dev/null || true)
else
    USER_BLOCK=""
fi

cp -f "${TEMPLATE_DIR}/zshrc.template" /root/.zshrc

if [ -n "$USER_BLOCK" ]; then
    awk 'BEGIN{skip=0} /# BEGIN USER CONFIG/{skip=1;print;next} /# END USER CONFIG/{skip=0} !skip{print}' /root/.zshrc > /tmp/.zshrc.tmp
    echo "" >> /tmp/.zshrc.tmp
    echo "$USER_BLOCK" >> /tmp/.zshrc.tmp
    mv /tmp/.zshrc.tmp /root/.zshrc
fi

cp -f "${TEMPLATE_DIR}/tmux.conf.template" /root/.tmux.conf
echo "  ✅ .zshrc and .tmux.conf updated from fresh image templates."



# Automated "Dotfiles" Bootstrapper
if [ -n "$DOTFILES_REPO" ]; then
    echo "⚙️ Bootstrapping Dotfiles from $DOTFILES_REPO..."
    if [ ! -d "/root/dotfiles" ]; then
        git clone "$DOTFILES_REPO" /root/dotfiles
        if [ -f "/root/dotfiles/install.sh" ]; then
            chmod +x /root/dotfiles/install.sh
            /root/dotfiles/install.sh || echo "⚠️ Dotfiles install.sh exited with non-zero status. Continuing..."
        fi
    else
        echo "✅ Dotfiles already initialized."
    fi
fi

# Generate Global Zero-Trust Nginx Authentication Overlay
echo "🔒 Securing container endpoints for user: $TERMINAL_USER..."
htpasswd -bc /etc/nginx/.htpasswd "$TERMINAL_USER" "$TERMINAL_PASSWORD"

# Generate Nginx configuration
echo "Configuring Nginx reverse proxy on port ${PORT}..."
# Read nginx template from /etc/cloud-terminal (baked into image, NOT on /data volume)
# Reading from /root/nginx.conf.template would hit the network volume = potential block
envsubst '${PORT}' < /etc/cloud-terminal/nginx.conf.template > /etc/nginx/sites-available/default

# Generate ttyd start command on internal port (8081)
# Auth is handled globally by Nginx - no -c flag needed here.
#
# Process Persistence:
#   - Default (PERSIST_TMUX unset):
#     ttyd launches plain zsh. The .zshrc sets NOHUP so background jobs (&)
#     survive tab close. Use `persist <cmd>` or `tmux` for foreground apps.
#   - PERSIST_TMUX=true:
#     ttyd wraps every session in tmux. Closing the tab NEVER kills processes.
#     All users share the 'main' tmux session (multi-window).
echo "Configuring terminal on Internal Port: 8081"

if [ "${PERSIST_TMUX:-false}" = "true" ]; then
    echo "  Mode: PERSIST_TMUX=true → tmux session persistence enabled"
    cat <<EOF > /usr/local/bin/start-ttyd.sh
#!/bin/bash
# Attach to existing tmux session or create a new one.
# SIGHUP from tab close never reaches user processes since tmux is the middleman.
exec /usr/local/bin/ttyd -W -p 8081 -m "${MAX_CLIENTS}" tmux new-session -A -s main
EOF
else
    echo "  Mode: plain zsh (use 'persist <cmd>' or 'tmux' for persistence)"
    cat <<EOF > /usr/local/bin/start-ttyd.sh
#!/bin/bash
# Plain zsh shell. .zshrc configures NOHUP so background jobs survive tab close.
# For foreground apps: run `persist npm run dev` or open tmux first.
exec /usr/local/bin/ttyd -W -p 8081 -m "${MAX_CLIENTS}" zsh
EOF
fi
chmod +x /usr/local/bin/start-ttyd.sh



cat <<'EOF' > /usr/local/bin/start-dockerd.sh
#!/bin/bash
if [ "$ENABLE_DIND" = "true" ]; then
    exec /usr/bin/dockerd --host=unix:///var/run/docker.sock --host=tcp://127.0.0.1:2375
else
    sleep infinity
fi
EOF
chmod +x /usr/local/bin/start-dockerd.sh

cat <<'EOF' > /usr/local/bin/start-cloudflared.sh
#!/bin/bash
if [ -n "$CLOUDFLARE_TOKEN" ]; then
    exec cloudflared tunnel --no-autoupdate run --token "$CLOUDFLARE_TOKEN"
else
    sleep infinity
fi
EOF
chmod +x /usr/local/bin/start-cloudflared.sh

# Start Supervisor in the foreground to keep the container alive and forward logs
echo "Initializing System Services..."
exec /usr/bin/supervisord -c /etc/supervisor/conf.d/supervisord.conf
