extends Control

# Post-match scene: shows final scoreboard + map vote/next-map prompt, then
# transitions back into a fresh match on the chosen map. Replaces the old
# auto-return-to-menu flash.

const VOTE_DURATION := 10.0
const RANDOM_CONTINUE_DELAY := 5.0
const FINALIZE_LEAD := 1.0  # host broadcasts winner this long before timer expires

@onready var title_label: Label = $Layout/Scoreboard/Title
@onready var subtitle_label: Label = $Layout/Scoreboard/Subtitle
@onready var stats_header: HBoxContainer = $Layout/Scoreboard/StatsHeader
@onready var stats_rows: VBoxContainer = $Layout/Scoreboard/StatsScroll/StatsRows
@onready var rotation_label: Label = $Layout/Rotation/RotationLabel
@onready var vote_buttons: VBoxContainer = $Layout/Rotation/VoteButtons
@onready var continue_button: Button = $Layout/Rotation/ContinueButton
@onready var timer_bar: ProgressBar = $Layout/Rotation/TimerBar
@onready var leave_button: Button = $Layout/Footer/LeaveButton

const COL_LABELS := ["Player", "K", "D", "K/D", "Streak", "Rounds"]
const COL_WIDTHS := [180, 50, 50, 60, 60, 70]

var time_left := VOTE_DURATION
var pool: Array[String] = []
var votes: Dictionary = {}  # voter_id -> map_key
var my_vote: String = ""
var winner_chosen := false
var next_map: String = ""
var button_for: Dictionary = {}  # map_key -> Button
var tally_for: Dictionary = {}  # map_key -> Label
var is_networked := false
var is_host := false
var rotation_mode: int = 0
var ticking := false

func _ready() -> void:
	is_networked = NetworkManager.room_code != ""
	is_host = NetworkManager.is_host if is_networked else true
	rotation_mode = GameSettings.rotation_mode
	pool = _effective_pool()

	leave_button.pressed.connect(_on_leave_pressed)
	continue_button.pressed.connect(_on_continue_pressed)
	continue_button.visible = false

	if is_networked:
		NetworkManager.game_data_received.connect(_on_game_data)
		NetworkManager.player_left.connect(_on_player_left)

	_populate_scoreboard()
	_configure_rotation_panel()

func _effective_pool() -> Array[String]:
	# Use configured pool, falling back to all available maps. Always include the
	# current map so single-map setups still work.
	var result: Array[String] = []
	for k in GameSettings.map_pool:
		if GameSettings.AVAILABLE_MAPS.has(k):
			result.append(k)
	if result.is_empty():
		for k in GameSettings.AVAILABLE_MAPS.keys():
			result.append(k)
	return result

func _populate_scoreboard() -> void:
	var winner_team: int = GameState.get_meta("last_winner_team", 0)
	var was_dm: bool = GameState.get_meta("last_was_deathmatch", false)
	var my_kills: int = GameState.get_meta("last_my_kills", 0)
	var player_wins: int = GameState.get_meta("last_player_wins", 0)
	var bot_wins: int = GameState.get_meta("last_bot_wins", 0)

	if was_dm:
		title_label.text = "VICTORY!" if winner_team == 0 else "MATCH OVER"
		subtitle_label.text = str(my_kills) + " kills"
	else:
		title_label.text = "VICTORY!" if winner_team == 0 else "DEFEAT"
		subtitle_label.text = str(player_wins) + " - " + str(bot_wins)

	# Header
	for child in stats_header.get_children():
		child.queue_free()
	for i in range(COL_LABELS.size()):
		var lbl = Label.new()
		lbl.text = COL_LABELS[i]
		lbl.add_theme_font_size_override("font_size", 12)
		lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8, 1.0))
		lbl.custom_minimum_size.x = COL_WIDTHS[i]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stats_header.add_child(lbl)

	# Rows — sorted by kills desc, local player highlighted
	for child in stats_rows.get_children():
		child.queue_free()
	var board: Array = []
	for id in GameState.match_stats:
		var s = GameState.match_stats[id]
		board.append({
			"id": id,
			"name": s.name if s.name != "" else ("Player" if id == 0 else "Bot"),
			"kills": s.kills,
			"deaths": s.deaths,
			"kd": GameState.get_kd_ratio(id),
			"best_streak": s.best_streak,
			"rounds_survived": s.rounds_survived,
		})
	board.sort_custom(func(a, b): return a.kills > b.kills)

	for entry in board:
		var row = HBoxContainer.new()
		var is_me = entry.id == 0
		var color = Color(0.6, 1.0, 0.6, 1.0) if is_me else Color(0.85, 0.85, 0.85, 1.0)
		var values = [
			entry.name,
			str(entry.kills),
			str(entry.deaths),
			"%.2f" % entry.kd,
			str(entry.best_streak),
			str(entry.rounds_survived),
		]
		for i in range(values.size()):
			var cell = Label.new()
			cell.text = values[i]
			cell.add_theme_font_size_override("font_size", 14)
			cell.add_theme_color_override("font_color", color)
			cell.custom_minimum_size.x = COL_WIDTHS[i]
			cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_CENTER
			row.add_child(cell)
		stats_rows.add_child(row)

