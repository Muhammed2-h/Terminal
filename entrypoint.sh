#!/bin/bash
set -e

echo "Starting Persistence Engine..."

# GPU Detection
if command -v nvidia-smi &> /dev/null && nvidia-smi &> /dev/null; then
    echo "✅ NVIDIA GPU Detected! Ollama will use hardware acceleration."
    export OLLAMA_GPU=true
else
    echo "ℹ️ No GPU detected or drivers missing. Falling back to CPU mode."
    export OLLAMA_GPU=false
fi

# Automatic System Updates (Security)
echo "Checking for system updates..."
apt-get update && apt-get upgrade -y && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure /data exists (this should be the mounted volume)
mkdir -p /data/root /data/home

# Function to handle persistence via symlinks without deleting image-baked files
persist_dir() {
    local target_dir=$1
    local storage_dir=$2

    echo "Syncing $target_dir with $storage_dir..."

    # Ensure storage exists
    mkdir -p "$storage_dir"

    # If target is a real directory (not yet a link), we need to migrate it
    if [ ! -L "$target_dir" ]; then
        # Merge contents: copy everything from image (target) to volume (storage) 
        # but skip files that already exist in volume to preserve persistence
        cp -an "$target_dir"/. "$storage_dir"/ 2>/dev/null || true
        
        # Now replace the directory with a symlink
        # We move it to a backup location first to be safe
        mv "$target_dir" "${target_dir}_bak"
        ln -s "$storage_dir" "$target_dir"
        
        # Finally, sync any missed files from backup and remove it
        cp -an "${target_dir}_bak"/. "$target_dir"/ 2>/dev/null || true
        rm -rf "${target_dir}_bak"
    fi
}

# Persist critical paths
# We do this BEFORE any other logic to ensure the environment is ready
persist_dir "/root" "/data/root"
persist_dir "/home" "/data/home"

# Install Premium Configs if not present
if [ ! -f "/root/.zshrc" ]; then
    echo "Installing Premium Zsh Config..."
    cp /root/.zshrc.template /root/.zshrc
fi
if [ ! -f "/root/.tmux.conf" ]; then
    echo "Installing Premium Tmux Config..."
    cp /root/.tmux.conf.template /root/.tmux.conf
fi

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
envsubst '${PORT}' < /root/nginx.conf.template > /etc/nginx/sites-available/default

# Generate ttyd start command on internal port (8081) with TMUX persistence
# Notice we omitted the -c (auth) flag here because Nginx now protects everything globally!
echo "Configuring terminal on Internal Port: 8081 with TMUX Persistence"

cat <<EOF > /usr/local/bin/start-ttyd.sh
#!/bin/bash
# -A attaches to an existing session, -s 'main' is the session name
exec /usr/local/bin/ttyd -W -p 8081 -m "${MAX_CLIENTS}" tmux new-session -A -s main
EOF
chmod +x /usr/local/bin/start-ttyd.sh

# Generate AI & Tool Launchers based on variables
cat <<'EOF' > /usr/local/bin/start-ollama.sh
#!/bin/bash
if ! command -v ollama &> /dev/null; then
    echo "Ollama not found. Installing now..."
    curl -fsSL https://ollama.com/install.sh | sh
fi
export OLLAMA_HOST="0.0.0.0"
exec ollama serve
EOF
chmod +x /usr/local/bin/start-ollama.sh

cat <<'EOF' > /usr/local/bin/start-openclaw.sh
#!/bin/bash
if [ ! -d "/root/openclaw" ]; then
    echo "Cloning OpenClaw..."
    git clone https://github.com/the-claw-team/openclaw /root/openclaw
    cd /root/openclaw && npm install
fi
cd /root/openclaw
exec npm start
EOF
chmod +x /usr/local/bin/start-openclaw.sh

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
