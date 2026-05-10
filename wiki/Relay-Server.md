# Relay Server

The relay server is a lightweight Node.js WebSocket server (~300 lines) that handles room management and packet routing. It has **zero game logic** — it doesn't know what a paintball is, it just moves bytes between connected clients.

---

## Technology

- **Runtime:** Node.js 18+
- **WebSocket library:** [ws](https://github.com/websockets/ws) (only dependency)
- **Default port:** 9090
- **Protocol:** JSON over WebSocket text frames

---

## Room Lifecycle

```
┌─────────────┐     create_room     ┌─────────────┐
│   (empty)   │ ──────────────────► │   waiting    │
│             │                     │   1 player   │
└─────────────┘                     │   (host)     │
                                    └──────┬───────┘
                                           │
                                    join_room (×N)
                                           │
                                    ┌──────▼───────┐
                                    │   waiting    │
                                    │  2-8 players │
                                    └──────┬───────┘
                                           │
                                    start_game (host only)
                                           │
                                    ┌──────▼───────┐
                                    │   playing    │
                                    │  game_data   │
                                    │  chat relay  │
                                    └──────┬───────┘
                                           │
                                    all players leave
                                           │
                                    ┌──────▼───────┐
                                    │   deleted    │
                                    └─────────────┘
```

---

## Message Protocol

All messages are JSON objects with a `type` field.

### Client → Server Messages

#### `create_room`
Create a new room. Sender becomes host.

```json
{ "type": "create_room", "name": "PlayerName" }
```

#### `join_room`
Join an existing room by code.

```json
{ "type": "join_room", "code": "ABCD23", "name": "PlayerName" }
```

#### `leave_room`
Leave the current room.

```json
{ "type": "leave_room" }
```

#### `start_game`
Start the game (host only, room must be in "waiting" state).

```json
{ "type": "start_game" }
```

#### `game_data`
Send game data to all other players in the room. The relay forwards this to everyone except the sender.

```json
{ "type": "game_data", "data": { "action": "state", "pos": [1, 2, 3], ... } }
```

#### `chat_message`
Send a chat message to all players in the room (including sender).

```json
{ "type": "chat_message", "text": "Hello everyone!" }
```

---

### Server → Client Messages

#### `room_created`
Sent to the player who created a room.

```json
{
  "type": "room_created",
  "code": "ABCD23",
  "playerId": 1,
  "players": [{ "id": 1, "name": "Host", "isHost": true }]
}
```

#### `room_joined`
Sent to the player who joined a room.

```json
{
  "type": "room_joined",
  "code": "ABCD23",
  "playerId": 2,
  "players": [
    { "id": 1, "name": "Host", "isHost": true },
    { "id": 2, "name": "Player2", "isHost": false }
  ]
}
```

#### `player_joined`
Broadcast to all existing room members when a new player joins.

```json
{
  "type": "player_joined",
  "playerId": 2,
  "name": "Player2",
  "players": [...]
}
```

#### `player_left`
Broadcast when a player leaves or disconnects.

```json
{
  "type": "player_left",
  "playerId": 2,
  "name": "Player2",
  "players": [...]
}
```

#### `you_are_host`
Sent when host role is transferred (original host left).

```json
{ "type": "you_are_host" }
```

#### `game_started`
Broadcast to all room members when the host starts the game.

```json
{
  "type": "game_started",
  "players": [...]
}
```

#### `game_data`
Relayed game data from another player.

```json
{
  "type": "game_data",
  "from": 1,
  "data": { "action": "state", "pos": [1, 2, 3], ... }
}
```

#### `chat_message`
Relayed chat message (sent to ALL room members including the original sender).

```json
{
  "type": "chat_message",
  "from": 1,
  "name": "PlayerName",
  "text": "Hello everyone!"
}
```

#### `error`
Sent when a client request is invalid.

```json
{ "type": "error", "message": "Room not found" }
```

#### `room_closed`
Sent when the room is closed (e.g., all players left).

```json
{ "type": "room_closed", "reason": "All players left" }
```

---

## Game Data Actions

The `game_data` messages carry an `action` field that the Godot client interprets. The relay server does not parse these — it just forwards them.

| Action | Direction | Payload | Purpose |
|--------|-----------|---------|---------|
| `state` | Each client → others | `pos`, `rot_y`, `head_x` | Position/rotation sync (20/sec) |
| `shoot` | Shooter → others | `origin`, `dir`, `color` | Spawn remote projectile |
| `eliminated` | Killer → others | `victim_id`, `killer_id` | Sync elimination events |

---

## Security Features

### Rate Limiting

- **Per-IP connection limit** — prevents a single IP from opening too many WebSocket connections
- **Message throttling** — excessive message rates from a single client are throttled

### Input Sanitization

- Chat messages are **stripped of HTML-like characters** (`< > & " ' \``)
- Messages are **truncated to 200 characters**
- Empty messages are silently dropped

### Room Constraints

- **Max 8 players** per room
- **6-character codes** using unambiguous characters (no I, O, 0, 1)
- **Empty rooms** are automatically deleted
- **Only the host** can start the game

### What the Server Does NOT Do

- ❌ Validate game actions (no anti-cheat)
- ❌ Store player data or accounts
- ❌ Log game content or chat history
- ❌ Run any game logic
- ❌ Persist anything to disk

This is by design — the server is a stateless message relay for casual games with friends.

---

## Running the Server

### Development

```bash
cd server
npm install
npm run dev    # auto-restarts on file changes (--watch)
```

### Production

```bash
cd server
npm ci --production
npm start
```

### Docker

```bash
docker build -t paintball-relay ./server
docker run -p 9090:9090 paintball-relay
```

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `9090` | WebSocket listen port |

---

## Deployment Webhook

The server includes a deploy webhook (`deploy-hook.js`) for CI/CD integration. It listens for GitHub Actions to trigger a re-deploy of the web export. This is used in the live deployment and can be ignored for self-hosting.
