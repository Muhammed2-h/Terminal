# Cloud Terminal: Enterprise Feature Documentation

This document explains the advanced features built into the Cloud Terminal environment, how they work under the hood, and how you can utilize them for your cloud development workflow.

---

## 1. 🌐 The Dual Interface (Terminal & VS Code)

### Feature

The container runs two simultaneous environments that share the exact same permissions, network, and file system.

- **Web Terminal**: A raw, hardware-accelerated TTY terminal accessible via your browser. (Powered by `ttyd` and `tmux`).
- **Web IDE (VS Code)**: A full desktop-grade VS Code editor accessible via the browser. (Powered by `code-server`).

### How to Use

1. **Access Terminal**: Visit `https://yourdomain.com/`
2. **Access VS Code**: Visit `https://yourdomain.com/ide/`

_The Magic_: If you install an extension in the Web IDE or run a build script in the Web Terminal, the changes are perfectly synced because it is literally the same underlying Linux machine.

---

## 2. 🛡️ Global Zero-Trust Authenticator

### Feature

Instead of configuring passwords for every individual tool (VS Code, Nginx, Terminal, Previews), the entire cloud container is placed behind a strict impenetrable wall via Nginx `.htpasswd` Basic Auth.

### How to Use

Set the following environment variables in your cloud provider:

- `TERMINAL_USER=admin`
- `TERMINAL_PASSWORD=yoursecretpassword`

_The Magic_: This blocks automated port scanners from stealing your GPU cycles or accessing your database APIs. Nginx intercepts the traffic and drops malicious requests before they even hit the Python/Node runtimes.

---

## 3. 💾 The Persistence Engine (Zero Data Loss)

### Feature

Cloud providers (like Railway or Render) delete your disk every time you deploy an update. This container uses an advanced `entrypoint.sh` engine to permanently save your work.

### How to Use

Simply attach a Persistent Volume to `/data` in your cloud host. No configuration needed in the terminal itself.

_The Magic_: When the container boots, the engine takes the temporary `/root` and `/home` folders and physically migrates them to your permanent `/data` volume using Symlinks. Things that survive redeployments:

- Your `bash_history` and `zsh_history`.
- Globally installed NPM/Pip packages.
- VS Code Extensions, Themes, and Settings.
- Downloaded Ollama Models.

---

## 4. 🔍 Dynamic "Live Preview" Auto-Proxy

### Feature

The hardest part about cloud development is seeing the web app you are building. If you are coding a React app and type `npm run dev`, it binds to port `5173`. How do you view it?

### How to Use

1. In the terminal, start your app (e.g., `npm run dev` or `python -m http.server 8000`).
2. Open a new browser tab and visit `https://yourdomain.com/preview/`.

_The Magic_: The background daemon `preview-watcher.sh` automatically detects when you open a new TCP port and dynamically rewrites Nginx routing rules in real-time. Wait 3 seconds, and your React app is live on the internet instantly. Kill the terminal process, and the route drops automatically.

---

## 5. 🚀 Serverless Auto-Recovery (Custom 502)

### Feature

If you host a production Python API or Node.js server within this container, you need enterprise reliability if the code crashes.

### How to Use

1. Start your production app using PM2: `pm2 start server.js`
2. If `server.js` throws a fatal exception, PM2 catches the error.

_The Magic_: Nginx is configured to detect process failures. Instead of throwing a generic "Bad Gateway" white screen, Nginx routes the user to a stunning `502.html` dark-mode UI. It then reaches into PM2, extracts the actual programming Traceback, and prints the stack trace securely right in the browser.

---

## 6. 🤖 AI Readiness: Ollama & OpenClaw

### Feature

The container can run local Large Language Models using hardware acceleration.

### How to Use

1. **Start Ollama**: In your terminal, type `ollama serve`.
2. **Access API**: Your local AI API becomes available securely at `https://yourdomain.com/ollama/`.
3. **Start OpenClaw**: In your terminal, type `/usr/local/bin/start-openclaw.sh`. It will automatically clone and serve the UI on port 3000.
4. **Hardware Acceleration**: The Docker image is built on `nvidia/cuda:12.2.2`. If your host has a GPU and you deploy using `--gpus all`, Ollama automatically utilizes the VRAM.

_The Magic_: By default, AI is disabled to save cloud costs. When started manually, it securely multiplexes through Nginx, meaning you don't have to manage port bindings or firewall rules. Nginx also applies TCP optimizations and removes proxy buffering specifically for the `/ollama/` route so LLM tokens stream back to the UI instantaneously.

---

## 7. ☁️ Cloudflare Tunnels (Bypass Firewalls)

### Feature

Sometimes you want to run this container locally on a cheap laptop under your desk, but access it globally from a fast URL without modifying your home router.

### How to Use

Set the following environment variable:

- `CLOUDFLARE_TOKEN=ey...`

_The Magic_: Supervisor automatically spins up the `cloudflared` daemon. It creates a secure outbound HTTPS connection to Cloudflare's Edge network. Your container is now safely isolated from the public internet, but globally routing through Cloudflare's CDN.

---

## 8. 🐳 Docker-in-Docker (DinD)

### Feature

You are running a Docker container. But what if you want to deploy Docker containers _inside_ your terminal?

### How to Use

1. Make sure your container host provides `--privileged` mode.
2. Set `ENABLE_DIND=true`.

_The Magic_: Supervisor starts an isolated Docker daemon (`dockerd`). You can now type `docker build` or `docker-compose up` directly inside the Web Terminal.

---

## 9. 🧱 Anti-DDoS & Botnet Protection

### Feature

The internet is filled with automated bots looking for exposed cloud infrastructure.

### How to Use

No configuration required. It works out of the box.

_The Magic_: Nginx uses `limit_req_zone` memory banks. If an IP address attempts to guess your password or query the terminal more than 10 times a second, it triggers a "Burst Limit". Nginx immediately drops their connection packets, saving your CPU graph from spiking during an attack.

---

## 10. ✨ Automated Dotfiles Bootstrapper

### Feature

Make your remote cloud container feel exactly like your home laptop.

### How to Use

Set the following environment variable:

- `DOTFILES_REPO=https://github.com/your-username/dotfiles.git`

_The Magic_: The moment the container boots for the very first time, it checks the Persistence Engine. It auto-clones your repo into the permanent `/data` volume and executes your `install.sh` script to load your custom Vim bindings, themes, and aliases before you even log in.
