class_name Bot
extends CharacterBody3D

# Movement
const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const GRAVITY := 9.8

# AI State machine
enum State { PATROL, CHASE, COVER, SHOOT, DEAD }
var state: State = State.PATROL

# Identity
var player_id := 0
var team := 1  # Bot team
var bot_name := "Bot"
var is_dead := false

# Combat
var target: Node3D = null
var weapon_name := "rifle"
var fire_cooldown := 0.0
var accuracy := 0.7  # 0-1, how accurate the bot is
var reaction_time := 0.4  # Seconds before shooting after spotting

# Navigation
var wander_target := Vector3.ZERO
var last_known_target_pos := Vector3.ZERO
var reaction_timer := 0.0
var state_timer := 0.0
var wander_timer := 0.0
var strafe_dir := 1.0  # 1 or -1 for strafing while shooting
var strafe_timer := 0.0

# Vision cache — avoid redundant raycasts per frame
var _vision_cached := false
var _can_see := false
var _vision_check_timer := 0.0
const VISION_CHECK_INTERVAL := 0.15  # Check 6-7 times/sec, not every frame

# Map bounds (warehouse)
const MAP_MIN := Vector3(-18, 0, -13)
const MAP_MAX := Vector3(18, 0, 13)

# Node references
@onready var character_model: Node3D = $CharacterModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var sight_ray: RayCast3D = $SightRay
@onready var weapon: Weapon3D = $Weapon3D
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound

signal eliminated(bot: Bot, killer_id: int)

func _ready() -> void:
	add_to_group("bot")
	add_to_group("player")  # So projectiles can hit us
	
	# Connect weapon
	weapon.fired.connect(_on_weapon_fired)
	
	# Start wandering immediately
	pick_wander_target()
	wander_timer = randf_range(2.0, 5.0)

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	# Update fire cooldown
	if fire_cooldown > 0:
		fire_cooldown -= delta
	
	# Refresh vision cache at throttled rate
	_vision_check_timer -= delta
	if _vision_check_timer <= 0:
		_vision_check_timer = VISION_CHECK_INTERVAL
		_vision_cached = true
		find_target()
		_can_see = _raycast_check()
	else:
		_vision_cached = true
	
	# State machine
	match state:
		State.PATROL:
			process_patrol(delta)
		State.CHASE:
			process_chase(delta)
		State.COVER:
			process_cover(delta)
		State.SHOOT:
			process_shoot(delta)
	
	move_and_slide()

func process_patrol(delta: float) -> void:
	# Pick a new wander target when timer runs out or we're close
	wander_timer -= delta
	var dist_to_wander = Vector2(global_position.x - wander_target.x, global_position.z - wander_target.z).length()
	if wander_timer <= 0 or dist_to_wander < 1.5:
		pick_wander_target()
		wander_timer = randf_range(3.0, 6.0)
	
	move_toward_point(wander_target, WALK_SPEED, delta)
	
	# Check for player
	if can_see_player():
		enter_chase_state()

