extends Control

@onready var play_solo_btn: Button = $CenterPanel/VBox/PlaySoloButton
@onready var create_game_btn: Button = $CenterPanel/VBox/CreateGameButton
@onready var join_row: HBoxContainer = $CenterPanel/VBox/JoinRow
@onready var code_input: LineEdit = $CenterPanel/VBox/JoinRow/CodeInput
@onready var join_btn: Button = $CenterPanel/VBox/JoinRow/JoinButton
@onready var name_input: LineEdit = $CenterPanel/VBox/NameInput
@onready var status_label: Label = $CenterPanel/VBox/StatusLabel

func _ready() -> void:
	play_solo_btn.pressed.connect(_on_play_solo)
	create_game_btn.pressed.connect(_on_create_game)
	join_btn.pressed.connect(_on_join_game)
	
	# Check URL for auto-join code (browser only)
	if OS.has_feature("web"):
		var url_code = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('code')", true
		)
		if url_code and str(url_code) != "" and str(url_code) != "null":
			code_input.text = str(url_code).to_upper()
			status_label.text = "Invite code detected! Enter your name and click Join."

func _on_play_solo() -> void:
	NetworkManager._reset_state()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_create_game() -> void:
	var player_name = _get_player_name("Host")
	status_label.text = "Connecting..."
	_disable_buttons()
	
	var relay_url = _get_relay_url()
	NetworkManager.connect_to_relay(relay_url)
	
	if not await _wait_for_connection():
		return
	
	NetworkManager.create_room(player_name)
	NetworkManager.room_created.connect(_on_room_created, CONNECT_ONE_SHOT)

func _on_join_game() -> void:
	var code = code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Enter a 6-character room code"
		return
	
	var player_name = _get_player_name("Player")
	status_label.text = "Connecting..."
	_disable_buttons()
	
	var relay_url = _get_relay_url()
	NetworkManager.connect_to_relay(relay_url)
	
	if not await _wait_for_connection():
		return
	
	NetworkManager.join_room(code, player_name)
	# Go straight to lobby
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _on_room_created(_code: String, _player_id: int) -> void:
	get_tree().change_scene_to_file("res://scenes/lobby.tscn")

func _wait_for_connection() -> bool:
	var connected = false
	var errored = false
	NetworkManager.connected_to_server.connect(func(): connected = true, CONNECT_ONE_SHOT)
	NetworkManager.error_received.connect(func(_m): errored = true, CONNECT_ONE_SHOT)
	
	# Poll until connected, errored, or timeout
	var elapsed := 0.0
	while not connected and not errored and elapsed < 5.0:
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	if not connected:
		status_label.text = "Connection failed. Check your internet."
		_enable_buttons()
		return false
	return true

func _get_player_name(fallback: String) -> String:
	var n = name_input.text.strip_edges()
	return n if n != "" else fallback

func _get_relay_url() -> String:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		var path = JavaScriptBridge.eval("window.location.pathname.replace(/\\/[^\\/]*$/, '')", true)
		var scheme = "wss" if str(origin).begins_with("https") else "ws"
		var host = str(origin).replace("https://", "").replace("http://", "")
		return scheme + "://" + host + str(path) + "/ws"
	if ProjectSettings.has_setting("network/relay_url"):
		return ProjectSettings.get_setting("network/relay_url")
	return "ws://localhost:9090"

func _disable_buttons() -> void:
	play_solo_btn.disabled = true
	create_game_btn.disabled = true
	join_btn.disabled = true

func _enable_buttons() -> void:
	play_solo_btn.disabled = false
	create_game_btn.disabled = false
	join_btn.disabled = false
