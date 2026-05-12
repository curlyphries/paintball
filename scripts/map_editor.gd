class_name MapEditor
extends Node3D

# Main map editor controller
# Handles object placement, selection, save/load, and UI coordination

enum Tool { SELECT, BOX, CYLINDER, SPHERE, SPAWN }
enum TransformMode { MOVE, ROTATE, SCALE }

@export var grid_snap: float = 1.0:
	set(value):
		grid_snap = value
		if grid_mesh != null:
			_update_grid()

@export var map_width: float = 40.0:
	set(value):
		map_width = value
		_update_bounds()

@export var map_depth: float = 30.0:
	set(value):
		map_depth = value
		_update_bounds()

@export var map_height: float = 20.0
@export var auto_walls: bool = true
@export var has_ceiling: bool = false

# Current state
var current_tool: Tool = Tool.SELECT
var current_transform_mode: TransformMode = TransformMode.MOVE
var current_spawn_team: String = "ffa"

# Data
var map_data: MapData = null
var current_file_path: String = ""
var is_dirty: bool = false

# Selection
var selected_objects: Array[Node] = []
var hovered_object: Node = null

# History for undo/redo
var history: Array[Dictionary] = []
var history_index: int = -1
const MAX_HISTORY = 50

# Placing state
var _is_placing: bool = false
var _placing_preview: Node = null
var _place_start_pos: Vector3 = Vector3.ZERO

# Gizmo
var _gizmo: EditorGizmo = null
var _gizmo_active: bool = false

# Clipboard for copy/paste
var _clipboard: Array[Dictionary] = []

# Dragging state
var _is_dragging: bool = false
var _drag_start_mouse: Vector2 = Vector2.ZERO
var _drag_start_transforms: Array[Transform3D] = []

# Nodes
@onready var camera: EditorCamera = $EditorCamera
@onready var object_container: Node3D = $Objects
@onready var spawn_container: Node3D = $SpawnPoints
@onready var environment: Node3D = $Environment
@onready var grid_mesh: MeshInstance3D = $Grid
@onready var floor: CSGBox3D = $Floor
@onready var bounds: Node3D = $Bounds
@onready var gizmo_container: Node3D = $GizmoContainer

# UI reference (set by UI controller)
var ui_controller: Control = null

func _ready() -> void:
	# Create gizmo
	_create_gizmo()
	
	# Initialize with new map
	new_map()
	
	# Setup input handling
	set_process_input(true)
	set_process(true)

func _create_gizmo() -> void:
	_gizmo = EditorGizmo.new()
	_gizmo.visible = false
	_gizmo.transform_started.connect(_on_gizmo_transform_started)
	_gizmo.transform_changed.connect(_on_gizmo_transform_changed)
	_gizmo.transform_finished.connect(_on_gizmo_transform_finished)
	
	if gizmo_container != null:
		gizmo_container.add_child(_gizmo)
	else:
		add_child(_gizmo)

func _input(event: InputEvent) -> void:
	# Handle keyboard shortcuts
	if event is InputEventKey:
		if event.pressed and not event.echo:
			match event.keycode:
				KEY_S:
					if event.ctrl_pressed:
						_save_map()
						event.handled = true
					elif not event.ctrl_pressed:
						set_tool(Tool.SELECT)
				KEY_O:
					if event.ctrl_pressed:
						_load_map_dialog()
						event.handled = true
				KEY_N:
					if event.ctrl_pressed:
						new_map()
						event.handled = true
				KEY_Z:
					if event.ctrl_pressed:
						if event.shift_pressed:
							_redo()
						else:
							_undo()
						event.handled = true
				KEY_Y:
					if event.ctrl_pressed:
						_redo()
						event.handled = true
				KEY_DELETE:
					_delete_selected()
					event.handled = true
				KEY_Q:
					set_tool(Tool.BOX)
				KEY_W:
					if not event.ctrl_pressed:
						set_tool(Tool.CYLINDER)
				KEY_E:
					if not event.ctrl_pressed:
						set_tool(Tool.SPHERE)
				KEY_R:
					set_tool(Tool.SPAWN)
				KEY_1:
					set_tool(Tool.SELECT)
				KEY_2:
					set_tool(Tool.BOX)
				KEY_3:
					set_tool(Tool.CYLINDER)
				KEY_4:
					set_tool(Tool.SPHERE)
				KEY_5:
					set_tool(Tool.SPAWN)
				KEY_F:
					_frame_selection()
				KEY_G:
					# Toggle grid snap
					grid_snap = 1.0 if grid_snap == 0.0 else 0.0
					_update_ui()
				KEY_ESCAPE:
					if _is_placing:
						_cancel_placement()
					elif selected_objects.size() > 0:
						_clear_selection()
					else:
						_show_exit_confirm()
				KEY_W:
					if event.ctrl_pressed:
						current_transform_mode = TransformMode.MOVE
						_update_ui()
				KEY_E:
					if event.ctrl_pressed:
						current_transform_mode = TransformMode.ROTATE
						_update_ui()
				KEY_R:
					if event.ctrl_pressed:
						current_transform_mode = TransformMode.SCALE
						_update_ui()
				KEY_C:
					if event.ctrl_pressed:
						_copy_selected()
						event.handled = true
				KEY_V:
					if event.ctrl_pressed:
						_paste()
						event.handled = true
				KEY_D:
					if event.ctrl_pressed:
						_duplicate_selected()
						event.handled = true
				KEY_F1:
					show_help()
					event.handled = true
				KEY_F5:
					test_play()
					event.handled = true
	
	# Handle mouse input
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if current_tool == Tool.SELECT:
					# Check if clicking on gizmo
					if _gizmo != null and selected_objects.size() > 0:
						var axis = _gizmo.get_axis_at_mouse(camera, event.position)
						if axis != EditorGizmo.Axis.NONE:
							_gizmo.start_drag(camera, event.position, axis)
							_is_dragging = true
							event.handled = true
							return
					_select_at_mouse(event.position)
				else:
					_start_placement(event.position)
			else:
				if _is_placing:
					_finish_placement(event.position)
				elif _is_dragging and _gizmo != null:
					_gizmo.end_drag()
					_is_dragging = false
	
	if event is InputEventMouseMotion:
		if _is_placing:
			_update_placement(event.position)
		elif _gizmo_active and _gizmo != null and _gizmo._is_dragging:
			# Gizmo handles this in _process
			pass
		else:
			_update_hover(event.position)
			# Check gizmo hover
			if _gizmo != null and selected_objects.size() > 0:
				var axis = _gizmo.get_axis_at_mouse(camera, event.position)
				_gizmo.set_highlight(axis)

