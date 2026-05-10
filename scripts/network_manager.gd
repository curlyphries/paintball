extends Node

# Network Manager - Handles WebSocket connection to relay server
# Autoload singleton: NetworkManager

signal connected_to_server
signal disconnected_from_server
signal room_created(code: String, player_id: int)
signal room_joined(code: String, player_id: int)
signal player_joined(player_id: int, player_name: String)
signal player_left(player_id: int, player_name: String)
signal game_started(players: Array)
signal game_data_received(from_id: int, data: Dictionary)
signal error_received(message: String)
signal became_host

# Connection
var ws: WebSocketPeer = null
var relay_url := "ws://localhost:9090"
var _connected := false

# Room state
var room_code := ""
var local_player_id := 0
var local_player_name := "Player"
var is_host := false
var players: Array = []  # [{id, name, isHost}]

func _ready() -> void:
	# Load relay URL from project settings or environment
	if ProjectSettings.has_setting("network/relay_url"):
		relay_url = ProjectSettings.get_setting("network/relay_url")

func _process(_delta: float) -> void:
	if ws == null:
		return
	
	ws.poll()
	var state = ws.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				connected_to_server.emit()
			while ws.get_available_packet_count() > 0:
				var packet = ws.get_packet()
				_handle_message(packet.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				disconnected_from_server.emit()
			ws = null

func connect_to_relay(url: String = "") -> void:
	if url != "":
		relay_url = url
	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(relay_url)
	if err != OK:
		push_error("WebSocket connection failed: " + str(err))
		error_received.emit("Failed to connect to server")

func disconnect_from_relay() -> void:
	if ws:
		ws.close()
	_reset_state()

func create_room(player_name: String = "Host") -> void:
	local_player_name = player_name
	_send({ "type": "create_room", "name": player_name })

func join_room(code: String, player_name: String = "Player") -> void:
	local_player_name = player_name
	_send({ "type": "join_room", "code": code.to_upper(), "name": player_name })

func leave_room() -> void:
	_send({ "type": "leave_room" })
	_reset_state()

func start_game() -> void:
	if is_host:
		_send({ "type": "start_game" })

func send_game_data(data: Dictionary) -> void:
	_send({ "type": "game_data", "data": data })

# --- Internal ---

func _send(msg: Dictionary) -> void:
	if ws and ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws.send_text(JSON.stringify(msg))

func _handle_message(text: String) -> void:
	var json = JSON.new()
	if json.parse(text) != OK:
		return
	var msg = json.data
	if not msg is Dictionary:
		return
	
	match msg.get("type", ""):
		"room_created":
			room_code = msg.code
			local_player_id = msg.playerId
			is_host = true
			players = msg.players
			room_created.emit(room_code, local_player_id)
		"room_joined":
			room_code = msg.code
			local_player_id = msg.playerId
			is_host = false
			players = msg.players
			room_joined.emit(room_code, local_player_id)
		"player_joined":
			players = msg.players
			player_joined.emit(msg.playerId, msg.name)
		"player_left":
			players = msg.players
			player_left.emit(msg.playerId, msg.name)
		"you_are_host":
			is_host = true
			became_host.emit()
		"game_started":
			players = msg.players
			game_started.emit(players)
		"game_data":
			game_data_received.emit(msg.from, msg.data)
		"error":
			error_received.emit(msg.message)
		"room_closed":
			_reset_state()
			error_received.emit("Room closed: " + msg.get("reason", "unknown"))

func _reset_state() -> void:
	room_code = ""
	local_player_id = 0
	is_host = false
	players = []
