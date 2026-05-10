# Scripts Reference

Every GDScript file in the project, explained with its responsibilities, key variables, signals, and how it connects to other scripts.

---

## Autoload Singletons

These three scripts are loaded automatically by Godot and are accessible globally from any script via their class name.

### `game_settings.gd` — GameSettings

**Purpose:** Stores all pre-game configuration. Set from the main menu, read by `main_game.gd` and `game_state.gd`.

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `game_mode` | `GameMode` enum | `TEAM_VS_TEAM` | Deathmatch, Team vs Team, or CTF |
| `bot_count` | `int` | `3` | Number of AI bots (0–7) |
| `bots_enabled` | `bool` | `true` | Whether bots are active |
| `selected_map` | `String` | `"warehouse"` | Key into `AVAILABLE_MAPS` |
| `time_limit_minutes` | `int` | `5` | Match timer (0 = no limit) |
| `rounds_to_win` | `int` | `3` | Rounds needed to win (team modes) |

**Key methods:**
- `get_map_scene_path()` — returns the `.tscn` path for the selected map
- `get_mode_name()` — returns a friendly display name for the current mode
- `get_effective_bot_count()` — returns 0 if bots disabled
- `reset_to_defaults()` — restores all settings

---

### `game_state.gd` — GameState

**Purpose:** Manages all runtime game state — match phase, rounds, scoring, eliminations, time limit, per-player stats, and the scoreboard.

**Signals:**

| Signal | Emitted When |
|--------|-------------|
| `round_started(round_number)` | A new round begins |
| `round_ended(winner_team)` | A round is decided |
| `match_ended(winner_team)` | The match is over |
| `player_eliminated(victim_id, killer_id)` | Someone gets eliminated |
| `score_updated(player_score, bot_score)` | Round wins change |
| `time_updated(seconds_remaining)` | Timer ticks (every frame) |
| `kill_score_updated(scores)` | Kill counts change (deathmatch) |
| `stats_updated()` | Any player stat changes |

**Key state:**
- `match_phase` — `WAITING`, `COUNTDOWN`, `PLAYING`, `ROUND_OVER`, `MATCH_OVER`
- `match_stats` — Dictionary of per-player stats (kills, deaths, accuracy, streaks)
- `kill_scores` — Kill counts per player (deathmatch mode)
- `players_alive` / `bots_alive` — alive tracking for team modes

**Key methods:**
- `register_elimination(victim, killer)` — updates stats, checks round end
- `record_shot_fired(id)` / `record_shot_hit(id)` — accuracy tracking
- `get_scoreboard()` — returns sorted array with all derived stats
- `get_mvp()` — returns the top-scoring player

---

### `network_manager.gd` — NetworkManager

**Purpose:** WebSocket client that connects to the relay server. Handles room create/join, message routing, and chat.

**Signals:**

| Signal | Emitted When |
|--------|-------------|
| `connected_to_server` | WebSocket handshake complete |
| `disconnected_from_server` | Connection lost |
| `room_created(code, player_id)` | Room successfully created |
| `room_joined(code, player_id)` | Successfully joined a room |
| `player_joined(player_id, name)` | Another player joined |
| `player_left(player_id, name)` | A player left |
| `game_started(players)` | Host started the game |
| `game_data_received(from_id, data)` | Game data from another player |
| `chat_message_received(from_id, name, text)` | Chat message from relay |
| `error_received(message)` | Server error |
| `became_host` | Host role transferred to us |

**Key methods:**
- `connect_to_relay(url)` — initiate WebSocket connection
- `create_room(name)` / `join_room(code, name)` — room management
- `send_game_data(data)` — send game state/actions to relay
- `send_chat_message(text)` — send chat through relay

---

## Game Scripts

### `main_game.gd` — Game Orchestrator

**Attached to:** `Main` (Node3D) in `main.tscn`

**Purpose:** The central coordinator that sets up the game world, spawns players and bots, manages rounds, handles eliminations, and shows the end-of-match scoreboard.

**Responsibilities:**
- Load the selected map scene dynamically
- Spawn the local player + AI bots
- Collect spawn points from the map
- Set up multiplayer sync (`GameSync`) if networked
- Run the round cycle: countdown → play → round end → next round
- Connect elimination signals to HUD messages
- Show scoreboard at match end → return to menu

---

### `player.gd` — Player Controller

**Attached to:** `Player` (CharacterBody3D) in `player.tscn`

**Purpose:** First/third-person character controller with movement, shooting, camera, weapon switching, and death animation.

**Key features:**
- WASD movement with sprint (1.6×) and crouch (0.5×)
- Mouse look with sensitivity and pitch clamp
- First-person / third-person camera toggle (V key)
- Weapon firing → spawns projectile → records `shot_fired`
- `take_hit(attacker_id)` → `die()` → death animation (model tips over)
- `respawn(position)` — resets everything
- Blocks all input when chat is active (`_is_chat_active()`)

**Signals:**
- `eliminated(player, killer_id)` — emitted on death

---

### `bot.gd` — AI Bot