func process_chase(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		state = State.PATROL
		return
	
	var dist = global_position.distance_to(target.global_position)
	
	# Keep minimum engagement distance — don't rush right into player
	if dist > 8.0:
		last_known_target_pos = target.global_position
		move_toward_point(last_known_target_pos, SPRINT_SPEED, delta)
	else:
		# Close enough, stop advancing
		velocity.x = 0
		velocity.z = 0
	
	# Look at target
	look_at_target(delta)
	
	# If close enough and can see, shoot
	if can_see_player() and dist < 25.0:
		reaction_timer -= delta
		if reaction_timer <= 0:
			state = State.SHOOT
	elif not can_see_player():
		# Lost sight, go to last known position
		state_timer += delta
		if state_timer > 5.0:
			state = State.PATROL
			state_timer = 0.0

func process_cover(delta: float) -> void:
	# Just transition out of cover after timer
	state_timer -= delta
	if state_timer <= 0:
		if can_see_player():
			state = State.SHOOT
		else:
			state = State.PATROL

func process_shoot(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		state = State.PATROL
		return
	
	# Face target
	look_at_target(delta)
	
	# Strafe while shooting to be harder to hit
	strafe_timer -= delta
	if strafe_timer <= 0:
		strafe_dir = -strafe_dir
		strafe_timer = randf_range(0.8, 2.0)
	
	var right = global_transform.basis.x
	velocity.x = right.x * strafe_dir * WALK_SPEED * 0.5
	velocity.z = right.z * strafe_dir * WALK_SPEED * 0.5
	
	if can_see_player():
		if fire_cooldown <= 0:
			fire_at_target()
	else:
		# Lost sight, chase
		enter_chase_state()

func enter_chase_state() -> void:
	state = State.CHASE
	reaction_timer = reaction_time
	state_timer = 0.0
	find_target()

func find_target() -> void:
	var players = get_tree().get_nodes_in_group("player")
	var closest_dist := 999.0
	target = null
	
	for p in players:
		if p == self or p.team == team:
			continue
		if p.is_dead:
			continue
		var dist = global_position.distance_to(p.global_position)
		if dist < closest_dist:
			closest_dist = dist
			target = p

func can_see_player() -> bool:
	# Use cached result if available (refreshed at VISION_CHECK_INTERVAL)
	if _vision_cached:
		return _can_see
	# Fallback for first frame
	find_target()
	return _raycast_check()

func _raycast_check() -> bool:
	if target == null:
		return false
	var direction = (target.global_position + Vector3.UP * 1.0 - global_position - Vector3.UP * 1.5).normalized()
	sight_ray.target_position = direction * 30.0
	sight_ray.force_raycast_update()
	if sight_ray.is_colliding():
		var collider = sight_ray.get_collider()
		if collider == target:
			return true
	return false

func look_at_target(delta: float) -> void:
	if target == null:
		return
	var look_pos = target.global_position
	look_pos.y = global_position.y  # Only rotate horizontally
	var dir = (look_pos - global_position).normalized()
	if dir.length() > 0.01:
		var angle = atan2(dir.x, dir.z)
		rotation.y = lerp_angle(rotation.y, angle, delta * 5.0)

func pick_wander_target() -> void:
	wander_target = Vector3(
		randf_range(MAP_MIN.x + 2, MAP_MAX.x - 2),
		global_position.y,
		randf_range(MAP_MIN.z + 2, MAP_MAX.z - 2)
	)

func move_toward_point(point: Vector3, speed: float, _delta: float) -> void:
	var direction = Vector3(point.x - global_position.x, 0, point.z - global_position.z)
	var dist = direction.length()
	if dist < 1.0:
		velocity.x = 0
		velocity.z = 0
		return
	
	direction = direction.normalized()
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed
	
	# Face movement direction
	var angle = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, angle, 0.1)

func fire_at_target() -> void:
	if target == null:
		return
	
	var weapon_data = GameState.get_weapon_data(weapon_name)
	fire_cooldown = weapon_data.fire_rate
	
	# Calculate direction with inaccuracy
	var aim_pos = target.global_position + Vector3.UP * 1.0
	var direction = (aim_pos - global_position - Vector3.UP * 1.5).normalized()
	
	# Add inaccuracy based on bot accuracy
	var inaccuracy = (1.0 - accuracy) * 0.1
	direction.x += randf_range(-inaccuracy, inaccuracy)
	direction.y += randf_range(-inaccuracy, inaccuracy)
	direction.z += randf_range(-inaccuracy, inaccuracy)
	direction = direction.normalized()
	
	# Spawn projectile
	var origin = global_position + Vector3.UP * 1.5 + direction * 0.5
	weapon.fire(origin, direction)

func _on_weapon_fired(pos: Vector3, direction: Vector3, spd: float, color: Color) -> void:
	var projectile = preload("res://scenes/projectile.tscn").instantiate()
	projectile.initialize(direction, spd, color, player_id, self)
	# Add to tree first, then set position (global_position requires being in tree)
	get_tree().root.get_node("Main/World").add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 1.5 + direction * 1.0
	
	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

func take_hit(attacker_id: int) -> void:
	if is_dead:
		return
	die(attacker_id)

func die(killer_id: int) -> void:
	is_dead = true
	visible = false
	collision_shape.disabled = true
	eliminated.emit(self, killer_id)
	GameState.register_elimination(player_id, killer_id)

func respawn(spawn_position: Vector3) -> void:
	is_dead = false
	visible = true
	collision_shape.disabled = false
	global_position = spawn_position
	velocity = Vector3.ZERO
	state = State.PATROL
	state_timer = 0.0
	reaction_timer = 0.0
