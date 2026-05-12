class_name EditorUI
extends Control

# UI controller for map editor
# Handles all UI panels, dialogs, and editor communication

@export var editor: MapEditor = null

# UI Nodes (will be set in scene or created dynamically)
var toolbar: HBoxContainer = null
var left_panel: VBoxContainer = null
var right_panel: VBoxContainer = null
var status_bar: HBoxContainer = null

var tool_buttons: Dictionary = {}
var property_panel: VBoxContainer = null

var file_dialog: FileDialog = null
var confirm_dialog: ConfirmationDialog = null

# Currently selected object for property editing
var _current_property_obj: Node = null

# Theme colors
const BG_COLOR = Color(0.12, 0.12, 0.14)
const PANEL_COLOR = Color(0.18, 0.18, 0.2)
const ACCENT_COLOR = Color(0.3, 0.6, 1.0)
const TEXT_COLOR = Color(0.9, 0.9, 0.9)
const WARNING_COLOR = Color(1.0, 0.8, 0.2)

func _ready() -> void:
	_setup_ui()
	_setup_file_dialog()
	_setup_confirm_dialog()

func _setup_ui() -> void:
	# Set this Control to fill the viewport
	anchors_preset = PRESET_FULL_RECT
	
	# Main background - semi-transparent dark
	var bg = ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.06, 0.8)
	bg.layout_mode = 1
	bg.anchors_preset = PRESET_FULL_RECT
	add_child(bg)
	
	# Toolbar
	toolbar = HBoxContainer.new()
	toolbar.layout_mode = 1
	toolbar.anchors_preset = PRESET_TOP_WIDE
	toolbar.offset_bottom = 40
	toolbar.theme_override_constants/separation = 8
	add_child(toolbar)
	
	var toolbar_bg = ColorRect.new()
	toolbar_bg.color = PANEL_COLOR
	toolbar_bg.layout_mode = 1
	toolbar_bg.anchors_preset = PRESET_FULL_RECT
	toolbar.add_child(toolbar_bg)
	toolbar.move_child(toolbar_bg, 0)
	
	_add_toolbar_buttons()
	
	# Left panel - Tool palette
	left_panel = VBoxContainer.new()
	left_panel.layout_mode = 1
	left_panel.anchors_preset = PRESET_LEFT_WIDE
	left_panel.offset_top = 45
	left_panel.offset_right = 180
	left_panel.offset_bottom = -35
	left_panel.theme_override_constants/separation = 8
	add_child(left_panel)
	
	var left_bg = ColorRect.new()
	left_bg.color = PANEL_COLOR
	left_bg.layout_mode = 1
	left_bg.anchors_preset = PRESET_FULL_RECT
	left_panel.add_child(left_bg)
	left_panel.move_child(left_bg, 0)
	
	_add_tool_palette()
	
	# Right panel - Properties
	right_panel = VBoxContainer.new()
	right_panel.layout_mode = 1
	right_panel.anchors_preset = PRESET_RIGHT_WIDE
	right_panel.offset_left = -250
	right_panel.offset_top = 45
	right_panel.offset_bottom = -35
	right_panel.theme_override_constants/separation = 8
	add_child(right_panel)
	
	var right_bg = ColorRect.new()
	right_bg.color = PANEL_COLOR
	right_bg.layout_mode = 1
	right_bg.anchors_preset = PRESET_FULL_RECT
	right_panel.add_child(right_bg)
	right_panel.move_child(right_bg, 0)
	
	_add_property_panel()
	
	# Status bar
	status_bar = HBoxContainer.new()
	status_bar.layout_mode = 1
	status_bar.anchors_preset = PRESET_BOTTOM_WIDE
	status_bar.offset_top = -30
	add_child(status_bar)
	
	var status_bg = ColorRect.new()
	status_bg.color = PANEL_COLOR.darkened(0.1)
	status_bg.layout_mode = 1
	status_bg.anchors_preset = PRESET_FULL_RECT
	status_bar.add_child(status_bg)
	status_bar.move_child(status_bg, 0)
	
	_add_status_bar()

