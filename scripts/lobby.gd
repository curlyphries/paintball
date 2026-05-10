extends Control

@onready var start_btn: Button = $VBox/StartButton
@onready var back_btn: Button = $VBox/BackButton
@onready var status_label: Label = $VBox/StatusLabel
@onready var player_list: VBoxContainer = $VBox/PlayerListContainer
@onready var room_code_label: Label = $VBox/RoomCodeLabel
@onready var invite_link_input: LineEdit = $VBox/InviteLinkRow/InviteLinkInput
@onready var copy_btn: Button = $VBox/InviteLinkRow/CopyButton
@onready var invite_link_row: HBoxContainer = $VBox/InviteLinkRow

func _ready() -> void:
	start_btn.pressed.connect(_on_start_pressed)
	back_btn.pressed.connect(_on_back_pressed)
	copy_btn.pressed.connect(_on_copy_link)
	start_btn.visible = false
	room_code_label.visible = false
	invite_link_row.visible = false
	
	NetworkManager.room_created.connect(_on_room_created)
	NetworkManager.room_joined.connect(_on_room_joined)
	NetworkManager.player_joined.connect(_on_player_joined)
	NetworkManager.player_left.connect(_on_player_left)
	NetworkManager.game_started.connect(_on_game_started)
	NetworkManager.error_received.connect(_on_error)
	NetworkManager.disconnected_from_server.connect(_on_disconnected)
	
	# If we already have a room (came from main menu create/join), show it
	if NetworkManager.room_code != "":
		_show_room(NetworkManager.room_code)

func _on_start_pressed() -> void:
	NetworkManager.start_game()

func _on_back_pressed() -> void:
	NetworkManager.leave_room()
	NetworkManager.disconnect_from_relay()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_copy_link() -> void:
	var link = invite_link_input.text
	if OS.has_feature("web"):
		JavaScriptBridge.eval("navigator.clipboard.writeText('" + link + "')")
	else:
		DisplayServer.clipboard_set(link)
	status_label.text = "Invite link copied!"

func _get_invite_url(code: String) -> String:
	if OS.has_feature("web"):
		var origin = JavaScriptBridge.eval("window.location.origin", true)
		var path = JavaScriptBridge.eval("window.location.pathname", true)
		return str(origin) + str(path) + "?code=" + code
	return "https://curlyphries.net/paintball/?code=" + code

func _show_room(code: String) -> void:
	room_code_label.text = "ROOM CODE: " + code
	room_code_label.visible = true
	invite_link_row.visible = true
	invite_link_input.text = _get_invite_url(code)
	if NetworkManager.is_host:
		start_btn.visible = true
	_refresh_player_list()

func _on_room_created(code: String, _player_id: int) -> void:
	_show_room(code)
	status_label.text = "Room created! Share the link with friends."

func _on_room_joined(code: String, _player_id: int) -> void:
	_show_room(code)
	status_label.text = "Joined! Waiting for host to start..."

func _on_player_joined(_player_id: int, player_name: String) -> void:
	status_label.text = player_name + " joined!"
	_refresh_player_list()

func _on_player_left(_player_id: int, player_name: String) -> void:
	status_label.text = player_name + " left."
	_refresh_player_list()

func _on_game_started(_players: Array) -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_error(message: String) -> void:
	status_label.text = "Error: " + message

func _on_disconnected() -> void:
	status_label.text = "Disconnected from server."

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
