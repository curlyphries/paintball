# Paintball Arena

3D first-person multiplayer paintball game. Host it yourself, share a room code, and play with friends in the browser.

Built with **Godot 4.6** + a lightweight **Node.js WebSocket relay**.

## Quick Start (Self-Hosting)

### Prerequisites
- Docker + Docker Compose
- Godot 4.6+ (for exporting the game)

### 1. Clone and configure

```bash
git clone <your-repo-url> paintball-arena
cd paintball-arena
cp .env.example .env
# Edit .env — set RELAY_URL to your public server address
```

### 2. Export the game to HTML5

Open in Godot Editor, then **Project → Export → Web → Export Project** to `export/web/index.html`.

Or via command line:
```bash
godot --headless --export-release "Web" export/web/index.html
```

### 3. Launch

```bash
docker-compose up -d
```

Game is now live at `http://your-server:8080`. Players visit the URL, create/join rooms with 6-character codes.

### Without Docker

```bash
# Start relay server
cd server && npm install && npm start

# Serve the export/web/ folder with any static file server
# (must include COOP/COEP headers — see nginx.conf)
```

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
# Run relay server in dev mode (auto-restart)
cd server && npm run dev

# Open game in Godot editor
godot --editor project.godot

# Play locally (skips lobby, plays with bots)
godot --path .
```

## Assets

All from [Kenney.nl](https://kenney.nl) (MIT/CC0):
- Character + blaster models
- Sound effects
- Skybox panorama

## License

Game code: MIT. Assets: CC0/MIT (Kenney).
