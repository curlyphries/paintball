extends Control

@onready var ammo_label: Label = $AmmoLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var round_label: Label = $RoundLabel
@onready var score_label: Label = $ScoreLabel
@onready var center_message: Label = $CenterMessage
@onready var elimination_feed: VBoxContainer = $EliminationFeed
@onready var crosshair: ColorRect = $Crosshair
@onready var player_list: VBoxContainer = $PlayerList
@onready var timer_label: Label = $TimerLabel
@onready var kill_score_label: Label = $KillScoreLabel
@onready var mode_label: Label = $ModeLabel
@onready var chat_panel: PanelContainer = $ChatPanel
@onready var chat_messages: VBoxContainer = $ChatPanel/ChatVBox/ChatScroll/ChatMessages
@onready var chat_scroll: ScrollContainer = $ChatPanel/ChatVBox/ChatScroll
@onready var chat_input: LineEdit = $ChatPanel/ChatVBox/ChatInputRow/ChatInput
@onready var chat_send_btn: Button = $ChatPanel/ChatVBox/ChatInputRow/ChatSendBtn
@onready var help_overlay: PanelContainer = $HelpOverlay
@onready var scoreboard_panel: PanelContainer = $ScoreboardPanel
@onready var scoreboard_result: Label = $ScoreboardPanel/ScoreboardVBox/ScoreboardResult
@onready var scoreboard_header: HBoxContainer = $ScoreboardPanel/ScoreboardVBox/ScoreboardHeader
@onready var scoreboard_rows: VBoxContainer = $ScoreboardPanel/ScoreboardVBox/ScoreboardScroll/ScoreboardRows
@onready var scoreboard_mvp: Label = $ScoreboardPanel/ScoreboardVBox/ScoreboardMVP
@onready var scoreboard_duration: Label = $ScoreboardPanel/ScoreboardVBox/ScoreboardDuration

var chat_is_open := false
const MAX_CHAT_MESSAGES := 50

func _ready() -> void:
	center_message.visible = false
	GameState.score_updated.connect(_on_score_updated)
	GameState.time_updated.connect(_on_time_updated)
	GameState.kill_score_updated.connect(_on_kill_score_updated)
	event_log_container = $EventLog
	
	# Show mode and map info
	mode_label.text = GameSettings.get_mode_name() + " | " + GameSettings.get_current_map_name()
	
	# Configure HUD for game mode
	var is_dm = GameSettings.game_mode == GameSettings.GameMode.DEATHMATCH
	round_label.visible = not is_dm
	score_label.visible = not is_dm
	kill_score_label.visible = is_dm
	timer_label.visible = GameState.time_limit_enabled
	
	if is_dm:
		kill_score_label.text = "Kills: 0"
	
	# Refresh player list every 0.5s
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_refresh_player_list)
	add_child(timer)
	
	# Panels setup
	scoreboard_panel.visible = false
	chat_panel.visible = false
	help_overlay.visible = false
	chat_input.text_submitted.connect(_on_chat_submitted)
	chat_send_btn.pressed.connect(_on_chat_send_pressed)
	
	# Listen for network chat messages
	NetworkManager.chat_message_received.connect(_on_network_chat_received)

func update_ammo(current: int, max_ammo: int) -> void:
	ammo_label.text = str(current) + " / " + str(max_ammo)

func update_weapon(weapon_name: String) -> void:
	weapon_label.text = weapon_name.to_upper()

func show_countdown(duration: float) -> void:
	center_message.visible = true
	for i in range(int(duration), 0, -1):
		center_message.text = str(i)
		await get_tree().create_timer(1.0).timeout
	center_message.text = "GO!"
	await get_tree().create_timer(0.5).timeout
	center_message.visible = false

func show_round_info(round_num: int, player_wins: int, bot_wins: int) -> void:
	round_label.text = "Round " + str(round_num)
	score_label.text = str(player_wins) + " - " + str(bot_wins)
	# Reset player list so it rebuilds with fresh state
	_list_built = false
	for child in player_list.get_children():
		player_list.remove_child(child)
		child.queue_free()

func show_elimination_message(msg: String) -> void:
	var label = Label.new()
	label.text = msg
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.add_theme_font_size_override("font_size", 14)
	label.modulate = Color(1, 0.3, 0.3)
	elimination_feed.add_child(label)
	
	# Also add to event log
	add_event(msg)
	
	# Fade out after 3 seconds
	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(label):
		label.queue_free()

func show_round_result(text: String) -> void:
	center_message.visible = true
	center_message.text = text
	await get_tree().create_timer(2.0).timeout
	center_message.visible = false

