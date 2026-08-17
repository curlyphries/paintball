class_name EditorGizmo
extends Node3D

# 3D transform gizmo for move/rotate/scale operations
# Shows X (red), Y (green), Z (blue) axes with draggable handles

enum TransformMode { MOVE, ROTATE, SCALE }
enum Axis { X, Y, Z, ALL, NONE }

signal transform_started
signal transform_changed(delta_transform: Transform3D)
signal transform_finished

var mode: TransformMode = TransformMode.MOVE
var axis: Axis = Axis.NONE

var _is_dragging: bool = false
var _drag_start_pos: Vector3 = Vector3.ZERO
var _drag_current_pos: Vector3 = Vector3.ZERO
var _drag_plane: Plane = Plane()
var _start_transform: Transform3D = Transform3D.IDENTITY

# Gizmo visuals
var _x_axis: MeshInstance3D = null
var _y_axis: MeshInstance3D = null
var _z_axis: MeshInstance3D = null
var _x_handle: MeshInstance3D = null
var _y_handle: MeshInstance3D = null
var _z_handle: MeshInstance3D = null
var _center_handle: MeshInstance3D = null

# Materials
var _mat_x: StandardMaterial3D = null
var _mat_y: StandardMaterial3D = null
var _mat_z: StandardMaterial3D = null
var _mat_highlight: StandardMaterial3D = null

const AXIS_LENGTH = 2.0
const AXIS_THICKNESS = 0.03
const HANDLE_SIZE = 0.25

func _ready() -> void:
	_create_materials()
	_create_gizmo()
	visible = false

func _create_materials() -> void:
	_mat_x = StandardMaterial3D.new()
	_mat_x.albedo_color = Color(1, 0.2, 0.2)
	_mat_x.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_mat_y = StandardMaterial3D.new()
	_mat_y.albedo_color = Color(0.2, 1, 0.2)
	_mat_y.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_mat_z = StandardMaterial3D.new()
	_mat_z.albedo_color = Color(0.2, 0.4, 1)
	_mat_z.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	
	_mat_highlight = StandardMaterial3D.new()
	_mat_highlight.albedo_color = Color(1, 1, 0)
	_mat_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

func _create_gizmo() -> void:
	# Create axis lines
	_x_axis = _create_axis_mesh(Vector3.RIGHT, _mat_x)
	_y_axis = _create_axis_mesh(Vector3.UP, _mat_y)
	_z_axis = _create_axis_mesh(Vector3.BACK, _mat_z)
	
	add_child(_x_axis)
	add_child(_y_axis)
	add_child(_z_axis)
	
	# Create handles
	_x_handle = _create_handle_mesh(Vector3(AXIS_LENGTH, 0, 0), _mat_x)
	_y_handle = _create_handle_mesh(Vector3(0, AXIS_LENGTH, 0), _mat_y)
	_z_handle = _create_handle_mesh(Vector3(0, 0, -AXIS_LENGTH), _mat_z)
	_center_handle = _create_center_handle()
	
	add_child(_x_handle)
	add_child(_y_handle)
	add_child(_z_handle)
	add_child(_center_handle)
	
	# Set up input ray picking
	_x_handle.input_ray_pickable = true
	_y_handle.input_ray_pickable = true
	_z_handle.input_ray_pickable = true
	_center_handle.input_ray_pickable = true

func _create_axis_mesh(direction: Vector3, material: Material) -> MeshInstance3D:
	var mesh = CylinderMesh.new()
	mesh.top_radius = AXIS_THICKNESS
	mesh.bottom_radius = AXIS_THICKNESS
	mesh.height = AXIS_LENGTH
	
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	# Position and orient the cylinder
	instance.position = direction * AXIS_LENGTH / 2
	if direction == Vector3.RIGHT:
		instance.rotation_degrees = Vector3(0, 0, -90)
	elif direction == Vector3.BACK:
		instance.rotation_degrees = Vector3(90, 0, 0)
	
	return instance

func _create_handle_mesh(pos: Vector3, material: Material) -> MeshInstance3D:
	var mesh = BoxMesh.new()
	mesh.size = Vector3(HANDLE_SIZE, HANDLE_SIZE, HANDLE_SIZE)
	
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.position = pos
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	return instance

func _create_center_handle() -> MeshInstance3D:
	var mesh = SphereMesh.new()
	mesh.radius = HANDLE_SIZE * 0.6
	radial_segments = 8
	
	var instance = MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _mat_highlight
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	
	return instance

func set_mode(new_mode: TransformMode) -> void:
	mode = new_mode
	_update_gizmo_appearance()

func _update_gizmo_appearance() -> void:
	match mode:
		TransformMode.MOVE:
			_x_axis.visible = true
			_y_axis.visible = true
			_z_axis.visible = true
			_x_handle.visible = true
			_y_handle.visible = true
			_z_handle.visible = true
			_center_handle.visible = true
		TransformMode.ROTATE:
			# For rotation, show rings instead of lines
			_x_axis.visible = true
			_y_axis.visible = true
			_z_axis.visible = true
			_x_handle.visible = false
			_y_handle.visible = false
			_z_handle.visible = false
			_center_handle.visible = true
		TransformMode.SCALE:
			_x_axis.visible = true
			_y_axis.visible = true
			_z_axis.visible = true
			_x_handle.visible = true
			_y_handle.visible = true
			_z_handle.visible = true
			_center_handle.visible = true

