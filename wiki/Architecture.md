# Architecture

This page describes the overall system design of Paintball Arena — how the pieces fit together, what runs where, and how data flows between players.

---

## High-Level Overview

```
┌─────────────┐         WebSocket         ┌─────────────┐
│  Browser A   │ ◄───────────────────────► │  Browser B   │
│  (Godot WASM)│                           │  (Godot WASM)│
│              │    ┌─────────────────┐    │              │
│  - Physics   │    │  Relay Server   │    │  - Physics   │
│  - AI bots   │◄──►│  (Node.js:9090) │◄──►│  - AI bots   │
│  - Rendering │    │                 │    │  - Rendering │
│  - Game logic│    │  - Room codes   │    │  - Game logic│
│              │    │  - Packet relay  │    │              │
└──────┬───────┘    │  - Chat relay   │    └──────┬───────┘
       │            │  - No game logic│           │
       │            └─────────────────┘           │
       │                                          │
       ▼                                          ▼
  ┌──────────┐                              ┌──────────┐
  │  nginx   │  ← serves HTML5 export  →    │  nginx   │
  │ :8080    │  (COOP/COEP headers)         │          │
  └──────────┘                              └──────────┘
```

### Key Design Decisions

1. **No authoritative server** — all game logic runs in the browser. The relay server is a dumb packet router. This means:
   - Zero server-side game state to maintain
   - Trivially scalable (the server is just a message bus)
   - Easy to self-host (one Node.js process + static files)
   - Trade-off: clients can theoretically cheat (acceptable for a casual game)

2. **Room-code matchmaking** — players create/join rooms with 6-character codes (e.g., `ABCD23`). No matchmaking queue, no account system. Share the code, play immediately.

3. **AI bots run client-side** — in solo play or to fill empty multiplayer slots, bots are spawned locally. Each client runs its own bot AI. In multiplayer, only the host spawns bots.

4. **Godot HTML5 export** — the entire game compiles to WebAssembly + JavaScript. Requires `SharedArrayBuffer` support (hence the COOP/COEP headers).

---

## Client Architecture (Godot)

The Godot client uses three **autoload singletons** that persist across scene changes:

```
┌─────────────────────────────────────────────────────┐
│                    Autoload Singletons                │
│                                                       │
│  GameSettings          GameState          NetworkManager
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  │ Game mode     │  │ Match phase  │  │ WebSocket    │
│  │ Map selection │  │ Rounds/score │  │ Room code    │
│  │ Bot count     │  │ Kill scores  │  │ Player list  │
│  │ Time limit    │  │ Match stats  │  │ Chat relay   │
│  │ Rounds to win │  │ Eliminations │  │ Game data    │
│  └──────────────┘  └──────────────┘  └──────────────┘
└─────────────────────────────────────────────────────┘
```

### Scene Flow

```
main_menu.tscn  ──(Play Solo)──►  main.tscn (game)
       │                              │
       ├──(Multiplayer)──► lobby.tscn ─┘
       │                     │
       └──(Settings)──►  (inline in main_menu)
```

1. **Main Menu** (`main_menu.tscn` / `main_menu.gd`) — game mode, map, bot count, settings
2. **Lobby** (`lobby.tscn` / `lobby.gd`) — create/join rooms, player list, start game
3. **Game** (`main.tscn` / `main_game.gd`) — the actual match with HUD, players, world

### Game Scene Hierarchy

