# Paintball Arena

A 3D first-person multiplayer paintball game that runs in the browser. Host it yourself, share a room code, and play with family and friends — no installs required.

Built with **Godot 4.6** (GDScript) + a lightweight **Node.js WebSocket relay server**.

> **Vibecoded with [Windsurf](https://codeium.com/windsurf)** — this entire game was built using AI-assisted development. See [How It Was Built](../../wiki/How-It-Was-Built) for the full story.

---

## Features

- **Browser-based** — no downloads, just visit a URL
- **Multiplayer** — up to 8 players via room codes
- **AI bots** — fill empty slots with configurable bot opponents
- **3 game modes** — Deathmatch, Team vs Team, Capture the Flag
- **3 maps** — Warehouse, Courtyard, Arena
- **5 weapons** — Pistol, Rifle, Sniper, Shotgun, SMG
- **1-hit elimination** — one paintball = out (this is paintball, after all)
- **In-game chat** — talk with teammates and opponents
- **End-of-match scoreboard** — kills, deaths, K/D, accuracy, streaks, MVP
- **Paint splatters** — surfaces get painted with every shot
- **Death animations** — characters fall over and linger before respawning
- **Self-hostable** — one command deploys everything with Docker

---

## Quick Start (Self-Hosting)

### Prerequisites

- **Docker + Docker Compose** (recommended)
- **Godot 4.6+** (for exporting the game to HTML5)

### One-Command Deploy

```bash
git clone https://github.com/curlyphries/paintball.git
cd paintball
./deploy.sh
```

The script will:
1. Find your Godot installation (native, Flatpak, or Snap)
2. Verify web export templates are installed
3. Export the game to HTML5
4. Start the Docker stack (relay server + nginx)

Game is live at **`http://localhost:8080`**. Share the URL with friends — they create or join rooms with 6-character codes.

### Manual Deploy

```bash
# 1. Export the game
godot --headless --path . --export-release "Web" export/web/index.html

# 2. Configure environment
cp .env.example .env   # Edit ports/relay URL if needed

# 3. Start services
docker-compose up -d
```

### Without Docker

```bash
# Start the relay server
cd server && npm install && npm start

# Serve export/web/ with any static file server
# IMPORTANT: Must set these headers (required for WASM threads):
#   Cross-Origin-Opener-Policy: same-origin
#   Cross-Origin-Embedder-Policy: require-corp
# See nginx.conf for a reference configuration.
```

### Production (HTTPS + Reverse Proxy)

If hosting behind nginx or Caddy with SSL:

1. Proxy WebSocket traffic to the relay: `/ws` → `http://127.0.0.1:9090`
2. Serve `export/web/` with COOP/COEP headers
3. The game auto-detects the relay URL from the page origin — no config needed

See the [Self-Hosting Guide](../../wiki/Self-Hosting-Guide) for detailed instructions.

---

## How It Works

```
Browser (Player A) ←──WebSocket──→ Relay Server (port 9090) ←──WebSocket──→ Browser (Player B)
                                          ↕
                                    Room Code System
                                   (create / join / relay)
```

1. One player clicks **Create Room** → gets a 6-character code
2. Friends enter the code → everyone joins the lobby
3. Host clicks **Start** → game begins for all players simultaneously
4. The relay server routes packets between browsers — **no game logic runs on the server**

All gameplay, physics, and AI run client-side in each player's browser via Godot's WASM export.

---

## Controls

| Key | Action |
|-----|--------|
| **WASD** | Move |
| **Mouse** | Aim / Look |
| **Left Click** | Shoot |
| **Right Click** | Aim (zoom) |
| **Shift** | Sprint |
| **Space** | Jump |
| **Ctrl** | Crouch |
| **R** | Reload |
| **1–5** | Select weapon |
| **Scroll** | Cycle weapons |
| **V** | Toggle 1st / 3rd person camera |
| **T** | Open chat |
| **Enter** | Send message |
| **Esc** | Close chat / Release cursor |
| **?** (Shift+/) | Toggle hotkey help overlay |

---

## Game Modes

| Mode | Description |
|------|-------------|
| **Team vs Team** | Round-based elimination. First team to win 3 rounds (configurable) wins the match. |
| **Deathmatch** | Free-for-all. Everyone respawns. Most kills when time expires wins. |
| **Capture the Flag** | Team-based objective mode (round-based). |

---

## Weapons

| Weapon | Fire Rate | Magazine | Spread | Notes |
|--------|-----------|----------|--------|-------|
| **Pistol** | Slow | 12 | Tight | Default starting weapon |
| **Rifle** | Fast | 30 | Very tight | All-purpose |
| **Sniper** | Very slow | 5 | None | Perfect accuracy, long range |
| **Shotgun** | Slow | 8 | Wide | 6 pellets per shot |
| **SMG** | Very fast | 45 | Moderate | Spray and pray |

All weapons are **1-hit kill** — this is paintball!

---

## End-of-Match Scoreboard

At the end of every match, a full scoreboard shows:

| Stat | Description |
|------|-------------|
| **Kills** | Total eliminations |
| **Deaths** | Times eliminated |
| **K/D** | Kill/death ratio |
| **Accuracy** | Shots hit ÷ shots fired |
| **Streak** | Best consecutive kills without dying |
| **Score** | `kills×100 + streak×50 − deaths×25 + rounds_survived×30` |
| **MVP** | Highest score — highlighted in gold |

---

## Project Structure

```
paintball/
├── scripts/                  # Game logic (GDScript)
│   ├── game_settings.gd      # Autoload — modes, maps, bot config
│   ├── game_state.gd         # Autoload — rounds, scoring, stats
│   ├── network_manager.gd    # Autoload — WebSocket client
│   ├── main_game.gd          # Game orchestrator (spawning, rounds, match flow)
│   ├── player.gd             # Player controller (movement, shooting, camera)
│   ├── bot.gd                # AI bot (patrol, chase, shoot state machine)
│   ├── weapon.gd             # Weapon mechanics (fire rate, reload, magazine)
│   ├── projectile.gd         # Paintball physics + hit detection
│   ├── hud.gd                # HUD, chat, help overlay, scoreboard
│   ├── game_sync.gd          # Multiplayer state sync
│   ├── net_player.gd         # Remote player puppet
│   ├── lobby.gd              # Multiplayer lobby UI
│   ├── main_menu.gd          # Main menu + settings
│   ├── pause_menu.gd         # Pause menu
│   └── paint_splat.gd        # Paint splatter effect
├── scenes/                   # Godot scenes (.tscn)
│   ├── main.tscn             # Game scene (HUD, players, world)
│   ├── main_menu.tscn        # Main menu
│   ├── lobby.tscn            # Multiplayer lobby
│   ├── player.tscn           # Player character
│   ├── bot.tscn              # AI bot character
│   ├── net_player.tscn       # Remote player puppet
│   ├── projectile.tscn       # Paintball projectile
│   ├── paint_splat.tscn      # Paint splatter decal
│   ├── pause_menu.tscn       # Pause overlay
│   └── maps/                 # Map scenes
│       ├── warehouse.tscn    # Indoor warehouse
│       ├── courtyard.tscn    # Outdoor courtyard
│       └── arena.tscn        # Circular arena
├── server/                   # WebSocket relay server (Node.js)
│   ├── index.js              # Room management, chat relay, packet routing
│   ├── package.json          # Dependencies (ws only)
│   └── Dockerfile            # Container build
├── assets/                   # Game assets (Kenney.nl — CC0/MIT)
│   ├── models/               # Character + weapon .glb files
│   ├── audio/                # Sound effects
│   └── textures/             # Skybox, surfaces
├── export/web/               # HTML5 export output (gitignored)
├── .github/workflows/
│   └── deploy.yml            # CI/CD: export → deploy → Docker → release
├── docker-compose.yml        # One-command deployment
├── Dockerfile                # All-in-one image (relay + nginx)
├── nginx.conf                # Static file server (COOP/COEP headers)
├── deploy.sh                 # One-command local deploy script
├── export_presets.cfg         # Godot export settings
├── .env.example              # Configuration template
└── LICENSE                   # MIT
```

---

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `RELAY_PORT` | `9090` | WebSocket relay server port |
| `WEB_PORT` | `8080` | HTTP port for the game client |
| `RELAY_URL` | `ws://localhost:9090` | Public relay URL players connect to |

For production, use `wss://` with a reverse proxy handling TLS termination.

---

## Development

```bash
# Run relay server with auto-restart
cd server && npm run dev

# Open in Godot editor
godot --editor project.godot

# Play locally (single-player with bots, no server needed)
godot --path .
```

The game auto-detects its environment:
- **Browser** — derives WebSocket URL from the page origin (works on any domain/path)
- **Desktop** — uses `network/relay_url` from `project.godot` (default `ws://localhost:9090`)
- **Lobby** — manual server URL override for testing

---

## CI/CD

The GitHub Actions workflow (`.github/workflows/deploy.yml`) runs on every push to `main`:

1. **Export** — installs Godot + templates, exports to HTML5
2. **Deploy** — triggers a webhook to update the live server
3. **Docker** — builds and pushes images to GHCR (on version tags)
4. **Release** — creates a GitHub Release with the web export zip (on version tags)

---

## Wiki

For deeper documentation, see the **[project wiki](../../wiki)**:

- [Home](../../wiki/Home) — Overview and navigation
- [Architecture](../../wiki/Architecture) — System design and data flow
- [Game Mechanics](../../wiki/Game-Mechanics) — Modes, weapons, scoring, stats
- [Relay Server](../../wiki/Relay-Server) — Protocol, message types, security
- [Scripts Reference](../../wiki/Scripts-Reference) — Every GDScript file explained
- [Self-Hosting Guide](../../wiki/Self-Hosting-Guide) — Docker, manual, HTTPS, reverse proxy
- [Development Guide](../../wiki/Development-Guide) — Forking, modding, adding maps/weapons
- [How It Was Built](../../wiki/How-It-Was-Built) — The vibecoding story

---

## Assets

All game assets from [Kenney.nl](https://kenney.nl) (CC0 / MIT):
- Character + blaster 3D models
- Sound effects (shooting, impacts, UI)
- Skybox panorama texture

---

## License

**Game code:** MIT — see [LICENSE](LICENSE).
**Assets:** CC0 1.0 / MIT ([Kenney.nl](https://kenney.nl)).
