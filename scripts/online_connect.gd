extends Control
## Pantalla de conexión al servidor online: se conecta directo al servidor
## fijo del usuario (Net.DEFAULT_SERVER_IP/DEFAULT_PORT) en cuanto se entra,
## sin pedir ni mostrar la IP en pantalla. Si la conexión tiene éxito, pasa a
## online_lobby.tscn (Net ya sabe el lado asignado en ese momento).

var _status: Label
var _retry_btn: Button

func _ready() -> void:
	UIStyle.add_screen_background(self)
	GameState.play_menu_music()
	Net.connection_succeeded.connect(_on_connected)
	Net.connection_failed.connect(_on_failed)

	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.position = Vector2(-220, -120)
	vb.custom_minimum_size = Vector2(440, 0)
	vb.add_theme_constant_override("separation", 16)
	add_child(vb)

	vb.add_child(UIStyle.screen_title("JUGAR ONLINE"))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.add_theme_color_override("font_color", Color(1, 0.8, 0.6))
	vb.add_child(_status)

	_retry_btn = Button.new()
	_retry_btn.custom_minimum_size = Vector2(0, 72)
	UIStyle.style_cta(_retry_btn, 26)
	_retry_btn.text = "Reintentar"
	_retry_btn.visible = false
	_retry_btn.pressed.connect(_connect)
	vb.add_child(_retry_btn)

	var back := Button.new()
	back.text = "◀ Volver"
	back.custom_minimum_size = Vector2(0, 46)
	UIStyle.style_back(back)
	back.pressed.connect(func():
		Net.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vb.add_child(back)

	_connect()

func _connect() -> void:
	_retry_btn.visible = false
	_status.text = "Conectando..."
	var err := Net.start_client(Net.DEFAULT_SERVER_IP, Net.DEFAULT_PORT)
	if err != OK:
		_on_failed()

func _on_connected() -> void:
	get_tree().change_scene_to_file("res://scenes/online_lobby.tscn")

func _on_failed() -> void:
	_status.text = "No se pudo conectar al servidor."
	_retry_btn.visible = true
