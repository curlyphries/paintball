# Paintball Arena Wiki

Welcome to the **Paintball Arena** wiki — the comprehensive guide to the game, its architecture, and how to make it your own.

Paintball Arena is a 3D first-person multiplayer paintball game that runs entirely in the browser. It's built with [Godot 4.6](https://godotengine.org/) (GDScript) and a lightweight Node.js WebSocket relay server. The entire project was **vibecoded** — built from scratch using AI-assisted development with [Windsurf](https://codeium.com/windsurf) as the IDE.

---

## Table of Contents

### Playing the Game
- **[Game Mechanics](Game-Mechanics)** — Game modes, weapons, maps, scoring system, controls

### Understanding the Code
- **[Architecture](Architecture)** — System design, client-server model, data flow
- **[Scripts Reference](Scripts-Reference)** — Every GDScript file explained with responsibilities
- **[Relay Server](Relay-Server)** — WebSocket protocol, message types, room lifecycle, security

### Hosting & Deploying
- **[Self-Hosting Guide](Self-Hosting-Guide)** — Docker, manual setup, reverse proxy, HTTPS, troubleshooting

### Contributing & Modding
- **[Development Guide](Development-Guide)** — Forking, local dev, adding maps, weapons, game modes

### Background
- **[How It Was Built](How-It-Was-Built)** — The vibecoding story — building a game with AI pair programming

---

## Quick Links

| What | Where |
|------|-------|
| Repository | [github.com/curlyphries/paintball](https://github.com/curlyphries/paintball) |
| Engine | [Godot 4.6](https://godotengine.org/) |
| Language | GDScript (game) + JavaScript (relay server) |
| License | MIT (code) + CC0/MIT (assets from [Kenney.nl](https://kenney.nl)) |
| Relay dependency | [ws](https://github.com/websockets/ws) (single npm package) |

---

## At a Glance

- **3 game modes** — Deathmatch, Team vs Team, Capture the Flag
- **3 maps** — Warehouse, Courtyard, Arena
- **5 weapons** — Pistol, Rifle, Sniper, Shotgun, SMG
- **Up to 8 players** per room with AI bot backfill
- **1-hit elimination** — one paintball, you're out
- **In-game chat** + hotkey help overlay
- **End-of-match scoreboard** with kills, deaths, K/D, accuracy, streaks, MVP
- **Self-hostable** with Docker or any static file server + Node.js