func start_drag(camera: Camera3D, mouse_pos: Vector2, clicked_axis: Axis) -> void:
	axis = clicked_axis
	_is_dragging = true
	_start_transform = get_parent().global_transform
	
	# Calculate drag plane based on axis and camera direction
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	var object_pos = global_position
	
	match axis:
		Axis.X:
			_drag_plane = Plane(Vector3.UP, object_pos)
		Axis.Y:
			_drag_plane = Plane(Vector3.RIGHT, object_pos)
		Axis.Z:
			_drag_plane = Plane(Vector3.UP, object_pos)
		Axis.ALL:
			# Use plane facing camera
			_drag_plane = Plane(-camera.global_transform.basis.z, object_pos)
		_:
			_drag_plane = Plane(Vector3.UP, object_pos)
	
	_drag_start_pos = _get_plane_intersection(ray_origin, ray_normal)
	_drag_current_pos = _drag_start_pos
	
	emit_signal("transform_started")

func update_drag(camera: Camera3D, mouse_pos: Vector2) -> void:
	if not _is_dragging:
		return
	
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	_drag_current_pos = _get_plane_intersection(ray_origin, ray_normal)
	
	var delta = _calculate_delta()
	emit_signal("transform_changed", delta)

func end_drag() -> void:
	if not _is_dragging:
		return
	
	_is_dragging = false
	axis = Axis.NONE
	emit_signal("transform_finished")

func _get_plane_intersection(ray_origin: Vector3, ray_normal: Vector3) -> Vector3:
	var intersection = Vector3.ZERO
	var t = _drag_plane.distance_to(ray_origin) / _drag_plane.normal.dot(ray_normal)
	intersection = ray_origin - ray_normal * t
	return intersection

func _calculate_delta() -> Transform3D:
	var delta_pos = _drag_current_pos - _drag_start_pos
	
	# Constrain to axis if needed
	match axis:
		Axis.X:
			delta_pos.y = 0
			delta_pos.z = 0
		Axis.Y:
			delta_pos.x = 0
			delta_pos.z = 0
		Axis.Z:
			delta_pos.x = 0
			delta_pos.y = 0
		_:
			pass  # Free movement
	
	var delta = Transform3D.IDENTITY
	
	match mode:
		TransformMode.MOVE:
			delta.origin = delta_pos
		TransformMode.ROTATE:
			# Calculate rotation based on drag
			var rotation = Vector3.ZERO
			match axis:
				Axis.X:
					rotation.x = delta_pos.y * 0.01
				Axis.Y:
					rotation.y = delta_pos.x * 0.01
				Axis.Z:
					rotation.z = delta_pos.x * 0.01
			delta.basis = Basis.from_euler(rotation)
		TransformMode.SCALE:
			var scale = Vector3.ONE
			match axis:
				Axis.X:
					scale.x = 1.0 + delta_pos.x * 0.01
				Axis.Y:
					scale.y = 1.0 + delta_pos.y * 0.01
				Axis.Z:
					scale.z = 1.0 + delta_pos.z * 0.01
				Axis.ALL:
					var uniform_scale = 1.0 + delta_pos.length() * 0.01
					scale = Vector3(uniform_scale, uniform_scale, uniform_scale)
			delta.basis = Basis.from_scale(scale)
	
	return delta

func get_axis_at_mouse(camera: Camera3D, mouse_pos: Vector2) -> Axis:
	var ray_origin = camera.project_ray_origin(mouse_pos)
	var ray_normal = camera.project_ray_normal(mouse_pos)
	
	# Check each handle
	if _check_intersection(_x_handle, ray_origin, ray_normal):
		return Axis.X
	if _check_intersection(_y_handle, ray_origin, ray_normal):
		return Axis.Y
	if _check_intersection(_z_handle, ray_origin, ray_normal):
		return Axis.Z
	if _check_intersection(_center_handle, ray_origin, ray_normal):
		return Axis.ALL
	
	return Axis.NONE

func _check_intersection(node: Node3D, ray_origin: Vector3, ray_normal: Vector3) -> bool:
	if node == null or not node.visible:
		return false
	
	var query = PhysicsRayQueryParameters3D.new()
	query.from = ray_origin
	query.to = ray_origin + ray_normal * 1000
	
	var space_state = get_world_3d().direct_space_state
	var result = space_state.intersect_ray(query)
	
	if result.size() > 0:
		return result.collider == node
	
	return false

func set_highlight(highlighted_axis: Axis) -> void:
	# Reset all to normal colors
	_x_handle.material_override = _mat_x if highlighted_axis != Axis.X else _mat_highlight
	_y_handle.material_override = _mat_y if highlighted_axis != Axis.Y else _mat_highlight
	_z_handle.material_override = _mat_z if highlighted_axis != Axis.Z else _mat_highlight
	_center_handle.material_override = _mat_highlight if highlighted_axis == Axis.ALL else _mat_highlight
