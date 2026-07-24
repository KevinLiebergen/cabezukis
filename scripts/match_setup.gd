extends Control
## Pantalla 2/2 de la preparación del partido: campo, balón y dificultad.
## El personaje ya se eligió en player_select (GameState.sel_my_id/rival_id).

var _ball_style := ""
var _field_id := ""
var _cpu_difficulty := ""
var _ball_buttons: Dictionary = {}
var _field_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _diff_pulse := 0.0
var _diff_tween: Tween

const DIFFICULTIES := ["facil", "media", "dificil"]
const DIFFICULTY_NAMES := {"facil": "Fácil", "media": "Media", "dificil": "Difícil"}

func _ready() -> void:
	# Por si se carga esta pantalla sin haber pasado por player_select.
	if GameState.sel_my_id == "" and PlayerDB.players.size() > 0:
		GameState.sel_my_id = PlayerDB.players[0].id

	UIStyle.add_screen_background(self, true)

	# Mismo marco (márgenes, título arriba, barra inferior abajo) que
	# player_select.gd: título y botones Volver/CTA quedan en las mismas
	# coordenadas en las dos pantallas, para que el paso entre ellas no
	# desplace nada. Los "spacers" con SIZE_EXPAND_FILL absorben el espacio
	# sobrante arriba y abajo del contenido, que queda centrado entre ambos.
	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var main_vb := VBoxContainer.new()
	main_vb.add_theme_constant_override("separation", 20)
	margin.add_child(main_vb)

	main_vb.add_child(UIStyle.screen_title("ELIGE CAMPO, BALÓN Y DIFICULTAD"))

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vb.add_child(top_spacer)

	# Campo ocupa su propia fila (para que las fotos de escenario se vean
	# grandes); balón y dificultad comparten la fila de abajo, con exactamente
	# la misma anchura total que la de Campo para que las tres tarjetas
	# queden alineadas.
	var field_block := UIStyle.option_block("Campo", _field_row())
	main_vb.add_child(field_block)

	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 28)
	main_vb.add_child(bottom_row)

	var ball_block := UIStyle.option_block("Balón", _ball_row())
	ball_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(ball_block)

	var diff_block := UIStyle.option_block("Dificultad", _difficulty_row())
	diff_block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom_row.add_child(diff_block)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vb.add_child(bottom_spacer)

	main_vb.add_child(_bottom_bar())

	_select_ball(GameState.ball_style if GameState.ball_style in BallStyles.STYLES else "trionda")
	var fid: String = GameState.field_id
	if FieldDB.get_field(fid).id != fid:
		fid = FieldDB.fields[0].id
	_select_field(fid)
	_select_difficulty(GameState.cpu_difficulty if GameState.cpu_difficulty in DIFFICULTIES else "dificil")

# ---------------- Filas de selección ----------------

func _ball_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	for style in BallStyles.STYLES:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(84, 94)
		var vb := VBoxContainer.new()
		vb.anchor_right = 1.0
		vb.anchor_bottom = 1.0
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		btn.add_child(vb)
		var icon := BallStyles.BallIcon.new(style)
		icon.custom_minimum_size = Vector2(56, 56)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(icon)
		var lbl := Label.new()
		lbl.text = BallStyles.NAMES[style]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(lbl)
		var s: String = style
		btn.pressed.connect(func(): _select_ball(s))
		_ball_buttons[style] = btn
		hb.add_child(btn)
	return hb

## Segmented control moderno: una única barra "píldora" con las tres
## opciones a igual anchura; la seleccionada se resalta con un relleno
## dorado que pulsa suavemente (brillo animado), las demás quedan atenuadas
## pero legibles.
func _difficulty_row() -> Control:
	var outer := Control.new()
	outer.custom_minimum_size = Vector2(0, 46)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var track := Control.new()
	track.anchor_right = 1.0
	track.anchor_bottom = 1.0
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.draw.connect(func():
		UIStyle.draw_card(track, Rect2(Vector2.ZERO, track.size), track.size.y / 2.0,
			Color(0.07, 0.15, 0.09, 0.85), Color(0.035, 0.09, 0.05, 0.85),
			Color(1, 1, 1, 0.07), 1.5, 0.2))
	outer.add_child(track)

	var hb := HBoxContainer.new()
	hb.anchor_right = 1.0
	hb.anchor_bottom = 1.0
	hb.add_theme_constant_override("separation", 0)
	outer.add_child(hb)

	for diff in DIFFICULTIES:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 46)
		btn.focus_mode = Control.FOCUS_NONE
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, empty)
		var lbl := Label.new()
		lbl.text = DIFFICULTY_NAMES[diff]
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.anchor_right = 1.0
		lbl.anchor_bottom = 1.0
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_font_override("font", UIStyle.spaced_font())
		btn.add_child(lbl)
		var d: String = diff
		btn.pressed.connect(func(): _select_difficulty(d))
		btn.draw.connect(func(): _draw_difficulty_segment(btn))
		_difficulty_buttons[diff] = {"btn": btn, "label": lbl}
		hb.add_child(btn)
	return outer

func _draw_difficulty_segment(btn: Button) -> void:
	if not btn.get_meta("selected", false):
		return
	var pad := 5.0
	var rect := Rect2(Vector2(pad, pad), btn.size - Vector2(pad, pad) * 2.0)
	var glow_a := 0.2 + 0.22 * _diff_pulse
	UIStyle.draw_card(btn, rect, rect.size.y / 2.0, Color(1, 0.88, 0.4), Color(0.93, 0.62, 0.1),
		Color(1, 0.95, 0.7, 0.9), 1.5, 0.0, Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, glow_a))

