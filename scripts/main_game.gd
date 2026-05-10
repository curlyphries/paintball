extends Node3D

const BOT_COUNT := 3
const SPAWN_OFFSET := 2.0

@onready var world: Node3D = $World
@onready var players_node: Node3D = $Players
@onready var hud: Control = $UI/HUD

var player: Player
var bots: Array[Bot] = []
var spawn_points: Array[Vector3] = []
var round_active := false
var game_sync: Node = null
var is_networked := false

func _ready() -> void:
	# Check if we came from lobby (networked game)
	is_networked = NetworkManager.room_code != ""
	
	# Collect spawn points from map
	var spawns = get_tree().get_nodes_in_group("spawn_point")
	for s in spawns:
		spawn_points.append(s.global_position)
	
	# If no spawn points defined, create defaults
	if spawn_points.is_empty():
		spawn_points = [
			Vector3(3, 1, 3),
			Vector3(-3, 1, 3),
			Vector3(3, 1, -3),
			Vector3(-3, 1, -3),
			Vector3(0, 1, 5),
			Vector3(0, 1, -5),
			Vector3(5, 1, 0),
			Vector3(-5, 1, 0),
		]
	
	# Connect game state signals
	GameState.round_ended.connect(_on_round_ended)
	GameState.match_ended.connect(_on_match_ended)
	
	# Spawn local player
	spawn_player()
	
	if is_networked:
		# Multiplayer — spawn remote player puppets
		_setup_network_sync()
	else:
		# Single player — spawn bots
		spawn_bots()
	
	# Add pause menu
	_add_pause_menu()
	
	# Start match
	GameState.start_match()
	start_round()

func _setup_network_sync() -> void:
	var sync_script = preload("res://scripts/game_sync.gd")
	game_sync = Node.new()
	game_sync.set_script(sync_script)
	game_sync.name = "GameSync"
	add_child(game_sync)
	game_sync.initialize(player, players_node)
	
	# Fill remaining slots with bots
	var remote_count = NetworkManager.players.size() - 1  # minus local
	var bot_slots = max(0, BOT_COUNT - remote_count)
	if bot_slots > 0:
		_spawn_filler_bots(bot_slots)

func spawn_player() -> void:
	var player_scene = preload("res://scenes/player.tscn")
	player = player_scene.instantiate()
	player.player_id = 0
	player.team = 0
	player.eliminated.connect(_on_player_eliminated)
	players_node.add_child(player)

func spawn_bots() -> void:
	var bot_scene = preload("res://scenes/bot.tscn")
	for i in range(BOT_COUNT):
		var bot = bot_scene.instantiate()
		bot.player_id = i + 1
		bot.team = 1
		bot.bot_name = "Bot " + str(i + 1)
		bot.accuracy = randf_range(0.5, 0.85)
		bot.reaction_time = randf_range(0.3, 0.8)
		bot.eliminated.connect(_on_bot_eliminated)
		bots.append(bot)
		players_node.add_child(bot)

func _spawn_filler_bots(count: int) -> void:
	var bot_scene = preload("res://scenes/bot.tscn")
	var start_id = 100  # High IDs to avoid collision with player IDs
	for i in range(count):
		var bot = bot_scene.instantiate()
		bot.player_id = start_id + i
		bot.team = 1
		bot.bot_name = "Bot " + str(i + 1)
		bot.accuracy = randf_range(0.5, 0.85)
		bot.reaction_time = randf_range(0.3, 0.8)
		bot.eliminated.connect(_on_bot_eliminated)
		bots.append(bot)
		players_node.add_child(bot)

func start_round() -> void:
	round_active = false
	
	# Reset alive lists
	GameState.players_alive = [0]
	GameState.bots_alive = []
	for bot in bots:
		GameState.bots_alive.append(bot.player_id)
	
	# Position everyone at spawn points
	var shuffled_spawns = spawn_points.duplicate()
	shuffled_spawns.shuffle()
	
	# Player gets first spawn
	player.respawn(shuffled_spawns[0])
	
	# Bots get remaining spawns
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
	
	# Start playing
	GameState.begin_play()
	round_active = true
	hud.show_round_info(GameState.current_round, GameState.player_wins, GameState.bot_wins)

func _on_player_eliminated(p: Player, killer_id: int) -> void:
	GameState.register_elimination(p.player_id, killer_id)
	var killer_name = _get_name_by_id(killer_id)
	hud.show_elimination_message(killer_name + " shot You")
	# Broadcast to network
	if is_networked and game_sync:
		game_sync.send_elimination(NetworkManager.local_player_id)

func _on_bot_eliminated(bot: Bot, killer_id: int) -> void:
	var killer_name = _get_name_by_id(killer_id)
	hud.show_elimination_message(killer_name + " shot " + bot.bot_name)

func _get_name_by_id(id: int) -> String:
	if id == NetworkManager.local_player_id:
		return "You"
	# Check remote players
	for p in NetworkManager.players:
		if p.id == id:
			return p.name
	# Check bots
	for bot in bots:
		if bot.player_id == id:
			return bot.bot_name
	return "Unknown"

func _on_round_ended(winner_team: int) -> void:
	round_active = false
	
	if winner_team == 0:
		hud.show_round_result("ROUND WON!")
	else:
		hud.show_round_result("ROUND LOST!")
	
	if not GameState.is_match_over():
		await get_tree().create_timer(GameState.ROUND_OVER_DELAY).timeout
		start_round()

func _on_match_ended(winner_team: int) -> void:
	if winner_team == 0:
		hud.show_match_result("VICTORY!", GameState.player_wins, GameState.bot_wins)
	else:
		hud.show_match_result("DEFEAT!", GameState.player_wins, GameState.bot_wins)
	
	await get_tree().create_timer(5.0).timeout
	
	if is_networked:
		if game_sync:
			game_sync.cleanup()
		NetworkManager.leave_room()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _add_pause_menu() -> void:
	var pause_scene = preload("res://scenes/pause_menu.tscn")
	var pause_menu = pause_scene.instantiate()
	$UI.add_child(pause_menu)
