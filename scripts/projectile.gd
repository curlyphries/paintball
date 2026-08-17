class_name Paintball
extends CharacterBody3D

var direction := Vector3.FORWARD
var speed := 40.0
var owner_id := -1
var paint_color := Color.YELLOW
var lifetime := 3.0
var owner_node: Node = null

@onready var mesh: MeshInstance3D = $MeshInstance3D
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Material cache — shared across all projectiles by color key
static var _mat_cache: Dictionary = {}

func _ready() -> void:
	# Reuse material by color to avoid creating thousands of materials
	var key = "%d_%d_%d" % [int(paint_color.r * 255), int(paint_color.g * 255), int(paint_color.b * 255)]
	if _mat_cache.has(key):
		mesh.material_override = _mat_cache[key]
	else:
		var mat = StandardMaterial3D.new()
		mat.albedo_color = paint_color
		mat.emission_enabled = true
		mat.emission = paint_color
		mat.emission_energy_multiplier = 2.0
		_mat_cache[key] = mat
		mesh.material_override = mat

	# Never collide with the shooter — lets shots connect at point-blank range
	if owner_node is PhysicsBody3D:
		add_collision_exception_with(owner_node)

func initialize(dir: Vector3, spd: float, color: Color, shooter_id: int, shooter: Node = null) -> void:
	direction = dir.normalized()
	speed = spd
	paint_color = color
	owner_id = shooter_id
	owner_node = shooter
	velocity = direction * speed

func _physics_process(delta: float) -> void:
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return
	
	# Apply gravity to paintball
	velocity.y -= 9.8 * delta * 0.3  # Slight drop

	var collision_info = move_and_collide(velocity * delta)
	if collision_info:
		_on_hit(collision_info)

func _on_hit(collision_info: KinematicCollision3D) -> void:
	var collider = collision_info.get_collider()
	
	# Check if we hit a player/bot
	var hit_character := false
	if collider is CharacterBody3D and collider.has_method("take_hit"):
		if collider.player_id != owner_id:
			GameState.record_shot_hit(owner_id)
			collider.take_hit(owner_id)
			hit_character = true
	
	# Only spawn paint splat on world surfaces, not on characters
	if not hit_character:
		spawn_paint_splat(collision_info.get_position(), collision_info.get_normal())
	
	queue_free()

func spawn_paint_splat(pos: Vector3, normal: Vector3) -> void:
	var splat = preload("res://scenes/paint_splat.tscn").instantiate()
	splat.paint_color = paint_color
	splat.surface_normal = normal
	
	# Add to world first so global_transform works
	get_tree().root.get_node("Main/World").add_child(splat)
	
	# Position slightly off the surface
	splat.global_position = pos + normal * 0.005
	
	# Build a basis where Y axis = surface normal
	# This makes the splat lie flat against any surface
	var up = normal
	var right: Vector3
	if abs(normal.dot(Vector3.UP)) < 0.99:
		right = Vector3.UP.cross(normal).normalized()
	else:
		right = Vector3.FORWARD.cross(normal).normalized()
	var forward = normal.cross(right).normalized()
	splat.global_transform.basis = Basis(right, up, forward)
