class_name MapData
extends RefCounted

# Map data structure for JSON serialization/deserialization
# Handles conversion between editor format and runtime format

const CURRENT_VERSION = "1.0"

var name: String = "Untitled Map"
var description: String = ""
var author: String = ""
var created_at: String = ""
var modified_at: String = ""
var version: String = CURRENT_VERSION

# Map dimensions (meters)
var map_width: float = 40.0
var map_depth: float = 30.0
var map_height: float = 20.0
var has_ceiling: bool = false
var auto_walls: bool = true

# Environment settings
var environment_theme: String = ""
var sky_top: Color = Color(0.20, 0.30, 0.50)
var sky_horizon: Color = Color(0.55, 0.50, 0.40)
var ground_color: Color = Color(0.40, 0.35, 0.30)
var light_color: Color = Color(1.00, 0.95, 0.85)
var light_energy: float = 1.4
var fog_color: Color = Color(0.55, 0.50, 0.40)
var fog_density: float = 0.005

# Objects array
var objects: Array[Dictionary] = []
# Spawn points array
var spawn_points: Array[Dictionary] = []

# Metadata for editor
var camera_position: Vector3 = Vector3(0, 10, 20)
var camera_rotation: Vector3 = Vector3(-30, 0, 0)
var grid_snap: float = 1.0

func to_dict() -> Dictionary:
	var now = Time.get_datetime_string_from_system()
	if modified_at.is_empty():
		modified_at = now
	
	return {
		"version": version,
		"metadata": {
			"name": name,
			"description": description,
			"author": author,
			"created_at": created_at if not created_at.is_empty() else now,
			"modified_at": modified_at,
		},
		"settings": {
			"map_width": map_width,
			"map_depth": map_depth,
			"map_height": map_height,
			"has_ceiling": has_ceiling,
			"auto_walls": auto_walls,
		},
		"environment": {
			"theme": environment_theme,
			"sky_top": _color_to_array(sky_top),
			"sky_horizon": _color_to_array(sky_horizon),
			"ground_color": _color_to_array(ground_color),
			"light_color": _color_to_array(light_color),
			"light_energy": light_energy,
			"fog_color": _color_to_array(fog_color),
			"fog_density": fog_density,
		},
		"objects": objects,
		"spawn_points": spawn_points,
		"editor_state": {
			"camera_position": _vec3_to_array(camera_position),
			"camera_rotation": _vec3_to_array(camera_rotation),
			"grid_snap": grid_snap,
		}
	}

func from_dict(data: Dictionary) -> bool:
	if not data.has("version"):
		push_error("Invalid map data: missing version")
		return false
	
	version = data.get("version", CURRENT_VERSION)
	
	var metadata = data.get("metadata", {})
	name = metadata.get("name", "Untitled Map")
	description = metadata.get("description", "")
	author = metadata.get("author", "")
	created_at = metadata.get("created_at", "")
	modified_at = metadata.get("modified_at", "")
	
	var settings = data.get("settings", {})
	map_width = settings.get("map_width", 40.0)
	map_depth = settings.get("map_depth", 30.0)
	map_height = settings.get("map_height", 20.0)
	has_ceiling = settings.get("has_ceiling", false)
	auto_walls = settings.get("auto_walls", true)
	
	var env = data.get("environment", {})
	environment_theme = env.get("theme", "")
	sky_top = _array_to_color(env.get("sky_top", [0.20, 0.30, 0.50]))
	sky_horizon = _array_to_color(env.get("sky_horizon", [0.55, 0.50, 0.40]))
	ground_color = _array_to_color(env.get("ground_color", [0.40, 0.35, 0.30]))
	light_color = _array_to_color(env.get("light_color", [1.00, 0.95, 0.85]))
	light_energy = env.get("light_energy", 1.4)
	fog_color = _array_to_color(env.get("fog_color", [0.55, 0.50, 0.40]))
	fog_density = env.get("fog_density", 0.005)
	
	objects = data.get("objects", [])
	spawn_points = data.get("spawn_points", [])
	
	var editor = data.get("editor_state", {})
	camera_position = _array_to_vec3(editor.get("camera_position", [0, 10, 20]))
	camera_rotation = _array_to_vec3(editor.get("camera_rotation", [-30, 0, 0]))
	grid_snap = editor.get("grid_snap", 1.0)
	
	return true

func save_to_file(path: String) -> bool:
	var json_string = JSON.stringify(to_dict(), "\t")
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Failed to open file for writing: " + path)
		return false
	file.store_string(json_string)
	file.close()
	return true

func load_from_file(path: String) -> bool:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Failed to open file for reading: " + path)
		return false
	var json_string = file.get_as_text()
	file.close()
	
	var json = JSON.new()
	var error = json.parse(json_string)
	if error != OK:
		push_error("JSON parse error: " + json.get_error_message())
		return false
	
	return from_dict(json.data)

func add_object(type: String, transform: Transform3D, properties: Dictionary) -> Dictionary:
	var obj = {
		"id": _generate_id(),
		"type": type,
		"position": _vec3_to_array(transform.origin),
		"rotation": _vec3_to_array(transform.basis.get_euler()),
		"scale": _vec3_to_array(transform.basis.get_scale()),
		"properties": properties.duplicate()
	}
	objects.append(obj)
	return obj

func update_object(id: String, transform: Transform3D, properties: Dictionary) -> bool:
	for obj in objects:
		if obj.get("id") == id:
			obj["position"] = _vec3_to_array(transform.origin)
			obj["rotation"] = _vec3_to_array(transform.basis.get_euler())
			obj["scale"] = _vec3_to_array(transform.basis.get_scale())
			obj["properties"] = properties.duplicate()
			return true
	return false

func remove_object(id: String) -> bool:
	for i in range(objects.size()):
		if objects[i].get("id") == id:
			objects.remove_at(i)
			return true
	return false

func add_spawn_point(team: String, position: Vector3, rotation: float = 0.0) -> Dictionary:
	var sp = {
		"id": _generate_id(),
		"team": team,  # "team1", "team2", "ffa"
		"position": _vec3_to_array(position),
		"rotation": rotation,
	}
	spawn_points.append(sp)
	return sp

func remove_spawn_point(id: String) -> bool:
	for i in range(spawn_points.size()):
		if spawn_points[i].get("id") == id:
			spawn_points.remove_at(i)
			return true
	return false

# Helper functions
func _generate_id() -> String:
	return str(Time.get_unix_time_from_system()) + "_" + str(randi())

func _vec3_to_array(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

func _array_to_vec3(arr: Array) -> Vector3:
	if arr.size() < 3:
		return Vector3.ZERO
	return Vector3(arr[0], arr[1], arr[2])

func _color_to_array(c: Color) -> Array:
	return [c.r, c.g, c.b, c.a]

func _array_to_color(arr: Array) -> Color:
	if arr.size() < 3:
		return Color.WHITE
	if arr.size() == 4:
		return Color(arr[0], arr[1], arr[2], arr[3])
	return Color(arr[0], arr[1], arr[2])

func get_spawn_point_count(team: String = "") -> int:
	if team.is_empty():
		return spawn_points.size()
	var count = 0
	for sp in spawn_points:
		if sp.get("team") == team:
			count += 1
	return count