func _add_toolbar_buttons() -> void:
	var buttons_data = [
		{"text": "New (Ctrl+N)", "callback": _on_new_pressed},
		{"text": "Open (Ctrl+O)", "callback": _on_open_pressed},
		{"text": "Save (Ctrl+S)", "callback": _on_save_pressed},
		{"text": "Save As...", "callback": _on_save_as_pressed},
		null,  # Separator
		{"text": "Undo (Ctrl+Z)", "callback": _on_undo_pressed},
		{"text": "Redo (Ctrl+Y)", "callback": _on_redo_pressed},
		null,  # Separator
		{"text": "Test Play (F5)", "callback": _on_test_pressed},
		{"text": "Export", "callback": _on_export_pressed},
		null,  # Separator
		{"text": "Help (F1)", "callback": _on_help_pressed},
		{"text": "Exit", "callback": _on_exit_pressed},
	]
	
	for data in buttons_data:
		if data == null:
			var sep = VSeparator.new()
			toolbar.add_child(sep)
		else:
			var btn = Button.new()
			btn.text = data.text
			btn.pressed.connect(data.callback)
			btn.flat = true
			toolbar.add_child(btn)

func _add_tool_palette() -> void:
	var title = Label.new()
	title.text = "Tools"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TEXT_COLOR)
	left_panel.add_child(title)
	
	var tools_data = [
		{"name": "select", "text": "Select (1/S)", "icon": null},
		{"name": "box", "text": "Box (2/Q)", "icon": null},
		{"name": "cylinder", "text": "Cylinder (3/W)", "icon": null},
		{"name": "sphere", "text": "Sphere (4/E)", "icon": null},
		{"name": "spawn", "text": "Spawn (5/R)", "icon": null},
	]
	
	for data in tools_data:
		var btn = Button.new()
		btn.text = data.text
		btn.toggle_mode = true
		btn.custom_minimum_size = Vector2(160, 32)
		btn.pressed.connect(_on_tool_selected.bind(data.name))
		tool_buttons[data.name] = btn
		left_panel.add_child(btn)
	
	# Separator
	left_panel.add_child(HSeparator.new())
	
	# Spawn team selection
	var team_title = Label.new()
	team_title.text = "Spawn Team"
	team_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	team_title.add_theme_color_override("font_color", TEXT_COLOR)
	left_panel.add_child(team_title)
	
	var team_select = OptionButton.new()
	team_select.add_item("FFA")
	team_select.add_item("Team 1 (Blue)")
	team_select.add_item("Team 2 (Red)")
	team_select.item_selected.connect(_on_team_changed)
	left_panel.add_child(team_select)
	
	# Separator
	left_panel.add_child(HSeparator.new())
	
	# Grid snap
	var snap_title = Label.new()
	snap_title.text = "Grid Snap"
	snap_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	snap_title.add_theme_color_override("font_color", TEXT_COLOR)
	left_panel.add_child(snap_title)
	
	var snap_select = OptionButton.new()
	snap_select.add_item("Off")
	snap_select.add_item("0.5m")
	snap_select.add_item("1.0m")
	snap_select.add_item("2.0m")
	snap_select.selected = 2  # Default 1.0m
	snap_select.item_selected.connect(_on_snap_changed)
	left_panel.add_child(snap_select)
	
	# Separator
	left_panel.add_child(HSeparator.new())
	
	# Spawn Management
	var spawn_mgmt_title = Label.new()
	spawn_mgmt_title.text = "Spawn Management"
	spawn_mgmt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawn_mgmt_title.add_theme_color_override("font_color", TEXT_COLOR)
	left_panel.add_child(spawn_mgmt_title)
	
	var test_spawn_btn = Button.new()
	test_spawn_btn.text = "🎲 Test Spawn"
	test_spawn_btn.pressed.connect(_on_test_spawn_pressed)
	test_spawn_btn.flat = true
	left_panel.add_child(test_spawn_btn)
	
	var clear_spawns_btn = Button.new()
	clear_spawns_btn.text = "🗑️ Clear All"
	clear_spawns_btn.pressed.connect(_on_clear_spawns_pressed)
	clear_spawns_btn.flat = true
	left_panel.add_child(clear_spawns_btn)
	
	# Spawn count display
	var spawn_count_label = Label.new()
	spawn_count_label.name = "SpawnCountLabel"
	spawn_count_label.text = "Spawns: 0"
	spawn_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spawn_count_label.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.3))
	left_panel.add_child(spawn_count_label)

