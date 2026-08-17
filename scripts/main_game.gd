extends Node3D

const SPAWN_OFFSET := 2.0
const DEATHMATCH_RESPAWN_TIME := 3.0

@onready var world: Node3D = $World
@onready var players_node: Node3D = $Players
@onready var hud: Control = $UI/HUD

var player: Player
var bots: Array[Bot] = []
var spawn_points: Array[Vector3] = []
var round_active := false
var game_sync: Node = null
var is_networked := false
var is_deathmatch := false

func _ready() -> void:
	is_networked = NetworkManager.room_code != ""

	# Solo: pick a map from the pool now (server picks for networked play).
	# Always randomize — pool of 1 still picks that map; pool of N varies the match.
	# Exception: if the post-match scene already chose a map (vote / next-in-pool /
	# random pick from the rotation panel), honor it and clear the one-shot flag.
	if not is_networked:
		if GameSettings.honor_current_map_next_load:
			GameSettings.honor_current_map_next_load = false
		else:
			GameSettings.current_map = GameSettings.pick_random_from_pool()
	
	# Force deathmatch if no bots in non-networked team mode (rounds don't work solo with 0 enemies)
	var bot_count_check = GameSettings.get_effective_bot_count()
	if not is_networked and bot_count_check == 0 and GameSettings.game_mode != GameSettings.GameMode.DEATHMATCH:
		GameSettings.game_mode = GameSettings.GameMode.DEATHMATCH
	
	is_deathmatch = GameSettings.game_mode == GameSettings.GameMode.DEATHMATCH
	
	# Load the selected map dynamically
	_load_map()
	
	# Collect spawn points from map
	var spawns = get_tree().get_nodes_in_group("spawn_point")
	for s in spawns:
		spawn_points.append(s.global_position)
	
	if spawn_points.is_empty():
		spawn_points = [
			Vector3(3, 1, 3), Vector3(-3, 1, 3),
			Vector3(3, 1, -3), Vector3(-3, 1, -3),
			Vector3(0, 1, 5), Vector3(0, 1, -5),
			Vector3(5, 1, 0), Vector3(-5, 1, 0),
		]
	
	# Connect game state signals
	GameState.round_ended.connect(_on_round_ended)
	GameState.match_ended.connect(_on_match_ended)
	
	# Spawn local player
	spawn_player()
	
	var bot_count = GameSettings.get_effective_bot_count()
	
	if is_networked:
		_setup_network_sync()
		# Fill remaining slots with bots
		var remote_count = NetworkManager.players.size() - 1
		var bot_slots = max(0, bot_count - remote_count)
		if bot_slots > 0:
			_spawn_bots(bot_slots, 100)
	else:
		if bot_count > 0:
			_spawn_bots(bot_count, 1)
	
	_add_pause_menu()
	
	GameState.start_match()
	start_round()

func _load_map() -> void:
	# Remove the default map if present
	var existing_map = world.get_node_or_null("Map")
	if existing_map:
		existing_map.queue_free()
	
	# Load current map
	var map_path = GameSettings.get_current_map_scene_path()
	var map_scene = load(map_path)
	if map_scene:
		var map_instance = map_scene.instantiate()
		map_instance.name = "Map"
		world.add_child(map_instance)
	else:
		push_error("Failed to load map: " + map_path)

func _setup_network_sync() -> void:
	var sync_script = preload("res://scripts/game_sync.gd")
	game_sync = Node.new()
	game_sync.set_script(sync_script)
	game_sync.name = "GameSync"
	add_child(game_sync)
	game_sync.initialize(player, players_node)

func spawn_player() -> void:
	var player_scene = preload("res://scenes/player.tscn")
	player = player_scene.instantiate()
	player.player_id = 0
	player.team = 0
	player.eliminated.connect(_on_player_eliminated)
	players_node.add_child(player)
	GameState.register_player(0, "You")

func _spawn_bots(count: int, start_id: int) -> void:
	# Set map bounds per map for bot wander
	var map_bounds = _get_map_bounds()
	var bot_scene = preload("res://scenes/bot.tscn")
	for i in range(count):
		var bot = bot_scene.instantiate()
		bot.player_id = start_id + i
		# In deathmatch all bots are independent teams, otherwise team 1
		bot.team = (start_id + i) if is_deathmatch else 1
		bot.bot_name = "Bot " + str(i + 1)
		bot.accuracy = randf_range(0.5, 0.85)
		bot.reaction_time = randf_range(0.3, 0.8)
		bot.MAP_MIN = map_bounds[0]
		bot.MAP_MAX = map_bounds[1]
		bot.eliminated.connect(_on_bot_eliminated)
		bots.append(bot)
		players_node.add_child(bot)
		GameState.register_player(bot.player_id, bot.bot_name)

