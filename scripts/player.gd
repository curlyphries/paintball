class_name Player
extends CharacterBody3D

# Movement constants
const WALK_SPEED := 6.5
const SPRINT_SPEED := 10.0
const CROUCH_SPEED := 3.0
const JUMP_VELOCITY := 5.5
const GRAVITY := 16.0
const MOUSE_SENSITIVITY := 0.002
const ACCEL := 18.0
const FRICTION := 14.0
const AIR_ACCEL := 6.0

# Camera
const CAMERA_DISTANCE_TPS := 3.5
const CAMERA_HEIGHT_TPS := 1.8
const CAMERA_DISTANCE_FPS := 0.0
const CAMERA_HEIGHT_FPS := 1.6
const BASE_FOV := 90.0
const SPRINT_FOV := 95.0
const SHOOT_FOV_KICK := 3.0

# Cached node refs
var _hud: Control = null

# State
var is_sprinting := false
var is_crouching := false
var is_dead := false
var is_first_person := true
var player_id := 0
var team := 0  # 0 = player team, 1 = bot team
var is_right_clicking := false

# Feel — camera bob, tilt, recoil, shake
var _bob_time := 0.0
var _recoil_pitch := 0.0
var _shake_amount := 0.0
var _fov_target := BASE_FOV
var _was_on_floor := false

# Weapons
var available_weapons: Array[String] = ["pistol", "rifle", "sniper", "shotgun", "smg"]
var current_weapon_index := 0

# Node references
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D
@onready var character_model: Node3D = $CharacterModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var weapon_holder: Node3D = $CameraPivot/WeaponHolder
@onready var weapon: Weapon3D = $CameraPivot/WeaponHolder/Weapon3D
@onready var raycast: RayCast3D = $CameraPivot/RayCast3D
@onready var shoot_sound: AudioStreamPlayer3D = $ShootSound
@onready var footstep_sound: AudioStreamPlayer3D = $FootstepSound

signal eliminated(player: Player, killer_id: int)

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	# Ensure camera is active (important for runtime-instantiated scenes)
	camera.current = true
	
	# Default to first person
	camera.position = Vector3(0, 0, 0)
	character_model.visible = false
	
	# Connect weapon signals
	weapon.fired.connect(_on_weapon_fired)
	weapon.ammo_changed.connect(_on_ammo_changed)
	
	# Cache HUD once to avoid per-frame string lookups
	_hud = get_node_or_null("/root/Main/UI/HUD")


func _is_chat_active() -> bool:
	return _hud != null and _hud.has_method("is_chat_active") and _hud.is_chat_active()

func _input(event: InputEvent) -> void:
	if is_dead:
		return
	if _is_chat_active():
		return
	
	# Mouse look — always active when captured
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		camera_pivot.rotate_x(-event.relative.y * MOUSE_SENSITIVITY)
		camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.2, 1.2)
	
	# Click to re-capture mouse if released
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	
	if event.is_action_pressed("toggle_camera"):
		toggle_camera_mode()
	
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Freeze during countdown — apply gravity so player stays grounded
	if GameState.match_phase != GameState.MatchPhase.PLAYING:
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)
		move_and_slide()
		_update_feel(delta)
		return
	
	if _is_chat_active():
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		velocity.x = move_toward(velocity.x, 0, FRICTION * delta)
		velocity.z = move_toward(velocity.z, 0, FRICTION * delta)
		move_and_slide()
		return
	
	var on_floor := is_on_floor()
	
	# Landing impact — FOV dip
	if on_floor and not _was_on_floor:
		_fov_target = BASE_FOV - 4.0
	_was_on_floor = on_floor
	
	# Gravity
	if not on_floor:
		velocity.y -= GRAVITY * delta
	
	# Jump
	if Input.is_action_just_pressed("jump") and on_floor:
		velocity.y = JUMP_VELOCITY
	
	# Sprint / crouch
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching
	
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			start_crouch()
	else:
		if is_crouching:
			end_crouch()
	
	# Movement with acceleration / friction
	var speed := WALK_SPEED
	if is_sprinting:
		speed = SPRINT_SPEED
	elif is_crouching:
		speed = CROUCH_SPEED
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	var accel := ACCEL if on_floor else AIR_ACCEL
	var friction := FRICTION if on_floor else 2.0
	
	if direction:
		velocity.x = move_toward(velocity.x, direction.x * speed, accel * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, accel * delta)
	else:
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)
	
	move_and_slide()
	
	# Shooting (in physics_process for frame-accurate hit timing)
	if not _is_chat_active():
		if Input.is_action_just_pressed("shoot"):
			var bots := get_tree().get_nodes_in_group("bot")
			for bot in bots:
				if bot.is_dead:
					continue
				if global_position.distance_to(bot.global_position) < 2.5:
					bot.take_hit(player_id)
		if Input.is_action_pressed("shoot"):
			var origin := camera_pivot.global_position
			var dir := -camera_pivot.global_transform.basis.z
			weapon.fire(origin, dir)
	
	# Camera feel update
	_update_feel(delta)