func _add_property_panel() -> void:
	var title = Label.new()
	title.text = "Properties"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", TEXT_COLOR)
	right_panel.add_child(title)
	
	property_panel = VBoxContainer.new()
	property_panel.theme_override_constants/separation = 8
	right_panel.add_child(property_panel)
	
	# Add environment panel
	_add_environment_panel()
	
	# Default message
	_update_property_panel_empty()

func _update_property_panel_empty() -> void:
	for child in property_panel.get_children():
		child.queue_free()
	
	var msg = Label.new()
	msg.text = "No object selected\nSelect an object to edit properties"
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.3))
	property_panel.add_child(msg)

func _update_property_panel_for_object(obj: Node) -> void:
	for child in property_panel.get_children():
		child.queue_free()
	
	if obj == null:
		_current_property_obj = null
		_update_property_panel_empty()
		return
	
	_current_property_obj = obj
	
	# Transform section
	var transform_title = Label.new()
	transform_title.text = "Transform"
	transform_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	transform_title.add_theme_color_override("font_color", ACCENT_COLOR)
	property_panel.add_child(transform_title)
	
	_add_vector3_input("Position", obj.position, _on_position_changed)
	_add_vector3_input("Rotation", obj.rotation_degrees, _on_rotation_changed)
	_add_vector3_input("Scale", obj.scale, _on_scale_changed)
	
	# Shape-specific properties
	if obj is CSGBox3D:
		property_panel.add_child(HSeparator.new())
		var shape_title = Label.new()
		shape_title.text = "Box Properties"
		shape_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shape_title.add_theme_color_override("font_color", ACCENT_COLOR)
		property_panel.add_child(shape_title)
		_add_vector3_input("Size", obj.size, _on_box_size_changed)
	elif obj is CSGCylinder3D:
		property_panel.add_child(HSeparator.new())
		var shape_title = Label.new()
		shape_title.text = "Cylinder Properties"
		shape_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shape_title.add_theme_color_override("font_color", ACCENT_COLOR)
		property_panel.add_child(shape_title)
		_add_float_input("Radius", obj.radius, _on_cylinder_radius_changed)
		_add_float_input("Height", obj.height, _on_cylinder_height_changed)
	elif obj is CSGSphere3D:
		property_panel.add_child(HSeparator.new())
		var shape_title = Label.new()
		shape_title.text = "Sphere Properties"
		shape_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		shape_title.add_theme_color_override("font_color", ACCENT_COLOR)
		property_panel.add_child(shape_title)
		_add_float_input("Radius", obj.radius, _on_sphere_radius_changed)
	
	# Material properties - always show
	property_panel.add_child(HSeparator.new())
	var mat_title = Label.new()
	mat_title.text = "Material"
	mat_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mat_title.add_theme_color_override("font_color", ACCENT_COLOR)
	property_panel.add_child(mat_title)
	
	var mat = obj.material as StandardMaterial3D if obj.material != null and obj.material is StandardMaterial3D else null
	_add_color_input("Color", mat.albedo_color if mat != null else Color.WHITE, _on_color_changed)
	_add_float_input("Roughness", mat.roughness if mat != null else 0.5, _on_roughness_changed, 0, 1, 0.01)
	_add_float_input("Metallic", mat.metallic if mat != null else 0.0, _on_metallic_changed, 0, 1, 0.01)