func _configure_rotation_panel() -> void:
	# Clear any prior children
	for child in vote_buttons.get_children():
		child.queue_free()
	button_for.clear()
	tally_for.clear()

	# Single-map pool — no vote, just continue.
	if pool.size() <= 1:
		next_map = pool[0] if not pool.is_empty() else GameSettings.current_map
		rotation_label.text = "Next round starting…"
		timer_bar.max_value = RANDOM_CONTINUE_DELAY
		timer_bar.value = RANDOM_CONTINUE_DELAY
		time_left = RANDOM_CONTINUE_DELAY
		ticking = true
		return

	match rotation_mode:
		GameSettings.RotationMode.RANDOM:
			next_map = pool[randi() % pool.size()]
			_show_next_map_prompt()
		GameSettings.RotationMode.ORDERED:
			next_map = GameSettings.get_next_ordered_map()
			_show_next_map_prompt()
		_:
			_show_vote_panel()

func _show_next_map_prompt() -> void:
	rotation_label.text = "Next map: " + GameSettings.AVAILABLE_MAPS[next_map].name
	continue_button.visible = true
	continue_button.text = "Continue"
	timer_bar.max_value = RANDOM_CONTINUE_DELAY
	timer_bar.value = RANDOM_CONTINUE_DELAY
	time_left = RANDOM_CONTINUE_DELAY
	ticking = true

func _show_vote_panel() -> void:
	rotation_label.text = "Vote for next map"
	timer_bar.max_value = VOTE_DURATION
	timer_bar.value = VOTE_DURATION
	time_left = VOTE_DURATION

	for map_key in pool:
		var info = GameSettings.AVAILABLE_MAPS[map_key]
		var row = HBoxContainer.new()
		var btn = Button.new()
		btn.text = info.name
		btn.custom_minimum_size.x = 220
		btn.toggle_mode = true
		btn.pressed.connect(_on_vote_pressed.bind(map_key))
		row.add_child(btn)

		var tally = Label.new()
		tally.text = "0"
		tally.custom_minimum_size.x = 60
		tally.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0, 1.0))
		row.add_child(tally)

		vote_buttons.add_child(row)
		button_for[map_key] = btn
		tally_for[map_key] = tally

	ticking = true

func _on_vote_pressed(map_key: String) -> void:
	if winner_chosen:
		return
	my_vote = map_key
	votes[_local_voter_id()] = map_key
	# Toggle button states
	for k in button_for:
		var b: Button = button_for[k]
		b.button_pressed = (k == map_key)
	_refresh_tally()
	if is_networked:
		NetworkManager.send_game_data({
			"action": "map_vote",
			"voter_id": NetworkManager.local_player_id,
			"map": map_key,
		})

func _local_voter_id() -> int:
	return NetworkManager.local_player_id if is_networked else 0

