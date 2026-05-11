extends Control

# --- Menu panel ---
@onready var menu_panel: Control = $CenterPanel/MenuPanel
@onready var play_solo_btn: Button = $CenterPanel/MenuPanel/VBox/PlaySoloButton
@onready var create_game_btn: Button = $CenterPanel/MenuPanel/VBox/CreateGameButton
@onready var join_row: HBoxContainer = $CenterPanel/MenuPanel/VBox/JoinRow
@onready var code_input: LineEdit = $CenterPanel/MenuPanel/VBox/JoinRow/CodeInput
@onready var join_btn: Button = $CenterPanel/MenuPanel/VBox/JoinRow/JoinButton
@onready var name_input: LineEdit = $CenterPanel/MenuPanel/VBox/NameInput
@onready var status_label: Label = $CenterPanel/MenuPanel/VBox/StatusLabel

# --- Settings panel ---
@onready var settings_panel: Control = $CenterPanel/SettingsPanel
@onready var mode_option: OptionButton = $CenterPanel/SettingsPanel/VBox/ModeOption
@onready var map_pool_container: VBoxContainer = $CenterPanel/SettingsPanel/VBox/MapPoolContainer
@onready var rotation_option: OptionButton = $CenterPanel/SettingsPanel/VBox/RotationOption
@onready var bots_check: CheckBox = $CenterPanel/SettingsPanel/VBox/BotsRow/BotsCheck
@onready var bots_count_label: Label = $CenterPanel/SettingsPanel/VBox/BotsRow/BotsCountLabel
@onready var bots_slider: HSlider = $CenterPanel/SettingsPanel/VBox/BotsSlider
@onready var time_limit_option: OptionButton = $CenterPanel/SettingsPanel/VBox/TimeLimitOption
@onready var volume_slider: HSlider = $CenterPanel/SettingsPanel/VBox/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $CenterPanel/SettingsPanel/VBox/VolumeRow/VolumeValueLabel
@onready var map_desc_label: Label = $CenterPanel/SettingsPanel/VBox/MapDesc
@onready var confirm_btn: Button = $CenterPanel/SettingsPanel/VBox/ConfirmButton
@onready var back_btn: Button = $CenterPanel/SettingsPanel/VBox/BackButton

# --- Lobby panel (shown after create/join) ---
@onready var lobby_panel: Control = $CenterPanel/LobbyPanel
@onready var room_code_label: Label = $CenterPanel/LobbyPanel/VBox/RoomCodeLabel
@onready var pool_summary_label: Label = $CenterPanel/LobbyPanel/VBox/PoolSummary
@onready var invite_link_input: LineEdit = $CenterPanel/LobbyPanel/VBox/InviteLinkRow/InviteLinkInput
@onready var copy_btn: Button = $CenterPanel/LobbyPanel/VBox/InviteLinkRow/CopyButton
@onready var player_list: VBoxContainer = $CenterPanel/LobbyPanel/VBox/PlayerListContainer
@onready var countdown_label: Label = $CenterPanel/LobbyPanel/VBox/CountdownLabel
@onready var start_now_btn: Button = $CenterPanel/LobbyPanel/VBox/StartNowButton
@onready var cancel_btn: Button = $CenterPanel/LobbyPanel/VBox/CancelButton
@onready var lobby_status: Label = $CenterPanel/LobbyPanel/VBox/LobbyStatus

const AUTO_START_SECONDS := 30
var _countdown_active := false
var _countdown_remaining := 0
var _settings_mode := ""  # "solo" or "create" — what happens after settings confirm

func _ready() -> void:
	play_solo_btn.pressed.connect(_on_play_solo)
	create_game_btn.pressed.connect(_on_create_game)
	join_btn.pressed.connect(_on_join_game)
	copy_btn.pressed.connect(_on_copy_link)
	start_now_btn.pressed.connect(_on_start_now)
	cancel_btn.pressed.connect(_on_cancel)
	confirm_btn.pressed.connect(_on_settings_confirm)
	back_btn.pressed.connect(_on_settings_back)
	
	# Settings control signals
	bots_check.toggled.connect(_on_bots_toggled)
	bots_slider.value_changed.connect(_on_bots_slider_changed)
	volume_slider.value_changed.connect(_on_volume_changed)
	
	lobby_panel.visible = false
	settings_panel.visible = false
	menu_panel.visible = true
	
	_populate_settings_controls()
	
	# Apply saved volume setting
	GameSettings.apply_volume()
	
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.error_received.connect(_on_error)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	
	# Check URL for auto-join code (browser only)
	if OS.has_feature("web"):
		var url_code = JavaScriptBridge.eval(
			"new URLSearchParams(window.location.search).get('code')", true
		)
		if url_code and str(url_code) != "" and str(url_code) != "null":
			code_input.text = str(url_code).to_upper()
			status_label.text = "Invite code detected! Enter your name and click Join."

# ---- Settings controls population ----