func start_crouch() -> void:
	is_crouching = true
	# Shrink collision shape
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = 1.0
	collision_shape.position.y = 0.5
	camera_pivot.position.y = 1.0

func end_crouch() -> void:
	is_crouching = false
	var shape = collision_shape.shape as CapsuleShape3D
	shape.height = 1.8
	collision_shape.position.y = 0.9
	camera_pivot.position.y = 1.6

func toggle_camera_mode() -> void:
	is_first_person = not is_first_person
	if is_first_person:
		camera.position = Vector3(0, 0, 0)
		character_model.visible = false
	else:
		camera.position = Vector3(0.5, 0.3, CAMERA_DISTANCE_TPS)
		character_model.visible = true

func take_hit(attacker_id: int) -> void:
	if is_dead:
		return
	# One hit elimination
	die(attacker_id)

const BODY_LINGER_TIME := 3.0

func die(killer_id: int) -> void:
	is_dead = true
	collision_shape.disabled = true
	velocity = Vector3.ZERO
	eliminated.emit(self, killer_id)
	_play_death_animation()

func _play_death_animation() -> void:
	# Switch to third person so the player can see their body fall
	character_model.visible = true
	camera.position = Vector3(0.5, 1.5, 3.5)  # Pull camera back and up
	
	# Tilt the character model sideways (fall over)
	var fall_dir = [-1.0, 1.0].pick_random()
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(character_model, "rotation:z", fall_dir * 1.5, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(character_model, "position:y", -0.4, 0.5).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	var lurch = randf_range(-0.3, 0.3)
	tween.tween_property(character_model, "position:z", lurch, 0.5).set_ease(Tween.EASE_IN)
	
	# Linger, then hide
	await get_tree().create_timer(BODY_LINGER_TIME).timeout
	if is_instance_valid(self) and is_dead:
		visible = false

func respawn(spawn_position: Vector3) -> void:
	is_dead = false
	visible = true
	collision_shape.disabled = false
	# Reset model from death animation
	character_model.rotation = Vector3.ZERO
	character_model.position = Vector3.ZERO
	# Restore camera to the player's preferred mode
	if is_first_person:
		camera.position = Vector3(0, 0, 0)
		character_model.visible = false
	else:
		camera.position = Vector3(0.5, 0.3, CAMERA_DISTANCE_TPS)
		character_model.visible = true
	global_position = spawn_position
	velocity = Vector3.ZERO

func _process(delta: float) -> void:
	if is_dead:
		return
	if _is_chat_active():
		return
	
	# Reload
	if Input.is_action_just_pressed("reload"):
		weapon.start_reload()
	
	# Weapon switching
	if Input.is_action_just_pressed("weapon_1"):
		switch_weapon(0)
	elif Input.is_action_just_pressed("weapon_2"):
		switch_weapon(1)
	elif Input.is_action_just_pressed("weapon_3"):
		switch_weapon(2)
	elif Input.is_action_just_pressed("weapon_4"):
		switch_weapon(3)
	elif Input.is_action_just_pressed("weapon_5"):
		switch_weapon(4)
	elif Input.is_action_just_pressed("next_weapon"):
		current_weapon_index = (current_weapon_index + 1) % available_weapons.size()
		switch_weapon(current_weapon_index)
	elif Input.is_action_just_pressed("prev_weapon"):
		current_weapon_index = (current_weapon_index - 1 + available_weapons.size()) % available_weapons.size()
		switch_weapon(current_weapon_index)

func _update_feel(delta: float) -> void:
	if not is_first_person:
		return
	
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	var is_moving := horiz_speed > 0.5 and is_on_floor()
	
	# Camera bob on weapon holder
	if is_moving:
		_bob_time += delta * (2.2 if is_sprinting else 1.6)
		var bob_x := sin(_bob_time * 2.0) * 0.006
		var bob_y := abs(sin(_bob_time)) * 0.008
		weapon_holder.position = weapon_holder.position.lerp(Vector3(bob_x, bob_y, 0.0), 12.0 * delta)
	else:
		weapon_holder.position = weapon_holder.position.lerp(Vector3.ZERO, 8.0 * delta)
	
	# Strafe tilt
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var tilt_target := -input_dir.x * 0.035
	camera_pivot.rotation.z = lerp(camera_pivot.rotation.z, tilt_target, 8.0 * delta)
	
	# Recoil recovery
	_recoil_pitch = lerp(_recoil_pitch, 0.0, 12.0 * delta)
	camera_pivot.rotation.x += _recoil_pitch * delta
	camera_pivot.rotation.x = clamp(camera_pivot.rotation.x, -1.2, 1.2)
	
	# Screen shake decay
	if _shake_amount > 0.0:
		_shake_amount = lerpf(_shake_amount, 0.0, 16.0 * delta)
		camera.position.x = randf_range(-_shake_amount, _shake_amount)
		camera.position.y = randf_range(-_shake_amount, _shake_amount)
	else:
		camera.position = Vector3.ZERO
	
	# FOV — sprint widens, shoot kicks, landing dips, recovers to base
	var fov_goal := SPRINT_FOV if is_sprinting else BASE_FOV
	_fov_target = lerpf(_fov_target, fov_goal, 8.0 * delta)
	camera.fov = lerpf(camera.fov, _fov_target, 20.0 * delta)

func apply_recoil(kick: float) -> void:
	_recoil_pitch -= kick
	_shake_amount = clampf(kick * 0.4, 0.0, 0.012)
	_fov_target = BASE_FOV - SHOOT_FOV_KICK

func switch_weapon(index: int) -> void:
	if index < 0 or index >= available_weapons.size():
		return
	current_weapon_index = index
	weapon.switch_to(available_weapons[index])
	if _hud:
		_hud.update_weapon(available_weapons[index])

func _on_weapon_fired(pos: Vector3, direction: Vector3, spd: float, color: Color) -> void:
	GameState.record_shot_fired(player_id)
	var projectile = preload("res://scenes/projectile.tscn").instantiate()
	projectile.initialize(direction, spd, color, player_id, self)
	get_tree().root.get_node("Main/World").add_child(projectile)
	var spawn_pos = pos + direction.normalized() * 1.0
	projectile.global_position = spawn_pos
	
	# Camera recoil kick
	apply_recoil(weapon.weapon_data.get("recoil", 0.03))
	
	# Broadcast shot over network
	var game_sync = get_node_or_null("/root/Main/GameSync")
	if game_sync:
		game_sync.send_shoot(spawn_pos, direction, color)
	
	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

func _on_ammo_changed(current: int, max_ammo: int) -> void:
	if _hud:
		_hud.update_ammo(current, max_ammo)

func get_aim_direction() -> Vector3:
	return -camera_pivot.global_transform.basis.z
