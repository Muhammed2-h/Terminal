# Cloud Terminal: Enterprise Feature Documentation

This document explains the advanced features built into the Cloud Terminal environment, how they work under the hood, and how you can utilize them for your cloud development workflow.

---

## 1. 🌐 The Dual Interface (Terminal & VS Code)

### Feature

The container runs two simultaneous environments that share the exact same permissions, network, and file system.

- **Web Terminal**: A raw, hardware-accelerated TTY terminal accessible via your browser. (Powered by `ttyd` + `zsh` with Oh My Zsh).
- **Web IDE (VS Code)**: A full desktop-grade VS Code editor accessible via the browser. (Powered by `code-server`).

### How to Use

1. **Access Terminal**: Visit `https://yourdomain.com/`
2. **Access VS Code**: Visit `https://yourdomain.com/ide/`
3. **Optional tmux**: Type `tmux` inside the terminal anytime for full session persistence across tab closes.

_The Magic_: Both interfaces run on the same underlying Linux machine — installing an extension in VS Code or running a build in the terminal affects the exact same filesystem. The terminal launches a plain `zsh` shell for speed and simplicity. If you need your processes to survive closing the browser tab, simply type `tmux` or use the `persist` command (see Feature 6).

---

## 2. 🛡️ Global Zero-Trust Authenticator & Nginx Reverse Proxy

### Feature

Instead of configuring isolated passwords for every individual tool (VS Code, Nginx, Terminal, Previews, API endpoints), the entire cloud container is placed behind a strict impenetrable wall via Nginx `.htpasswd` Basic Authentication. Nginx acts as the single entry point (Reverse Proxy) for all internal container services.

### How to Use

Set the following environment variables in your cloud provider:

- `TERMINAL_USER=admin`
- `TERMINAL_PASSWORD=yoursecretpassword`

_The Magic_: When the container starts, the `entrypoint.sh` dynamically generates the `.htpasswd` file. Nginx intercepts all traffic on Port 8080. If an unauthenticated user or automated botnet scanner from the public web tries to hit your React app Preview, your Ollama API, or the VS Code UI, Nginx immediately throws a `401 Unauthorized` block and drops the packet. It never even reaches the internal Python/Node runtimes, securing your GPU cycles and source code completely. Nginx handles the SSL termination (if behind a load balancer), WebSocket `Upgrade` headers, and local proxying to ports `8081` (terminal), `8082` (VS Code), etc.

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

## 4. 🔍 Enhanced "Live Preview" System

### Feature

The hardest part about cloud development is seeing the web app you are building. Start any web server in the terminal — React, Next.js, FastAPI, Flask, or a simple static server — and a premium preview panel appears automatically at `/preview/` with zero configuration.

### How to Use

1. In the terminal, start your app: `npm run dev`, `python -m http.server 3000`, `uvicorn app:app`, etc.
2. Visit `https://yourdomain.com/preview/` in your browser.
3. The panel detects your app within **2 seconds** and loads it in a full-height iframe.

**Optional — Pin a specific port** (useful if multiple ports are active):

```
PREVIEW_PORT=3000
PREVIEW_APP_NAME=MyApp   # override the auto-detected app name
```

**Direct port forwarding** — access any port instantly without any configuration:

```
https://yourdomain.com/port/3000/
https://yourdomain.com/port/8888/   # Jupyter Notebook, etc.
```

_The Magic_: The system is built in two layers:

**Layer 1 — `preview-watcher.sh` daemon**: Runs continuously in the background (via Supervisor). Every 2 seconds it scans `ss -tlnp` for new listening TCP ports, excluding all known system ports. When a new port appears, it:

- Inspects `/proc/<pid>/comm` and `cmdline` to detect the runtime and map it to a friendly name (`node` → `Next.js`/`Vite`, `python` → `FastAPI`/`Flask`/`Django`, `ruby`, `php`, etc.)
- Writes a `preview.conf` nginx block routing `/preview/proxy/` to that port
- Writes `/usr/share/nginx/html/preview/status.json` with `{"port":"3000","app":"Next.js"}`
- Runs `nginx -s reload` without dropping active WebSocket connections

Supports two modes:
| Mode | Trigger | Behaviour |
|------|---------|----------|
| **Auto-scan** | No env set | Finds the lowest new listening TCP port automatically |
| **Static pin** | `PREVIEW_PORT=3000` | Waits for exactly that port; reconnects if the app restarts |

**Layer 2 — `preview.html` panel**: A premium dark-theme UI served at `/preview/` that:

- Polls `status.json` every 2 seconds and updates the iframe live
- Shows a **live status badge** with pulsing green dot when app is active
- Displays the **detected app name** and active port in the toolbar
- Provides a **Refresh** button and a **Popout** button (opens `/preview/proxy/` full-screen in new tab)
- Shows a **no-app state** with ready-to-paste starter commands when nothing is running
- Handles **error recovery** with a retry button
- Automatically switches when the port changes (e.g. app restarts on a different port)

---

## 5. 🚀 Serverless Auto-Recovery (Custom 502)

### Feature

If you host a production Python API or Node.js server within this container, you need enterprise reliability if the code crashes.

### How to Use