**Attached to:** `Bot` (CharacterBody3D) in `bot.tscn`

**Purpose:** AI opponent with a 3-state behavior system (patrol, chase, shoot).

**State machine:**
- **PATROL** — wander randomly within map bounds, pick new waypoints
- **CHASE** — move toward detected target
- **SHOOT** — stop, aim at target, fire with configured accuracy/reaction time
- **DEAD** — death animation playing

**Configurable per-bot:**
- `accuracy` — 0.5–0.85 (random per bot)
- `reaction_time` — 0.3s–0.8s (random per bot)
- `bot_name` — display name (e.g., "Bot 1")
- `MAP_MIN` / `MAP_MAX` — wander bounds

---

### `weapon.gd` — Weapon Mechanics

**Attached to:** `Weapon3D` (Node3D) inside Player/Bot scenes

**Purpose:** Handles fire rate cooldown, magazine/reload system, and projectile spawning delegation.

**Key features:**
- `fire(origin, direction)` — respects cooldown, fires N pellets with spread
- `start_reload()` / `finish_reload()` — timed reload system
- `switch_to(weapon_name)` — instantly swap weapon type

**Signals:**
- `fired(pos, direction, speed, color)` — connected to Player/Bot for projectile spawning
- `ammo_changed(current, max)` — HUD updates
- `reload_started(duration)` / `reload_finished()` — reload feedback

---

### `projectile.gd` — Paintball Physics

**Class name:** `Paintball`
**Attached to:** `Projectile` (CharacterBody3D) in `projectile.tscn`

**Purpose:** Paintball projectile with physics, hit detection, paint splatters, and stat recording.

**Behavior:**
- Travels at weapon speed with slight gravity drop
- Collision disabled briefly after spawn (prevents hitting shooter)
- On hit: checks if target is a character → `record_shot_hit()` → `take_hit()`
- On surface hit: spawns `PaintSplat` at impact point
- Auto-despawns after 3 seconds
- **Material cache:** shares materials by color across all projectiles (performance)

---

### `hud.gd` — Heads-Up Display

**Attached to:** `HUD` (Control) in `main.tscn`

**Purpose:** All UI during gameplay — ammo, weapons, scores, timer, player list, elimination feed, event log, chat, help overlay, and end-of-match scoreboard.

**Major systems:**
- **Player list** — auto-refreshes every 0.5s, shows alive/dead status
- **Elimination feed** — top-right kill messages, fade after 3s
- **Chat panel** — T to open, Enter to send, Esc to close
- **Help overlay** — ? (Shift+/) to toggle, lists all controls
- **Scoreboard** — `show_scoreboard()` builds a table from `GameState.get_scoreboard()`
- **Input handling** — `_input()` manages chat open/close and help toggle

---

### `game_sync.gd` — Multiplayer State Sync

**Purpose:** Bridges the local game with the relay server. Syncs player positions, shots, and eliminations.

**Key features:**
- Sends local player state 20 times/second
- Receives remote states → updates `NetPlayer` puppets
- Relays shot events → spawns remote projectiles
- Relays elimination events → kills remote characters
- Auto-spawns `NetPlayer` for late joiners

---

### `net_player.gd` — Remote Player Puppet

**Attached to:** `NetPlayer` (CharacterBody3D) in `net_player.tscn`

**Purpose:** Visual representation of a remote player. Receives state updates from `GameSync` and interpolates position/rotation.

---

### `lobby.gd` — Multiplayer Lobby

**Attached to:** `Lobby` (Control) in `lobby.tscn`

**Purpose:** UI for creating/joining rooms, showing player list, and starting the game.

---

### `main_menu.gd` — Main Menu

**Attached to:** root control in `main_menu.tscn`

**Purpose:** Game entry point. Displays mode selection, map picker, bot count, time limit settings, and Play/Multiplayer buttons.

---

### `pause_menu.gd` — Pause Menu

**Attached to:** `PauseMenu` (Control) in `pause_menu.tscn`

**Purpose:** Pause overlay with resume/quit options.

---

### `paint_splat.gd` — Paint Splatter

**Attached to:** `PaintSplat` (Node3D) in `paint_splat.tscn`

**Purpose:** Colored paint decal that appears on surfaces where paintballs hit. Fades out and self-destructs after ~5 seconds. Aligns to the surface normal for proper orientation on walls, floors, and ceilings.

---

## Script Dependency Graph

```
GameSettings ◄──── main_menu.gd (writes settings)
     │
     ├──── main_game.gd (reads mode, map, bots)
     └──── game_state.gd (reads mode for scoring logic)

GameState ◄──── main_game.gd (start_match, round flow)
     │
     ├──── player.gd (register_elimination via bot)
     ├──── bot.gd (register_elimination on death)
     ├──── projectile.gd (record_shot_hit)
     ├──── player.gd / bot.gd (record_shot_fired)
     └──── hud.gd (reads scores, stats, scoreboard)

NetworkManager ◄──── lobby.gd (create/join rooms)
     │
     ├──── game_sync.gd (send/receive game data)
     └──── hud.gd (send/receive chat messages)
```
