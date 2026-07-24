extends Control
## Menú principal.

func _ready() -> void:
	UIStyle.add_screen_background(self)
	# No hace nada si ya estaba sonando (p.ej. al volver aquí desde otra
	# pantalla de menú): solo arranca de cero al entrar desde el partido o
	# al abrir la app.
	GameState.play_menu_music()

	var title := Label.new()
	title.text = "CABEZUKIS"
	title.anchor_left = 0.0
	title.anchor_right = 1.0
	title.position.y = 14
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 92)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.25))
	title.add_theme_constant_override("outline_size", 20)
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.1, 0.05))
	add_child(title)

	# Más pequeños que antes y bajados a la zona de las gradas/pista del
	# fondo (no sobre el cielo/los edificios), para que no tapen la imagen.
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_right = 0.5
	vb.position = Vector2(-230, 378)
	vb.custom_minimum_size = Vector2(460, 0)
	vb.add_theme_constant_override("separation", 20)
	add_child(vb)

	vb.add_child(_menu_button("▶  Jugar", func():
		get_tree().change_scene_to_file("res://scenes/player_select.tscn")))
	vb.add_child(_menu_button("🌐  Online", func():
		get_tree().change_scene_to_file("res://scenes/online_connect.tscn")))
	vb.add_child(_menu_button("👤  Jugadores", func():
		get_tree().change_scene_to_file("res://scenes/manage_players.tscn")))
	vb.add_child(_menu_button("⛳  Escenarios", func():
		get_tree().change_scene_to_file("res://scenes/manage_fields.tscn")))

	# Salir: en la esquina superior derecha en vez de en la lista de abajo
	# (no tiene el mismo peso que Jugar/Jugadores/Escenarios). No aparece en
	# móvil, como antes: ahí se sale con el gesto/botón del sistema, no hace
	# falta un botón propio dentro de la app.
	if not OS.has_feature("mobile"):
		var exit_btn := Button.new()
		exit_btn.text = "SALIR"
		exit_btn.custom_minimum_size = Vector2(110, 40)
		exit_btn.anchor_left = 1.0
		exit_btn.anchor_right = 1.0
		exit_btn.position = Vector2(-126, 16)
		exit_btn.add_theme_font_size_override("font_size", 16)
		UIStyle.style_back(exit_btn)
		exit_btn.pressed.connect(func():
			GameState.play_nav_click()
			get_tree().quit())
		add_child(exit_btn)

## Mismo naranja y mismo estilo que el CTA de "SELECCIONA EL CABEZUKI"
## (UIStyle.style_cta): degradado, sombra, y animación de hover/pulsación.
func _menu_button(text: String, action: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 56)
	UIStyle.style_cta(btn, 24)
	btn.pressed.connect(func():
		GameState.play_nav_click()
		action.call())
	return btn