1. Start your production app using PM2: `pm2 start server.js`
2. If `server.js` throws a fatal exception, PM2 catches the error.

_The Magic_: Nginx is configured to detect process failures. Instead of throwing a generic "Bad Gateway" white screen, Nginx routes the user to a stunning `502.html` dark-mode UI. It then reaches into PM2, extracts the actual programming Traceback, and prints the stack trace securely right in the browser.

---

## 6. ⚡ Process Persistence (Survive Tab Close)

### Feature

By default, closing the browser tab sends a `SIGHUP` signal to the shell, which kills all foreground child processes. This container solves this at multiple layers so your apps keep running even when you close the tab.

### How to Use

**Method 1 — `persist` command** (recommended for foreground apps):

```bash
persist npm run dev
persist python app.py
persist node server.js
```

Prints the PID and a log file path. Use `tail -f /tmp/persist-node-<PID>.log` to follow output. Kill with `kill <PID>`.

**Method 2 — Background with `&`** (works automatically):

```bash
npm run dev &       # zsh NOHUP option protects this from tab-close SIGHUP
disown              # optional: remove from job table
```

**Method 3 — tmux** (full session persistence):

```bash
tmux                # open a tmux session
npm run dev         # run app inside tmux — tab close has zero effect
# Ctrl+B, D to detach; come back anytime with: tmux attach
```

**Method 4 — `PERSIST_TMUX=true` env var** (admin opt-in, Railway/Docker):
Set this in your cloud provider's environment variables. Every terminal session will automatically open inside a shared `tmux` session. Processes are 100% persistent — no user action required.

**Useful aliases** available in the terminal:

- `logs` — tail all `persist` background log files
- `plist` — list running background processes with uptime

_The Magic_: The persistence system works at three levels:

1. **`setopt NOHUP` + `setopt NO_CHECK_JOBS`** in `.zshrc` — prevents zsh from forwarding `SIGHUP` to background jobs (`&`) when the shell exits. This is automatic for anything backgrounded.
2. **`persist()` function** — uses `setsid` to create a completely new Linux process session, fully detached from the terminal PTY. The process becomes a child of PID 1 and cannot receive `SIGHUP` under any circumstances.
3. **`PERSIST_TMUX=true`** — wraps `ttyd` with `tmux new-session -A -s main`. Since `tmux` is itself the process group leader and a proper session manager daemon, closing the WebSocket has zero effect on anything running inside it.

---

## 7. ☁️ Cloudflare Tunnels (Bypass Firewalls & CGNAT)

### Feature

Sometimes you want to run this container locally on a cheap laptop under your desk or a Raspberry Pi, but access it globally from a fast URL without modifying your home router, port-forwarding, or dealing with Carrier-Grade NAT (CGNAT) from your ISP.

### How to Use

Set the following environment variable:

- `CLOUDFLARE_TOKEN=ey...`

_The Magic_: When this variable is detected by Supervisor, it automatically spins up the `cloudflared` daemon in the background alongside Nginx. Rather than waiting for incoming traffic on port 8080 (which firewalls usually block), `cloudflared` creates a secure _outbound_ HTTPS connection to Cloudflare's Edge network. Cloudflare proxies the traffic securely from your public Cloudflare domain directly down into the container. Your container is completely invisible to the public internet, has no open open inbound ports, yet remains robustly accessible globally through Cloudflare's CDN.

---

## 8. 🐳 Docker-in-Docker (DinD)

### Feature

You are running a Docker container. But what if you want to deploy Docker containers _inside_ your terminal?

### How to Use

1. Make sure your container host provides `--privileged` mode.
2. Set `ENABLE_DIND=true`.

_The Magic_: Supervisor starts an isolated Docker daemon (`dockerd`). You can now type `docker build` or `docker-compose up` directly inside the Web Terminal.

---

## 9. 🧱 Anti-DDoS & Botnet Protection (Nginx Limit Zones)

### Feature

The public internet is filled with automated bots scanning every IP address for weak points, trying brute-force password attacks, or simply launching Layer 7 Application DDoS attacks to run up your server bills.

### How to Use

No configuration required. It works out of the box entirely natively within the Nginx templating engine.

_The Magic_: The container utilizes Nginx memory directives: `limit_req_zone $binary_remote_addr zone=terminal_limit:10m rate=10r/s;`. This maps 10 Megabytes of RAM to track IP addresses. If an attacker attempts to guess your password or send junk HTTP traffic to your terminal more than 10 times a second, it hits the `limit_req` directive. A short "Burst" is allowed for things like large file loads, but if it sustains, Nginx simply drops their connection packets instantly (returning 503 Service Unavailable). This happens at the very edge of the container in highly optimized C-code, completely sparing your Python processes and CPU usage graph from spiking during an attack.

---

## 10. ✨ Automated Dotfiles Bootstrapper

### Feature

Make your remote cloud container feel exactly like your home laptop.

### How to Use

Set the following environment variable:

- `DOTFILES_REPO=https://github.com/your-username/dotfiles.git`

_The Magic_: The moment the container boots for the very first time, it checks the Persistence Engine. It auto-clones your repo into the permanent `/data` volume and executes your `install.sh` script to load your custom Vim bindings, themes, and aliases before you even log in.
