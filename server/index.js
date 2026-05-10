const { WebSocketServer } = require("ws");

const PORT = process.env.PORT || 9090;
const MAX_PLAYERS_PER_ROOM = 8;

// Room storage: code -> { players: Map<ws, playerInfo>, host: ws, state: string }
const rooms = new Map();

const MAX_CONNECTIONS_PER_IP = 5;
const MAX_ROOMS_PER_IP = 3;
const ipConnections = new Map(); // ip -> count
const ipRoomCreations = new Map(); // ip -> { count, resetAt }

const wss = new WebSocketServer({ host: "127.0.0.1", port: PORT, maxPayload: 64 * 1024 });

console.log(`[Relay] Paintball Arena relay server running on ws://127.0.0.1:${PORT}`);

wss.on("connection", (ws, req) => {
  const ip = req.headers["x-real-ip"] || req.socket.remoteAddress;
  
  // Per-IP connection limit
  const conns = (ipConnections.get(ip) || 0) + 1;
  if (conns > MAX_CONNECTIONS_PER_IP) {
    ws.close(1008, "Too many connections");
    console.log(`[Relay] Rejected connection from ${ip} (limit: ${MAX_CONNECTIONS_PER_IP})`);
    return;
  }
  ipConnections.set(ip, conns);

  ws.isAlive = true;
  ws.roomCode = null;
  ws.playerId = null;
  ws._ip = ip;

  ws.on("pong", () => { ws.isAlive = true; });

  ws.on("message", (data) => {
    let msg;
    try {
      msg = JSON.parse(data);
    } catch {
      ws.send(JSON.stringify({ type: "error", message: "Invalid JSON" }));
      return;
    }

    switch (msg.type) {
      case "create_room":
        handleCreateRoom(ws, msg);
        break;
      case "join_room":
        handleJoinRoom(ws, msg);
        break;
      case "leave_room":
        handleLeaveRoom(ws);
        break;
      case "game_data":
        handleGameData(ws, msg);
        break;
      case "start_game":
        handleStartGame(ws);
        break;
      case "chat_message":
        handleChatMessage(ws, msg);
        break;
      default:
        ws.send(JSON.stringify({ type: "error", message: `Unknown type: ${msg.type}` }));
    }
  });

  ws.on("close", () => {
    handleLeaveRoom(ws);
    // Decrement per-IP connection count
    if (ws._ip) {
      const c = (ipConnections.get(ws._ip) || 1) - 1;
      if (c <= 0) ipConnections.delete(ws._ip);
      else ipConnections.set(ws._ip, c);
    }
  });
});

// Heartbeat to clean dead connections
const heartbeat = setInterval(() => {
  wss.clients.forEach((ws) => {
    if (!ws.isAlive) {
      handleLeaveRoom(ws);
      return ws.terminate();
    }
    ws.isAlive = false;
    ws.ping();
  });
}, 30000);

wss.on("close", () => clearInterval(heartbeat));

// --- Handlers ---