func _process(delta: float) -> void:
	# Update placing preview
	if _is_placing and _placing_preview != null:
		var mouse_pos = get_viewport().get_mouse_position()
		var world_pos = camera.get_ground_intersection(mouse_pos)
		world_pos = _snap_position(world_pos)
		_placing_preview.position = world_pos
	
	# Update gizmo position to selection center
	_update_gizmo_position()
	
	# Handle gizmo dragging
	if _gizmo_active and _gizmo != null and _gizmo._is_dragging:
		var mouse_pos = get_viewport().get_mouse_position()
		_gizmo.update_drag(camera, mouse_pos)

# === Tool Management ===

func set_tool(tool: Tool) -> void:
	current_tool = tool
	_cancel_placement()
	_clear_selection()
	_update_ui()

func set_transform_mode(mode: TransformMode) -> void:
	current_transform_mode = mode
	_update_ui()

func set_spawn_team(team: String) -> void:
	current_spawn_team = team

# === Map Management ===

func new_map() -> void:
	map_data = MapData.new()
	current_file_path = ""
	is_dirty = false
	_clear_all_objects()
	_update_environment()
	_update_grid()
	_update_bounds()
	_update_ui()
	_clear_history()
	_add_history_state("New Map")

func _clear_all_objects() -> void:
	# Remove all objects
	for child in object_container.get_children():
		child.queue_free()
	selected_objects.clear()
	hovered_object = null
	
	# Remove all spawn points
	for child in spawn_container.get_children():
		child.queue_free()

func _update_environment() -> void:
	# Update floor size
	if floor != null:
		floor.size = Vector3(map_width, 0.5, map_depth)
	
	# Update grid
	_update_grid()

func _update_grid() -> void:
	if grid_mesh == null:
		return
	
	var grid_size = max(map_width, map_depth)
	var grid_subdivisions = int(grid_size / grid_snap) if grid_snap > 0 else int(grid_size)
	
	# Create grid mesh
	var immediate = ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES)
	
	var color = Color(0.5, 0.5, 0.5, 0.5)
	var half_w = map_width / 2
	var half_d = map_depth / 2
	
	if grid_snap > 0:
		# Draw grid lines
		for i in range(-half_w, half_w + 1, grid_snap):
			immediate.surface_set_color(color)
			immediate.surface_add_vertex(Vector3(i, 0.01, -half_d))
			immediate.surface_set_color(color)
			immediate.surface_add_vertex(Vector3(i, 0.01, half_d))
		
		for i in range(-half_d, half_d + 1, grid_snap):
			immediate.surface_set_color(color)
			immediate.surface_add_vertex(Vector3(-half_w, 0.01, i))
			immediate.surface_set_color(color)
			immediate.surface_add_vertex(Vector3(half_w, 0.01, i))
	
	# Draw bounds
	var bound_color = Color(1, 0.5, 0, 0.8)
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(-half_w, 0.01, -half_d))
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(half_w, 0.01, -half_d))
	
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(half_w, 0.01, -half_d))
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(half_w, 0.01, half_d))
	
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(half_w, 0.01, half_d))
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(-half_w, 0.01, half_d))
	
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(-half_w, 0.01, half_d))
	immediate.surface_set_color(bound_color)
	immediate.surface_add_vertex(Vector3(-half_w, 0.01, -half_d))
	
	immediate.surface_end()
	
	grid_mesh.mesh = immediate

func _update_bounds() -> void:
	if bounds == null:
		return
	
	# Clear existing bounds
	for child in bounds.get_children():
		child.queue_free()
	
	if not auto_walls:
		return
	
	var half_w = map_width / 2
	var half_d = map_depth / 2
	var wall_height = map_height
	var wall_thickness = 0.5
	
	# Create boundary walls
	var wall_mat = StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.3, 0.3, 0.35)
	
	# North wall
	var wall_n = CSGBox3D.new()
	wall_n.size = Vector3(map_width, wall_height, wall_thickness)
	wall_n.position = Vector3(0, wall_height / 2, -half_d - wall_thickness / 2)
	wall_n.material = wall_mat
	wall_n.use_collision = true
	bounds.add_child(wall_n)
	
	# South wall
	var wall_s = CSGBox3D.new()
	wall_s.size = Vector3(map_width, wall_height, wall_thickness)
	wall_s.position = Vector3(0, wall_height / 2, half_d + wall_thickness / 2)
	wall_s.material = wall_mat
	wall_s.use_collision = true
	bounds.add_child(wall_s)
	
	# East wall
	var wall_e = CSGBox3D.new()
	wall_e.size = Vector3(wall_thickness, wall_height, map_depth)
	wall_e.position = Vector3(half_w + wall_thickness / 2, wall_height / 2, 0)
	wall_e.material = wall_mat
	wall_e.use_collision = true
	bounds.add_child(wall_e)
	
	# West wall
	var wall_w = CSGBox3D.new()
	wall_w.size = Vector3(wall_thickness, wall_height, map_depth)
	wall_w.position = Vector3(-half_w - wall_thickness / 2, wall_height / 2, 0)
	wall_w.material = wall_mat
	wall_w.use_collision = true
	bounds.add_child(wall_w)

func _snap_position(pos: Vector3) -> Vector3:
	if grid_snap <= 0:
		return pos
	return Vector3(
		round(pos.x / grid_snap) * grid_snap,
		max(0, pos.y),
		round(pos.z / grid_snap) * grid_snap
	)

# === Object Placement ===

func _start_placement(mouse_pos: Vector2) -> void:
	var world_pos = camera.get_ground_intersection(mouse_pos)
	world_pos = _snap_position(world_pos)
	_place_start_pos = world_pos
	
	match current_tool:
		Tool.BOX:
			_placing_preview = _create_box_preview()
		Tool.CYLINDER:
			_placing_preview = _create_cylinder_preview()
		Tool.SPHERE:
			_placing_preview = _create_sphere_preview()
		Tool.SPAWN:
			_placing_preview = _create_spawn_preview()
	
	if _placing_preview != null:
		object_container.add_child(_placing_preview)
		_placing_preview.position = world_pos
		_is_placing = true

