class_name Weapon3D
extends Node3D

@export var weapon_name: String = "pistol"

var weapon_data: Dictionary
var current_ammo: int
var is_reloading := false
var fire_cooldown := 0.0
var reload_timer := 0.0

# Projectile scene
var projectile_scene: PackedScene = preload("res://scenes/projectile.tscn")

signal fired(pos: Vector3, direction: Vector3, speed: float, color: Color)
signal ammo_changed(current: int, max_ammo: int)
signal reload_started(duration: float)
signal reload_finished()

func _ready() -> void:
	weapon_data = GameState.get_weapon_data(weapon_name)
	current_ammo = weapon_data.magazine

func _process(delta: float) -> void:
	if fire_cooldown > 0:
		fire_cooldown -= delta
	
	if is_reloading:
		reload_timer -= delta
		if reload_timer <= 0:
			finish_reload()

func can_fire() -> bool:
	return fire_cooldown <= 0 and not is_reloading

func fire(origin: Vector3, direction: Vector3) -> void:
	if not can_fire():
		return
	
	fire_cooldown = weapon_data.fire_rate
	
	# Fire pellets (shotgun fires multiple)
	for i in range(weapon_data.pellets):
		var spread_dir = direction
		if weapon_data.spread > 0:
			spread_dir = spread_dir.rotated(Vector3.UP, randf_range(-weapon_data.spread, weapon_data.spread))
			spread_dir = spread_dir.rotated(Vector3.RIGHT, randf_range(-weapon_data.spread, weapon_data.spread))
		
		fired.emit(origin, spread_dir.normalized(), weapon_data.speed, weapon_data.color)

func start_reload() -> void:
	if is_reloading or current_ammo == weapon_data.magazine:
		return
	is_reloading = true
	reload_timer = weapon_data.reload_time
	reload_started.emit(weapon_data.reload_time)

func finish_reload() -> void:
	is_reloading = false
	current_ammo = weapon_data.magazine
	ammo_changed.emit(current_ammo, weapon_data.magazine)
	reload_finished.emit()

func switch_to(new_weapon: String) -> void:
	weapon_name = new_weapon
	weapon_data = GameState.get_weapon_data(weapon_name)
	current_ammo = weapon_data.magazine
	is_reloading = false
	fire_cooldown = 0.0
	ammo_changed.emit(current_ammo, weapon_data.magazine)
