@tool
class_name MapEnvironment
extends Node3D

# Drop-in environment for maps. Instance `_environment.tscn` at the top of
# any map and assign a MapTheme via `theme` to tint sky / sun / fog.
# Overrides can also be set per-property in editor for one-off tweaks.

@export var theme: MapTheme:
	set(value):
		theme = value
		_apply_theme()

# Per-map manual overrides (used if theme is null)
@export_group("Manual Overrides")
@export var override_sky_top: Color = Color(0.20, 0.30, 0.50)
@export var override_sky_horizon: Color = Color(0.55, 0.50, 0.40)
@export var override_ground_color: Color = Color(0.40, 0.35, 0.30)
@export var override_light_color: Color = Color(1.00, 0.95, 0.85)
@export var override_light_energy: float = 1.4
@export var override_fog_color: Color = Color(0.55, 0.50, 0.40)
@export var override_fog_density: float = 0.005

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Sun

func _ready() -> void:
	_apply_theme()

func _apply_theme() -> void:
	if not is_inside_tree():
		return
	if world_env == null or sun == null:
		# Editor: nodes may not be ready yet
		return

	var t_top := override_sky_top
	var t_horizon := override_sky_horizon
	var t_ground := override_ground_color
	var t_light := override_light_color
	var t_light_e := override_light_energy
	var t_fog := override_fog_color
	var t_fog_d := override_fog_density

	if theme != null:
		t_top = theme.sky_top
		t_horizon = theme.sky_horizon
		t_ground = theme.ground_horizon
		t_light = theme.light_color
		t_light_e = theme.light_energy
		t_fog = theme.fog_color
		t_fog_d = theme.fog_density

	var env := world_env.environment as Environment
	if env != null:
		var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
		if sky_mat != null:
			sky_mat.sky_top_color = t_top
			sky_mat.sky_horizon_color = t_horizon
			sky_mat.ground_horizon_color = t_ground
			sky_mat.ground_bottom_color = t_ground.darkened(0.4)
		env.fog_light_color = t_fog
		env.fog_density = t_fog_d

	sun.light_color = t_light
	sun.light_energy = t_light_e