func _update_placement(mouse_pos: Vector2) -> void:
	if _placing_preview == null:
		return
	
	var world_pos = camera.get_ground_intersection(mouse_pos)
	world_pos = _snap_position(world_pos)
	_placing_preview.position = world_pos

func _finish_placement(mouse_pos: Vector2) -> void:
	if _placing_preview == null:
		return
	
	var world_pos = camera.get_ground_intersection(mouse_pos)
	world_pos = _snap_position(world_pos)
	
	match current_tool:
		Tool.BOX:
			_create_box(world_pos)
		Tool.CYLINDER:
			_create_cylinder(world_pos)
		Tool.SPHERE:
			_create_sphere(world_pos)
		Tool.SPAWN:
			_create_spawn_point(world_pos)
	
	_cancel_placement()
	is_dirty = true
	_add_history_state("Place Object")

func _cancel_placement() -> void:
	_is_placing = false
	if _placing_preview != null:
		_placing_preview.queue_free()
		_placing_preview = null

func _create_box_preview() -> CSGBox3D:
	var box = CSGBox3D.new()
	box.size = Vector3(2, 2, 2)
	box.material = _create_preview_material()
	box.use_collision = false
	return box

func _create_cylinder_preview() -> CSGCylinder3D:
	var cyl = CSGCylinder3D.new()
	cyl.radius = 0.5
	cyl.height = 1.5
	cyl.material = _create_preview_material()
	cyl.use_collision = false
	return cyl

func _create_sphere_preview() -> CSGSphere3D:
	var sph = CSGSphere3D.new()
	sph.radius = 1.0
	sph.material = _create_preview_material()
	sph.use_collision = false
	return sph

func _create_spawn_preview() -> Marker3D:
	var marker = Marker3D.new()
	# Add a visual indicator
	var visual = MeshInstance3D.new()
	var mesh = PrismMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	visual.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0, 1, 0) if current_spawn_team == "ffa" else Color(0, 0, 1) if current_spawn_team == "team1" else Color(1, 0, 0)
	visual.material_override = mat
	
	marker.add_child(visual)
	return marker

func _create_preview_material() -> Material:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.8, 1, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func _create_box(pos: Vector3) -> CSGBox3D:
	var box = CSGBox3D.new()
	box.size = Vector3(2, 2, 2)
	box.position = pos + Vector3(0, 1, 0)  # Sit on ground
	box.use_collision = true
	box.collision_layer = 1
	box.material = _create_default_material()
	object_container.add_child(box)
	
	# Add EditorObject component for selection visuals
	var editor_obj = EditorObject.new()
	editor_obj.object_id = _generate_object_id()
	editor_obj.object_type = "box"
	editor_obj.selected.connect(_on_object_selected)
	editor_obj.deselected.connect(_on_object_deselected)
	box.add_child(editor_obj)
	
	var props = {"type": "box", "size": [2, 2, 2]}
	map_data.add_object("box", box.transform, props)
	
	return box

func _create_cylinder(pos: Vector3) -> CSGCylinder3D:
	var cyl = CSGCylinder3D.new()
	cyl.radius = 0.5
	cyl.height = 1.5
	cyl.position = pos + Vector3(0, 0.75, 0)
	cyl.use_collision = true
	cyl.collision_layer = 1
	cyl.material = _create_default_material()
	object_container.add_child(cyl)
	
	# Add EditorObject component for selection visuals
	var editor_obj = EditorObject.new()
	editor_obj.object_id = _generate_object_id()
	editor_obj.object_type = "cylinder"
	editor_obj.selected.connect(_on_object_selected)
	editor_obj.deselected.connect(_on_object_deselected)
	cyl.add_child(editor_obj)
	
	var props = {"type": "cylinder", "radius": 0.5, "height": 1.5}
	map_data.add_object("cylinder", cyl.transform, props)
	
	return cyl

func _create_sphere(pos: Vector3) -> CSGSphere3D:
	var sph = CSGSphere3D.new()
	sph.radius = 1.0
	sph.position = pos + Vector3(0, 1, 0)
	sph.use_collision = true
	sph.collision_layer = 1
	sph.material = _create_default_material()
	object_container.add_child(sph)
	
	# Add EditorObject component for selection visuals
	var editor_obj = EditorObject.new()
	editor_obj.object_id = _generate_object_id()
	editor_obj.object_type = "sphere"
	editor_obj.selected.connect(_on_object_selected)
	editor_obj.deselected.connect(_on_object_deselected)
	sph.add_child(editor_obj)
	
	var props = {"type": "sphere", "radius": 1.0}
	map_data.add_object("sphere", sph.transform, props)
	
	return sph

func _create_spawn_point(pos: Vector3) -> Marker3D:
	var marker = Marker3D.new()
	marker.position = pos + Vector3(0, 0.5, 0)
	marker.add_to_group("spawn_point")
	
	# Visual indicator
	var visual = MeshInstance3D.new()
	var mesh = PrismMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	visual.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	match current_spawn_team:
		"team1": mat.albedo_color = Color(0, 0, 1)
		"team2": mat.albedo_color = Color(1, 0, 0)
		_: mat.albedo_color = Color(0, 1, 0)
	visual.material_override = mat
	
	marker.add_child(visual)
	spawn_container.add_child(marker)
	
	map_data.add_spawn_point(current_spawn_team, marker.position)
	
	return marker

func _create_default_material() -> StandardMaterial3D:
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.5, 0.5)
	return mat

# === Selection ===

func _update_hover(mouse_pos: Vector2) -> void:
	var ray = camera.get_ray_from_mouse(mouse_pos)
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray.origin
	query.to = ray.origin + ray.normal * 1000
	
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(query)
	
	if result.size() > 0:
		var collider = result.collider
		# Get the parent CSG shape (in case we hit a child mesh)
		var obj = collider
		if obj.get_parent() is CSGShape3D:
			obj = obj.get_parent()
		
		if obj != hovered_object:
			if hovered_object != null:
				var editor_obj = hovered_object.get_node_or_null("EditorObject")
				if editor_obj != null:
					editor_obj.set_hover(false)
			hovered_object = obj
			var editor_obj = hovered_object.get_node_or_null("EditorObject")
			if editor_obj != null:
				editor_obj.set_hover(true)
	else:
		if hovered_object != null:
			var editor_obj = hovered_object.get_node_or_null("EditorObject")
			if editor_obj != null:
				editor_obj.set_hover(false)
			hovered_object = null

