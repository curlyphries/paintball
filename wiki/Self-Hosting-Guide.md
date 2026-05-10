# Self-Hosting Guide

Everything you need to host Paintball Arena for your family and friends — from a quick Docker deploy to production HTTPS setups.

---

## Prerequisites

| Requirement | Why |
|-------------|-----|
| **Godot 4.6+** | Needed to export the game to HTML5 (one-time step) |
| **Node.js 18+** | Runs the relay server |
| **Docker** (optional) | Easiest deployment method |

> **Don't have Godot?** You can download the pre-built web export from the [GitHub Releases](https://github.com/curlyphries/paintball/releases) page instead of exporting yourself.

---

## Option 1: One-Command Deploy (Docker)

The fastest way to get running:

```bash
git clone https://github.com/curlyphries/paintball.git
cd paintball
./deploy.sh
```

This script will:
1. Find your Godot installation (checks native, Flatpak, Snap)
2. Verify web export templates are installed
3. Export the game to `export/web/`
4. Create `.env` from template if it doesn't exist
5. Build and start Docker containers

**Result:** Game at `http://localhost:8080`, relay at `ws://localhost:9090`

### Stopping

```bash
docker-compose down
```

### Updating

```bash
git pull
./deploy.sh    # re-exports and restarts
```

---

## Option 2: Docker Compose (Manual)

If `deploy.sh` doesn't fit your setup:

```bash
# 1. Export the game (skip if using pre-built release)
godot --headless --path . --export-release "Web" export/web/index.html

# 2. Configure
cp .env.example .env
nano .env   # adjust ports if needed

# 3. Start
docker-compose up -d --build
```

### What Docker Compose Runs

| Service | Image | Port | Purpose |
|---------|-------|------|---------|
| `relay` | Built from `server/` | 9090 | WebSocket relay server |
| `web` | `nginx:alpine` | 8080 | Serves the HTML5 game with COOP/COEP headers |

### Customizing Ports

Edit `.env`:

```bash
RELAY_PORT=9090     # WebSocket relay
WEB_PORT=8080       # Web server
RELAY_URL=ws://your-server:9090   # URL players connect to
```

---

## Option 3: All-in-One Docker Image

A single container that bundles the relay server + nginx:

```bash
# Build
docker build -t paintball .

# Run
docker run -p 8080:80 -p 9090:9090 paintball
```

This image is also available from GitHub Container Registry on tagged releases:

```bash
docker run -p 8080:80 -p 9090:9090 ghcr.io/curlyphries/paintball:latest
```

---

## Option 4: Without Docker

### Relay Server

```bash
cd server
npm install
npm start    # listens on port 9090
```

For development with auto-restart:
```bash
npm run dev
```

### Web Server

Serve the `export/web/` directory with **any** static file server, but you **must** set these HTTP headers (required for Godot WASM / SharedArrayBuffer):

```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

#### Example: Python (quick test)

Python's built-in server doesn't set COOP/COEP headers. Use a wrapper:

```python
# serve.py
from http.server import HTTPServer, SimpleHTTPRequestHandler
import os

class CORPHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        super().end_headers()

os.chdir('export/web')
HTTPServer(('0.0.0.0', 8080), CORPHandler).serve_forever()
```

```bash
python3 serve.py
```

#### Example: nginx (reference config included)

```bash
# Copy the included nginx config
sudo cp nginx.conf /etc/nginx/sites-available/paintball
sudo ln -s /etc/nginx/sites-available/paintball /etc/nginx/sites-enabled/
sudo nginx -t && sudo nginx -s reload
```

---

## Production: HTTPS + Reverse Proxy

For hosting on a real server with a domain name and SSL.

### nginx + Let's Encrypt

```nginx
server {
    listen 443 ssl http2;
    server_name paintball.yourdomain.com;

    ssl_certificate /etc/letsencrypt/live/paintball.yourdomain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/paintball.yourdomain.com/privkey.pem;

    # Required headers for Godot WASM
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;

    # Serve the game
    root /path/to/paintball/export/web;
    index index.html;

    location / {
        try_files $uri $uri/ /index.html;
    }

    # WebSocket relay proxy
    location /ws {
        proxy_pass http://127.0.0.1:9090;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_read_timeout 86400;
    }

    # Cache static assets
    location ~* \.(wasm|pck|js|worker\.js)$ {
        add_header Cross-Origin-Opener-Policy "same-origin" always;
        add_header Cross-Origin-Embedder-Policy "require-corp" always;
        add_header Cache-Control "public, max-age=604800";
    }
}

