extends Node

# Round-based game state for one-hit elimination paintball

enum MatchPhase { WAITING, COUNTDOWN, PLAYING, ROUND_OVER, MATCH_OVER }

signal round_started(round_number: int)
signal round_ended(winner_team: int)
signal match_ended(winner_team: int)
signal player_eliminated(victim_id: int, killer_id: int)
signal score_updated(player_score: int, bot_score: int)

# Match settings
const ROUNDS_TO_WIN := 3
const TOTAL_ROUNDS := 5
const COUNTDOWN_TIME := 3.0
const ROUND_OVER_DELAY := 2.0

# State
var match_phase: MatchPhase = MatchPhase.WAITING
var current_round := 0
var player_wins := 0
var bot_wins := 0
var players_alive: Array[int] = []  # IDs of alive players on team 0
var bots_alive: Array[int] = []     # IDs of alive bots on team 1

# Weapon data
var weapons: Dictionary = {
	"pistol": {"damage": 1, "fire_rate": 0.4, "magazine": 12, "reload_time": 1.5, "speed": 40.0, "pellets": 1, "spread": 0.01, "color": Color.YELLOW},
	"rifle": {"damage": 1, "fire_rate": 0.15, "magazine": 30, "reload_time": 2.0, "speed": 60.0, "pellets": 1, "spread": 0.005, "color": Color.GREEN},
	"sniper": {"damage": 1, "fire_rate": 1.5, "magazine": 5, "reload_time": 3.0, "speed": 100.0, "pellets": 1, "spread": 0.0, "color": Color.PURPLE},
	"shotgun": {"damage": 1, "fire_rate": 0.8, "magazine": 8, "reload_time": 2.5, "speed": 30.0, "pellets": 6, "spread": 0.08, "color": Color.RED},
	"smg": {"damage": 1, "fire_rate": 0.08, "magazine": 45, "reload_time": 2.0, "speed": 50.0, "pellets": 1, "spread": 0.03, "color": Color.CYAN}
}

func get_weapon_data(weapon_name: String) -> Dictionary:
	if weapons.has(weapon_name):
		return weapons[weapon_name]
	return weapons["pistol"]

func start_match() -> void:
	current_round = 0
	player_wins = 0
	bot_wins = 0
	start_round()

func start_round() -> void:
	current_round += 1
	match_phase = MatchPhase.COUNTDOWN
	round_started.emit(current_round)

func begin_play() -> void:
	match_phase = MatchPhase.PLAYING

func register_elimination(victim_id: int, killer_id: int) -> void:
	if match_phase != MatchPhase.PLAYING:
		return
	
	player_eliminated.emit(victim_id, killer_id)
	
	# Remove from alive lists
	players_alive.erase(victim_id)
	bots_alive.erase(victim_id)
	
	# Check round over
	if players_alive.is_empty():
		end_round(1)  # Bots win
	elif bots_alive.is_empty():
		end_round(0)  # Player wins

func end_round(winner_team: int) -> void:
	match_phase = MatchPhase.ROUND_OVER
	
	if winner_team == 0:
		player_wins += 1
	else:
		bot_wins += 1
	
	score_updated.emit(player_wins, bot_wins)
	round_ended.emit(winner_team)
	
	# Check match over
	if player_wins >= ROUNDS_TO_WIN or bot_wins >= ROUNDS_TO_WIN:
		match_phase = MatchPhase.MATCH_OVER
		match_ended.emit(0 if player_wins >= ROUNDS_TO_WIN else 1)

func is_match_over() -> bool:
	return match_phase == MatchPhase.MATCH_OVER