func _select_at_mouse(mouse_pos: Vector2) -> void:
	if not Input.is_key_pressed(KEY_CTRL):
		_clear_selection()
	
	var ray = camera.get_ray_from_mouse(mouse_pos)
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray.origin
	query.to = ray.origin + ray.normal * 1000
	
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(query)
	
	if result.size() > 0:
		var collider = result.collider
		# Get the parent CSG shape (in case we hit a child mesh)
		var obj = collider
		if obj.get_parent() is CSGShape3D:
			obj = obj.get_parent()
		
		if obj.get_parent() == object_container:
			_select_object(obj, Input.is_key_pressed(KEY_CTRL))

func _select_object(obj: Node, additive: bool = false) -> void:
	if not additive:
		_clear_selection()
	
	if obj in selected_objects:
		if additive:
			_deselect_object(obj)
			_update_gizmo_visibility()
		return
	
	selected_objects.append(obj)
	var editor_obj = obj.get_node_or_null("EditorObject")
	if editor_obj != null:
		editor_obj.set_selected(true)
	
	_update_gizmo_visibility()
	_update_ui()

func _deselect_object(obj: Node) -> void:
	selected_objects.erase(obj)
	var editor_obj = obj.get_node_or_null("EditorObject")
	if editor_obj != null:
		editor_obj.set_selected(false)
	_update_ui()

func _clear_selection() -> void:
	for obj in selected_objects:
		var editor_obj = obj.get_node_or_null("EditorObject")
		if editor_obj != null:
			editor_obj.set_selected(false)
	selected_objects.clear()
	_update_gizmo_visibility()
	_update_ui()

func _delete_selected() -> void:
	for obj in selected_objects:
		obj.queue_free()
	selected_objects.clear()
	is_dirty = true
	_update_ui()
	_add_history_state("Delete Objects")

func _frame_selection() -> void:
	if selected_objects.size() > 0:
		var center = Vector3.ZERO
		for obj in selected_objects:
			center += obj.global_position
		center /= selected_objects.size()
		camera.frame_object(center)

func _duplicate_selected() -> void:
	_copy_selected()
	_paste()

func _copy_selected() -> void:
	_clipboard.clear()
	for obj in selected_objects:
		var data = _serialize_object(obj)
		if not data.is_empty():
			_clipboard.append(data)

func _paste() -> void:
	if _clipboard.is_empty():
		return
	
	var new_selection: Array[Node] = []
	var offset = Vector3(1, 0, 1)  # Offset slightly for visibility
	
	for data in _clipboard:
		var new_obj = _deserialize_object(data)
		if new_obj != null:
			new_obj.position += offset
			object_container.add_child(new_obj)
			new_selection.append(new_obj)
			
			# Add EditorObject component
			var editor_obj = EditorObject.new()
			editor_obj.object_id = _generate_object_id()
			editor_obj.object_type = data.get("type", "box")
			editor_obj.selected.connect(_on_object_selected)
			editor_obj.deselected.connect(_on_object_deselected)
			new_obj.add_child(editor_obj)
	
	_clear_selection()
	for obj in new_selection:
		_select_object(obj, true)
	
	is_dirty = true
	_add_history_state("Paste Objects")

func _serialize_object(obj: Node) -> Dictionary:
	var data = {
		"position": [obj.position.x, obj.position.y, obj.position.z],
		"rotation": [obj.rotation.x, obj.rotation.y, obj.rotation.z],
		"scale": [obj.scale.x, obj.scale.y, obj.scale.z],
		"properties": {}
	}
	
	if obj is CSGBox3D:
		data["type"] = "box"
		data["properties"]["size"] = [obj.size.x, obj.size.y, obj.size.z]
	elif obj is CSGCylinder3D:
		data["type"] = "cylinder"
		data["properties"]["radius"] = obj.radius
		data["properties"]["height"] = obj.height
	elif obj is CSGSphere3D:
		data["type"] = "sphere"
		data["properties"]["radius"] = obj.radius
	else:
		return {}
	
	# Serialize material
	if obj.material != null and obj.material is StandardMaterial3D:
		var mat = obj.material as StandardMaterial3D
		data["properties"]["color"] = [mat.albedo_color.r, mat.albedo_color.g, mat.albedo_color.b, mat.albedo_color.a]
		data["properties"]["roughness"] = mat.roughness
		data["properties"]["metallic"] = mat.metallic
		data["properties"]["emission_enabled"] = mat.emission_enabled
		if mat.emission_enabled:
			data["properties"]["emission"] = [mat.emission.r, mat.emission.g, mat.emission.b]
			data["properties"]["emission_energy"] = mat.emission_energy
	
	return data

func _deserialize_object(data: Dictionary) -> Node:
	var type = data.get("type", "box")
	var props = data.get("properties", {})
	
	var obj: Node = null
	match type:
		"box":
			obj = CSGBox3D.new()
			if obj is CSGBox3D:
				var s = props.get("size", [2, 2, 2])
				obj.size = Vector3(s[0], s[1], s[2])
		"cylinder":
			obj = CSGCylinder3D.new()
			if obj is CSGCylinder3D:
				obj.radius = props.get("radius", 0.5)
				obj.height = props.get("height", 1.5)
		"sphere":
			obj = CSGSphere3D.new()
			if obj is CSGSphere3D:
				obj.radius = props.get("radius", 1.0)
	
	if obj == null:
		return null
	
	var pos = data.get("position", [0, 0, 0])
	var rot = data.get("rotation", [0, 0, 0])
	var scl = data.get("scale", [1, 1, 1])
	
	obj.position = Vector3(pos[0], pos[1], pos[2])
	obj.rotation = Vector3(rot[0], rot[1], rot[2])
	obj.scale = Vector3(scl[0], scl[1], scl[2])
	obj.use_collision = true
	obj.collision_layer = 1
	
	# Apply material
	if props.has("color"):
		var mat = StandardMaterial3D.new()
		var c = props["color"]
		mat.albedo_color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
		mat.roughness = props.get("roughness", 0.5)
		mat.metallic = props.get("metallic", 0.0)
		if props.get("emission_enabled", false):
			mat.emission_enabled = true
			if props.has("emission"):
				var e = props["emission"]
				mat.emission = Color(e[0], e[1], e[2])
			mat.emission_energy = props.get("emission_energy", 1.0)
		obj.material = mat
	else:
		obj.material = _create_default_material()
	
	return obj

