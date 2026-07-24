extends Node
## Estado global: jugadores seleccionados y registro de controles.

const SETTINGS_PATH := "user://settings.json"

var p1: Dictionary = {}
var p2: Dictionary = {}
## Elección de personajes hecha en player_select, pendiente de resolver a
## p1/p2 en match_setup (rival "random" se sortea justo antes de jugar).
var sel_my_id := ""
var sel_rival_id := "random"
var match_duration := 60.0
var ball_style := "trionda"
var field_id := "estadio"
var cpu_difficulty := "dificil"

func _ready() -> void:
	_load_settings()
	_register_action("move_left", [KEY_A, KEY_LEFT])
	_register_action("move_right", [KEY_D, KEY_RIGHT])
	_register_action("jump", [KEY_W, KEY_UP])
	_register_action("kick", [KEY_SPACE, KEY_S, KEY_DOWN, KEY_X])
	_register_action("use_powerup", [KEY_C, KEY_SHIFT])
	# Sonido de clic para CUALQUIER botón de las pantallas de menú (incluidas
	# las que se creen más adelante, p.ej. las tarjetas de manage_players):
	# en vez de conectarlo botón a botón en cada pantalla, se engancha solo
	# una vez aquí a todo nodo Button que entre en el árbol, y al pulsarlo
	# decide si suena mirando la escena activa (nunca durante el partido).
	# Los botones "de navegación" (Jugar/Jugadores/Escenarios/Volver/
	# Siguiente/¡A JUGAR!, con meta "ui_nav_sound" puesta por
	# UIStyle.style_cta/style_back) NO pasan por aquí: quedan fuera a
	# propósito y cada uno llama a GameState.play_nav_click() directamente
	# en su propio pressed.connect(), junto a su acción de navegación, sin
	# depender de esta conexión genérica indirecta.
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is Button and not node.has_meta("ui_nav_sound"):
		node.pressed.connect(_play_click_if_menu)

func _play_click_if_menu() -> void:
	var scene := get_tree().current_scene
	if scene != null and scene.name != "Match":
		play_click()

func _register_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)

func is_touch_device() -> bool:
	# SHOT_FORCE_TOUCH: para poder capturar los controles táctiles con
	# shot.gd desde PC (ver CLAUDE.md), donde no hay pantalla táctil real.
	return DisplayServer.is_touchscreen_available() or OS.has_feature("mobile") or OS.get_environment("SHOT_FORCE_TOUCH") == "1"

# ---------------- Música del descanso ----------------

const HALFTIME_BASE := "user://halftime"
const HALFTIME_EXTS := ["ogg", "mp3", "wav"]
const HALFTIME_DEFAULT := "res://audio/piti_time.ogg"

func halftime_audio_path() -> String:
	for ext in HALFTIME_EXTS:
		var p: String = HALFTIME_BASE + "." + ext
		if FileAccess.file_exists(p):
			return p
	return ""

func halftime_stream() -> AudioStream:
	var p := halftime_audio_path()
	if p != "":
		return PlayerDB._load_audio_file(p)
	return load(HALFTIME_DEFAULT)

## Guarda el audio elegido como música del descanso. Devuelve "" o un error.
func set_halftime_audio(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() == 0:
		return "No se pudo leer el audio."
	var ext: String = PlayerDB._detect_audio_ext(bytes, path)
	if ext == "":
		return "Formato de audio no soportado (usa OGG, MP3 o WAV)."
	clear_halftime_audio()
	var f := FileAccess.open(HALFTIME_BASE + "." + ext, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	# Validar que Godot puede decodificarlo
	var test := halftime_stream()
	if test == null or test.get_length() <= 0.0:
		clear_halftime_audio()
		return "El audio no se pudo decodificar. Si es un .ogg de WhatsApp es Opus: conviértelo a OGG Vorbis, MP3 o WAV."
	return ""

func clear_halftime_audio() -> void:
	for ext in HALFTIME_EXTS:
		var p: String = HALFTIME_BASE + "." + ext
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)

func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
	var d = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if typeof(d) == TYPE_DICTIONARY:
		ball_style = d.get("ball_style", ball_style)
		field_id = d.get("field_id", field_id)
		cpu_difficulty = d.get("cpu_difficulty", cpu_difficulty)

func save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({
		"ball_style": ball_style,
		"field_id": field_id,
		"cpu_difficulty": cpu_difficulty,
	}))
	f.close()

# ---------------- Sonido de clic de menú ----------------

var _click_player: AudioStreamPlayer

func play_click() -> void:
	if _click_player == null:
		_click_player = AudioStreamPlayer.new()
		_click_player.stream = load("res://audio/fart.ogg")
		_click_player.volume_db = -6.0
		add_child(_click_player)
	# from_position=0 para que un segundo clic rápido reinicie el sonido en
	# vez de solaparse con la cola del anterior sonando a la vez.
	_click_player.play(0.0)

var _nav_click_player: AudioStreamPlayer

func play_nav_click() -> void:
	if _nav_click_player == null:
		_nav_click_player = AudioStreamPlayer.new()
		_nav_click_player.stream = load("res://audio/menubuttons.ogg")
		_nav_click_player.volume_db = -6.0
		add_child(_nav_click_player)
	_nav_click_player.play(0.0)

# ---------------- Música de menús ----------------

const MENU_MUSIC := "res://audio/musicamenus.ogg"

var _menu_music_player: AudioStreamPlayer

## Arranca (o reanuda) la música de menús en bucle. Se llama desde cada
## pantalla de menú al entrar; no hace nada si ya está sonando, así que
## pasar de una pantalla de menú a otra no la reinicia ni la corta.
func play_menu_music() -> void:
	if _menu_music_player == null:
		_menu_music_player = AudioStreamPlayer.new()
		var stream: AudioStream = load(MENU_MUSIC)
		stream.loop = true
		_menu_music_player.stream = stream
		_menu_music_player.volume_db = -10.0
		add_child(_menu_music_player)
	if not _menu_music_player.playing:
		_menu_music_player.play()

## Para la música de menús: se llama al entrar en el partido, donde no debe
## sonar.
func stop_menu_music() -> void:
	if _menu_music_player != null:
		_menu_music_player.stop()
