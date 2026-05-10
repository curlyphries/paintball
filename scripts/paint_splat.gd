extends Node3D

var paint_color := Color.YELLOW
var surface_normal := Vector3.UP
var lifetime := 4.0
var fade_start := 2.5
var elapsed := 0.0
var _mat: StandardMaterial3D

# Global splat pool — cap total active splats to keep draw calls manageable
static var _active_splats: Array[Node] = []
const MAX_SPLATS := 80

# Shared low-poly mesh (created once, reused by all splats)
static var _shared_mesh: SphereMesh

func _ready() -> void:
	# Remove the template mesh
	var template = $MeshInstance3D
	template.queue_free()
	
	# Evict oldest splat if over cap
	_active_splats.append(self)
	while _active_splats.size() > MAX_SPLATS:
		var oldest = _active_splats.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()
	
	# Lazily create shared mesh
	if _shared_mesh == null:
		_shared_mesh = SphereMesh.new()
		_shared_mesh.radius = 1.0
		_shared_mesh.height = 0.3
		_shared_mesh.radial_segments = 6
		_shared_mesh.rings = 2
	
	# Single material for all droplets in this splat
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = paint_color
	_mat.emission_enabled = true
	_mat.emission = paint_color
	_mat.emission_energy_multiplier = 0.3
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	
	# Center blob
	_add_droplet(Vector3.ZERO, randf_range(0.1, 0.18))
	
	# 2-3 satellite droplets (was 4-7)
	var num_drops = randi_range(2, 3)
	for i in num_drops:
		var angle = randf() * TAU
		var dist = randf_range(0.05, 0.15)
		var offset = Vector3(cos(angle) * dist, 0.001, sin(angle) * dist)
		_add_droplet(offset, randf_range(0.03, 0.06))

func _add_droplet(offset: Vector3, radius: float) -> void:
	var mesh_inst = MeshInstance3D.new()
	mesh_inst.mesh = _shared_mesh
	mesh_inst.position = offset
	mesh_inst.scale = Vector3(radius, radius, radius)
	mesh_inst.material_override = _mat
	add_child(mesh_inst)

func _process(delta: float) -> void:
	elapsed += delta
	
	if elapsed > fade_start:
		var fade_progress = (elapsed - fade_start) / (lifetime - fade_start)
		_mat.albedo_color.a = clamp(1.0 - fade_progress, 0.0, 1.0)
	
	if elapsed >= lifetime:
		_active_splats.erase(self)
		queue_free()