# === Save/Load ===

func _save_map() -> void:
	if current_file_path.is_empty():
		_save_map_as_dialog()
	else:
		_perform_save(current_file_path)

func _save_map_as_dialog() -> void:
	# This will be called by UI - signal to show dialog
	if ui_controller != null:
		ui_controller.show_save_dialog()

func _load_map_dialog() -> void:
	if ui_controller != null:
		ui_controller.show_load_dialog()

func perform_save_as(path: String) -> bool:
	current_file_path = path
	return _perform_save(path)

func _perform_save(path: String) -> bool:
	# Update map data from current scene
	_sync_map_data_from_scene()
	
	if map_data.save_to_file(path):
		is_dirty = false
		_update_ui()
		return true
	return false

func perform_load(path: String) -> bool:
	var new_data = MapData.new()
	if new_data.load_from_file(path):
		map_data = new_data
		current_file_path = path
		is_dirty = false
		_rebuild_scene_from_data()
		_update_ui()
		_clear_history()
		_add_history_state("Load Map")
		return true
	return false

func _sync_map_data_from_scene() -> void:
	# Sync map settings
	map_data.map_width = map_width
	map_data.map_depth = map_depth
	map_data.map_height = map_height
	map_data.has_ceiling = has_ceiling
	map_data.auto_walls = auto_walls
	
	# Sync camera
	map_data.camera_position = camera.position
	map_data.camera_rotation = camera.rotation_degrees
	map_data.grid_snap = grid_snap

func _rebuild_scene_from_data() -> void:
	_clear_all_objects()
	
	# Apply map settings
	map_width = map_data.map_width
	map_depth = map_data.map_depth
	map_height = map_data.map_height
	has_ceiling = map_data.has_ceiling
	auto_walls = map_data.auto_walls
	
	# Restore camera
	camera.position = map_data.camera_position
	camera.rotation_degrees = map_data.camera_rotation
	grid_snap = map_data.grid_snap
	
	# Rebuild objects
	for obj_data in map_data.objects:
		_recreate_object(obj_data)
	
	# Rebuild spawn points
	for sp_data in map_data.spawn_points:
		_recreate_spawn_point(sp_data)
	
	_update_environment()

func _recreate_object(obj_data: Dictionary) -> void:
	var type = obj_data.get("type", "box")
	var pos = obj_data.get("position", [0, 0, 0])
	var rot = obj_data.get("rotation", [0, 0, 0])
	var scl = obj_data.get("scale", [1, 1, 1])
	var props = obj_data.get("properties", {})
	
	var obj: Node = null
	match type:
		"box":
			obj = CSGBox3D.new()
			if obj is CSGBox3D:
				var size_arr = props.get("size", [2, 2, 2])
				obj.size = Vector3(size_arr[0], size_arr[1], size_arr[2])
		"cylinder":
			obj = CSGCylinder3D.new()
			if obj is CSGCylinder3D:
				obj.radius = props.get("radius", 0.5)
				obj.height = props.get("height", 1.5)
		"sphere":
			obj = CSGSphere3D.new()
			if obj is CSGSphere3D:
				obj.radius = props.get("radius", 1.0)
	
	if obj != null:
		obj.position = Vector3(pos[0], pos[1], pos[2])
		obj.rotation = Vector3(rot[0], rot[1], rot[2])
		obj.scale = Vector3(scl[0], scl[1], scl[2])
		obj.use_collision = true
		obj.collision_layer = 1
		
		# Apply material
		if props.has("color"):
			var mat = StandardMaterial3D.new()
			var c = props["color"]
			mat.albedo_color = Color(c[0], c[1], c[2], c[3] if c.size() > 3 else 1.0)
			mat.roughness = props.get("roughness", 0.5)
			mat.metallic = props.get("metallic", 0.0)
			if props.get("emission_enabled", false):
				mat.emission_enabled = true
				if props.has("emission"):
					var e = props["emission"]
					mat.emission = Color(e[0], e[1], e[2])
				mat.emission_energy = props.get("emission_energy", 1.0)
			obj.material = mat
		else:
			obj.material = _create_default_material()
		
		object_container.add_child(obj)
		
		# Add EditorObject component
		var editor_obj = EditorObject.new()
		editor_obj.object_id = obj_data.get("id", _generate_object_id())
		editor_obj.object_type = type
		editor_obj.selected.connect(_on_object_selected)
		editor_obj.deselected.connect(_on_object_deselected)
		obj.add_child(editor_obj)

func _recreate_spawn_point(sp_data: Dictionary) -> void:
	var team = sp_data.get("team", "ffa")
	var pos = sp_data.get("position", [0, 0.5, 0])
	
	var marker = Marker3D.new()
	marker.position = Vector3(pos[0], pos[1], pos[2])
	marker.add_to_group("spawn_point")
	
	var visual = MeshInstance3D.new()
	var mesh = PrismMesh.new()
	mesh.size = Vector3(0.5, 0.5, 0.5)
	visual.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	match team:
		"team1": mat.albedo_color = Color(0, 0, 1)
		"team2": mat.albedo_color = Color(1, 0, 0)
		_: mat.albedo_color = Color(0, 1, 0)
	visual.material_override = mat
	
	marker.add_child(visual)
	spawn_container.add_child(marker)

# === History (Undo/Redo) ===

func _clear_history() -> void:
	history.clear()
	history_index = -1

func _add_history_state(action_name: String) -> void:
	# Remove future history if we're not at the end
	while history_index < history.size() - 1:
		history.pop_back()
	
	# Add new state
	var state = {
		"action": action_name,
		"data": map_data.to_dict()
	}
	history.append(state)
	
	# Limit history size
	if history.size() > MAX_HISTORY:
		history.pop_front()
	else:
		history_index += 1

func _undo() -> void:
	if history_index > 0:
		history_index -= 1
		var state = history[history_index]
		map_data = MapData.new()
		map_data.from_dict(state["data"])
		_rebuild_scene_from_data()
		is_dirty = true

func _redo() -> void:
	if history_index < history.size() - 1:
		history_index += 1
		var state = history[history_index]
		map_data = MapData.new()
		map_data.from_dict(state["data"])
		_rebuild_scene_from_data()
		is_dirty = true

# === UI Updates ===

func _update_ui() -> void:
	if ui_controller != null:
		ui_controller.update_from_editor(self)

