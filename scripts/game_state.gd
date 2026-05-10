extends Node

# Round-based game state for one-hit elimination paintball
# Supports: Team vs Team (rounds), Deathmatch (kills), Capture the Flag

enum MatchPhase { WAITING, COUNTDOWN, PLAYING, ROUND_OVER, MATCH_OVER }

signal round_started(round_number: int)
signal round_ended(winner_team: int)
signal match_ended(winner_team: int)
signal player_eliminated(victim_id: int, killer_id: int)
signal score_updated(player_score: int, bot_score: int)
signal time_updated(seconds_remaining: float)
signal kill_score_updated(scores: Dictionary)

# Constants
const COUNTDOWN_TIME := 3.0
const ROUND_OVER_DELAY := 2.0

# State
var match_phase: MatchPhase = MatchPhase.WAITING
var current_round := 0
var player_wins := 0
var bot_wins := 0
var players_alive: Array[int] = []  # IDs of alive players on team 0
var bots_alive: Array[int] = []     # IDs of alive bots on team 1

# Time limit
var time_remaining := 0.0
var time_limit_enabled := false

# Deathmatch scoring — kill counts per player/bot ID
var kill_scores: Dictionary = {}

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

func _process(delta: float) -> void:
	if match_phase == MatchPhase.PLAYING and time_limit_enabled:
		time_remaining -= delta
		time_updated.emit(time_remaining)
		if time_remaining <= 0:
			time_remaining = 0
			_on_time_expired()

func start_match() -> void:
	current_round = 0
	player_wins = 0
	bot_wins = 0
	kill_scores.clear()
	match_phase = MatchPhase.WAITING
	
	# Configure time limit from settings
	if GameSettings.time_limit_minutes > 0:
		time_limit_enabled = true
		time_remaining = GameSettings.time_limit_minutes * 60.0
	else:
		time_limit_enabled = false
		time_remaining = 0.0

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
	
	var mode = GameSettings.game_mode
	
	if mode == GameSettings.GameMode.DEATHMATCH:
		# Track kills per player
		if not kill_scores.has(killer_id):
			kill_scores[killer_id] = 0
		kill_scores[killer_id] += 1
		kill_score_updated.emit(kill_scores)
	else:
		# Team vs Team / CTF — round-based elimination
		var was_player = victim_id in players_alive
		var was_bot = victim_id in bots_alive
		players_alive.erase(victim_id)
		bots_alive.erase(victim_id)
		
		# Only check round end if both teams had members at round start
		if was_player and players_alive.is_empty() and not bots_alive.is_empty():
			end_round(1)  # Bots win — all players eliminated
		elif was_bot and bots_alive.is_empty() and not players_alive.is_empty():
			end_round(0)  # Player wins — all bots eliminated
		elif players_alive.is_empty() and bots_alive.is_empty():
			end_round(0)  # Draw — give to player

func end_round(winner_team: int) -> void:
	match_phase = MatchPhase.ROUND_OVER
	
	if winner_team == 0:
		player_wins += 1
	else:
		bot_wins += 1
	
	score_updated.emit(player_wins, bot_wins)
	round_ended.emit(winner_team)
	
	# Check match over
	var rounds_needed = GameSettings.rounds_to_win
	if player_wins >= rounds_needed or bot_wins >= rounds_needed:
		match_phase = MatchPhase.MATCH_OVER
		match_ended.emit(0 if player_wins >= rounds_needed else 1)

func _on_time_expired() -> void:
	var mode = GameSettings.game_mode
	
	if mode == GameSettings.GameMode.DEATHMATCH:
		# Whoever has most kills wins
		match_phase = MatchPhase.MATCH_OVER
		var best_id := -1
		var best_kills := -1
		for id in kill_scores:
			if kill_scores[id] > best_kills:
				best_kills = kill_scores[id]
				best_id = id
		# Team 0 = player, anything else = bot
		var winner = 0 if best_id == 0 else 1
		match_ended.emit(winner)
	else:
		# Team modes — whoever has more round wins
		match_phase = MatchPhase.MATCH_OVER
		var winner = 0 if player_wins >= bot_wins else 1
		match_ended.emit(winner)

func is_match_over() -> bool:
	return match_phase == MatchPhase.MATCH_OVER

func get_kill_score(id: int) -> int:
	return kill_scores.get(id, 0)
