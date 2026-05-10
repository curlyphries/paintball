# Game Mechanics

Everything about how Paintball Arena plays — game modes, weapons, maps, scoring, controls, and the end-of-match stats system.

---

## Core Rules

- **1-hit elimination** — a single paintball hit takes you out. No health bars, no shields. You get hit, you're down.
- **Paint splatters** — every shot that hits a surface leaves a colored paint splat that fades after ~5 seconds.
- **Death animation** — when eliminated, your character model tips sideways and lingers on the ground for 3 seconds before disappearing.

---

## Game Modes

### Team vs Team (Default)

- **Format:** Round-based elimination
- **Teams:** Players vs Bots (or mixed in multiplayer)
- **Win condition:** Eliminate all enemies to win the round
- **Match win:** First team to win 3 rounds (configurable: 1–5)
- **No respawning** during a round — once you're out, you watch
- **3-second countdown** at the start of each round
- **Round survivors** earn bonus points in the scoreboard

### Deathmatch

- **Format:** Free-for-all with respawns
- **Respawn delay:** 3 seconds after death
- **Win condition:** Most kills when the time limit expires
- **Time limits:** 3, 5, 10, 15, or 30 minutes (configurable)
- **All bots are independent** — no teams, everyone for themselves
- **Auto-switch:** If you pick Team vs Team with 0 bots in solo mode, the game auto-switches to Deathmatch

### Capture the Flag

- **Format:** Team-based, round-based
- **Rules:** Same round structure as Team vs Team
- **Objective mode** with flag capture mechanics

---

## Weapons

All weapons are **1-hit kill**. The difference is fire rate, magazine size, accuracy, and projectile speed.

| Weapon | Key | Fire Rate | Magazine | Reload | Speed | Spread | Pellets | Color |
|--------|-----|-----------|----------|--------|-------|--------|---------|-------|
| **Pistol** | 1 | 0.4s | 12 | 1.5s | 40 | 0.01 | 1 | Yellow |
| **Rifle** | 2 | 0.15s | 30 | 2.0s | 60 | 0.005 | 1 | Green |
| **Sniper** | 3 | 1.5s | 5 | 3.0s | 100 | 0.0 | 1 | Purple |
| **Shotgun** | 4 | 0.8s | 8 | 2.5s | 30 | 0.08 | 6 | Red |
| **SMG** | 5 | 0.08s | 45 | 2.0s | 50 | 0.03 | 1 | Cyan |

### Weapon Notes

- **Pistol** — reliable all-rounder. Default starting weapon.
- **Rifle** — fast fire rate + tight spread = dependable at all ranges.
- **Sniper** — zero spread, fastest projectile. Best for long-range picks but punishing if you miss.
- **Shotgun** — fires 6 pellets in a wide cone. Devastating at close range, useless at distance.
- **SMG** — highest fire rate in the game. Moderate spread means you need to be somewhat close.

### Projectile Behavior

- Paintballs travel in a straight line with slight **gravity drop** over distance
- Each paintball has the weapon's assigned **color** (visible in flight and on impact)
- Paintballs have a brief **spawn delay** (0.05s) before collision activates — prevents shooting yourself
- Projectiles auto-despawn after 3 seconds if they don't hit anything

---

## Maps

### Warehouse
- **Theme:** Classic indoor warehouse
- **Layout:** Crates, corridors, tight sightlines
- **Bounds:** 36m × 26m
- **Best for:** Close-quarters combat, shotgun/SMG playstyle

### Courtyard
- **Theme:** Open outdoor courtyard
- **Layout:** Walls, pillars, mixed cover
- **Bounds:** 40m × 30m
- **Best for:** Mixed engagement ranges

### Arena
- **Theme:** Circular arena with raised platforms
- **Layout:** Elevated positions, open center
- **Bounds:** 32m × 32m
- **Best for:** Sniper/rifle play, vertical engagements

---

## AI Bots

Bots use a **3-state state machine**:

1. **Patrol** — wander randomly within map bounds
2. **Chase** — move toward a detected target
3. **Shoot** — stop and fire at the target