func _refresh_tally() -> void:
	var counts: Dictionary = {}
	for v in votes.values():
		counts[v] = counts.get(v, 0) + 1
	for k in tally_for:
		var lbl: Label = tally_for[k]
		lbl.text = str(counts.get(k, 0))

func _process(delta: float) -> void:
	if not ticking or winner_chosen:
		return
	time_left -= delta
	timer_bar.value = max(time_left, 0.0)

	# Vote-mode host broadcasts the winner slightly before the timer expires so
	# all clients transition together.
	if rotation_mode == GameSettings.RotationMode.VOTE and pool.size() > 1:
		if is_networked and is_host and time_left <= FINALIZE_LEAD:
			_finalize_vote_and_broadcast()
			return

	if time_left <= 0.0:
		if rotation_mode == GameSettings.RotationMode.VOTE and pool.size() > 1:
			# Solo or non-host fallback path. Non-host should normally receive
			# set_next_map from the host; if not, fall back to local tally.
			if next_map == "":
				next_map = _pick_vote_winner()
			_transition_to_next_map()
		else:
			# RANDOM/ORDERED or single-map countdown finished.
			_transition_to_next_map()

func _finalize_vote_and_broadcast() -> void:
	next_map = _pick_vote_winner()
	if is_networked:
		NetworkManager.send_game_data({
			"action": "set_next_map",
			"map": next_map,
		})
	winner_chosen = true
	rotation_label.text = "Next map: " + GameSettings.AVAILABLE_MAPS[next_map].name
	# Wait the remaining lead time then transition so everyone lines up.
	await get_tree().create_timer(max(time_left, 0.0)).timeout
	_transition_to_next_map()

func _pick_vote_winner() -> String:
	if pool.is_empty():
		return GameSettings.current_map
	if votes.is_empty():
		return pool[randi() % pool.size()]
	var counts: Dictionary = {}
	for v in votes.values():
		counts[v] = counts.get(v, 0) + 1
	var best := -1
	var leaders: Array[String] = []
	for k in counts:
		if counts[k] > best:
			best = counts[k]
			leaders = [k]
		elif counts[k] == best:
			leaders.append(k)
	return leaders[randi() % leaders.size()]

func _on_continue_pressed() -> void:
	if winner_chosen:
		return
	_transition_to_next_map()

func _transition_to_next_map() -> void:
	if winner_chosen:
		return
	winner_chosen = true
	ticking = false
	if next_map == "":
		next_map = GameSettings.current_map
	GameSettings.current_map = next_map
	GameSettings.honor_current_map_next_load = true
	GameState.reset_match()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_leave_pressed() -> void:
	winner_chosen = true
	ticking = false
	if is_networked:
		NetworkManager.leave_room()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# --- Networking ---

func _on_game_data(from_id: int, data: Dictionary) -> void:
	var action = data.get("action", "")
	match action:
		"map_vote":
			var voter = int(data.get("voter_id", from_id))
			var map_key = String(data.get("map", ""))
			if map_key != "" and map_key in pool:
				votes[voter] = map_key
				_refresh_tally()
		"set_next_map":
			# Authoritative — non-host clients trust the host's broadcast.
			if is_host:
				return
			var map_key = String(data.get("map", ""))
			if map_key in pool:
				next_map = map_key
				winner_chosen = true
				ticking = false
				rotation_label.text = "Next map: " + GameSettings.AVAILABLE_MAPS[next_map].name
				# Brief pause so the prompt is visible, then transition.
				await get_tree().create_timer(FINALIZE_LEAD).timeout
				_do_transition_from_remote()

func _do_transition_from_remote() -> void:
	ticking = false
	GameSettings.current_map = next_map
	GameSettings.honor_current_map_next_load = true
	GameState.reset_match()
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_player_left(player_id: int, _player_name: String) -> void:
	if votes.has(player_id):
		votes.erase(player_id)
		_refresh_tally()
	# If everyone else left and we were waiting on host broadcast, fall back to solo.
	if is_networked and NetworkManager.players.size() <= 1:
		is_host = true
		is_networked = false
