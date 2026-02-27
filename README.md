# 🚀 Premium Cloud Ubuntu Terminal

A production-grade, containerized Ubuntu LTS environment with persistent storage, web-based terminal access, and built-in support for AI tools (Ollama, OpenClaw).

## ✨ Features

- **🌐 Web Terminal**: Access your terminal from any browser via `ttyd`.
- **💻 VS Code Server**: Full browser-based IDE via `code-server` mapped to `/ide/`. Shares all extensions and workspaces with your container.
- **🚀 GPU Optimized**: Automatic detection and support for NVIDIA GPUs via CUDA 12.2 base image.
- **⚡ Ultra-Low Latency**: Nginx optimizations (`tcp_nodelay`, HTTP/1.1 `keep-alive`, disabled buffering) for instant internal API responses.
- **🛠️ Multi-Language Ready**: Ships with **Node.js (v22 latest)**, `npm`, `pnpm`, `yarn`, and **Python 3** (+ `pip`, `venv`).
- **🔍 Dynamic Live Preview**: Nginx instantly detects when you start a web server in the terminal and maps it to `yourdomain.com/preview/`.
- **🐳 Docker-in-Docker (DinD)**: Run `docker build` inside your terminal (Requires `--privileged` mode).
- **☁️ Cloudflare Tunnels**: Built-in `cloudflared` for punching a secure hole to your terminal from anywhere using `CLOUDFLARE_TOKEN`.
- **✨ Dotfiles Bootstrapper**: Auto-clones and runs your laptop's dotfiles via `DOTFILES_REPO`.
- **🚀 Serverless Auto-Recovery**: Built-in `pm2` automatically restarts crashed apps. Nginx automatically detects the crash and routes to a gorgeous custom 502 page displaying the live PM2 Python/Node stack trace!
- **📊 Minimal UI Dashboards**: Fast, built-in CLI monitoring via `btop` and `nvtop` included.
- **🔄 Auto-Updates**: Automatically performs `apt upgrade` on both build and container startup.
- **💾 100% Persistence**: Data in `/root`, `/home`, and tool configs survive redeployments.
- **🤖 AI Ready**: Toggle `Ollama` and `OpenClaw` via environment variables.
- **🛡️ Global Zero-Trust Auth**: Replaced individual app logins with a global Nginx `.htpasswd` padlock. Protects **all** endpoints (Ollama, UI, Previews) simultaneously.
- **🧱 Anti-DDoS Rate Limiting**: Built-in `limit_req` zones drop malicious bot-nets attempting brute force attacks before they touch your CPU.
- **🩺 Auto-healing**: Supervisor monitors and restarts failed processes.

## 🛠️ Deployment Instructions (Railway / Docker)

### 1. Environment Variables

Configure these in your hosting dashboard:

| Variable            | Default       | Description                        |
| :------------------ | :------------ | :--------------------------------- |
| `PORT`              | `8080`        | Port for the web terminal          |
| `TERMINAL_USER`     | `admin`       | Your login username                |
| `TERMINAL_PASSWORD` | `password123` | Your login password                |
| `MAX_CLIENTS`       | `10`          | Max simultaneous terminal sessions |
| `ENABLE_OLLAMA`     | `false`       | Set to `true` to enable Ollama     |
| `ENABLE_OPENCLAW`   | `false`       | Set to `true` to enable OpenClaw   |

### 2. Volume Mounting (CRITICAL)

For data to persist, you **MUST** mount a persistent volume to the `/data` directory.

- **Railway**: Create a Volume and mount it to `/data`.
- **Docker**: `-v my-data-volume:/data`

### 3. Railway Deployment

1. Connect your GitHub repo.
2. In Railway, go to **Settings** > **Volumes** > **Add Volume**.
3. Mount the volume to `/data`.
4. Add the Environment Variables listed above.
5. Deploy.

### 4. Render Deployment

1. Create a new **Web Service**.
2. Connect your repo.
3. Select **Docker** as the runtime.
4. Add a **Persistent Disk** mounted at `/data`.
5. Add the Environment Variables.

### 5. Universal VPS (using Docker Compose)

```bash
git clone <your-repo>
cd cloud-terminal
# Edit .env or set variables
docker-compose up -d
```

## 🧪 Local Testing

```bash
# Build the image
docker build -t cloud-terminal .

# Run with persistence
docker run -p 8080:8080 \
  -e TERMINAL_PASSWORD=mysecret \
  -e ENABLE_OLLAMA=true \
  -v ./local_data:/data \
  cloud-terminal
```

## 🧠 Redeploy Safety Explanation

Standard containers lose all changes on redeploy because they are ephemeral. This system solves this by:

1. **The /data Anchor**: Using a persistent volume mounted at `/data`.
2. **Symlink Migration**: On startup, the `entrypoint.sh` script checks if `/root` and `/home` are linked to `/data`.
3. **Internal Redirect**: If not linked, it moves existing files to the volume and replaces the system directories with symlinks.
   Result: When you install a package or save a file in `~`, it is physically stored on the persistent disk, not the container layer.

## 🔒 Production Hardening Checklist

- [ ] Change the default `TERMINAL_PASSWORD`.
- [ ] Limit `MAX_CLIENTS` to prevent OOM (Out Of Memory) attacks.
- [ ] Use a reverse proxy (like Nginx) for SSL/HTTPS.
- [ ] Ensure the `/data` volume is backed up.
- [ ] (Optional) Set up an IP IP allowlist at the firewall level.

## 🚦 Healthcheck

The container uses an isolated dummy endpoint `/healthz` on Nginx for load balancers. Monitoring this endpoint avoids polluting authentication logs or starting zombie shell sessions.

## 📄 License

This project is licensed under the **MIT License**. You are free to use, modify, and distribute this software, even for commercial purposes. See the [LICENSE](LICENSE) file for details.