func show_match_result(text: String, player_wins: int, bot_wins: int) -> void:
	center_message.visible = true
	if player_wins == 0 and bot_wins == 0:
		center_message.text = text  # Deathmatch — no round score
	else:
		center_message.text = text + "\n" + str(player_wins) + " - " + str(bot_wins)

var event_log_container: VBoxContainer = null

func _on_score_updated(player_score: int, bot_score: int) -> void:
	score_label.text = str(player_score) + " - " + str(bot_score)

func _on_time_updated(seconds_remaining: float) -> void:
	if seconds_remaining <= 0:
		timer_label.text = "0:00"
		return
	var mins = int(seconds_remaining) / 60
	var secs = int(seconds_remaining) % 60
	timer_label.text = str(mins) + ":" + ("0" + str(secs) if secs < 10 else str(secs))
	# Flash red when under 30 seconds
	if seconds_remaining < 30:
		timer_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2, 1.0))

func _on_kill_score_updated(scores: Dictionary) -> void:
	var my_kills = scores.get(0, 0)
	kill_score_label.text = "Kills: " + str(my_kills)

var _list_built := false

func _refresh_player_list() -> void:
	var players_node = get_node_or_null("/root/Main/Players")
	if not players_node:
		return
	
	# Build list once, then just update text/colors
	if not _list_built:
		_build_player_list(players_node)
		_list_built = true
		return
	
	# Update existing labels
	var idx := 1  # Skip team header at index 0
	for child in players_node.get_children():
		if child is Player:
			if idx < player_list.get_child_count():
				var label = player_list.get_child(idx) as Label
				var status = "ALIVE" if not child.is_dead else "DEAD"
				label.text = "  You - " + status
				if child.is_dead:
					label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
				else:
					label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 1.0))
				idx += 1
	
	idx += 1  # Skip enemy header
	for child in players_node.get_children():
		if child is Bot:
			if idx < player_list.get_child_count():
				var label = player_list.get_child(idx) as Label
				var status = "ALIVE" if not child.is_dead else "DEAD"
				label.text = "  " + child.bot_name + " - " + status
				if child.is_dead:
					label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 1.0))
				else:
					label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 1.0))
				idx += 1

func _build_player_list(players_node: Node) -> void:
	# Build static labels once
	var team_header = Label.new()
	team_header.text = "-- YOUR TEAM --"
	team_header.add_theme_font_size_override("font_size", 11)
	team_header.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0, 1.0))
	player_list.add_child(team_header)
	
	for child in players_node.get_children():
		if child is Player:
			var entry = Label.new()
			entry.text = "  You - ALIVE"
			entry.add_theme_font_size_override("font_size", 12)
			entry.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0, 1.0))
			player_list.add_child(entry)
	
	var enemy_header = Label.new()
	enemy_header.text = "-- ENEMY TEAM --"
	enemy_header.add_theme_font_size_override("font_size", 11)
	enemy_header.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4, 1.0))
	player_list.add_child(enemy_header)
	
	for child in players_node.get_children():
		if child is Bot:
			var entry = Label.new()
			entry.text = "  " + child.bot_name + " - ALIVE"
			entry.add_theme_font_size_override("font_size", 12)
			entry.add_theme_color_override("font_color", Color(1.0, 0.7, 0.7, 1.0))
			player_list.add_child(entry)

# --- Chat ---

func _input(event: InputEvent) -> void:
	# Toggle help overlay with ? (Shift+/)
	if event.is_action_pressed("toggle_help"):
		help_overlay.visible = not help_overlay.visible
		get_viewport().set_input_as_handled()
		return
	
	# Open chat with T (only when chat is closed and not typing)
	if event.is_action_pressed("open_chat") and not chat_is_open:
		_open_chat()
		get_viewport().set_input_as_handled()
		return
	
	# Close chat with Escape
	if chat_is_open and event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE:
			_close_chat()
			get_viewport().set_input_as_handled()
			return

func _open_chat() -> void:
	chat_is_open = true
	chat_panel.visible = true
	chat_input.grab_focus()
	chat_input.text = ""
	# Release mouse so player can type
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _close_chat() -> void:
	chat_is_open = false
	chat_input.release_focus()
	# Re-capture mouse immediately
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	# Keep chat panel visible briefly to see messages, then auto-hide
	await get_tree().create_timer(3.0).timeout
	if not chat_is_open:
		chat_panel.visible = false

func _on_chat_submitted(text: String) -> void:
	if text.strip_edges() == "":
		_close_chat()
		return
	_send_chat(text.strip_edges())
	chat_input.text = ""
	_close_chat()

func _on_chat_send_pressed() -> void:
	var text = chat_input.text.strip_edges()
	if text == "":
		return
	_send_chat(text)
	chat_input.text = ""
	_close_chat()

