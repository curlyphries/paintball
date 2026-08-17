class_name EditorCamera
extends Camera3D

# Camera controller for map editor
# Supports fly mode (WASD) and orbit mode (around selection)

@export var move_speed: float = 10.0
@export var fast_speed: float = 30.0
@export var slow_speed: float = 2.0
@export var mouse_sensitivity: float = 0.2
@export var orbit_sensitivity: float = 0.4
@export var zoom_sensitivity: float = 0.1

enum CameraMode { FLY, ORBIT }
var mode: CameraMode = CameraMode.FLY

var _orbiting: bool = false
var _panning: bool = false
var _orbit_target: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = -30.0

@onready var _editor = get_parent()

func _ready() -> void:
	# Initialize rotation from current transform
	var euler = rotation_degrees
	_yaw = euler.y
	_pitch = euler.x
	_update_transform()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting = event.pressed
			if _orbiting:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			event.handled = true
		elif event.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = event.pressed
			if _panning:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			event.handled = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if mode == CameraMode.ORBIT:
				position = position.lerp(_orbit_target, zoom_sensitivity)
			event.handled = true
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if mode == CameraMode.ORBIT:
				position = position.lerp(_orbit_target, -zoom_sensitivity * 0.5)
			event.handled = true
	
	if event is InputEventMouseMotion:
		if _orbiting:
			_yaw -= event.relative.x * mouse_sensitivity
			_pitch -= event.relative.y * mouse_sensitivity
			_pitch = clamp(_pitch, -89, 89)
			_update_transform()
			event.handled = true
		elif _panning:
			var right = transform.basis.x
			var up = transform.basis.y
			var pan = (right * -event.relative.x + up * event.relative.y) * 0.01
			position += pan
			_orbit_target += pan
			event.handled = true

func _process(delta: float) -> void:
	if mode == CameraMode.FLY and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_handle_fly_movement(delta)

func _handle_fly_movement(delta: float) -> void:
	var speed = move_speed
	if Input.is_key_pressed(KEY_SHIFT):
		speed = fast_speed
	elif Input.is_key_pressed(KEY_ALT):
		speed = slow_speed
	
	var forward = -transform.basis.z
	var right = transform.basis.x
	var up = transform.basis.y
	
	var move_dir = Vector3.ZERO
	
	if Input.is_key_pressed(KEY_W):
		move_dir += forward
	if Input.is_key_pressed(KEY_S):
		move_dir -= forward
	if Input.is_key_pressed(KEY_A):
		move_dir -= right
	if Input.is_key_pressed(KEY_D):
		move_dir += right
	if Input.is_key_pressed(KEY_E):
		move_dir += up
	if Input.is_key_pressed(KEY_Q):
		move_dir -= up
	
	if move_dir.length_squared() > 0:
		position += move_dir.normalized() * speed * delta

func _update_transform() -> void:
	rotation_degrees = Vector3(_pitch, _yaw, 0)

func set_orbit_target(target: Vector3) -> void:
	_orbit_target = target
	mode = CameraMode.ORBIT
	look_at(_orbit_target)
	var euler = rotation_degrees
	_yaw = euler.y
	_pitch = euler.x

func frame_object(obj_position: Vector3, distance: float = 10.0) -> void:
	var direction = (position - obj_position).normalized()
	position = obj_position + direction * distance
	look_at(obj_position)
	_orbit_target = obj_position
	mode = CameraMode.ORBIT
	var euler = rotation_degrees
	_yaw = euler.y
	_pitch = euler.x

func get_ray_from_mouse(mouse_pos: Vector2) -> Dictionary:
	var ray_origin = project_ray_origin(mouse_pos)
	var ray_normal = project_ray_normal(mouse_pos)
	return {"origin": ray_origin, "normal": ray_normal}

func get_ground_intersection(mouse_pos: Vector2, ground_y: float = 0.0) -> Vector3:
	var ray = get_ray_from_mouse(mouse_pos)
	var t = (ground_y - ray.origin.y) / ray.normal.y
	if t < 0:
		return Vector3.ZERO
	return ray.origin + ray.normal * t
