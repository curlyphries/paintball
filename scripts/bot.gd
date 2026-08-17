class_name Bot
extends CharacterBody3D

# Movement
const WALK_SPEED := 4.0
const SPRINT_SPEED := 6.5
const GRAVITY := 16.7  # matches player.gd so everyone falls at the same rate
const JUMP_VELOCITY := 5.9

# Combat ranges — sized for the redesigned 50-60m maps
const VISION_RANGE := 45.0
const ENGAGE_RANGE := 38.0

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

# Stuck detection — no navmesh, so bots escape geometry by detouring/hopping
var _stuck_check_timer := 0.5
var _stuck_ref_pos := Vector3.ZERO

# Vision cache — avoid redundant raycasts per frame
var _vision_cached := false
var _can_see := false
var _vision_check_timer := 0.0
const VISION_CHECK_INTERVAL := 0.15  # Check 6-7 times/sec, not every frame

# Map bounds — set per map
var MAP_MIN := Vector3(-18, 0, -13)
var MAP_MAX := Vector3(18, 0, 13)

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

	# Stuck escape: if we've been trying to move but barely displaced,
	# hop (clears crates/low walls) and pick a fresh destination
	_stuck_check_timer -= delta
	if _stuck_check_timer <= 0.0:
		var wanted_move := Vector2(velocity.x, velocity.z).length() > 1.0
		var moved := global_position.distance_to(_stuck_ref_pos)
		if wanted_move and moved < 0.3 and (state == State.PATROL or state == State.CHASE):
			if is_on_floor():
				velocity.y = JUMP_VELOCITY
			pick_wander_target()
			wander_timer = randf_range(2.0, 4.0)
		_stuck_ref_pos = global_position
		_stuck_check_timer = 0.6

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
	if can_see_player() and dist < ENGAGE_RANGE:
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
		# Only fire while the round is live — no countdown kills
		if fire_cooldown <= 0 and GameState.match_phase == GameState.MatchPhase.PLAYING:
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
	# Direct-space query in global coordinates. (The old version assigned a
	# global direction to sight_ray.target_position, which is local space —
	# vision veered off-target whenever the bot was rotated.)
	if target == null:
		return false
	var from := global_position + Vector3.UP * 1.5
	var to: Vector3 = target.global_position + Vector3.UP * 1.0
	if from.distance_to(to) > VISION_RANGE:
		return false
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	return hit and hit.get("collider") == target

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
	# Hunt bias: usually head toward an enemy's area so bots converge on the
	# fight instead of wandering the corners of the big maps
	var enemies: Array = []
	for p in get_tree().get_nodes_in_group("player"):
		if p != self and p.team != team and not p.is_dead:
			enemies.append(p)
	if not enemies.is_empty() and randf() < 0.6:
		var e: Node3D = enemies.pick_random()
		wander_target = e.global_position + Vector3(randf_range(-6, 6), 0, randf_range(-6, 6))
		wander_target.x = clampf(wander_target.x, MAP_MIN.x + 2, MAP_MAX.x - 2)
		wander_target.z = clampf(wander_target.z, MAP_MIN.z + 2, MAP_MAX.z - 2)
		wander_target.y = global_position.y
		return
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

	direction = _steer_around_obstacles(direction.normalized())
	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	# Face movement direction
	var angle = atan2(direction.x, direction.z)
	rotation.y = lerp_angle(rotation.y, angle, 0.1)

func _steer_around_obstacles(direction: Vector3) -> Vector3:
	# Whisker probe: if the direct path is blocked within 2.5m, try rotated
	# headings (nearest first, alternating sides) and take the first clear one
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3.UP * 1.2
	for offset in [0.0, 0.6, -0.6, 1.2, -1.2]:
		var probe_dir := direction.rotated(Vector3.UP, offset)
		var query := PhysicsRayQueryParameters3D.create(from, from + probe_dir * 2.5)
		query.exclude = [get_rid()]
		if not space.intersect_ray(query):
			return probe_dir
	return direction  # fully boxed in — the stuck timer will hop us out

func fire_at_target() -> void:
	if target == null:
		return
	
	var weapon_data = GameState.get_weapon_data(weapon_name)
	fire_cooldown = weapon_data.fire_rate

	# Calculate direction with target leading — aim where they'll be when
	# the paintball arrives, not where they are
	var eye := global_position + Vector3.UP * 1.5
	var aim_pos: Vector3 = target.global_position + Vector3.UP * 1.0
	if target is CharacterBody3D:
		var lead_time: float = eye.distance_to(aim_pos) / weapon_data.speed
		aim_pos += Vector3(target.velocity.x, 0, target.velocity.z) * lead_time * 0.9
	var direction = (aim_pos - eye).normalized()
	
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
	GameState.record_shot_fired(player_id)
	var projectile = preload("res://scenes/projectile.tscn").instantiate()
	projectile.initialize(direction, spd, color, player_id, self)
	# Add to tree first, then set position (global_position requires being in tree)
	get_tree().root.get_node("Main/World").add_child(projectile)
	projectile.global_position = global_position + Vector3.UP * 1.5 + direction * 0.3
	
	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

func take_hit(attacker_id: int) -> void:
	if is_dead:
		return
	die(attacker_id)

const BODY_LINGER_TIME := 3.0

func die(killer_id: int) -> void:
	is_dead = true
	state = State.DEAD
	collision_shape.disabled = true
	velocity = Vector3.ZERO
	eliminated.emit(self, killer_id)
	GameState.register_elimination(player_id, killer_id)
	_play_death_animation()

func _play_death_animation() -> void:
	# Tilt the character model sideways to simulate falling over
	var fall_dir = [-1.0, 1.0].pick_random()
	var tween = create_tween()
	tween.set_parallel(true)
	# Rotate model sideways (fall over on Z axis)
	tween.tween_property(character_model, "rotation:z", fall_dir * 1.5, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Drop model slightly (knees buckle)
	tween.tween_property(character_model, "position:y", -0.4, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	# Small forward/backward lurch
	var lurch = randf_range(-0.3, 0.3)
	tween.tween_property(character_model, "position:z", lurch, 0.5).set_ease(Tween.EASE_IN)
	
	# Wait for body to linger, then hide
	await get_tree().create_timer(BODY_LINGER_TIME).timeout
	if is_instance_valid(self) and is_dead:
		visible = false

func respawn(spawn_position: Vector3) -> void:
	is_dead = false
	visible = true
	collision_shape.disabled = false
	# Reset model transform from death animation
	character_model.rotation = Vector3.ZERO
	character_model.position = Vector3.ZERO
	global_position = spawn_position
	velocity = Vector3.ZERO
	state = State.PATROL
	state_timer = 0.0
	reaction_timer = 0.0
