extends Node3D

var paint_color := Color.YELLOW
var surface_normal := Vector3.UP
var lifetime := 5.0
var fade_start := 3.0
var elapsed := 0.0
var splat_meshes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Remove the template mesh
	var template = $MeshInstance3D
	template.queue_free()
	
	# Droplets are placed in local XZ plane (Y is the surface normal after basis is set)
	# Center blob
	_add_droplet(Vector3.ZERO, randf_range(0.1, 0.18))
	
	# Satellite droplets spread along the surface
	var num_drops = randi_range(4, 7)
	for i in num_drops:
		var angle = randf() * TAU
		var dist = randf_range(0.05, 0.2)
		var offset = Vector3(cos(angle) * dist, 0.001, sin(angle) * dist)
		_add_droplet(offset, randf_range(0.02, 0.07))

func _add_droplet(offset: Vector3, radius: float) -> void:
	var mesh_inst = MeshInstance3D.new()
	var sphere = SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 0.3  # Very flat — hugs the surface
	sphere.radial_segments = 8
	sphere.rings = 4
	mesh_inst.mesh = sphere
	mesh_inst.position = offset
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = paint_color
	mat.emission_enabled = true
	mat.emission = paint_color
	mat.emission_energy_multiplier = 0.3
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh_inst.material_override = mat
	
	add_child(mesh_inst)
	splat_meshes.append(mesh_inst)

func _process(delta: float) -> void:
	elapsed += delta
	
	if elapsed > fade_start:
		var fade_progress = (elapsed - fade_start) / (lifetime - fade_start)
		var alpha = clamp(1.0 - fade_progress, 0.0, 1.0)
		for m in splat_meshes:
			if is_instance_valid(m) and m.material_override:
				m.material_override.albedo_color.a = alpha
	
	if elapsed >= lifetime:
		queue_free()
