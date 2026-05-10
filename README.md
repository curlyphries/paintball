# Paintball Arena

3D first-person multiplayer paintball game. Host it yourself, share a room code, and play with friends in the browser.

Built with **Godot 4.6** + a lightweight **Node.js WebSocket relay**.

## Quick Start (Self-Hosting)

### Prerequisites
- Docker + Docker Compose
- Godot 4.6+ (for exporting the game)

### 1. Clone and deploy

```bash
git clone https://github.com/curlyphries/paintball.git
cd paintball
./deploy.sh
```

The deploy script will:
- Find your Godot installation (native, flatpak, or snap)
- Verify web export templates are installed
- Export the game to HTML5
- Start Docker (relay server + nginx)

Game is live at `http://localhost:8080`. Players visit the URL, create/join rooms with 6-character codes.

### Manual steps (if deploy.sh doesn't fit your setup)

```bash
# 1. Export game
godot --headless --path . --export-release "Web" export/web/index.html

# 2. Configure
cp .env.example .env
# Edit .env if needed (ports, relay URL)

# 3. Start
docker-compose up -d
```

### Without Docker

```bash
# Start relay server
cd server && npm install && npm start

# Serve export/web/ with any static file server that supports:
# - Cross-Origin-Opener-Policy: same-origin
# - Cross-Origin-Embedder-Policy: require-corp
# (required for SharedArrayBuffer / WASM threads)
# See nginx.conf for reference config.
```

### Behind a reverse proxy (HTTPS)

If you're hosting behind nginx/caddy with SSL:
- Proxy `/your-path/ws` → `http://127.0.0.1:9090` (WebSocket upgrade)
- Serve `export/web/` at `/your-path` with COOP/COEP headers
- The game auto-detects the relay URL from the page origin — no config needed

## How It Works

```
Browser (Player A) ←→ WebSocket Relay (port 9090) ←→ Browser (Player B)
                            ↕
                      Room Code System
```

1. One player clicks **Create Room** → gets a 6-character code
2. Friends enter the code → everyone lands in the lobby
3. Host clicks **Start** → game begins for everyone
4. Relay server routes game packets between players (no game logic on server)

## Controls

| Key | Action |
|-----|--------|
| WASD | Move |
| Mouse | Aim / Look |
| Left Click | Shoot |
| Shift | Sprint |
| Space | Jump |
| Ctrl | Crouch |
| V | Toggle first/third person |
| Esc | Release mouse cursor |

## Game Rules

- **1-hit elimination** — one paintball = out
- **Best of 5 rounds** — first to 3 wins
- **Up to 8 players** per room
- **AI bots** fill empty slots
- **Unlimited ammo** — just shoot
- Paint splatters on surfaces, fade after 5 seconds

## Project Structure

```
paintball-arena/
├── server/              # WebSocket relay server (Node.js)
│   ├── index.js         # Room management + packet relay
│   ├── package.json
│   └── Dockerfile
├── scripts/             # Godot game scripts (GDScript)
│   ├── network_manager.gd   # WebSocket client (autoload)
│   ├── lobby.gd             # Room create/join UI
│   ├── player.gd            # Player controller
│   ├── bot.gd               # AI bot behavior
│   └── ...
├── scenes/              # Godot scenes (.tscn)
│   ├── lobby.tscn       # Multiplayer lobby UI
│   ├── main.tscn        # Game scene
│   └── ...
├── export/web/          # HTML5 export output (gitignored)
├── docker-compose.yml   # One-command deployment
├── nginx.conf           # Static file server config (COOP/COEP headers)
├── .env.example         # Configuration template
└── export_presets.cfg   # Godot export configuration
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RELAY_PORT` | 9090 | WebSocket relay port |
| `WEB_PORT` | 8080 | HTTP port for game client |
| `RELAY_URL` | ws://localhost:9090 | Public relay URL (players connect here) |

For production with HTTPS, put a reverse proxy (nginx/caddy) in front and use `wss://` for the relay URL.

## Development

```bash
# Run relay server in dev mode (auto-restart on file change)
cd server && npm run dev

# Open game in Godot editor
godot --editor project.godot

# Play locally (single-player with bots, no server needed)
godot --path .
```

The game auto-detects its environment:
- **Browser**: derives WebSocket URL from page origin (works with any domain/path)
- **Desktop**: uses `network/relay_url` from `project.godot` (default: `ws://localhost:9090`)
- **Lobby server field**: manual override for testing

## Assets

All from [Kenney.nl](https://kenney.nl) (MIT/CC0):
- Character + blaster models
- Sound effects
- Skybox panorama

## License

Game code: MIT. Assets: CC0/MIT (Kenney).