func _send_chat(text: String) -> void:
	var is_networked = NetworkManager.room_code != ""
	if is_networked:
		NetworkManager.send_chat_message(text)
	else:
		# Solo mode — show locally as "You"
		_add_chat_message("You", text, Color(0.5, 0.8, 1.0))

func _on_network_chat_received(from_id: int, player_name: String, text: String) -> void:
	var color = Color(0.5, 0.8, 1.0) if from_id == NetworkManager.local_player_id else Color(1.0, 0.85, 0.5)
	_add_chat_message(player_name, text, color)
	# Auto-show chat panel briefly when a message arrives
	if not chat_is_open:
		chat_panel.visible = true
		await get_tree().create_timer(5.0).timeout
		if not chat_is_open:
			chat_panel.visible = false

func _add_chat_message(sender: String, text: String, name_color: Color) -> void:
	var label = RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.bbcode_text = "[color=#" + name_color.to_html(false) + "]" + sender + ":[/color] " + text
	label.add_theme_font_size_override("normal_font_size", 13)
	chat_messages.add_child(label)
	
	# Cap message count
	while chat_messages.get_child_count() > MAX_CHAT_MESSAGES:
		chat_messages.get_child(0).queue_free()
	
	# Scroll to bottom
	await get_tree().process_frame
	chat_scroll.scroll_vertical = int(chat_scroll.get_v_scroll_bar().max_value)

func is_chat_active() -> bool:
	return chat_is_open

# --- Scoreboard ---

const _SB_COLUMNS := ["#", "Name", "Kills", "Deaths", "K/D", "Acc%", "Streak", "Score"]
const _SB_WIDTHS := [30, 100, 50, 50, 50, 50, 50, 60]

func show_scoreboard(result_text: String) -> void:
	# Hide normal HUD elements
	crosshair.visible = false
	round_label.visible = false
	score_label.visible = false
	kill_score_label.visible = false
	timer_label.visible = false
	player_list.visible = false
	elimination_feed.visible = false
	center_message.visible = false
	
	scoreboard_panel.visible = true
	scoreboard_result.text = result_text
	
	# Build header row
	for child in scoreboard_header.get_children():
		child.queue_free()
	for i in range(_SB_COLUMNS.size()):
		var lbl = Label.new()
		lbl.text = _SB_COLUMNS[i]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1.0))
		lbl.custom_minimum_size.x = _SB_WIDTHS[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		scoreboard_header.add_child(lbl)
	
	# Build player rows from scoreboard data
	for child in scoreboard_rows.get_children():
		child.queue_free()
	
	var board = GameState.get_scoreboard()
	var mvp = GameState.get_mvp()
	
	for rank_idx in range(board.size()):
		var entry = board[rank_idx]
		var row = HBoxContainer.new()
		
		var is_me = entry.id == 0
		var is_mvp = (not mvp.is_empty()) and entry.id == mvp.id
		var row_color = Color(0.5, 1.0, 0.5, 1.0) if is_me else Color(0.85, 0.85, 0.85, 1.0)
		if is_mvp and not is_me:
			row_color = Color(1.0, 0.85, 0.3, 1.0)
		
		var values = [
			str(rank_idx + 1),
			entry.name + (" *" if is_mvp else ""),
			str(entry.kills),
			str(entry.deaths),
			"%.1f" % entry.kd,
			"%.0f" % entry.accuracy,
			str(entry.best_streak),
			str(entry.score)
		]
		
		for i in range(values.size()):
			var cell = Label.new()
			cell.text = values[i]
			cell.add_theme_font_size_override("font_size", 13)
			cell.add_theme_color_override("font_color", row_color)
			cell.custom_minimum_size.x = _SB_WIDTHS[i]
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(cell)
		
		scoreboard_rows.add_child(row)
	
	# MVP line
	if not mvp.is_empty():
		scoreboard_mvp.text = "MVP: " + mvp.name + " (" + str(mvp.kills) + " kills, " + "%.0f" % mvp.accuracy + "% acc, " + str(mvp.best_streak) + " streak)"
	else:
		scoreboard_mvp.text = ""
	
	# Match duration
	var duration = GameState.get_match_duration()
	var mins = int(duration) / 60
	var secs = int(duration) % 60
	scoreboard_duration.text = "Match duration: " + str(mins) + "m " + str(secs) + "s"

func add_event(msg: String) -> void:
	if not event_log_container:
		return
	var label = Label.new()
	label.text = msg
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1.0))
	event_log_container.add_child(label)
	
	# Keep max 8 entries visible
	while event_log_container.get_child_count() > 8:
		event_log_container.get_child(0).queue_free()
