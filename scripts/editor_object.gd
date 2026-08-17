class_name EditorObject
extends Node

# Helper component that adds selection/hover visuals to CSG shapes
# Attach this as a child of any CSGBox3D, CSGCylinder3D, or CSGSphere3D

signal selected(obj: Node3D)
signal deselected(obj: Node3D)
signal modified(obj: Node3D)

var object_id: String = ""
var object_type: String = "box"  # box, cylinder, sphere
var is_selected: bool = false
var is_hovering: bool = false

var _outline: MeshInstance3D = null
var _parent: CSGShape3D = null

func _ready() -> void:
	_parent = get_parent() as CSGShape3D
	if _parent == null:
		push_error("EditorObject must be child of a CSGShape3D")
		return
	
	# Input handling - enable ray picking on parent
	_parent.input_ray_pickable = true
	
	# Create outline mesh
	_create_outline()

func _create_outline() -> void:
	_outline = MeshInstance3D.new()
	_outline.visible = false
	_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	var outline_mat = ShaderMaterial.new()
	var shader = Shader.new()
	shader.code = """
	shader_type spatial;
	render_mode unshaded, cull_front;
	
	uniform vec4 outline_color : source_color = vec4(1.0, 0.5, 0.0, 1.0);
	uniform float outline_thickness : hint_range(0.0, 0.1) = 0.02;
	
	void vertex() {
		VERTEX += NORMAL * outline_thickness;
	}
	
	void fragment() {
		ALBEDO = outline_color.rgb;
		ALPHA = outline_color.a;
	}
	"""
	outline_mat.shader = shader
	outline_mat.set_shader_parameter("outline_color", Color(1, 0.5, 0, 1))
	outline_mat.set_shader_parameter("outline_thickness", 0.02)
	_outline.material_override = outline_mat
	
	add_child(_outline)
	_update_outline_mesh()

func _update_outline_mesh() -> void:
	if _outline == null or _parent == null:
		return
	
	var mesh: Mesh = null
	match object_type:
		"box":
			if _parent is CSGBox3D:
				var box = BoxMesh.new()
				box.size = _parent.size
				mesh = box
		"cylinder":
			if _parent is CSGCylinder3D:
				var cyl = CylinderMesh.new()
				cyl.top_radius = _parent.radius
				cyl.bottom_radius = _parent.radius
				cyl.height = _parent.height
				mesh = cyl
		"sphere":
			if _parent is CSGSphere3D:
				var sph = SphereMesh.new()
				sph.radius = _parent.radius
				mesh = sph
	
	if mesh != null:
		_outline.mesh = mesh

func set_selected(selected: bool) -> void:
	is_selected = selected
	if _outline != null:
		_outline.visible = selected
	
	if selected:
		emit_signal("selected", _parent)
	else:
		emit_signal("deselected", _parent)

func set_hover(hover: bool) -> void:
	is_hovering = hover
	if _parent == null:
		return
	if not is_selected:
		if hover:
			_parent.modulate = Color(1.2, 1.2, 1.2)
		else:
			_parent.modulate = Color.WHITE

func get_properties() -> Dictionary:
	if _parent == null:
		return {}
	
	var props = {
		"name": _parent.name,
		"type": object_type,
	}
	
	match object_type:
		"box":
			if _parent is CSGBox3D:
				props["size"] = [_parent.size.x, _parent.size.y, _parent.size.z]
		"cylinder":
			if _parent is CSGCylinder3D:
				props["radius"] = _parent.radius
				props["height"] = _parent.height
		"sphere":
			if _parent is CSGSphere3D:
				props["radius"] = _parent.radius
	
	if _parent.material != null and _parent.material is StandardMaterial3D:
		var mat = _parent.material as StandardMaterial3D
		props["color"] = [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.albedo_color.a]
		props["roughness"] = mat.roughness
		props["metallic"] = mat.metallic
		props["emission_enabled"] = mat.emission_enabled
		if mat.emission_enabled:
			props["emission"] = [mat.emission.r, mat.emission.g, mat.emission.b]
			props["emission_energy"] = mat.emission_energy
	
	return props

func apply_properties(props: Dictionary) -> void:
	if _parent == null:
		return
	
	if props.has("name"):
		_parent.name = props["name"]
	
	match object_type:
		"box":
			if _parent is CSGBox3D and props.has("size"):
				var s = props["size"]
				_parent.size = Vector3(s[0], s[1], s[2])
		"cylinder":
			if _parent is CSGCylinder3D:
				if props.has("radius"):
					_parent.radius = props["radius"]
				if props.has("height"):
					_parent.height = props["height"]
		"sphere":
			if _parent is CSGSphere3D and props.has("radius"):
				_parent.radius = props["radius"]
	
	# Apply material properties
	if props.has("color"):
		var c = props["color"]
		var new_mat = StandardMaterial3D.new()
		new_mat.albedo_color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
		new_mat.roughness = props.get("roughness", 0.5)
		new_mat.metallic = props.get("metallic", 0.0)
		
		if props.get("emission_enabled", false):
			new_mat.emission_enabled = true
			if props.has("emission"):
				var e = props["emission"]
				new_mat.emission = Color(e[0], e[1], e[2])
			new_mat.emission_energy = props.get("emission_energy", 1.0)
		
		_parent.material = new_mat
	
	_update_outline_mesh()
	emit_signal("modified", _parent)