```
Main (Node3D) — main_game.gd
├── World (Node3D) — dynamically loaded map
│   └── Map (loaded from scenes/maps/*.tscn)
│       ├── Static geometry (walls, floors, props)
│       └── SpawnPoint nodes (group: "spawn_point")
├── Players (Node3D) — player + bot container
│   ├── Player (CharacterBody3D) — player.gd
│   ├── Bot 1 (CharacterBody3D) — bot.gd
│   ├── Bot 2 ...
│   └── NetPlayer (CharacterBody3D) — net_player.gd (multiplayer only)
├── UI (CanvasLayer)
│   ├── HUD (Control) — hud.gd
│   │   ├── Crosshair, Ammo, Weapon, Score, Timer, ...
│   │   ├── ChatPanel — in-game chat
│   │   ├── HelpOverlay — hotkey reference (?-key)
│   │   └── ScoreboardPanel — end-of-match stats
│   └── PauseMenu (Control) — pause_menu.gd
├── DirectionalLight3D — sunlight
└── WorldEnvironment — skybox, ambient light, SSAO
```

---

## Relay Server Architecture (Node.js)

The relay server (`server/index.js`) is ~300 lines of JavaScript. It uses the `ws` library (zero other dependencies).

### Server State

```javascript
rooms: Map<roomCode, {
  code: String,
  host: WebSocket,
  players: Map<playerId, WebSocket>,
  state: "waiting" | "playing",
  nextId: Number
}>
```

### Connection Lifecycle

```
Client connects (WebSocket)
    │
    ├── create_room → allocate room, assign ID 1 (host)
    │
    ├── join_room(code) → validate room, assign next ID
    │
    ├── start_game → host only, transitions to "playing"
    │
    ├── game_data → relay to all others in room
    │
    ├── chat_message → broadcast to all in room (including sender)
    │
    └── disconnect / leave_room → remove from room, reassign host
```

### Security Measures

- **Rate limiting** — per-IP connection limits, message rate throttling
- **Input sanitization** — chat messages stripped of HTML characters, truncated to 200 chars
- **Room capacity** — max 8 players per room
- **Room expiry** — empty rooms auto-deleted
- **No game state** — server never interprets game data, just routes it

---

## Multiplayer Data Flow

### State Synchronization

```
Local Player ──(20 ticks/sec)──► NetworkManager ──► Relay ──► All Other Clients
     │                                                              │
     │  Packet: {                                                   │
     │    action: "state",                                          │
     │    pos: [x, y, z],                                          │
     │    rot_y: float,                                             │
     │    head_x: float                                             │
     │  }                                                           │
     │                                                              ▼
     │                                              NetPlayer.apply_state()
     │                                              (interpolates position)
```

### Shooting

```
Player fires weapon
    │
    ├── Spawn local projectile (immediate feedback)
    │
    └── game_sync.send_shoot(origin, direction, color)
            │
            └── Relay ──► Other clients
                              │
                              └── game_sync._spawn_remote_projectile()
```

### Elimination

```
Projectile hits character
    │
    ├── Local: character.take_hit(shooter_id)
    │           → character.die(shooter_id)
    │           → GameState.register_elimination()
    │
    └── game_sync.send_elimination(victim_id)
            │
            └── Relay ──► Other clients
                              │
                              └── game_sync._handle_remote_elimination()
```

---

## Stats System

Per-player stats are tracked in `GameState.match_stats`:

```
match_stats[player_id] = {
    kills: int,
    deaths: int,
    shots_fired: int,    # recorded in weapon fire callback
    shots_hit: int,      # recorded in projectile hit callback
    streak: int,         # current kill streak
    best_streak: int,    # highest streak this match
    rounds_survived: int, # team modes only
    name: String
}
```

**Score formula:** `kills × 100 + best_streak × 50 − deaths × 25 + rounds_survived × 30`

The player with the highest score is the **MVP**.

---

## Technology Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| Game engine | [Godot](https://godotengine.org/) | 4.6 |
| Game language | GDScript | 4.x |
| Relay server | Node.js | 18+ |
| WebSocket library | ws | 8.16+ |
| Web server | nginx (alpine) | latest |
| Containerization | Docker + Docker Compose | any |
| CI/CD | GitHub Actions | - |
| Assets | Kenney.nl | CC0/MIT |
| Export target | HTML5 (WebAssembly) | - |
