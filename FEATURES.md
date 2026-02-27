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

## 4. 🔍 Dynamic "Live Preview" Auto-Proxy

### Feature

The hardest part about cloud development is seeing the web app you are building. If you are coding a React app and type `npm run dev`, it binds to port `5173`. If you run a Python Flask app, it binds to `5000`. Normally, in a cloud container, you would have to expose and map each of these ports manually via Docker files or Cloud Provider dashboards to see them.

### How to Use

1. In the terminal, start your app (e.g., `npm run dev` or `python -m http.server 8000`).
2. Open a new browser tab and visit `https://yourdomain.com/preview/`.

_The Magic_: We wrote a background daemon called `preview-watcher.sh`. It continuously loops and parses the output of `ss -tlnp` to find any new TCP listening ports that don't belong to known system services (like Nginx, SSH, VS Code).
When you type `npm run dev`, the script detects port `5173` within 3 seconds. It dynamically generates a new `/etc/nginx/conf.d/preview.conf` routing block that ties `location /preview/` to `proxy_pass http://127.0.0.1:5173`. Finally, it runs `nginx -s reload` without dropping active Terminal WebSocket connections. Your React app is live on the internet instantly, protected by Nginx Auth. Kill the terminal process, and the route drops automatically as Nginx is reloaded again.

---

## 5. 🚀 Serverless Auto-Recovery (Custom 502)

### Feature

If you host a production Python API or Node.js server within this container, you need enterprise reliability if the code crashes.

### How to Use

1. Start your production app using PM2: `pm2 start server.js`
2. If `server.js` throws a fatal exception, PM2 catches the error.

_The Magic_: Nginx is configured to detect process failures. Instead of throwing a generic "Bad Gateway" white screen, Nginx routes the user to a stunning `502.html` dark-mode UI. It then reaches into PM2, extracts the actual programming Traceback, and prints the stack trace securely right in the browser.

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
