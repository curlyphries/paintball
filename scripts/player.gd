class_name Player
extends CharacterBody3D

# Movement constants
const WALK_SPEED := 5.0
const SPRINT_SPEED := 8.0
const CROUCH_SPEED := 2.5
const JUMP_VELOCITY := 4.5
const GRAVITY := 9.8
const MOUSE_SENSITIVITY := 0.002

# Camera
const CAMERA_DISTANCE_TPS := 3.5
const CAMERA_HEIGHT_TPS := 1.8
const CAMERA_DISTANCE_FPS := 0.0
const CAMERA_HEIGHT_FPS := 1.6

# State
var is_sprinting := false
var is_crouching := false
var is_dead := false
var is_first_person := true
var player_id := 0
var team := 0  # 0 = player team, 1 = bot team
var is_right_clicking := false

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

func _is_chat_active() -> bool:
	var hud = get_node_or_null("/root/Main/UI/HUD")
	if hud and hud.has_method("is_chat_active"):
		return hud.is_chat_active()
	return false

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
	if _is_chat_active():
		# Stop movement while chatting but still apply gravity
		if not is_on_floor():
			velocity.y -= GRAVITY * delta
		velocity.x = 0
		velocity.z = 0
		move_and_slide()
		return
	
	# Gravity
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	
	# Jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY
	
	# Sprint / crouch
	is_sprinting = Input.is_action_pressed("sprint") and not is_crouching
	
	if Input.is_action_pressed("crouch"):
		if not is_crouching:
			start_crouch()
	else:
		if is_crouching:
			end_crouch()
	
	# Movement
	var speed := WALK_SPEED
	if is_sprinting:
		speed = SPRINT_SPEED
	elif is_crouching:
		speed = CROUCH_SPEED
	
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0, speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0, speed * delta * 10.0)
	
	move_and_slide()

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

func _process(_delta: float) -> void:
	if is_dead:
		return
	if _is_chat_active():
		return
	
	# Melee range check — if a bot is right on top of us, next shot eliminates them
	if Input.is_action_just_pressed("shoot"):
		var bots = get_tree().get_nodes_in_group("bot")
		for bot in bots:
			if bot.is_dead:
				continue
			var dist = global_position.distance_to(bot.global_position)
			if dist < 2.5:
				bot.take_hit(player_id)
	
	# Shooting
	if Input.is_action_pressed("shoot"):
		var origin = camera_pivot.global_position
		var direction = -camera_pivot.global_transform.basis.z
		weapon.fire(origin, direction)
	
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

func switch_weapon(index: int) -> void:
	if index < 0 or index >= available_weapons.size():
		return
	current_weapon_index = index
	weapon.switch_to(available_weapons[index])
	# Update HUD
	var hud = get_node_or_null("/root/Main/UI/HUD")
	if hud:
		hud.update_weapon(available_weapons[index])

func _on_weapon_fired(pos: Vector3, direction: Vector3, spd: float, color: Color) -> void:
	GameState.record_shot_fired(player_id)
	var projectile = preload("res://scenes/projectile.tscn").instantiate()
	projectile.initialize(direction, spd, color, player_id, self)
	# Add to tree first, then set position (global_position requires being in tree)
	get_tree().root.get_node("Main/World").add_child(projectile)
	var spawn_pos = pos + direction.normalized() * 1.0
	projectile.global_position = spawn_pos
	
	# Broadcast shot over network
	var game_sync = get_node_or_null("/root/Main/GameSync")
	if game_sync:
		game_sync.send_shoot(spawn_pos, direction, color)
	
	# Play shoot sound
	if shoot_sound:
		shoot_sound.play()

func _on_ammo_changed(current: int, max_ammo: int) -> void:
	var hud = get_node_or_null("/root/Main/UI/HUD")
	if hud:
		hud.update_ammo(current, max_ammo)

func get_aim_direction() -> Vector3:
	return -camera_pivot.global_transform.basis.z
