extends Control

@onready var name_input: LineEdit = $VBoxContainer/NameInput
@onready var code_input: LineEdit = $VBoxContainer/JoinRow/CodeInput
@onready var create_btn: Button = $VBoxContainer/CreateButton
@onready var join_btn: Button = $VBoxContainer/JoinRow/JoinButton
@onready var start_btn: Button = $VBoxContainer/StartButton
@onready var status_label: Label = $VBoxContainer/StatusLabel
@onready var player_list: VBoxContainer = $VBoxContainer/PlayerListContainer
@onready var room_code_label: Label = $VBoxContainer/RoomCodeLabel
@onready var server_input: LineEdit = $VBoxContainer/ServerInput

func _ready() -> void:
	create_btn.pressed.connect(_on_create_pressed)
	join_btn.pressed.connect(_on_join_pressed)
	start_btn.pressed.connect(_on_start_pressed)
	start_btn.visible = false
	room_code_label.visible = false
	
	NetworkManager.connected_to_server.connect(_on_connected)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.error_received.connect(_on_error)

func _get_relay_url() -> String:
	# 1. User typed something in the server field
	var manual = server_input.text.strip_edges()
	if manual != "":
		return manual
	# 2. In browser: derive from page origin (https://example.com/paintball -> wss://example.com/paintball/ws)
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		var path = JavaScriptBridge.eval("window.location.pathname.replace(/\\/[^\\/]*$/, '')", true)
		var scheme = "wss" if str(origin).begins_with("https") else "ws"
		var host = str(origin).replace("https://", "").replace("http://", "")
		return scheme + "://" + host + str(path) + "/ws"
	# 3. Fallback: project setting or localhost
	if ProjectSettings.has_setting("network/relay_url"):
		return ProjectSettings.get_setting("network/relay_url")
	return "ws://localhost:9090"

func _on_create_pressed() -> void:
	var player_name = name_input.text.strip_edges()
	if player_name == "":
		player_name = "Host"
	var server_url = _get_relay_url()
	
	status_label.text = "Connecting to " + server_url + "..."
	create_btn.disabled = true
	join_btn.disabled = true
	
	NetworkManager.connect_to_relay(server_url)
	# Wait with timeout
	var connected = false
	NetworkManager.connected_to_server.connect(func(): connected = true, CONNECT_ONE_SHOT)
	NetworkManager.error_received.connect(func(_m): connected = false, CONNECT_ONE_SHOT)
	await get_tree().create_timer(5.0).timeout
	if not connected and not NetworkManager._connected:
		status_label.text = "Connection timed out. Check server URL."
		_reset_ui()
		return
	if not NetworkManager._connected:
		return
	NetworkManager.create_room(player_name)

func _on_join_pressed() -> void:
	var player_name = name_input.text.strip_edges()
	if player_name == "":
		player_name = "Player"
	var code = code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Enter a 6-character room code"
		return
	var server_url = _get_relay_url()
	
	status_label.text = "Connecting to " + server_url + "..."
	create_btn.disabled = true
	join_btn.disabled = true
	
	NetworkManager.connect_to_relay(server_url)
	var connected = false
	NetworkManager.connected_to_server.connect(func(): connected = true, CONNECT_ONE_SHOT)
	NetworkManager.error_received.connect(func(_m): connected = false, CONNECT_ONE_SHOT)
	await get_tree().create_timer(5.0).timeout
	if not connected and not NetworkManager._connected:
		status_label.text = "Connection timed out. Check server URL."
		_reset_ui()
		return
	if not NetworkManager._connected:
		return
	NetworkManager.join_room(code, player_name)

func _on_start_pressed() -> void:
	NetworkManager.start_game()

func _on_connected() -> void:
	status_label.text = "Connected!"

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server"
	_reset_ui()

func _on_room_created(code: String, _player_id: int) -> void:
	room_code_label.text = "ROOM CODE: " + code
	room_code_label.visible = true
	start_btn.visible = true
	status_label.text = "Room created! Share the code with friends."
	_refresh_player_list()

func _on_room_joined(code: String, _player_id: int) -> void:
	room_code_label.text = "ROOM CODE: " + code
	room_code_label.visible = true
	status_label.text = "Joined! Waiting for host to start..."
	_refresh_player_list()

func _on_player_joined(_player_id: int, player_name: String) -> void:
	status_label.text = player_name + " joined!"
	_refresh_player_list()

func _on_player_left(_player_id: int, player_name: String) -> void:
	status_label.text = player_name + " left."
	_refresh_player_list()

func _on_game_started(_players: Array) -> void:
	# Switch to game scene
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_error(message: String) -> void:
	status_label.text = "Error: " + message
	_reset_ui()

func _reset_ui() -> void:
	create_btn.disabled = false
	join_btn.disabled = false
	start_btn.visible = false
	room_code_label.visible = false

func _refresh_player_list() -> void:
	# Clear existing
	for child in player_list.get_children():
		child.queue_free()
	
	for p in NetworkManager.players:
		var label = Label.new()
		var host_tag = " (HOST)" if p.isHost else ""
		label.text = "  " + p.name + host_tag
		label.add_theme_font_size_override("font_size", 16)
		if p.isHost:
			label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2, 1.0))
		else:
			label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0, 1.0))
		player_list.add_child(label)