func _add_vector3_input(label: String, value: Vector3, callback: Callable) -> void:
	var row = HBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(60, 0)
	row.add_child(lbl)
	
	var x_spin = SpinBox.new()
	x_spin.min_value = -1000
	x_spin.max_value = 1000
	x_spin.step = 0.1
	x_spin.value = value.x
	x_spin.value_changed.connect(callback.bind("x"))
	row.add_child(x_spin)
	
	var y_spin = SpinBox.new()
	y_spin.min_value = -1000
	y_spin.max_value = 1000
	y_spin.step = 0.1
	y_spin.value = value.y
	y_spin.value_changed.connect(callback.bind("y"))
	row.add_child(y_spin)
	
	var z_spin = SpinBox.new()
	z_spin.min_value = -1000
	z_spin.max_value = 1000
	z_spin.step = 0.1
	z_spin.value = value.z
	z_spin.value_changed.connect(callback.bind("z"))
	row.add_child(z_spin)
	
	property_panel.add_child(row)

func _add_float_input(label: String, value: float, callback: Callable, min_v: float = 0, max_v: float = 100, step: float = 0.1) -> void:
	var row = HBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(lbl)
	
	var spin = SpinBox.new()
	spin.min_value = min_v
	spin.max_value = max_v
	spin.step = step
	spin.value = value
	spin.value_changed.connect(callback)
	row.add_child(spin)
	
	property_panel.add_child(row)

func _add_color_input(label: String, value: Color, callback: Callable) -> void:
	var row = HBoxContainer.new()
	
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size = Vector2(80, 0)
	row.add_child(lbl)
	
	var color_btn = ColorPickerButton.new()
	color_btn.color = value
	color_btn.custom_minimum_size = Vector2(80, 24)
	color_btn.color_changed.connect(callback)
	row.add_child(color_btn)
	
	property_panel.add_child(row)

func _add_status_bar() -> void:
	var coords_label = Label.new()
	coords_label.name = "CoordsLabel"
	coords_label.text = "X: 0.0 Y: 0.0 Z: 0.0"
	coords_label.add_theme_color_override("font_color", TEXT_COLOR)
	status_bar.add_child(coords_label)
	
	status_bar.add_child(VSeparator.new())
	
	var snap_label = Label.new()
	snap_label.name = "SnapLabel"
	snap_label.text = "Snap: 1.0m"
	snap_label.add_theme_color_override("font_color", TEXT_COLOR)
	status_bar.add_child(snap_label)
	
	status_bar.add_child(VSeparator.new())
	
	var selection_label = Label.new()
	selection_label.name = "SelectionLabel"
	selection_label.text = "Selected: 0"
	selection_label.add_theme_color_override("font_color", TEXT_COLOR)
	status_bar.add_child(selection_label)
	
	status_bar.add_spacer(false)
	
	var dirty_label = Label.new()
	dirty_label.name = "DirtyLabel"
	dirty_label.text = ""
	dirty_label.add_theme_color_override("font_color", WARNING_COLOR)
	status_bar.add_child(dirty_label)

func _setup_file_dialog() -> void:
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.filters = PackedStringArray(["*.json ; JSON Map Files"])
	file_dialog.min_size = Vector2(600, 400)
	file_dialog.title = "Save Map"
	add_child(file_dialog)
	file_dialog.file_selected.connect(_on_file_dialog_confirmed)

func _setup_confirm_dialog() -> void:
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.min_size = Vector2(300, 100)
	add_child(confirm_dialog)

# === UI Update from Editor ===