func _field_row() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.alignment = BoxContainer.ALIGNMENT_CENTER
	hb.add_theme_constant_override("separation", 16)
	for f in FieldDB.fields:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(168, 116)
		var vb := VBoxContainer.new()
		vb.anchor_right = 1.0
		vb.anchor_bottom = 1.0
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		btn.add_child(vb)
		vb.add_child(_field_thumb(f))
		var lbl := Label.new()
		lbl.text = f.name
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.add_theme_font_size_override("font_size", 15)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(lbl)
		var fid: String = f.id
		btn.pressed.connect(func(): _select_field(fid))
		_field_buttons[f.id] = btn
		hb.add_child(btn)
	return hb

## Miniatura de un campo: foto o el dibujo escalado.
func _field_thumb(f: Dictionary) -> Control:
	if f.kind == "photo" and f.texture != null:
		var tr := TextureRect.new()
		tr.texture = f.texture
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.custom_minimum_size = Vector2(152, 86)
		tr.clip_contents = true
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		return tr
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(152, 86)
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var art := FieldArt.new()
	art.setup(f)
	art.scale = Vector2.ONE * (152.0 / 1280.0)
	holder.add_child(art)
	return holder

# ---------------- Botones inferiores ----------------

func _bottom_bar() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 96)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	const START_W := 380.0
	const START_H := 92.0
	const BACK_W := 150.0
	const BACK_H := 54.0
	const GAP := 30.0

	var back := Button.new()
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.offset_right = -(START_W / 2.0 + GAP)
	back.offset_left = back.offset_right - BACK_W
	back.offset_top = (START_H - BACK_H) / 2.0
	back.offset_bottom = back.offset_top + BACK_H
	UIStyle.style_back(back)
	var back_lbl := Label.new()
	back_lbl.text = "◀ Volver"
	back_lbl.anchor_right = 1.0
	back_lbl.anchor_bottom = 1.0
	back_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	back_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	back_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back_lbl.add_theme_font_size_override("font_size", 18)
	back.add_child(back_lbl)
	back.pressed.connect(func():
		GameState.play_nav_click()
		get_tree().change_scene_to_file("res://scenes/player_select.tscn"))
	wrap.add_child(back)

	var start := Button.new()
	start.anchor_left = 0.5
	start.anchor_right = 0.5
	start.offset_left = -START_W / 2.0
	start.offset_right = START_W / 2.0
	start.offset_top = 0.0
	start.offset_bottom = START_H
	UIStyle.style_cta(start)
	var start_hb := HBoxContainer.new()
	start_hb.anchor_right = 1.0
	start_hb.anchor_bottom = 1.0
	start_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	start_hb.add_theme_constant_override("separation", 12)
	start_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var start_lbl := Label.new()
	start_lbl.text = "¡A JUGAR!"
	start_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	start_lbl.add_theme_font_size_override("font_size", 32)
	start_lbl.add_theme_font_override("font", UIStyle.spaced_font())
	start_lbl.add_theme_color_override("font_color", Color(1, 1, 1))
	start_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	start_hb.add_child(start_lbl)
	start.add_child(start_hb)
	start.pressed.connect(_start)
	wrap.add_child(start)

	return wrap

# ---------------- Selección ----------------

func _select_ball(style: String) -> void:
	_ball_style = style
	for bid in _ball_buttons:
		UIStyle.style_thumb(_ball_buttons[bid], bid == style)

func _select_field(id: String) -> void:
	_field_id = id
	for bid in _field_buttons:
		UIStyle.style_thumb(_field_buttons[bid], bid == id)

func _select_difficulty(diff: String) -> void:
	_cpu_difficulty = diff
	for d in _difficulty_buttons:
		var entry: Dictionary = _difficulty_buttons[d]
		var selected: bool = d == diff
		entry.btn.set_meta("selected", selected)
		entry.label.add_theme_color_override("font_color",
			Color(0.15, 0.09, 0.02) if selected else Color(0.78, 0.85, 0.8, 0.55))
		entry.btn.queue_redraw()
	_restart_diff_pulse()

## Brillo amarillo animado (pulso suave, en bucle) del segmento seleccionado.
func _restart_diff_pulse() -> void:
	if _diff_tween != null:
		_diff_tween.kill()
	_diff_pulse = 0.0
	_diff_tween = create_tween()
	_diff_tween.set_loops()
	_diff_tween.tween_method(_set_diff_pulse, 0.0, 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_diff_tween.tween_method(_set_diff_pulse, 1.0, 0.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _set_diff_pulse(v: float) -> void:
	_diff_pulse = v
	if _difficulty_buttons.has(_cpu_difficulty):
		_difficulty_buttons[_cpu_difficulty].btn.queue_redraw()

func _start() -> void:
	GameState.play_nav_click()
	GameState.p1 = PlayerDB.get_player(GameState.sel_my_id)
	if GameState.sel_rival_id == "random":
		GameState.p2 = PlayerDB.random_player(GameState.sel_my_id)
	else:
		GameState.p2 = PlayerDB.get_player(GameState.sel_rival_id)
	GameState.ball_style = _ball_style
	GameState.field_id = _field_id
	GameState.cpu_difficulty = _cpu_difficulty
	GameState.save_settings()
	get_tree().change_scene_to_file("res://scenes/match.tscn")
