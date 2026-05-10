extends Node

# Game Settings — Autoload singleton
# Configurable before starting a game, read by main_game.gd and game_state.gd

# --- Game mode ---
enum GameMode { DEATHMATCH, TEAM_VS_TEAM, CAPTURE_THE_FLAG }
var game_mode: GameMode = GameMode.TEAM_VS_TEAM

# --- Bots ---
var bot_count: int = 3  # 0 = no bots
var bots_enabled: bool = true

# --- Map ---
const AVAILABLE_MAPS: Dictionary = {
	"warehouse": {
		"name": "Warehouse",
		"scene": "res://scenes/maps/warehouse.tscn",
		"description": "Classic indoor warehouse with crates and corridors",
	},
	"courtyard": {
		"name": "Courtyard",
		"scene": "res://scenes/maps/courtyard.tscn",
		"description": "Open outdoor courtyard with walls and pillars",
	},
	"arena": {
		"name": "Arena",
		"scene": "res://scenes/maps/arena.tscn",
		"description": "Circular arena with raised platforms",
	},
}

# Pool of maps eligible for play (subset of AVAILABLE_MAPS keys).
var map_pool: Array[String] = ["warehouse", "courtyard", "arena"]
# The map actively being played. Set by the server, or by solo at match start.
var current_map: String = "warehouse"

enum RotationMode { VOTE, RANDOM, ORDERED }
var rotation_mode: int = RotationMode.VOTE

# Deprecated alias — reads/writes current_map. Remove after one PR cycle.
var selected_map: String:
	get:
		return current_map
	set(value):
		current_map = value

# --- Time limit ---
var time_limit_minutes: int = 5  # 0 = no time limit
const TIME_LIMIT_OPTIONS: Array = [0, 3, 5, 10, 15, 30]

# --- Round settings (for TEAM_VS_TEAM) ---
var rounds_to_win: int = 3

# --- Helpers ---

func get_current_map_scene_path() -> String:
	if AVAILABLE_MAPS.has(current_map):
		return AVAILABLE_MAPS[current_map].scene
	return AVAILABLE_MAPS["warehouse"].scene

func get_current_map_name() -> String:
	if AVAILABLE_MAPS.has(current_map):
		return AVAILABLE_MAPS[current_map].name
	return "Warehouse"

func is_in_pool(map_key: String) -> bool:
	return map_pool.has(map_key)

func pick_random_from_pool() -> String:
	if map_pool.is_empty():
		return "warehouse"
	return map_pool[randi() % map_pool.size()]

func get_rotation_mode_name() -> String:
	match rotation_mode:
		RotationMode.VOTE:
			return "Vote"
		RotationMode.RANDOM:
			return "Random"
		RotationMode.ORDERED:
			return "Ordered"
	return "Vote"

func get_pool_summary() -> String:
	var names: Array[String] = []
	for key in map_pool:
		if AVAILABLE_MAPS.has(key):
			names.append(AVAILABLE_MAPS[key].name)
	return ", ".join(names)

# Deprecated — kept for one PR cycle. Use get_current_map_scene_path().
func get_map_scene_path() -> String:
	return get_current_map_scene_path()

# Deprecated — kept for one PR cycle. Use get_current_map_name().
func get_map_name() -> String:
	return get_current_map_name()

func get_mode_name() -> String:
	match game_mode:
		GameMode.DEATHMATCH:
			return "Deathmatch"
		GameMode.TEAM_VS_TEAM:
			return "Team vs Team"
		GameMode.CAPTURE_THE_FLAG:
			return "Capture the Flag"
	return "Unknown"

func get_effective_bot_count() -> int:
	return bot_count if bots_enabled else 0

func reset_to_defaults() -> void:
	game_mode = GameMode.TEAM_VS_TEAM
	bot_count = 3
	bots_enabled = true
	map_pool.assign(["warehouse", "courtyard", "arena"])
	current_map = "warehouse"
	rotation_mode = RotationMode.VOTE
	time_limit_minutes = 5
	rounds_to_win = 3
