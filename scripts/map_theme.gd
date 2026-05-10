class_name MapTheme
extends Resource

# Shared visual identity for a map. Maps in scenes/maps/ pick a theme .tres
# from assets/themes/ and apply its colors via material overrides on nodes
# tagged with the conventional groups: floor, wall, cover, landmark, accent,
# emission. The MapThemeApplier helper does this automatically when set.
#
# Brightness rule: floor stays below 0.55 so paintball splat decals remain
# readable. Accent and emission colors should pop hard against floor/wall.

@export var theme_name: String = "industrial"

# Geometry colors
@export var floor_color: Color = Color(0.35, 0.33, 0.30)
@export var wall_primary: Color = Color(0.55, 0.50, 0.45)
@export var wall_accent: Color = Color(0.65, 0.55, 0.40)
@export var cover_color: Color = Color(0.60, 0.40, 0.20)
@export var landmark_color: Color = Color(0.50, 0.50, 0.55)
@export var accent_color: Color = Color(1.00, 0.70, 0.20)

# Emission tint for pads, signs, line strips. Maps that want a glow apply
# this as an emission override on group=emission nodes.
@export var emission_color: Color = Color(0.20, 0.60, 1.00)
@export var emission_energy: float = 1.5

# Sky / atmosphere — overrides the procedural sky in _environment.tscn
@export var sky_top: Color = Color(0.20, 0.30, 0.50)
@export var sky_horizon: Color = Color(0.55, 0.50, 0.40)
@export var ground_horizon: Color = Color(0.40, 0.35, 0.30)
@export var ground_bottom: Color = Color(0.20, 0.18, 0.15)

# Sun
@export var light_color: Color = Color(1.00, 0.95, 0.85)
@export var light_energy: float = 1.4

# Fog — depth cue, lightly applied
@export var fog_color: Color = Color(0.55, 0.50, 0.40)
@export var fog_density: float = 0.005