function sanitizeName(name) {
  return String(name || "").replace(/[<>&"'`]/g, "").trim().slice(0, 20) || "Player";
}

function checkRoomRateLimit(ip) {
  const now = Date.now();
  const entry = ipRoomCreations.get(ip);
  if (!entry || now > entry.resetAt) {
    ipRoomCreations.set(ip, { count: 1, resetAt: now + 60000 }); // 1 min window
    return true;
  }
  if (entry.count >= MAX_ROOMS_PER_IP) return false;
  entry.count++;
  return true;
}

function handleCreateRoom(ws, msg) {
  if (ws.roomCode) {
    ws.send(JSON.stringify({ type: "error", message: "Already in a room" }));
    return;
  }

  if (!checkRoomRateLimit(ws._ip)) {
    ws.send(JSON.stringify({ type: "error", message: "Too many rooms created. Wait a minute." }));
    return;
  }

  const code = generateRoomCode();
  const playerName = sanitizeName(msg.name) || "Host";

  const room = {
    players: new Map(),
    host: ws,
    state: "lobby", // lobby | playing
    createdAt: Date.now(),
  };

  ws.roomCode = code;
  ws.playerId = 1;
  ws.playerName = playerName;
  room.players.set(ws, { id: 1, name: playerName, isHost: true });
  rooms.set(code, room);

  ws.send(JSON.stringify({
    type: "room_created",
    code,
    playerId: 1,
    players: getPlayerList(room),
  }));

  console.log(`[Room ${code}] Created by "${playerName}"`);
}

function handleJoinRoom(ws, msg) {
  if (ws.roomCode) {
    ws.send(JSON.stringify({ type: "error", message: "Already in a room" }));
    return;
  }

  const code = (msg.code || "").toUpperCase();
  const room = rooms.get(code);

  if (!room) {
    ws.send(JSON.stringify({ type: "error", message: "Room not found" }));
    return;
  }

  if (room.state !== "lobby") {
    ws.send(JSON.stringify({ type: "error", message: "Game already in progress" }));
    return;
  }

  if (room.players.size >= MAX_PLAYERS_PER_ROOM) {
    ws.send(JSON.stringify({ type: "error", message: "Room is full" }));
    return;
  }

  const playerName = sanitizeName(msg.name) || `Player ${room.players.size + 1}`;
  const playerId = room.players.size + 1;

  ws.roomCode = code;
  ws.playerId = playerId;
  ws.playerName = playerName;
  room.players.set(ws, { id: playerId, name: playerName, isHost: false });

  // Tell the joiner about the room
  ws.send(JSON.stringify({
    type: "room_joined",
    code,
    playerId,
    players: getPlayerList(room),
  }));

  // Tell everyone else about the new player
  broadcastToRoom(room, {
    type: "player_joined",
    playerId,
    name: playerName,
    players: getPlayerList(room),
  }, ws);

  console.log(`[Room ${code}] "${playerName}" joined (${room.players.size} players)`);
}

function handleLeaveRoom(ws) {
  const code = ws.roomCode;
  if (!code) return;

  const room = rooms.get(code);
  if (!room) {
    ws.roomCode = null;
    return;
  }

  const playerInfo = room.players.get(ws);
  room.players.delete(ws);
  ws.roomCode = null;

  if (room.players.size === 0) {
    rooms.delete(code);
    console.log(`[Room ${code}] Deleted (empty)`);
    return;
  }

  // If host left, assign new host
  if (room.host === ws) {
    const [newHost] = room.players.keys();
    room.host = newHost;
    const hostInfo = room.players.get(newHost);
    hostInfo.isHost = true;

    newHost.send(JSON.stringify({ type: "you_are_host" }));
    console.log(`[Room ${code}] Host migrated to "${hostInfo.name}"`);
  }

  // Notify remaining players
  broadcastToRoom(room, {
    type: "player_left",
    playerId: playerInfo?.id,
    name: playerInfo?.name,
    players: getPlayerList(room),
  });

  console.log(`[Room ${code}] "${playerInfo?.name}" left (${room.players.size} remaining)`);
}

function handleGameData(ws, msg) {
  const code = ws.roomCode;
  if (!code) return;

  const room = rooms.get(code);
  if (!room) return;

  // Relay game data to all other players in the room
  const relay = JSON.stringify({
    type: "game_data",
    from: ws.playerId,
    data: msg.data,
  });

  for (const [client] of room.players) {
    if (client !== ws && client.readyState === 1) {
      client.send(relay);
    }
  }
}

function handleStartGame(ws) {
  const code = ws.roomCode;
  if (!code) return;

  const room = rooms.get(code);
  if (!room || room.host !== ws) {
    ws.send(JSON.stringify({ type: "error", message: "Only host can start" }));
    return;
  }

  room.state = "playing";

  broadcastToRoom(room, {
    type: "game_started",
    players: getPlayerList(room),
  });

  console.log(`[Room ${code}] Game started with ${room.players.size} players`);
}

function handleChatMessage(ws, msg) {
  const code = ws.roomCode;
  if (!code) return;

  const room = rooms.get(code);
  if (!room) return;

  // Sanitize and truncate message
  const text = String(msg.text || "").replace(/[<>&"'`]/g, "").trim().slice(0, 200);
  if (!text) return;

  // Broadcast to all players in the room (including sender)
  broadcastToRoom(room, {
    type: "chat_message",
    from: ws.playerId,
    name: ws.playerName,
    text,
  });
}

// --- Utilities ---

function generateRoomCode() {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // No I/O/0/1 to avoid confusion
  let code;
  do {
    code = "";
    for (let i = 0; i < 6; i++) {
      code += chars[Math.floor(Math.random() * chars.length)];
    }
  } while (rooms.has(code));
  return code;
}

function getPlayerList(room) {
  const list = [];
  for (const [, info] of room.players) {
    list.push({ id: info.id, name: info.name, isHost: info.isHost });
  }
  return list;
}

function broadcastToRoom(room, msg, exclude = null) {
  const payload = JSON.stringify(msg);
  for (const [client] of room.players) {
    if (client !== exclude && client.readyState === 1) {
      client.send(payload);
    }
  }
}

// Clean stale rooms every 5 minutes
setInterval(() => {
  const now = Date.now();
  for (const [code, room] of rooms) {
    // Delete rooms older than 2 hours
    if (now - room.createdAt > 2 * 60 * 60 * 1000) {
      broadcastToRoom(room, { type: "room_closed", reason: "timeout" });
      rooms.delete(code);
      console.log(`[Room ${code}] Cleaned up (timeout)`);
    }
  }
}, 5 * 60 * 1000);