### Bot Behavior

- **Detection range:** Bots spot targets within line of sight
- **Accuracy:** Random per bot, ranges from 50%–85%
- **Reaction time:** Random per bot, ranges from 0.3s–0.8s
- **Weapon switching:** Bots may use different weapons
- **Respawn:** In deathmatch, bots respawn after 3 seconds (same as players)
- **Death animation:** Same as players — model tips over, lingers, then disappears

### Bot Count

Configurable from the main menu: **0–7 bots** (up to 8 total participants).

---

## Controls

| Key | Action |
|-----|--------|
| **WASD** | Move (forward, left, back, right) |
| **Mouse** | Aim / Look around |
| **Left Click** | Shoot |
| **Right Click** | Aim (zoom) |
| **Shift** | Sprint |
| **Space** | Jump |
| **Ctrl** | Crouch |
| **R** | Reload |
| **1–5** | Select weapon directly |
| **Scroll Wheel** | Cycle through weapons |
| **V** | Toggle 1st person ↔ 3rd person camera |
| **T** | Open in-game chat |
| **Enter** | Send chat message |
| **Esc** | Close chat / Release mouse cursor |
| **?** (Shift+/) | Toggle hotkey help overlay |

### Camera Modes

- **First person** (default) — camera at eye level, character model hidden
- **Third person** — camera offset behind and above, character model visible
- **Death camera** — automatically switches to 3rd person to show your body falling

### Chat System

- Press **T** to open the chat panel (bottom-left)
- Type your message, press **Enter** to send
- **Esc** closes chat without sending
- Mouse cursor is released while typing (movement/shooting disabled)
- Chat panel auto-shows for 5 seconds when a message arrives
- In **multiplayer**, messages relay through the server to all room members
- In **solo mode**, messages display locally

---

## Scoring & Stats

### Per-Match Stats (tracked for every player and bot)

| Stat | How It's Tracked |
|------|------------------|
| **Kills** | Incremented when you eliminate someone |
| **Deaths** | Incremented when you're eliminated |
| **Shots Fired** | Counted every time your weapon fires (each pellet counts for shotgun) |
| **Shots Hit** | Counted when your projectile connects with a character |
| **Current Streak** | Consecutive kills without dying (resets on death) |
| **Best Streak** | Highest streak achieved during the match |
| **Rounds Survived** | Number of rounds you were alive when the round ended (team modes) |

### Derived Stats

| Stat | Formula |
|------|---------|
| **K/D Ratio** | `kills ÷ deaths` (if 0 deaths, K/D = kills) |
| **Accuracy %** | `(shots_hit ÷ shots_fired) × 100` |
| **Score** | `kills×100 + best_streak×50 − deaths×25 + rounds_survived×30` |

### MVP

The player with the **highest score** at match end is the MVP, highlighted in gold on the scoreboard.

### End-of-Match Scoreboard

Displayed for 10 seconds at the end of every match. Shows a table with columns:

| # | Name | Kills | Deaths | K/D | Acc% | Streak | Score |
|---|------|-------|--------|-----|------|--------|-------|

- **Your row** is highlighted in green
- **MVP row** is highlighted in gold with a `*` marker
- Below the table: MVP summary line + match duration

---

## Multiplayer Specifics

### Room System

- A host creates a room → gets a **6-character alphanumeric code** (e.g., `ABCD23`)
- Other players join by entering the code
- Max **8 players** per room
- Characters that might cause confusion are excluded (no I, O, 0, 1)

### Host Privileges

- Only the host can click **Start Game**
- If the host disconnects, host status automatically transfers to the next player

### Network Model

- **Peer-to-peer via relay** — all game data routes through the WebSocket server
- **Client-authoritative** — each client runs its own physics and game logic
- **Sync rate:** 20 ticks/second for position updates
- **No server-side validation** — designed for casual play with friends, not competitive anti-cheat

### What Gets Synced

- Player position (x, y, z)
- Player rotation (body Y, head X)
- Shots fired (origin, direction, color)
- Eliminations (victim ID, killer ID)
- Chat messages (sender name, text)