func _show_exit_confirm() -> void:
	if ui_controller != null:
		if is_dirty:
			ui_controller.show_confirm_dialog("Exit without saving?", _confirm_exit)
		else:
			_confirm_exit()

func _confirm_exit() -> void:
	# Return to main menu
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

# === Public API for UI ===

func set_map_settings(width: float, depth: float, height: float, walls: bool, ceiling: bool) -> void:
	map_width = width
	map_depth = depth
	map_height = height
	auto_walls = walls
	has_ceiling = ceiling
	_update_bounds()
	_update_grid()
	is_dirty = true

func get_map_settings() -> Dictionary:
	return {
		"width": map_width,
		"depth": map_depth,
		"height": map_height,
		"auto_walls": auto_walls,
		"has_ceiling": has_ceiling,
	}

func _on_object_selected(obj: Node3D) -> void:
	# Handle object selection event
	pass

func _on_object_deselected(obj: Node3D) -> void:
	# Handle object deselection event
	pass

func _generate_object_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi())

# === Gizmo Management ===

func _update_gizmo_visibility() -> void:
	if _gizmo == null:
		return
	
	var has_selection = selected_objects.size() > 0
	_gizmo.visible = has_selection and current_tool == Tool.SELECT
	
	if has_selection:
		_gizmo.set_mode(current_transform_mode)
		_update_gizmo_position()

func _update_gizmo_position() -> void:
	if _gizmo == null or selected_objects.is_empty():
		return
	
	# Position gizmo at center of selection
	var center = Vector3.ZERO
	for obj in selected_objects:
		center += obj.global_position
	center /= selected_objects.size()
	
	_gizmo.global_position = center
	_gizmo.global_rotation = selected_objects[0].global_rotation if selected_objects.size() == 1 else Vector3.ZERO

func _on_gizmo_transform_started() -> void:
	# Store initial transforms
	_drag_start_transforms.clear()
	for obj in selected_objects:
		_drag_start_transforms.append(obj.transform)

func _on_gizmo_transform_changed(delta_transform: Transform3D) -> void:
	# Apply delta to all selected objects
	for i in range(selected_objects.size()):
		var obj = selected_objects[i]
		var start_transform = _drag_start_transforms[i]
		
		match current_transform_mode:
			TransformMode.MOVE:
				obj.position = start_transform.origin + delta_transform.origin
			TransformMode.ROTATE:
				# Apply rotation
				var new_basis = start_transform.basis * delta_transform.basis
				obj.transform.basis = new_basis
			TransformMode.SCALE:
				# Apply scale
				var new_scale = start_transform.basis.get_scale() * delta_transform.basis.get_scale()
				obj.scale = new_scale

func _on_gizmo_transform_finished() -> void:
	is_dirty = true
	_add_history_state("Transform Objects")
	_drag_start_transforms.clear()

# === Public API for UI ===

func set_object_property(obj: Node, property: String, value: Variant) -> void:
	if not obj in selected_objects:
		return
	
	match property:
		"position_x":
			obj.position.x = value
		"position_y":
			obj.position.y = value
		"position_z":
			obj.position.z = value
		"rotation_x":
			obj.rotation_degrees.x = value
		"rotation_y":
			obj.rotation_degrees.y = value
		"rotation_z":
			obj.rotation_degrees.z = value
		"scale_x":
			obj.scale.x = value
		"scale_y":
			obj.scale.y = value
		"scale_z":
			obj.scale.z = value
		"size_x", "size_y", "size_z":
			if obj is CSGBox3D:
				var axis = property.split("_")[1]
				match axis:
					"x": obj.size.x = value
					"y": obj.size.y = value
					"z": obj.size.z = value
		"radius":
			if obj is CSGCylinder3D:
				obj.radius = value
			elif obj is CSGSphere3D:
				obj.radius = value
		"height":
			if obj is CSGCylinder3D:
				obj.height = value
		"color":
			if obj.material == null or not (obj.material is StandardMaterial3D):
				obj.material = StandardMaterial3D.new()
			(obj.material as StandardMaterial3D).albedo_color = value
		"roughness":
			if obj.material == null or not (obj.material is StandardMaterial3D):
				obj.material = StandardMaterial3D.new()
			(obj.material as StandardMaterial3D).roughness = value
		"metallic":
			if obj.material == null or not (obj.material is StandardMaterial3D):
				obj.material = StandardMaterial3D.new()
			(obj.material as StandardMaterial3D).metallic = value
	
	# Update EditorObject visuals if size changed
	var editor_obj = obj.get_node_or_null("EditorObject")
	if editor_obj != null and property.begins_with("size"):
		editor_obj._update_outline_mesh()
	
	is_dirty = true
	_update_gizmo_position()

func get_object_property(obj: Node, property: String) -> Variant:
	match property:
		"position_x": return obj.position.x
		"position_y": return obj.position.y
		"position_z": return obj.position.z
		"rotation_x": return obj.rotation_degrees.x
		"rotation_y": return obj.rotation_degrees.y
		"rotation_z": return obj.rotation_degrees.z
		"scale_x": return obj.scale.x
		"scale_y": return obj.scale.y
		"scale_z": return obj.scale.z
		"size_x", "size_y", "size_z":
			if obj is CSGBox3D:
				match property.split("_")[1]:
					"x": return obj.size.x
					"y": return obj.size.y
					"z": return obj.size.z
		"radius":
			if obj is CSGCylinder3D:
				return obj.radius
			elif obj is CSGSphere3D:
				return obj.radius
		"height":
			if obj is CSGCylinder3D:
				return obj.height
		"color":
			if obj.material != null and obj.material is StandardMaterial3D:
				return (obj.material as StandardMaterial3D).albedo_color
			return Color.WHITE
		"roughness":
			if obj.material != null and obj.material is StandardMaterial3D:
				return (obj.material as StandardMaterial3D).roughness
			return 0.5
		"metallic":
			if obj.material != null and obj.material is StandardMaterial3D:
				return (obj.material as StandardMaterial3D).metallic
			return 0.0
	return null

