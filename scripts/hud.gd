extends Control

@onready var ammo_label: Label = $AmmoLabel
@onready var weapon_label: Label = $WeaponLabel
@onready var round_label: Label = $RoundLabel
@onready var score_label: Label = $ScoreLabel
@onready var center_message: Label = $CenterMessage
@onready var elimination_feed: VBoxContainer = $EliminationFeed
@onready var crosshair: ColorRect = $Crosshair
@onready var player_list: VBoxContainer = $PlayerList

func _ready() -> void:
	center_message.visible = false
	GameState.score_updated.connect(_on_score_updated)
	event_log_container = $EventLog
	# Refresh player list every 0.5s
	var timer = Timer.new()
	timer.wait_time = 0.5
	timer.autostart = true
	timer.timeout.connect(_refresh_player_list)
	add_child(timer)

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
	center_message.text = text + "\n" + str(player_wins) + " - " + str(bot_wins)

var event_log_container: VBoxContainer = null

func _on_score_updated(player_score: int, bot_score: int) -> void:
	score_label.text = str(player_score) + " - " + str(bot_score)

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