func _get_map_bounds() -> Array:
	# Matched to the redesigned map footprints (warehouse 60x45,
	# courtyard 60x60, arena 50m circle — inscribed square minus margin)
	match GameSettings.current_map:
		"courtyard":
			return [Vector3(-27, 0, -27), Vector3(27, 0, 27)]
		"arena":
			return [Vector3(-17, 0, -17), Vector3(17, 0, 17)]
		_:  # warehouse
			return [Vector3(-28, 0, -20), Vector3(28, 0, 20)]

func start_round() -> void:
	round_active = false
	GameState.start_round()
	
	# Reset alive lists
	GameState.players_alive = [0]
	GameState.bots_alive = []
	for bot in bots:
		GameState.bots_alive.append(bot.player_id)
	
	# Position everyone at spawn points
	var shuffled_spawns = spawn_points.duplicate()
	shuffled_spawns.shuffle()
	
	player.respawn(shuffled_spawns[0])
	
	for i in range(bots.size()):
		var spawn_idx = (i + 1) % shuffled_spawns.size()
		bots[i].respawn(shuffled_spawns[spawn_idx])
	
	# Respawn net players
	if game_sync:
		var net_idx = bots.size() + 1
		for id in game_sync.net_players:
			var puppet = game_sync.net_players[id]
			if is_instance_valid(puppet):
				var spawn_idx = net_idx % shuffled_spawns.size()
				puppet.respawn(shuffled_spawns[spawn_idx])
				net_idx += 1
	
	# Countdown
	hud.show_countdown(GameState.COUNTDOWN_TIME)
	await get_tree().create_timer(GameState.COUNTDOWN_TIME).timeout
	
	GameState.begin_play()
	round_active = true
	
	if is_deathmatch:
		hud.show_round_info(0, 0, 0)  # Deathmatch doesn't show rounds
	else:
		hud.show_round_info(GameState.current_round, GameState.player_wins, GameState.bot_wins)

func _on_player_eliminated(p: Player, killer_id: int) -> void:
	GameState.register_elimination(p.player_id, killer_id)
	var killer_name = _get_name_by_id(killer_id)
	hud.show_elimination_message(killer_name + " shot You")
	
	if is_networked and game_sync:
		game_sync.send_elimination(NetworkManager.local_player_id, killer_id)
	
	# Deathmatch: auto-respawn after delay
	if is_deathmatch and not GameState.is_match_over():
		await get_tree().create_timer(DEATHMATCH_RESPAWN_TIME).timeout
		if is_instance_valid(player) and not GameState.is_match_over():
			var shuffled = spawn_points.duplicate()
			shuffled.shuffle()
			player.respawn(shuffled[0])

func _on_bot_eliminated(bot: Bot, killer_id: int) -> void:
	var killer_name = _get_name_by_id(killer_id)
	hud.show_elimination_message(killer_name + " shot " + bot.bot_name)
	
	# Deathmatch: auto-respawn bots after delay
	if is_deathmatch and not GameState.is_match_over():
		await get_tree().create_timer(DEATHMATCH_RESPAWN_TIME).timeout
		if is_instance_valid(bot) and not GameState.is_match_over():
			var shuffled = spawn_points.duplicate()
			shuffled.shuffle()
			bot.respawn(shuffled[0])

func _get_name_by_id(id: int) -> String:
	if id == NetworkManager.local_player_id:
		return "You"
	for p in NetworkManager.players:
		if p.id == id:
			return p.name
	for bot in bots:
		if bot.player_id == id:
			return bot.bot_name
	return "Unknown"

func _on_round_ended(winner_team: int) -> void:
	round_active = false
	
	# Record rounds survived for alive players
	if not player.is_dead:
		GameState.record_round_survived(0)
	for bot in bots:
		if not bot.is_dead:
			GameState.record_round_survived(bot.player_id)
	
	if winner_team == 0:
		hud.show_round_result("ROUND WON!")
	else:
		hud.show_round_result("ROUND LOST!")
	
	if not GameState.is_match_over():
		await get_tree().create_timer(GameState.ROUND_OVER_DELAY).timeout
		start_round()

func _on_match_ended(winner_team: int) -> void:
	# Stash the result on GameState autoload so the post-match scene can title itself
	# (VICTORY/DEFEAT/MATCH OVER). The scene reads match_stats directly for the table.
	GameState.set_meta("last_winner_team", winner_team)
	GameState.set_meta("last_was_deathmatch", is_deathmatch)
	GameState.set_meta("last_player_wins", GameState.player_wins)
	GameState.set_meta("last_bot_wins", GameState.bot_wins)
	GameState.set_meta("last_my_kills", GameState.get_kill_score(0))

	# Tear down match-scene-owned networking puppets but keep the NetworkManager
	# session alive — post_match will broadcast the vote and the next main scene
	# rebuilds game_sync on _ready.
	if is_networked and game_sync:
		game_sync.cleanup()

	get_tree().change_scene_to_file("res://scenes/post_match.tscn")

func _add_pause_menu() -> void:
	var pause_scene = preload("res://scenes/pause_menu.tscn")
	var pause_menu = pause_scene.instantiate()
	$UI.add_child(pause_menu)