func update_from_editor(ed: MapEditor) -> void:
	if editor == null:
		editor = ed
	
	# Update tool buttons
	var current_tool_name = _tool_to_name(ed.current_tool)
	for name in tool_buttons.keys():
		var btn = tool_buttons[name] as Button
		btn.set_pressed_no_signal(name == current_tool_name)
	
	# Update status bar
	var coords_label = status_bar.get_node("CoordsLabel")
	if coords_label != null:
		coords_label.text = "X: %.1f Y: %.1f Z: %.1f" % [ed.camera.position.x, ed.camera.position.y, ed.camera.position.z]
	
	var snap_label = status_bar.get_node("SnapLabel")
	if snap_label != null:
		snap_label.text = "Snap: %.1fm" % ed.grid_snap if ed.grid_snap > 0 else "Snap: Off"
	
	var selection_label = status_bar.get_node("SelectionLabel")
	if selection_label != null:
		selection_label.text = "Selected: %d" % ed.selected_objects.size()
	
	var dirty_label = status_bar.get_node("DirtyLabel")
	if dirty_label != null:
		dirty_label.text = "* Modified" if ed.is_dirty else ""
	
	# Update spawn count in left panel
	var spawn_count_label = left_panel.get_node_or_null("SpawnCountLabel")
	if spawn_count_label != null and ed.map_data != null:
		var counts = ed.get_spawn_point_counts()
		var text = "Spawns: %d (FFA:%d T1:%d T2:%d)" % [counts["total"], counts["ffa"], counts["team1"], counts["team2"]]
		spawn_count_label.text = text
	
	# Update property panel
	if ed.selected_objects.size() == 1:
		_update_property_panel_for_object(ed.selected_objects[0])
	elif ed.selected_objects.size() > 1:
		_update_property_panel_multi_select(ed.selected_objects.size())
	else:
		_update_property_panel_empty()

func _update_property_panel_multi_select(count: int) -> void:
	for child in property_panel.get_children():
		child.queue_free()
	
	var msg = Label.new()
	msg.text = "%d objects selected\n(Multi-editing not yet implemented)" % count
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD
	msg.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.3))
	property_panel.add_child(msg)

func _tool_to_name(tool: int) -> String:
	match tool:
		MapEditor.Tool.SELECT: return "select"
		MapEditor.Tool.BOX: return "box"
		MapEditor.Tool.CYLINDER: return "cylinder"
		MapEditor.Tool.SPHERE: return "sphere"
		MapEditor.Tool.SPAWN: return "spawn"
	return "select"

func _name_to_tool(name: String) -> int:
	match name:
		"select": return MapEditor.Tool.SELECT
		"box": return MapEditor.Tool.BOX
		"cylinder": return MapEditor.Tool.CYLINDER
		"sphere": return MapEditor.Tool.SPHERE
		"spawn": return MapEditor.Tool.SPAWN
	return MapEditor.Tool.SELECT

# === Button Callbacks ===

func _on_tool_selected(tool_name: String) -> void:
	if editor != null:
		editor.set_tool(_name_to_tool(tool_name))

func _on_team_changed(index: int) -> void:
	if editor != null:
		var team = ["ffa", "team1", "team2"][index]
		editor.set_spawn_team(team)

func _on_snap_changed(index: int) -> void:
	if editor != null:
		var snap = [0.0, 0.5, 1.0, 2.0][index]
		editor.grid_snap = snap

func _on_new_pressed() -> void:
	if editor != null:
		if editor.is_dirty:
			show_confirm_dialog("Create new map without saving?", _do_new)
		else:
			_do_new()

func _do_new() -> void:
	if editor != null:
		editor.new_map()

func _on_open_pressed() -> void:
	show_load_dialog()

func _on_save_pressed() -> void:
	if editor != null:
		editor._save_map()

func _on_save_as_pressed() -> void:
	show_save_dialog()

func _on_undo_pressed() -> void:
	if editor != null:
		editor._undo()

func _on_redo_pressed() -> void:
	if editor != null:
		editor._redo()

func _on_test_pressed() -> void:
	if editor != null:
		editor.test_play()

func _on_help_pressed() -> void:
	if editor != null:
		editor.show_help()

