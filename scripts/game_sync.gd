extends Node

# GameSync — Handles sending/receiving player state over the network
# Attach to Main scene when in multiplayer mode

const SYNC_RATE := 1.0 / 20.0  # 20 ticks per second

var sync_timer := 0.0
var net_players: Dictionary = {}  # player_id -> NetPlayer node
var local_player: Player = null
var players_node: Node3D = null

func _ready() -> void:
	NetworkManager.game_data_received.connect(_on_game_data)
	NetworkManager.player_left.connect(_on_player_left)

func initialize(p_local_player: Player, p_players_node: Node3D) -> void:
	local_player = p_local_player
	players_node = p_players_node
	
	# Spawn NetPlayer puppets for all remote players
	for p in NetworkManager.players:
		if p.id != NetworkManager.local_player_id:
			_spawn_net_player(p.id, p.name)

func _physics_process(delta: float) -> void:
	if local_player == null or not NetworkManager.room_code:
		return
	
	sync_timer += delta
	if sync_timer >= SYNC_RATE:
		sync_timer = 0.0
		_send_local_state()

func _send_local_state() -> void:
	if local_player.is_dead:
		return
	
	var pos = local_player.global_position
	var state = {
		"action": "state",
		"pos": [pos.x, pos.y, pos.z],
		"rot_y": local_player.rotation.y,
		"head_x": local_player.camera_pivot.rotation.x,
	}
	NetworkManager.send_game_data(state)

func send_shoot(origin: Vector3, direction: Vector3, color: Color) -> void:
	NetworkManager.send_game_data({
		"action": "shoot",
		"origin": [origin.x, origin.y, origin.z],
		"dir": [direction.x, direction.y, direction.z],
		"color": [color.r, color.g, color.b],
	})

func send_elimination(victim_id: int) -> void:
	NetworkManager.send_game_data({
		"action": "eliminated",
		"victim_id": victim_id,
		"killer_id": NetworkManager.local_player_id,
	})

# Map vote / rotation RPCs. game_sync is freed during the post-match scene, so
# post_match.gd sends these directly via NetworkManager — but exposing them here
# keeps the action vocabulary in one place and works for in-match callers.

func send_map_vote(map_key: String) -> void:
	NetworkManager.send_game_data({
		"action": "map_vote",
		"voter_id": NetworkManager.local_player_id,
		"map": map_key,
	})

func send_set_next_map(map_key: String) -> void:
	NetworkManager.send_game_data({
		"action": "set_next_map",
		"map": map_key,
	})

func _on_game_data(from_id: int, data: Dictionary) -> void:
	var action = data.get("action", "")
	
	match action:
		"state":
			_apply_remote_state(from_id, data)
		"shoot":
			_spawn_remote_projectile(from_id, data)
		"eliminated":
			_handle_remote_elimination(data)

func _apply_remote_state(from_id: int, data: Dictionary) -> void:
	if not net_players.has(from_id):
		# Late joiner — spawn their puppet
		var name_str = "Player " + str(from_id)
		for p in NetworkManager.players:
			if p.id == from_id:
				name_str = p.name
				break
		_spawn_net_player(from_id, name_str)
	
	var puppet = net_players[from_id]
	if puppet and is_instance_valid(puppet):
		puppet.apply_state(data)

func _spawn_remote_projectile(from_id: int, data: Dictionary) -> void:
	var origin = Vector3(data.origin[0], data.origin[1], data.origin[2])
	var dir = Vector3(data.dir[0], data.dir[1], data.dir[2])
	var color = Color(data.color[0], data.color[1], data.color[2])
	
	var projectile = preload("res://scenes/projectile.tscn").instantiate()
	projectile.initialize(dir, 40.0, color, from_id, null)
	var world = get_node_or_null("/root/Main/World")
	if world:
		world.add_child(projectile)
		projectile.global_position = origin

func _handle_remote_elimination(data: Dictionary) -> void:
	var victim_id = data.get("victim_id", -1)
	var killer_id = data.get("killer_id", -1)
	
	# If we're the victim
	if victim_id == NetworkManager.local_player_id:
		if local_player and not local_player.is_dead:
			local_player.die(killer_id)
	# If a remote player is the victim
	elif net_players.has(victim_id):
		var puppet = net_players[victim_id]
		if puppet and is_instance_valid(puppet) and not puppet.is_dead:
			puppet.die(killer_id)

func _spawn_net_player(id: int, player_name: String) -> void:
	if net_players.has(id):
		return
	
	var puppet = preload("res://scenes/net_player.tscn").instantiate()
	puppet.player_id = id
	puppet.player_name = player_name
	puppet.team = 1  # All remote players are "enemy" for now
	
	if players_node:
		players_node.add_child(puppet)
	net_players[id] = puppet

func _on_player_left(player_id: int, _player_name: String) -> void:
	if net_players.has(player_id):
		var puppet = net_players[player_id]
		if is_instance_valid(puppet):
			puppet.queue_free()
		net_players.erase(player_id)

func cleanup() -> void:
	for id in net_players:
		var puppet = net_players[id]
		if is_instance_valid(puppet):
			puppet.queue_free()
	net_players.clear()
