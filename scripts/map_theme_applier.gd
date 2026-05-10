@tool
class_name MapThemeApplier
extends Node3D

# Optional helper. Attach to a map root, set theme in editor, hit Apply.
# Walks descendants and sets material_override.albedo_color (or emission)
# based on which conventional group each node belongs to.
#
# Maps don't have to use this — they can hardcode colors. But it makes
# theme tweaks one-export-property-change in editor.

@export var theme: MapTheme:
	set(value):
		theme = value
		if Engine.is_editor_hint() and is_inside_tree():
			apply()

@export var apply_now: bool = false:
	set(value):
		if value:
			apply()

const GROUP_FLOOR := "floor"
const GROUP_WALL := "wall"
const GROUP_WALL_ACCENT := "wall_accent"
const GROUP_COVER := "cover"
const GROUP_LANDMARK := "landmark"
const GROUP_ACCENT := "accent"
const GROUP_EMISSION := "emission"

func apply() -> void:
	if theme == null:
		return
	_apply_to(get_parent() if get_parent() else self)

func _apply_to(root: Node) -> void:
	for node in _walk(root):
		if not node is GeometryInstance3D and not _is_csg(node):
			continue
		if node.is_in_group(GROUP_EMISSION):
			_set_emission(node, theme.emission_color, theme.emission_energy)
		elif node.is_in_group(GROUP_ACCENT):
			_set_albedo(node, theme.accent_color)
		elif node.is_in_group(GROUP_LANDMARK):
			_set_albedo(node, theme.landmark_color)
		elif node.is_in_group(GROUP_COVER):
			_set_albedo(node, theme.cover_color)
		elif node.is_in_group(GROUP_WALL_ACCENT):
			_set_albedo(node, theme.wall_accent)
		elif node.is_in_group(GROUP_WALL):
			_set_albedo(node, theme.wall_primary)
		elif node.is_in_group(GROUP_FLOOR):
			_set_albedo(node, theme.floor_color)

func _walk(node: Node) -> Array:
	var out: Array = [node]
	for child in node.get_children():
		out.append_array(_walk(child))
	return out

func _is_csg(node: Node) -> bool:
	return node is CSGShape3D

func _set_albedo(node: Node, color: Color) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	if node is CSGShape3D:
		node.material = mat
	elif node is GeometryInstance3D:
		node.material_override = mat

func _set_emission(node: Node, color: Color, energy: float) -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	if node is CSGShape3D:
		node.material = mat
	elif node is GeometryInstance3D:
		node.material_override = mat