func _populate_settings_controls() -> void:
	# Game modes
	mode_option.clear()
	mode_option.add_item("Team vs Team", 0)
	mode_option.add_item("Deathmatch", 1)
	mode_option.add_item("Capture the Flag", 2)
	mode_option.selected = GameSettings.game_mode
	
	# Map pool — one checkbox per available map
	for child in map_pool_container.get_children():
		child.queue_free()
	for key in GameSettings.AVAILABLE_MAPS:
		var cb := CheckBox.new()
		cb.text = GameSettings.AVAILABLE_MAPS[key].name
		cb.set_meta("map_key", key)
		cb.button_pressed = GameSettings.is_in_pool(key)
		cb.toggled.connect(_on_map_pool_toggled)
		map_pool_container.add_child(cb)
	_update_map_pool_constraint()
	_update_map_description()

	# Rotation mode
	rotation_option.clear()
	rotation_option.add_item("Vote", GameSettings.RotationMode.VOTE)
	rotation_option.add_item("Random", GameSettings.RotationMode.RANDOM)
	rotation_option.add_item("Ordered", GameSettings.RotationMode.ORDERED)
	rotation_option.selected = GameSettings.rotation_mode
	
	# Bots
	bots_check.button_pressed = GameSettings.bots_enabled
	bots_slider.value = GameSettings.bot_count
	bots_slider.editable = GameSettings.bots_enabled
	bots_count_label.text = "Count: " + str(GameSettings.bot_count)
	
	# Time limit
	time_limit_option.clear()
	var tl_idx := 0
	for mins in GameSettings.TIME_LIMIT_OPTIONS:
		if mins == 0:
			time_limit_option.add_item("No Limit", tl_idx)
		else:
			time_limit_option.add_item(str(mins) + " min", tl_idx)
		if mins == GameSettings.time_limit_minutes:
			time_limit_option.selected = tl_idx
		tl_idx += 1

	# Volume
	volume_slider.value = GameSettings.master_volume
	_update_volume_label()

func _on_bots_toggled(pressed: bool) -> void:
	bots_slider.editable = pressed
	if not pressed:
		bots_count_label.text = "Count: 0"
	else:
		bots_count_label.text = "Count: " + str(int(bots_slider.value))

func _on_bots_slider_changed(value: float) -> void:
	bots_count_label.text = "Count: " + str(int(value))

func _on_volume_changed(value: float) -> void:
	GameSettings.master_volume = value
	GameSettings.apply_volume()
	_update_volume_label()

func _update_volume_label() -> void:
	var percent := int(GameSettings.master_volume * 100)
	volume_value_label.text = str(percent) + "%"

func _on_map_pool_toggled(_pressed: bool) -> void:
	_update_map_pool_constraint()
	_update_map_description()

func _update_map_pool_constraint() -> void:
	# Enforce: at least one map must remain checked. If only one is checked,
	# disable that checkbox so the user cannot uncheck the last one.
	var checked: Array[CheckBox] = []
	for child in map_pool_container.get_children():
		if child is CheckBox and child.button_pressed:
			checked.append(child)
	var only_one := checked.size() == 1
	for child in map_pool_container.get_children():
		if child is CheckBox:
			child.disabled = only_one and child.button_pressed

func _selected_map_keys() -> Array[String]:
	var keys: Array[String] = []
	for child in map_pool_container.get_children():
		if child is CheckBox and child.button_pressed:
			keys.append(str(child.get_meta("map_key")))
	return keys

func _update_map_description() -> void:
	var keys := _selected_map_keys()
	if keys.size() == 1 and GameSettings.AVAILABLE_MAPS.has(keys[0]):
		map_desc_label.text = GameSettings.AVAILABLE_MAPS[keys[0]].description
	else:
		map_desc_label.text = "%d maps in pool" % keys.size()

func _apply_settings() -> void:
	GameSettings.game_mode = mode_option.selected as GameSettings.GameMode
	var pool := _selected_map_keys()
	if pool.is_empty():
		# Constraint should prevent this, but be defensive.
		pool.append("warehouse")
	GameSettings.map_pool.assign(pool)
	if not GameSettings.is_in_pool(GameSettings.current_map):
		GameSettings.current_map = pool[0]
	GameSettings.rotation_mode = rotation_option.selected
	GameSettings.bots_enabled = bots_check.button_pressed
	GameSettings.bot_count = int(bots_slider.value)
	var tl_idx = time_limit_option.selected
	if tl_idx >= 0 and tl_idx < GameSettings.TIME_LIMIT_OPTIONS.size():
		GameSettings.time_limit_minutes = GameSettings.TIME_LIMIT_OPTIONS[tl_idx]
	GameSettings.master_volume = volume_slider.value
	GameSettings.apply_volume()

# ---- Menu actions ----

func _on_play_solo() -> void:
	_settings_mode = "solo"
	_show_settings()

func _on_create_game() -> void:
	_settings_mode = "create"
	_show_settings()

func _on_settings_confirm() -> void:
	_apply_settings()
	if _settings_mode == "solo":
		NetworkManager._reset_state()
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	elif _settings_mode == "create":
		var player_name = _get_player_name("Host")
		status_label.text = "Connecting..."
		_show_menu()
		_disable_buttons()
		NetworkManager.connect_to_relay(_get_relay_url())
		if not await _wait_for_connection():
			return
		NetworkManager.create_room(player_name)

