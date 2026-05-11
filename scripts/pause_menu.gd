extends Control

# Pause Menu — toggled with Esc during gameplay

@onready var resume_btn: Button = $Panel/VBox/ResumeButton
@onready var volume_slider: HSlider = $Panel/VBox/VolumeRow/VolumeSlider
@onready var volume_value_label: Label = $Panel/VBox/VolumeRow/VolumeValueLabel
@onready var quit_btn: Button = $Panel/VBox/QuitButton

func _ready() -> void:
	resume_btn.pressed.connect(_on_resume)
	quit_btn.pressed.connect(_on_quit)
	volume_slider.value_changed.connect(_on_volume_changed)
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Initialize volume from settings
	volume_slider.value = GameSettings.master_volume
	_update_volume_label()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if visible:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()

func _pause() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _on_resume() -> void:
	_resume()

func _on_volume_changed(value: float) -> void:
	GameSettings.master_volume = value
	GameSettings.apply_volume()
	GameSettings.save_prefs()
	_update_volume_label()

func _update_volume_label() -> void:
	var percent := int(GameSettings.master_volume * 100)
	volume_value_label.text = str(percent) + "%"

func _on_quit() -> void:
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	
	# Clean up network if in multiplayer
	if NetworkManager.room_code != "":
		var game_sync = get_node_or_null("/root/Main/GameSync")
		if game_sync:
			game_sync.cleanup()
		NetworkManager.leave_room()
		NetworkManager.disconnect_from_relay()
	
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
