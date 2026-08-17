extends Node

const PREFS_PATH := "user://prefs.cfg"

# Game Settings — Autoload singleton
# Configurable before starting a game, read by main_game.gd and game_state.gd

func _ready() -> void:
	load_prefs()

# --- Game mode ---
enum GameMode { DEATHMATCH, TEAM_VS_TEAM, CAPTURE_THE_FLAG }
var game_mode: GameMode = GameMode.TEAM_VS_TEAM

# --- Bots ---
var bot_count: int = 3  # 0 = no bots
var bots_enabled: bool = true

# --- Bot difficulty ---
enum BotDifficulty { EASY, NORMAL, HARD }
var bot_difficulty: int = BotDifficulty.NORMAL

# Per-difficulty tuning applied at spawn. accuracy/reaction are [min, max]
# ranges randomized per bot so a squad doesn't feel like clones. lead is the
# fraction of target velocity the bot aims ahead by, fire_mult scales weapon
# cooldown (higher = slower shooting).
const BOT_DIFFICULTY_PRESETS := {
	BotDifficulty.EASY: {"name": "Easy", "accuracy": [0.3, 0.5], "reaction": [0.9, 1.4], "lead": 0.25, "vision": 32.0, "engage": 24.0, "fire_mult": 1.6},
	BotDifficulty.NORMAL: {"name": "Normal", "accuracy": [0.45, 0.65], "reaction": [0.55, 0.95], "lead": 0.55, "vision": 40.0, "engage": 32.0, "fire_mult": 1.25},
	BotDifficulty.HARD: {"name": "Hard", "accuracy": [0.6, 0.85], "reaction": [0.3, 0.55], "lead": 0.85, "vision": 45.0, "engage": 38.0, "fire_mult": 1.0},
}

func get_bot_preset() -> Dictionary:
	return BOT_DIFFICULTY_PRESETS.get(bot_difficulty, BOT_DIFFICULTY_PRESETS[BotDifficulty.NORMAL])

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

# One-shot bypass for main_game's solo randomizer. The post-match scene sets
# this to true before transitioning so the chosen/voted map isn't overwritten
# by the next match's _ready. main_game consumes the flag back to false.
var honor_current_map_next_load: bool = false

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

# --- Audio settings ---
var master_volume: float = 1.0  # 0.0 to 1.0
const MIN_VOLUME_DB: float = -60.0  # Muted
const MAX_VOLUME_DB: float = 0.0   # Full volume

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

func get_next_ordered_map() -> String:
	# Next-in-pool relative to current_map. Used by the post-match scene's
	# ORDERED rotation mode.
	if map_pool.is_empty():
		return current_map
	var idx = map_pool.find(current_map)
	if idx < 0:
		return map_pool[0]
	return map_pool[(idx + 1) % map_pool.size()]

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

func apply_volume() -> void:
	# Convert linear 0.0-1.0 to decibel scale
	var volume_db: float
	if master_volume <= 0.0:
		volume_db = MIN_VOLUME_DB
	else:
		volume_db = lerp(MIN_VOLUME_DB, MAX_VOLUME_DB, master_volume)
	AudioServer.set_bus_volume_db(0, volume_db)  # 0 is Master bus

func save_prefs() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("bots", "difficulty", bot_difficulty)
	cfg.save(PREFS_PATH)

func load_prefs() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return
	master_volume = clampf(float(cfg.get_value("audio", "master_volume", 1.0)), 0.0, 1.0)
	bot_difficulty = clampi(int(cfg.get_value("bots", "difficulty", BotDifficulty.NORMAL)), BotDifficulty.EASY, BotDifficulty.HARD)
	apply_volume()

func reset_to_defaults() -> void:
	game_mode = GameMode.TEAM_VS_TEAM
	bot_count = 3
	bots_enabled = true
	bot_difficulty = BotDifficulty.NORMAL
	map_pool.assign(["warehouse", "courtyard", "arena"])
	current_map = "warehouse"
	rotation_mode = RotationMode.VOTE
	time_limit_minutes = 5
	rounds_to_win = 3
	master_volume = 1.0
	apply_volume()
