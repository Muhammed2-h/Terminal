# Use NVIDIA CUDA base for automatic GPU acceleration support
FROM nvidia/cuda:12.2.2-runtime-ubuntu22.04

# Avoid prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Update system and install core dependencies
RUN apt-get update && apt-get upgrade -y && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    wget \
    git \
    sudo \
    locales \
    tzdata \
    ca-certificates \
    supervisor \
    nano \
    tar \
    unzip \
    nginx \
    gettext-base \
    apache2-utils \
    zsh \
    tmux \
    python3 \
    python3-pip \
    python3-venv \
    python-is-python3 \
    docker.io \
    docker-compose-v2 \
    iptables \
    iproute2 \
    btop \
    nvtop \
    htop \
    jq \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Install Cloudflare Tunnels (cloudflared)
RUN wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb && \
    dpkg -i cloudflared-linux-amd64.deb && \
    rm cloudflared-linux-amd64.deb

# Install Code-Server (VS Code in Browser)
RUN curl -fsSL https://code-server.dev/install.sh | sh

# Install Oh My Zsh for a premium terminal feel
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting && \
    # Back up plugins into /etc/cloud-terminal/omz-plugins so entrypoint.sh can \
    # restore them to /data/root without any network access on a fresh volume. \
    mkdir -p /etc/cloud-terminal/omz-plugins && \
    cp -r ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions /etc/cloud-terminal/omz-plugins/ && \
    cp -r ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting /etc/cloud-terminal/omz-plugins/

# Set ZSH as default shell for root
RUN chsh -s $(which zsh)

# Set up locales
RUN locale-gen en_US.UTF-8
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    TERM=xterm-256color

# Install ttyd
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then TTYD_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then TTYD_ARCH="aarch64"; \
    else TTYD_ARCH="x86_64"; fi && \
    wget https://github.com/tsl0922/ttyd/releases/download/1.7.3/ttyd.${TTYD_ARCH} -O /usr/local/bin/ttyd && \
    chmod +x /usr/local/bin/ttyd

# Install Node.js v22 and global package managers (npm, pnpm, yarn, pm2)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    npm install -g npm@latest pnpm yarn pm2 && \
    rm -rf /var/lib/apt/lists/* && apt-get clean

# Create essential directories
RUN mkdir -p /var/log/supervisor /etc/cloud-terminal

# Set up workspace
WORKDIR /root

# Copy configuration files
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
# All templates go to /etc/cloud-terminal/ — baked into image, NEVER on /data volume.
# entrypoint.sh reads exclusively from here, never from /root.
COPY nginx.conf.template /etc/cloud-terminal/nginx.conf.template
COPY nginx.conf.template /root/nginx.conf.template
COPY .zshrc.template    /etc/cloud-terminal/zshrc.template
COPY .tmux.conf.template /etc/cloud-terminal/tmux.conf.template
COPY .zshrc.template    /root/.zshrc.template
COPY .tmux.conf.template /root/.tmux.conf.template
COPY preview-watcher.sh /usr/local/bin/preview-watcher.sh
COPY pm2-error-watcher.sh /usr/local/bin/pm2-error-watcher.sh
RUN mkdir -p /usr/share/nginx/html/preview
COPY 502.html     /usr/share/nginx/html/502.html
COPY preview.html /usr/share/nginx/html/preview/preview.html
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/preview-watcher.sh /usr/local/bin/pm2-error-watcher.sh

# Environment variables with defaults
ENV PORT=8080
ENV TERMINAL_USER=admin
ENV TERMINAL_PASSWORD=password123
ENV MAX_CLIENTS=10
ENV OLLAMA_MODEL=llama3

# Expose the terminal port
EXPOSE ${PORT}

# Healthcheck
# Use ${PORT:-8080} so the healthcheck works whether Railway overrides PORT or not.
# start-period=30s gives supervisord + nginx enough time to fully start.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=5 \
    CMD curl -f http://localhost:${PORT:-8080}/healthz || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