func test_play() -> void:
	"""Launch the game with the current map for testing"""
	# First ensure map is saved
	if is_dirty:
		_save_map()
	
	# Validate before testing
	var validation = validate_map()
	if not validation.valid:
		push_error("Cannot test: " + validation.error)
		return
	
	# Set as current map in game settings
	GameSettings.honor_current_map_next_load = true
	
	# Save current map to a temp location for testing
	var temp_path = OS.get_user_data_dir() + "/temp_test_map.json"
	if map_data.save_to_file(temp_path):
		print("Test map saved to: " + temp_path)
		
		# Mark this as the map to use
		# TODO: Convert JSON to playable .tscn and set as current_map
		# For now, just launch the main game
		get_tree().change_scene_to_file("res://scenes/main.tscn")
	else:
		push_error("Failed to save test map")

func generate_thumbnail() -> Image:
	"""Generate a thumbnail image from current camera view"""
	# Get viewport texture
	var viewport = get_viewport()
	if viewport == null:
		return null
	
	# Wait for render (single frame)
	await get_tree().process_frame
	
	# Get the viewport texture
	var tex = viewport.get_texture()
	if tex == null:
		return null
	
	# Get image from texture
	var img = tex.get_image()
	if img == null:
		return null
	
	# Resize to thumbnail size (256x144 - 16:9 aspect)
	img.resize(256, 144, Image.INTERPOLATION_LANCZOS)
	
	return img

func save_thumbnail(path: String) -> bool:
	"""Save thumbnail to specified path"""
	var img = await generate_thumbnail()
	if img == null:
		return false
	
	var error = img.save_png(path)
	return error == OK

func export_map_with_thumbnail() -> Dictionary:
	"""Export map with thumbnail. Returns result dict."""
	var result = {"success": false, "map_path": "", "thumb_path": "", "error": ""}
	
	# Validate
	var validation = validate_map()
	if not validation.valid:
		result.error = validation.error
		return result
	
	# Create user maps directory
	var user_maps_dir = OS.get_user_data_dir() + "/maps"
	DirAccess.make_dir_recursive_absolute(user_maps_dir)
	
	# Generate map ID
	var map_id = map_data.name.to_snake_case().replace(" ", "_") + "_" + str(Time.get_unix_time_from_system())
	
	var map_path = user_maps_dir + "/" + map_id + ".json"
	var thumb_path = user_maps_dir + "/" + map_id + "_thumb.png"
	
	# Save map
	if not map_data.save_to_file(map_path):
		result.error = "Failed to save map"
		return result
	
	# Generate and save thumbnail
	var img = await generate_thumbnail()
	if img != null:
		img.save_png(thumb_path)
		result.thumb_path = thumb_path
	
	result.success = true
	result.map_path = map_path
	is_dirty = false
	_update_ui()
	
	print("Map exported: " + map_path)
	if not result.thumb_path.is_empty():
		print("Thumbnail: " + thumb_path)
	
	return result

func export_to_pool() -> void:
	"""Export map to user maps folder with thumbnail"""
	var result = await export_map_with_thumbnail()
	
	if not result.success:
		push_error("Export failed: " + result.error)
		return
	
	print("Map successfully exported to pool!")
	print("Map: " + result.map_path)
	if not result.thumb_path.is_empty():
		print("Thumbnail: " + result.thumb_path)
	
	# TODO: Register in GameSettings for use in-game
	# This would add the map to AVAILABLE_MAPS dynamically

func save_to_file_dialog() -> void:
	_save_map_as_dialog()

# === Spawn Point Management ===

func test_spawn_point() -> void:
	"""Teleport camera to a random spawn point to verify placement"""
	if spawn_container.get_child_count() == 0:
		push_warning("No spawn points to test")
		return
	
	# Pick a random spawn point
	var spawns = spawn_container.get_children()
	var random_spawn = spawns[randi() % spawns.size()]
	
	# Move camera to spawn position + eye height
	var spawn_pos = random_spawn.global_position
	camera.position = spawn_pos + Vector3(0, 1.6, 0)  # Eye level
	camera.rotation_degrees = Vector3(0, random_spawn.global_rotation.y, 0)
	
	print("Testing spawn at: " + str(spawn_pos))

func clear_all_spawn_points() -> void:
	"""Remove all spawn points from the map"""
	for child in spawn_container.get_children():
		child.queue_free()
	map_data.spawn_points.clear()
	is_dirty = true
	_update_ui()
	_add_history_state("Clear Spawn Points")

func get_spawn_point_counts() -> Dictionary:
	"""Returns count of spawn points per team"""
	var counts = {"ffa": 0, "team1": 0, "team2": 0, "total": 0}
	for sp in map_data.spawn_points:
		var team = sp.get("team", "ffa")
		if counts.has(team):
			counts[team] += 1
		counts["total"] += 1
	return counts

func select_all_spawn_points() -> void:
	"""Select all spawn point visual markers"""
	_clear_selection()
	for marker in spawn_container.get_children():
		# Spawn points use a different selection method
		marker.set_meta("selected", true)
		var visual = marker.get_child(0) if marker.get_child_count() > 0 else null
		if visual != null:
			visual.modulate = Color(1.5, 1.5, 0.5)  # Highlight

# === Environment Settings ===

func set_environment_theme(theme_name: String) -> void:
	map_data.environment_theme = theme_name
	_apply_environment_theme()
	is_dirty = true

func _apply_environment_theme() -> void:
	# Apply theme to the environment node if it has MapEnvironment
	if environment == null:
		return
	
	var map_env = environment.get_node_or_null("MapEnvironment")
	if map_env != null and map_env.has_method("set_theme"):
		map_env.set_theme(map_data.environment_theme)

func set_sky_color(top: Color, horizon: Color) -> void:
	map_data.sky_top = top
	map_data.sky_horizon = horizon
	_apply_sky_colors()
	is_dirty = true

func _apply_sky_colors() -> void:
	var world_env = environment.get_node_or_null("WorldEnvironment") if environment != null else null
	if world_env == null:
		return
	
	var env = world_env.environment
	if env == null or env.sky == null or env.sky.sky_material == null:
		return
	
	var sky_mat = env.sky.sky_material as ProceduralSkyMaterial
	if sky_mat != null:
		sky_mat.sky_top_color = map_data.sky_top
		sky_mat.sky_horizon_color = map_data.sky_horizon

func set_lighting(color: Color, energy: float) -> void:
	map_data.light_color = color
	map_data.light_energy = energy
	_apply_lighting()
	is_dirty = true

func _apply_lighting() -> void:
	var sun = environment.get_node_or_null("Sun") if environment != null else null
	if sun != null and sun is DirectionalLight3D:
		sun.light_color = map_data.light_color
		sun.light_energy = map_data.light_energy

