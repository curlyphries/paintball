class_name NetPlayer
extends CharacterBody3D

# Remote player puppet — no local input, driven by network data

var player_id := 0
var player_name := "Remote"
var team := 0
var is_dead := false

# Interpolation targets
var target_position := Vector3.ZERO
var target_rotation_y := 0.0
var target_head_rotation_x := 0.0
var interp_speed := 15.0

@onready var character_model: Node3D = $CharacterModel
@onready var collision_shape: CollisionShape3D = $CollisionShape3D
@onready var name_label: Label3D = $NameLabel

signal eliminated(net_player: NetPlayer, killer_id: int)

func _ready() -> void:
	add_to_group("player")
	add_to_group("net_player")
	if name_label:
		name_label.text = player_name

func _physics_process(delta: float) -> void:
	if is_dead:
		return
	
	# Smoothly interpolate to network target
	global_position = global_position.lerp(target_position, interp_speed * delta)
	rotation.y = lerp_angle(rotation.y, target_rotation_y, interp_speed * delta)

func apply_state(state: Dictionary) -> void:
	if state.has("pos"):
		var p = state.pos
		target_position = Vector3(p[0], p[1], p[2])
		# State is only broadcast while alive — a packet from a "dead" puppet
		# means they respawned. Revive and snap (don't lerp across the map).
		if is_dead:
			respawn(target_position)
	if state.has("rot_y"):
		target_rotation_y = state.rot_y
	if state.has("head_x"):
		target_head_rotation_x = state.head_x

func take_hit(attacker_id: int) -> void:
	if is_dead:
		return
	die(attacker_id)

func die(killer_id: int) -> void:
	is_dead = true
	visible = false
	collision_shape.disabled = true
	eliminated.emit(self, killer_id)

func respawn(spawn_position: Vector3) -> void:
	is_dead = false
	visible = true
	collision_shape.disabled = false
	global_position = spawn_position
	target_position = spawn_position
	velocity = Vector3.ZERO