func _on_export_pressed() -> void:
	if editor != null:
		editor.export_to_pool()

func _on_exit_pressed() -> void:
	if editor != null:
		editor._show_exit_confirm()

# === File Dialog ===

func show_save_dialog() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.title = "Save Map"
	file_dialog.ok_button_text = "Save"
	file_dialog.popup_centered()

func show_load_dialog() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.title = "Load Map"
	file_dialog.ok_button_text = "Load"
	file_dialog.popup_centered()

func _on_file_dialog_confirmed(path: String) -> void:
	if editor != null:
		if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
			editor.perform_save_as(path)
		else:
			editor.perform_load(path)

# === Confirm Dialog ===

func show_confirm_dialog(message: String, callback: Callable) -> void:
	confirm_dialog.dialog_text = message
	confirm_dialog.confirmed.connect(callback, CONNECT_ONE_SHOT)
	confirm_dialog.popup_centered()

# === Property Callbacks (simplified - needs full implementation) ===

func _on_position_changed(value: float, axis: String) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "position_" + axis, value)

func _on_rotation_changed(value: float, axis: String) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "rotation_" + axis, value)

func _on_scale_changed(value: float, axis: String) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "scale_" + axis, value)

func _on_box_size_changed(value: float, axis: String) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "size_" + axis, value)

func _on_cylinder_radius_changed(value: float) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "radius", value)

func _on_cylinder_height_changed(value: float) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "height", value)

func _on_sphere_radius_changed(value: float) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "radius", value)

func _on_color_changed(color: Color) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "color", color)

func _on_roughness_changed(value: float) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "roughness", value)

func _on_metallic_changed(value: float) -> void:
	if editor != null and _current_property_obj != null:
		editor.set_object_property(_current_property_obj, "metallic", value)

# === Environment Panel ===

func _add_environment_panel() -> void:
	# Environment section in right panel
	var env_separator = HSeparator.new()
	right_panel.add_child(env_separator)
	
	var env_title = Label.new()
	env_title.text = "Environment"
	env_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	env_title.add_theme_color_override("font_color", ACCENT_COLOR)
	right_panel.add_child(env_title)
	
	var env_panel = VBoxContainer.new()
	env_panel.theme_override_constants/separation = 6
	env_panel.name = "EnvironmentPanel"
	right_panel.add_child(env_panel)
	
	# Theme selector
	var theme_row = HBoxContainer.new()
	var theme_lbl = Label.new()
	theme_lbl.text = "Theme:"
	theme_lbl.custom_minimum_size = Vector2(60, 0)
	theme_row.add_child(theme_lbl)
	
	var theme_select = OptionButton.new()
	theme_select.add_item("Custom")
	theme_select.add_item("Day")
	theme_select.add_item("Sunset")
	theme_select.add_item("Night")
	theme_select.item_selected.connect(_on_theme_changed)
	theme_select.name = "ThemeSelect"
	theme_row.add_child(theme_select)
	env_panel.add_child(theme_row)
	
	# Light energy
	var light_row = HBoxContainer.new()
	var light_lbl = Label.new()
	light_lbl.text = "Light Energy:"
	light_lbl.custom_minimum_size = Vector2(80, 0)
	light_row.add_child(light_lbl)
	
	var light_spin = SpinBox.new()
	light_spin.min_value = 0
	light_spin.max_value = 5
	light_spin.step = 0.1
	light_spin.value = 1.4
	light_spin.value_changed.connect(_on_light_energy_changed)
	light_spin.name = "LightEnergySpin"
	light_row.add_child(light_spin)
	env_panel.add_child(light_row)
	
	# Fog density
	var fog_row = HBoxContainer.new()
	var fog_lbl = Label.new()
	fog_lbl.text = "Fog Density:"
	fog_lbl.custom_minimum_size = Vector2(80, 0)
	fog_row.add_child(fog_lbl)
	
	var fog_spin = SpinBox.new()
	fog_spin.min_value = 0
	fog_spin.max_value = 0.1
	fog_spin.step = 0.001
	fog_spin.value = 0.005
	fog_spin.value_changed.connect(_on_fog_density_changed)
	fog_spin.name = "FogDensitySpin"
	fog_row.add_child(fog_spin)
	env_panel.add_child(fog_row)
	
	# Validation section
	var val_separator = HSeparator.new()
	right_panel.add_child(val_separator)
	
	var val_title = Label.new()
	val_title.text = "Validation"
	val_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_title.add_theme_color_override("font_color", ACCENT_COLOR)
	right_panel.add_child(val_title)
	
	var validate_btn = Button.new()
	validate_btn.text = "✓ Validate Map"
	validate_btn.pressed.connect(_on_validate_pressed)
	validate_btn.flat = true
	right_panel.add_child(validate_btn)
	
	var autofix_btn = Button.new()
	autofix_btn.text = "🔧 Auto-fix Issues"
	autofix_btn.pressed.connect(_on_autofix_pressed)
	autofix_btn.flat = true
	right_panel.add_child(autofix_btn)
	
	var validation_label = Label.new()
	validation_label.name = "ValidationLabel"
	validation_label.text = "Not validated"
	validation_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	validation_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	validation_label.add_theme_color_override("font_color", TEXT_COLOR.darkened(0.3))
	right_panel.add_child(validation_label)