# HTTP → HTTPS redirect
server {
    listen 80;
    server_name paintball.yourdomain.com;
    return 301 https://$host$request_uri;
}
```

### Caddy (simpler alternative)

```
paintball.yourdomain.com {
    header Cross-Origin-Opener-Policy "same-origin"
    header Cross-Origin-Embedder-Policy "require-corp"

    handle /ws {
        reverse_proxy localhost:9090
    }

    handle {
        root * /path/to/paintball/export/web
        file_server
        try_files {path} /index.html
    }
}
```

Caddy handles SSL automatically via Let's Encrypt.

### Auto-Detection

The Godot client **auto-detects** the relay URL from the page origin. If the game is served at `https://paintball.yourdomain.com`, it will try to connect the WebSocket to `wss://paintball.yourdomain.com/ws`. No client-side configuration needed.

---

## Subdirectory Hosting

If you want to serve the game at a subpath (e.g., `https://yourdomain.com/games/paintball/`):

```nginx
location /games/paintball/ {
    alias /path/to/paintball/export/web/;
    add_header Cross-Origin-Opener-Policy "same-origin" always;
    add_header Cross-Origin-Embedder-Policy "require-corp" always;
    try_files $uri $uri/ /games/paintball/index.html;
}

location /games/paintball/ws {
    proxy_pass http://127.0.0.1:9090;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
}
```

---

## Firewall / Port Requirements

| Port | Protocol | Direction | Purpose |
|------|----------|-----------|---------|
| 8080 (or 80/443) | TCP | Inbound | Web server (game client) |
| 9090 | TCP | Inbound | WebSocket relay (if not proxied) |

If using a reverse proxy, only port 80/443 needs to be open — the relay runs behind the proxy.

---

## Troubleshooting

### "SharedArrayBuffer is not defined"

The COOP/COEP headers are missing. Make sure your web server sends:
```
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
```

### Game loads but can't connect to relay

- Check that the relay server is running (`npm start` or Docker container)
- Verify the WebSocket URL — in browser DevTools console, look for `[Network] Connecting to: ws://...`
- If behind a reverse proxy, ensure WebSocket upgrade is configured

### "Room not found" error

- Room codes expire when all players leave
- Codes are case-insensitive (auto-uppercased)
- Check that both players are connecting to the same relay server

### Game is very slow / choppy

- Godot WASM is demanding — Chrome/Edge tend to perform better than Firefox
- Close other heavy tabs
- Reduce the number of bots (fewer AI = less CPU)

### Export fails ("templates not found")

Install Godot export templates:
1. Open Godot Editor
2. **Editor → Manage Export Templates → Download and Install**
3. Or download from [godotengine.org/releases](https://github.com/godotengine/godot/releases)

---

## Resource Requirements

### Server (relay only)

- **CPU:** Minimal (< 1% for 8 players)
- **RAM:** ~30 MB (Node.js baseline)
- **Bandwidth:** ~2 KB/s per player (position updates)
- **Disk:** None (no persistence)

### Client (browser)

- **CPU:** Moderate (WebAssembly + 3D rendering)
- **RAM:** ~200–400 MB
- **GPU:** Basic WebGL 2.0 support
- **Browser:** Chrome, Edge, Firefox, or Safari 16.4+