func _on_settings_back() -> void:
	_show_menu()

func _on_join_game() -> void:
	var code = code_input.text.strip_edges().to_upper()
	if code.length() != 6:
		status_label.text = "Enter a 6-character room code"
		return
	var player_name = _get_player_name("Player")
	status_label.text = "Connecting..."
	_disable_buttons()
	
	NetworkManager.connect_to_relay(_get_relay_url())
	if not await _wait_for_connection():
		return
	NetworkManager.join_room(code, player_name)

# ---- Lobby actions ----

func _on_start_now() -> void:
	_countdown_active = false
	NetworkManager.start_game()

func _on_cancel() -> void:
	_countdown_active = false
	NetworkManager.leave_room()
	NetworkManager.disconnect_from_relay()
	_show_menu()

func _on_copy_link() -> void:
	var link = invite_link_input.text
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('" + link + "')")
	else:
		DisplayServer.clipboard_set(link)
	lobby_status.text = "Invite link copied!"

# ---- Network callbacks ----

func _on_room_created(code: String, _player_id: int) -> void:
	_show_lobby(code)
	lobby_status.text = "Share the link — game auto-starts in " + str(AUTO_START_SECONDS) + "s"
	_start_countdown()

func _on_room_joined(code: String, _player_id: int) -> void:
	_show_lobby(code)
	start_now_btn.visible = false
	lobby_status.text = "Joined! Waiting for host to start..."
	countdown_label.text = "Waiting for host..."

func _on_player_joined(_player_id: int, player_name: String) -> void:
	lobby_status.text = player_name + " joined!"
	_refresh_player_list()

func _on_player_left(_player_id: int, player_name: String) -> void:
	lobby_status.text = player_name + " left."
	_refresh_player_list()

func _on_game_started(_players: Array) -> void:
	_countdown_active = false
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_error(message: String) -> void:
	if lobby_panel.visible:
		lobby_status.text = "Error: " + message
	else:
		status_label.text = "Error: " + message
		_enable_buttons()

func _on_disconnected() -> void:
	_countdown_active = false
	if lobby_panel.visible:
		lobby_status.text = "Disconnected from server."
	else:
		status_label.text = "Disconnected."
		_enable_buttons()

# ---- UI switching ----

func _show_settings() -> void:
	menu_panel.visible = false
	lobby_panel.visible = false
	settings_panel.visible = true
	if _settings_mode == "solo":
		confirm_btn.text = "START GAME"
	else:
		confirm_btn.text = "CREATE & HOST"

func _show_lobby(code: String) -> void:
	menu_panel.visible = false
	settings_panel.visible = false
	lobby_panel.visible = true
	room_code_label.text = code
	invite_link_input.text = _get_invite_url(code)
	start_now_btn.visible = NetworkManager.is_host
	_refresh_pool_summary()
	_refresh_player_list()

func _refresh_pool_summary() -> void:
	pool_summary_label.text = "Pool: %s · Mode: %s" % [
		GameSettings.get_pool_summary(),
		GameSettings.get_rotation_mode_name(),
	]

func _show_menu() -> void:
	lobby_panel.visible = false
	settings_panel.visible = false
	menu_panel.visible = true
	_enable_buttons()
	status_label.text = ""

# ---- Countdown ----

func _start_countdown() -> void:
	_countdown_remaining = AUTO_START_SECONDS
	_countdown_active = true
	while _countdown_active and _countdown_remaining > 0:
		countdown_label.text = "Game starts in " + str(_countdown_remaining) + "s"
		await get_tree().create_timer(1.0).timeout
		_countdown_remaining -= 1
	if _countdown_active:
		countdown_label.text = "Starting..."
		NetworkManager.start_game()

# ---- Helpers ----

func _refresh_player_list() -> void:
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

func _wait_for_connection() -> bool:
	var connected = false
	var errored = false
	
	# Already connected from a previous session?
	if NetworkManager._connected:
		return true
	
	NetworkManager.connected_to_server.connect(func(): connected = true, CONNECT_ONE_SHOT)
	NetworkManager.error_received.connect(func(_m): errored = true, CONNECT_ONE_SHOT)
	
	var elapsed := 0.0
	while not connected and not errored and elapsed < 8.0:
		# Also check manager state directly (signal may have fired before lambda attached)
		if NetworkManager._connected:
			connected = true
			break
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	
	if not connected and not NetworkManager._connected:
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

func _get_invite_url(code: String) -> String:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		var path = JavaScriptBridge.eval("window.location.pathname", true)
		return str(origin) + str(path) + "?code=" + code
	return "https://curlyphries.net/paintball/?code=" + code

func _disable_buttons() -> void:
	play_solo_btn.disabled = true
	create_game_btn.disabled = true
	join_btn.disabled = true

func _enable_buttons() -> void:
	play_solo_btn.disabled = false
	create_game_btn.disabled = false
	join_btn.disabled = false
