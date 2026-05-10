# How It Was Built

Paintball Arena was **vibecoded** — built entirely through AI-assisted pair programming using [Windsurf](https://codeium.com/windsurf) as the IDE and its AI assistant, Cascade, as the coding partner.

This page is a transparent look at the process: what vibecoding actually looks like in practice, what worked well, what the limitations were, and what someone forking this project should know about how the code was written.

---

## What is Vibecoding?

Vibecoding (sometimes called "vibe-driven development") is a style of programming where the human provides intent, direction, and creative decisions while an AI assistant handles the implementation details. Instead of writing every line by hand, you describe what you want at a high level and the AI writes, debugs, and iterates on the code.

Think of it as pair programming where your partner types very fast and knows every API by heart, but you're the one deciding what to build and when something feels right.

---

## The Stack Choice

The project started with a decision: **make a multiplayer game that runs in the browser with no installs.**

The AI helped evaluate the options and the choice landed on:

- **Godot 4.6** — open-source game engine with HTML5 export
- **GDScript** — Godot's built-in language (Python-like, easy to iterate on)
- **WebSocket relay** — simplest possible multiplayer architecture
- **Node.js + ws** — single-dependency relay server
- **Docker** — containerized deployment

This stack was chosen for simplicity and self-hostability. No Unity, no Unreal, no Firebase, no complex networking — just a game engine that compiles to WASM and a relay server you can run on a Raspberry Pi.

---

## How Development Actually Happened

### The Workflow

1. **Human decides what to build** — "Let's add a shotgun" or "We need a scoreboard at the end of matches"
2. **AI reads the existing code** — understands the codebase structure, patterns, and conventions
3. **AI proposes and implements** — writes the code, adds to correct files, follows existing patterns
4. **Human reviews and play-tests** — runs the game, identifies issues
5. **Iterate** — "The bots are too accurate" or "Chat input should block shooting"
6. **Export, deploy, push** — AI handles the full deploy pipeline

### What the AI Did

- Wrote all GDScript game logic (player controller, bot AI, weapons, projectiles, networking)
- Designed the scene tree hierarchy in `.tscn` files
- Implemented the WebSocket relay server from scratch
- Built the HUD, menus, and UI layouts
- Set up Docker deployment, nginx config, CI/CD pipeline
- Created this documentation and wiki

### What the Human Did

- Decided the game concept (paintball, browser-based, self-hostable)
- Chose game mechanics (1-hit kill, room codes, 5 weapons)
- Directed feature priorities ("chat first, then scoreboard")
- Play-tested and reported issues ("shooting still works while typing")
- Made creative decisions ("paint should splatter on walls")
- Approved/rejected implementation approaches

---

## Feature Development Timeline

Here's roughly how the game evolved through vibecoding sessions:

### Foundation
- Basic Godot project setup, player movement + camera
- First-person controller with WASD, mouse look, jumping, sprinting
- Simple test map (warehouse)

### Combat
- Weapon system with fire rate, magazine, reload
- Projectile physics (travel, gravity drop, hit detection)
- 1-hit elimination mechanic
- Multiple weapons (pistol, rifle, sniper, shotgun, SMG)
- Paint splatters on surfaces

### AI
- Bot state machine (patrol, chase, shoot)
- Per-bot accuracy and reaction time randomization
- Map boundary awareness
- Target detection and line-of-sight checks

### Maps
- Three map scenes (warehouse, courtyard, arena)
- Spawn point system using Godot groups
- Map selection in main menu

### Game Modes
- Team vs Team (round-based elimination)
- Deathmatch (free-for-all with respawns and time limit)
- Capture the Flag framework
- Configurable rounds-to-win and time limits

### Multiplayer
- WebSocket relay server (room codes, packet routing)
- NetworkManager autoload (connect, create, join, send)
- GameSync for position/rotation/shot/elimination sync
- NetPlayer puppets for remote players
- Lobby UI (room creation, player list, start button)
- Auto-detection of relay URL from page origin

### Polish
- Main menu with full settings UI
- Pause menu
- Death animations (tip-over + linger)
- Third-person camera toggle
- Elimination feed (top-right kill messages)
- Player list with alive/dead status

### Chat & Communication
- In-game chat panel (T to open, Enter to send)
- Chat relay through WebSocket server
- Help overlay listing all controls (? key)
- Input blocking while chatting (prevents shooting while typing)

### Competitive Stats
- Per-player stat tracking (kills, deaths, shots, hits, streaks)
- Accuracy calculation (shots hit ÷ shots fired)
- Score formula with kills, streaks, deaths penalty, rounds survived bonus
- MVP calculation
- End-of-match scoreboard UI with ranked table

### Deployment
- Dockerfile (all-in-one image)
- docker-compose.yml (relay + nginx)
- deploy.sh (one-command local deploy)
- GitHub Actions CI/CD (export → deploy → Docker → releases)
- Service worker patching for PWA support
- nginx config with required COOP/COEP headers

---

## Observations About Vibecoding

### What Worked Really Well

- **Speed** — features that might take days went from idea to deployed in a single session
- **Consistency** — the AI maintained code style and patterns across files without deviation
- **Boilerplate elimination** — Docker configs, CI/CD, nginx configs, scene files — stuff that's tedious but important
- **Knowledge breadth** — the AI knows Godot APIs, Node.js, Docker, nginx, GitHub Actions, etc. without context-switching
- **Iterative debugging** — describe a bug, the AI traces it through the code and fixes the root cause

### What Required Human Judgment

- **Game feel** — "is the shotgun spread right?" requires actually playing the game
- **Feature prioritization** — knowing what matters for the game experience
- **Creative direction** — paint splatters, death animations, gold MVP highlight — these were human decisions
- **Quality assessment** — "this is good enough" vs "this needs more work"
- **Architecture decisions** — client-authoritative vs server-authoritative, for instance

### Limitations Encountered

- **Scene editing** — `.tscn` files are text-based in Godot 4, which is great for AI, but visual layout adjustments sometimes need the editor
- **Play-testing** — the AI can't press play and evaluate how the game feels
- **Asset creation** — using pre-made assets (Kenney.nl) because AI can't model 3D characters
- **Performance tuning** — needed human to assess frame rate and feel on real hardware

---

## For Forkers

If you're forking this repo to make it your own, here are some helpful things to know:

### Code Quality

The code is clean and consistent. The AI followed GDScript conventions throughout. Comments are minimal but the code is self-documenting with descriptive variable and function names.

### Architecture

The architecture is intentionally simple:
- **3 autoloads** (`GameSettings`, `GameState`, `NetworkManager`) manage global state
- **Signals** connect everything loosely — scripts don't hard-reference each other
- **Data-driven** weapons (dictionary in `GameState`) — add weapons without new scripts
- **Scene composition** — maps are independent scenes loaded dynamically

### Extending It

The [Development Guide](Development-Guide) has step-by-step instructions for:
- Adding new maps
- Adding new weapons
- Adding new game modes
- Modifying bot AI
- Extending the relay server

### Tools Used

| Tool | Purpose |
|------|---------|
| [Windsurf](https://codeium.com/windsurf) | IDE with AI assistant (Cascade) |
| [Godot 4.6](https://godotengine.org/) | Game engine |
| [Kenney.nl](https://kenney.nl) | Free game assets (CC0/MIT) |
| [Docker](https://docker.com) | Containerized deployment |
| [GitHub Actions](https://github.com/features/actions) | CI/CD pipeline |

---

## Final Thoughts

Vibecoding isn't "AI wrote a game by itself." It's a human with a vision directing an AI that can type code faster than any human. The human still makes every meaningful decision — the AI just handles the translation from intent to implementation.

The result is a fully functional, self-hostable, multiplayer 3D game built in a fraction of the time it would normally take. And if you're reading this wiki, you have everything you need to understand, host, and modify it.