func set_fog(color: Color, density: float) -> void:
	map_data.fog_color = color
	map_data.fog_density = density
	_apply_fog()
	is_dirty = true

func _apply_fog() -> void:
	var world_env = environment.get_node_or_null("WorldEnvironment") if environment != null else null
	if world_env == null:
		return
	
	var env = world_env.environment
	if env != null:
		env.fog_light_color = map_data.fog_color
		env.fog_density = map_data.fog_density

# === Map Validation ===

class ValidationResult:
	var valid: bool = true
	var error: String = ""
	var warnings: Array[String] = []
	
	func _init(v: bool = true, e: String = "") -> void:
		valid = v
		error = e

func validate_map() -> ValidationResult:
	var result = ValidationResult.new()
	
	# Check for minimum spawn points
	var spawn_counts = get_spawn_point_counts()
	
	if spawn_counts["total"] == 0:
		result.valid = false
		result.error = "Map has no spawn points. Add at least 2 FFA or 1 per team spawn points."
		return result
	
	if spawn_counts["ffa"] > 0 and spawn_counts["ffa"] < 2:
		result.warnings.append("FFA mode: Only 1 spawn point. Recommend at least 4-8 for good gameplay.")
	
	if spawn_counts["team1"] > 0 and spawn_counts["team2"] == 0:
		result.warnings.append("Team 1 spawns exist but no Team 2 spawns. Add Team 2 spawns for TDM mode.")
	
	if spawn_counts["team2"] > 0 and spawn_counts["team1"] == 0:
		result.warnings.append("Team 2 spawns exist but no Team 1 spawns. Add Team 1 spawns for TDM mode.")
	
	# Check for objects
	if object_container.get_child_count() == 0:
		result.warnings.append("Map has no obstacles/cover. Consider adding boxes, walls, or pillars for gameplay.")
	
	# Check map size
	if map_width < 10 or map_depth < 10:
		result.warnings.append("Map is very small (" + str(map_width) + "x" + str(map_depth) + "m). Consider increasing size for better gameplay.")
	
	# Check for excessive objects (performance)
	if object_container.get_child_count() > 200:
		result.warnings.append("Map has many objects (" + str(object_container.get_child_count()) + "). May impact performance on low-end devices.")
	
	return result

func auto_fix_map() -> Dictionary:
	"""Auto-fix common map issues. Returns dict of fixes applied."""
	var fixes = {"spawn_adjustments": 0, "objects_adjusted": 0, "issues_remaining": []}
	
	# Fix spawn points inside geometry
	for spawn in spawn_container.get_children():
		var spawn_pos = spawn.global_position
		var was_adjusted = false
		
		# Simple check - if spawn is below floor, raise it
		if spawn_pos.y < 0.5:
			spawn_pos.y = 0.5
			was_adjusted = true
		
		# Check if spawn is outside map bounds
		var half_w = map_width / 2
		var half_d = map_depth / 2
		if abs(spawn_pos.x) > half_w - 1 or abs(spawn_pos.z) > half_d - 1:
			spawn_pos.x = clamp(spawn_pos.x, -half_w + 1, half_w - 1)
			spawn_pos.z = clamp(spawn_pos.z, -half_d + 1, half_d - 1)
			was_adjusted = true
		
		if was_adjusted:
			spawn.global_position = spawn_pos
			fixes["spawn_adjustments"] += 1
			# Update in map_data
			for sp_data in map_data.spawn_points:
				if sp_data.get("id", "") == spawn.get_meta("id", ""):
					sp_data["position"] = [spawn_pos.x, spawn_pos.y, spawn_pos.z]
					break
	
	# Validate again to report remaining issues
	var validation = validate_map()
	fixes["issues_remaining"] = validation.warnings
	if not validation.valid:
		fixes["issues_remaining"].append("ERROR: " + validation.error)
	
	if fixes["spawn_adjustments"] > 0 or fixes["objects_adjusted"] > 0:
		is_dirty = true
		_add_history_state("Auto-fix Map")
	
	return fixes

# === Public API for UI ===

func get_environment_settings() -> Dictionary:
	return {
		"theme": map_data.environment_theme,
		"sky_top": map_data.sky_top,
		"sky_horizon": map_data.sky_horizon,
		"ground_color": map_data.ground_color,
		"light_color": map_data.light_color,
		"light_energy": map_data.light_energy,
		"fog_color": map_data.fog_color,
		"fog_density": map_data.fog_density,
	}

func load_from_file_dialog() -> void:
	_load_map_dialog()

func show_help() -> void:
	"""Show keyboard shortcut help"""
	var help_text = """
=== MAP EDITOR CONTROLS ===

MOVEMENT:
WASD - Fly camera
Q/E - Move up/down
Shift - Speed boost
Right-click drag - Orbit
Middle-click drag - Pan
Mouse wheel - Zoom

TOOLS:
1/S - Select tool
2/Q - Box tool
3/W - Cylinder tool
4/E - Sphere tool
5/R - Spawn tool

TRANSFORM (with object selected):
W (or Ctrl+W) - Move mode
E (or Ctrl+E) - Rotate mode
R (or Ctrl+R) - Scale mode
Click gizmo axes to transform

SELECTION:
Click - Select object
Ctrl+Click - Multi-select
Delete - Remove selected
Ctrl+D - Duplicate
Ctrl+C/V - Copy/Paste
F - Frame selected

FILE:
Ctrl+N - New map
Ctrl+O - Open map
Ctrl+S - Save map
Ctrl+Z/Y - Undo/Redo

PLAY & HELP:
F5 - Test Play (launch game)
F1 - Show this help

GRID:
G - Toggle grid snap

OTHER:
Esc - Deselect / Cancel

EDITOR PANELS:
Left: Tools, Spawn Team, Grid, Spawn Management
Right: Properties, Environment, Validation
"""
	print(help_text)

func get_editor_info() -> Dictionary:
	"""Get editor statistics and info"""
	return {
		"version": "1.0",
		"map_name": map_data.name if map_data != null else "Untitled",
		"objects_count": object_container.get_child_count(),
		"spawn_points_count": spawn_container.get_child_count(),
		"is_dirty": is_dirty,
		"has_file_path": not current_file_path.is_empty(),
		"grid_snap": grid_snap,
		"map_size": Vector3(map_width, map_height, map_depth),
	}
