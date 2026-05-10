# Development Guide

How to fork, modify, and extend Paintball Arena — adding maps, weapons, game modes, and more.

---

## Getting Started

### Prerequisites

- **Godot 4.6+** — [Download](https://godotengine.org/download) (native, Flatpak, or Snap)
- **Node.js 18+** — for the relay server
- **Git** — version control

### Clone & Run

```bash
git clone https://github.com/curlyphries/paintball.git
cd paintball

# Start relay server (background)
cd server && npm install && npm run dev &

# Open in Godot editor
cd ..
godot --editor project.godot
```

Press **F5** in the editor to play-test. The game works in solo mode without a relay server — bots are spawned locally.

### Project Layout

```
scripts/    → Game logic (GDScript) — this is where most changes go
scenes/     → Godot scene files (.tscn) — node trees and UI layouts
assets/     → Models, textures, audio (Kenney.nl CC0/MIT)
server/     → Relay server (Node.js) — rarely needs changes
```

---

## Adding a New Map

Maps live in `scenes/maps/`. Each map is a standalone `.tscn` scene.

### Step 1: Create the Scene

1. In Godot, create a new scene: **Scene → New Scene → Node3D** (root node)
2. Name the root node `Map`
3. Build your level using:
   - `StaticBody3D` + `CollisionShape3D` for walls/floors
   - `MeshInstance3D` for visual geometry
   - `Node3D` nodes in the `"spawn_point"` group for spawn locations

### Step 2: Add Spawn Points

Add at least 8 `Node3D` nodes and put each one in the `"spawn_point"` group:

1. Select the node
2. **Node → Groups → Type `spawn_point` → Add**

Position them spread around the map, ~1m above the floor.

### Step 3: Register the Map

Open `scripts/game_settings.gd` and add your map to `AVAILABLE_MAPS`:

```gdscript
const AVAILABLE_MAPS: Dictionary = {
    # ... existing maps ...
    "your_map": {
        "name": "Your Map Name",
        "scene": "res://scenes/maps/your_map.tscn",
        "description": "A brief description of the map",
    },
}
```

### Step 4: Set Bounds for Bots

In `scripts/main_game.gd`, add your map's bounds to `_get_map_bounds()`:

```gdscript
func _get_map_bounds() -> Array:
    match GameSettings.selected_map:
        # ... existing maps ...
        "your_map":
            return [Vector3(-20, 0, -20), Vector3(20, 0, 20)]
```

These bounds keep bots from wandering outside the playable area.

That's it — the main menu will automatically show your new map in the selection.

---

## Adding a New Weapon

Weapons are defined as data in `game_state.gd` — no new scripts needed.

### Step 1: Define Weapon Data

Open `scripts/game_state.gd` and add to the `weapons` dictionary:

```gdscript
var weapons: Dictionary = {
    # ... existing weapons ...
    "launcher": {
        "damage": 1,
        "fire_rate": 2.0,       # seconds between shots
        "magazine": 3,          # shots before reload
        "reload_time": 3.5,     # seconds to reload
        "speed": 20.0,          # projectile speed
        "pellets": 1,           # projectiles per shot (>1 for shotgun-style)
        "spread": 0.05,         # aim cone radius
        "color": Color.ORANGE   # paintball color
    },
}
```

### Step 2: Add Keybind (if using slot 6+)

In `project.godot`, add a new input action. Or modify the weapon cycling in `player.gd` to include your weapon.

The player's `available_weapons` array in `player.gd` controls which weapons are accessible:

```gdscript
var available_weapons: Array[String] = ["pistol", "rifle", "sniper", "shotgun", "smg", "launcher"]
```

### Balancing Tips

Since all weapons are 1-hit kill, balance comes from:
- **Fire rate** — how forgiving is a miss?
- **Spread** — accurate at range, or close-quarters only?
- **Magazine** — can you sustain fire?
- **Projectile speed** — can targets dodge at distance?
- **Pellets** — shotgun pattern width/density

---

## Adding a New Game Mode

Game modes are managed by `GameSettings.GameMode` enum and the scoring logic in `game_state.gd`.

### Step 1: Add the Enum Value

In `scripts/game_settings.gd`:

```gdscript
enum GameMode { DEATHMATCH, TEAM_VS_TEAM, CAPTURE_THE_FLAG, YOUR_MODE }
```

### Step 2: Add a Name

```gdscript
func get_mode_name() -> String:
    match game_mode:
        # ... existing ...
        GameMode.YOUR_MODE:
            return "Your Mode"
    return "Unknown"
```

### Step 3: Add Scoring Logic

In `scripts/game_state.gd`, modify `register_elimination()` and/or `_on_time_expired()` to handle your new mode's win conditions.

### Step 4: Add Spawning Logic

In `scripts/main_game.gd`, add any special spawning or respawn behavior for your mode.

### Step 5: Add to Main Menu

The main menu (`scripts/main_menu.gd`) dynamically creates buttons for game modes. You may need to add your mode there.

---

## Modifying Bot AI

Bot behavior lives in `scripts/bot.gd`. The state machine is:

```
PATROL → (target found) → CHASE → (in range + line of sight) → SHOOT
   ↑                                                               │
   └────────────────── (target lost / died) ──────────────────────┘
```

### Tuning Difficulty

- `accuracy` — lower = wider aim deviation (0.0–1.0)
- `reaction_time` — higher = slower to start shooting
- These are set randomly per bot in `main_game.gd._spawn_bots()`

### Adding New Behaviors

Add new states to the `State` enum and handle them in `_physics_process()`:

```gdscript
enum State { PATROL, CHASE, SHOOT, DEAD, YOUR_STATE }
```

---

## Modifying the Relay Server

The relay server (`server/index.js`) is straightforward JavaScript.

### Adding a New Message Type

1. Add a `case` in the message handler switch:

```javascript
case "your_message":
    handleYourMessage(ws, msg);
    break;
```

2. Implement the handler:

```javascript
function handleYourMessage(ws, msg) {
    const room = rooms.get(ws.roomCode);
    if (!room) return;
    
    // Process and broadcast
    broadcastToRoom(room, {
        type: "your_message",
        from: ws.playerId,
        data: msg.data
    });
}
```

3. Handle it in `NetworkManager.gd`:

```gdscript
"your_message":
    your_signal.emit(msg.from, msg.data)
```

---

## Exporting

### HTML5 (Web)

```bash
godot --headless --path . --export-release "Web" export/web/index.html
```

The export preset (`export_presets.cfg`) excludes server files, Docker configs, and the README from the game bundle.

### Service Worker Patch

After exporting, run the service worker patch if deploying as a PWA:

```bash
bash scripts/patch-service-worker.sh export/web/index.service.worker.js
```

---

## Testing

### Solo Mode

- Press F5 in Godot editor (or run `godot --path .`)
- Plays locally with bots, no server needed
- All game modes and features work

### Multiplayer (Local)

1. Start relay: `cd server && npm run dev`
2. Export: `godot --headless --path . --export-release "Web" export/web/index.html`
3. Serve: use the Docker setup or any COOP/COEP-enabled web server
4. Open two browser tabs → create room in one, join in the other

### Multiplayer (Remote)

Same as local, but ensure the relay server's port (9090) is accessible from the internet. Use a reverse proxy with WebSocket support for production.

---

## Code Style

This project follows idiomatic GDScript conventions:

- **Snake_case** for variables and functions
- **PascalCase** for class names and enums
- **UPPER_CASE** for constants
- **Signals** use past-tense names (`player_eliminated`, `round_ended`)
- **Autoloads** accessed by name (`GameState`, `GameSettings`, `NetworkManager`)
- **@onready** for node references
- **Typed variables** where practical (`var count: int = 0`)

---

## Contributing

1. **Fork** the repository
2. **Create a branch** for your feature (`git checkout -b feature/my-feature`)
3. **Make changes** — test in solo mode first, then multiplayer
4. **Commit** with descriptive messages
5. **Push** and open a Pull Request

### Good First Contributions

- Add a new map scene
- Add a new weapon definition
- Improve bot AI (e.g., taking cover, retreating)
- Add sound effects for more actions
- UI polish (HUD animations, transitions)
- Performance optimizations
