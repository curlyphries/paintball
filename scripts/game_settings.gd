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
var selected_map: String = "warehouse"  # key into AVAILABLE_MAPS
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

# --- Time limit ---
var time_limit_minutes: int = 5  # 0 = no time limit
const TIME_LIMIT_OPTIONS: Array = [0, 3, 5, 10, 15, 30]

# --- Round settings (for TEAM_VS_TEAM) ---
var rounds_to_win: int = 3

# --- Helpers ---

func get_map_scene_path() -> String:
	if AVAILABLE_MAPS.has(selected_map):
		return AVAILABLE_MAPS[selected_map].scene
	return AVAILABLE_MAPS["warehouse"].scene

func get_map_name() -> String:
	if AVAILABLE_MAPS.has(selected_map):
		return AVAILABLE_MAPS[selected_map].name
	return "Warehouse"

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
	selected_map = "warehouse"
	time_limit_minutes = 5
	rounds_to_win = 3