# === Phase 3 Callbacks ===

func _on_test_spawn_pressed() -> void:
	if editor != null:
		editor.test_spawn_point()

func _on_clear_spawns_pressed() -> void:
	if editor != null:
		editor.clear_all_spawn_points()

func _on_theme_changed(index: int) -> void:
	if editor != null:
		var themes = ["", "day", "sunset", "night"]
		editor.set_environment_theme(themes[index])

func _on_sky_top_changed(color: Color) -> void:
	if editor != null:
		var horizon = editor.map_data.sky_horizon if editor.map_data != null else Color(0.55, 0.5, 0.4)
		editor.set_sky_color(color, horizon)

func _on_sky_horizon_changed(color: Color) -> void:
	if editor != null:
		var top = editor.map_data.sky_top if editor.map_data != null else Color(0.2, 0.3, 0.5)
		editor.set_sky_color(top, color)

func _on_light_energy_changed(value: float) -> void:
	if editor != null:
		var color = editor.map_data.light_color if editor.map_data != null else Color(1, 0.95, 0.85)
		editor.set_lighting(color, value)

func _on_fog_density_changed(value: float) -> void:
	if editor != null:
		var color = editor.map_data.fog_color if editor.map_data != null else Color(0.55, 0.5, 0.4)
		editor.set_fog(color, value)

func _on_validate_pressed() -> void:
	if editor != null:
		var result = editor.validate_map()
		var label = right_panel.get_node_or_null("ValidationLabel")
		if label != null:
			if result.valid:
				if result.warnings.is_empty():
					label.text = "✓ Map is valid!"
					label.add_theme_color_override("font_color", Color(0.2, 0.8, 0.2))
				else:
					label.text = "⚠ Valid with warnings:\n" + "\n".join(result.warnings)
					label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
					label.custom_minimum_size = Vector2(0, 60)
			else:
				label.text = "✗ Invalid:\n" + result.error
				label.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
				label.custom_minimum_size = Vector2(0, 40)

func _on_autofix_pressed() -> void:
	if editor != null:
		var fixes = editor.auto_fix_map()
		var label = right_panel.get_node_or_null("ValidationLabel")
		if label != null:
			var msg = "Fixed: " + str(fixes["spawn_adjustments"]) + " spawns"
			if not fixes["issues_remaining"].is_empty():
				msg += "\nRemaining issues:\n" + "\n".join(fixes["issues_remaining"])
			else:
				msg += "\nAll issues resolved!"
			label.text = msg
			label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.2))
