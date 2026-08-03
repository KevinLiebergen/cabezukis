extends Control
## Pantalla 1/2 de la preparación del partido: elegir cabezuki propio y
## rival. El campo, balón y dificultad se eligen después, en match_setup.

var _my_id := ""
var _rival_id := "random"
var _my_buttons: Dictionary = {}
var _rival_buttons: Dictionary = {}

var _my_featured_face: TextureRect
var _my_featured_dice: Label
var _my_name_label: Label
var _rival_featured_face: TextureRect
var _rival_featured_dice: Label
var _rival_name_label: Label

func _ready() -> void:
	UIStyle.add_screen_background(self, true)

	# Mismo marco que match_setup.gd (márgenes, título arriba, barra Volver/CTA
	# abajo en las mismas coordenadas): el paso entre las dos pantallas de
	# preparación del partido no desplaza nada.
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

	main_vb.add_child(UIStyle.screen_title("SELECCIONA PERSONAJE"))

	# Hueco pequeño y fijo (no expansivo): el título queda cerca del
	# contenido a propósito, para dejar todo el espacio posible a las cajas
	# de grupo de abajo y que quepa todo sin scroll ni recortar la barra
	# inferior (ver _player_row).
	var top_spacer := Control.new()
	top_spacer.custom_minimum_size = Vector2(0, 6)
	main_vb.add_child(top_spacer)

	main_vb.add_child(_vs_header())

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vb.add_child(bottom_spacer)

	main_vb.add_child(_bottom_bar())

	if PlayerDB.players.size() > 0:
		_select_player(true, PlayerDB.players[0].id)
	_select_player(false, "random")

# ---------------- Cabecera VS ----------------

func _vs_header() -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 0)

	var my_col := _player_column(true)
	my_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(my_col)

	# "VS" a la altura de las caras (TÚ/RIVAL), no centrado en toda la
	# columna (que con las cajas de grupo debajo es mucho más alta y dejaba
	# el VS mucho más abajo de las caras): un hueco arriba que iguale la
	# etiqueta TÚ/RIVAL + su separación, y centrado solo en la banda del
	# retrato grande, no en la columna entera.
	var vs_col := VBoxContainer.new()
	vs_col.custom_minimum_size = Vector2(140, 0)
	vs_col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var vs_top_gap := Control.new()
	vs_top_gap.custom_minimum_size = Vector2(0, 24)
	vs_col.add_child(vs_top_gap)
	var vs_wrap := CenterContainer.new()
	vs_wrap.custom_minimum_size = Vector2(0, 92)
	var vs_lbl := Label.new()
	vs_lbl.text = "VS"
	vs_lbl.add_theme_font_size_override("font_size", 68)
	vs_lbl.add_theme_color_override("font_color", UIStyle.GOLD)
	vs_lbl.add_theme_constant_override("outline_size", 12)
	vs_lbl.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.02))
	vs_wrap.add_child(vs_lbl)
	vs_col.add_child(vs_wrap)
	hb.add_child(vs_col)

	var rival_col := _player_column(false)
	rival_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(rival_col)

	return hb

## Columna de un lado del VS: etiqueta TÚ/RIVAL, retrato grande destacado,
## nombre, fila de miniaturas y (solo el rival) una fila aparte para
## "Aleatorio".
func _player_column(mine: bool) -> VBoxContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)

	var tag := Label.new()
	tag.text = "TÚ" if mine else "RIVAL"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 15)
	tag.add_theme_color_override("font_color", Color(1, 0.9, 0.3) if mine else Color(1, 0.6, 0.4))
	vb.add_child(tag)

	var featured := PanelContainer.new()
	featured.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	featured.custom_minimum_size = Vector2(92, 92)
	var fsb := StyleBoxFlat.new()
	fsb.set_corner_radius_all(46)
	fsb.bg_color = Color(0.15, 0.13, 0.04, 0.9)
	fsb.set_border_width_all(4)
	fsb.border_color = UIStyle.GOLD
	fsb.shadow_color = Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.55)
	fsb.shadow_size = 12
	featured.add_theme_stylebox_override("panel", fsb)
	vb.add_child(featured)

	var center := CenterContainer.new()
	featured.add_child(center)

	var face_tr := TextureRect.new()
	face_tr.custom_minimum_size = Vector2(76, 76)
	face_tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face_tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face_tr.material = FaceUtil.circle_material()
	face_tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(face_tr)

	var dice_lbl := Label.new()
	dice_lbl.text = "🎲"
	dice_lbl.add_theme_font_size_override("font_size", 52)
	dice_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(dice_lbl)

	var name_lbl := Label.new()
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 18)
	vb.add_child(name_lbl)

	# Hueco entre el retrato grande destacado y las cajas de grupo de abajo:
	# antes iban pegados (separación de 4 heredada del resto de la columna,
	# pensada para tag/retrato/nombre) y costaba distinguir "el seleccionado
	# ahora mismo" de "la lista para elegir otro".
	var pick_gap := Control.new()
	pick_gap.custom_minimum_size = Vector2(0, 16)
	vb.add_child(pick_gap)

	vb.add_child(_player_row(mine))

	if mine:
		_my_featured_face = face_tr
		_my_featured_dice = dice_lbl
		_my_name_label = name_lbl
	else:
		_rival_featured_face = face_tr
		_rival_featured_dice = dice_lbl
		_rival_name_label = name_lbl

	return vb

func _update_featured(mine: bool, id: String) -> void:
	var face: Texture2D = null
	var pname := "Aleatorio"
	if id != "random":
		var p := PlayerDB.get_player(id)
		if p.has("face"):
			face = p.face
			pname = p.name
	var face_tr := _my_featured_face if mine else _rival_featured_face
	var dice_lbl := _my_featured_dice if mine else _rival_featured_dice
	var name_lbl := _my_name_label if mine else _rival_name_label
	face_tr.visible = face != null
	dice_lbl.visible = face == null
	if face != null:
		face_tr.texture = face
	name_lbl.text = pname

# ---------------- Filas de selección ----------------

## Nombres que van al grupo "LEGENDARIOS" en vez de al grupo normal
## "CABEZUKIS". El ORDEN de esta lista es también el orden en que aparecen
## sus tarjetas (ver el sort_custom en _player_row): sin eso, el orden
## dependería de en qué orden devuelve el sistema de archivos las carpetas de
## bundled_players/, que no tiene por qué coincidir con este -Mawii tiene que
## quedar a la derecha de La Matriarca pase lo que pase.
const LEGENDARY_NAMES := ["La Matriarca", "Mawii"]

## Antes era una fila que desbordaba en scroll horizontal: con más de un
## puñado de jugadores, las últimas tarjetas quedaban cortadas a la mitad en
## el borde y, con pocos, se apiñaban a la izquierda en vez de centrarse.
## Un FlowContainer que envuelve línea y centra (y se estira con la columna,
## al ser hijo directo del VBoxContainer) deja todas las tarjetas enteras y
## centradas debajo de "TÚ"/"RIVAL" tenga las que tenga. Además, separados
## en dos grupos con su propia etiqueta: "CABEZUKIS" (la plantilla normal,
## con "Aleatorio" como primera opción del rival) y "LEGENDARIOS" (personajes
## especiales, de momento solo La Matriarca).
func _player_row(mine: bool) -> VBoxContainer:
	var normal := PlayerDB.players.filter(func(p): return not (p.name in LEGENDARY_NAMES))
	var legendary := PlayerDB.players.filter(func(p): return p.name in LEGENDARY_NAMES)
	# Orden fijo según LEGENDARY_NAMES, no el de llegada desde PlayerDB.players
	# (que sigue el orden de carpetas en bundled_players/, fuera de nuestro
	# control): así Mawii siempre queda a la derecha de La Matriarca.
	legendary.sort_custom(func(a, b): return LEGENDARY_NAMES.find(a.name) < LEGENDARY_NAMES.find(b.name))

	var vb := VBoxContainer.new()
	# Separación entre cajas de grupo (CABEZUKIS / LEGENDARIOS): más que la
	# interna de cada caja, para que se lean como bloques distintos.
	vb.add_theme_constant_override("separation", 18)

	var cabezukis_inner := VBoxContainer.new()
	cabezukis_inner.add_theme_constant_override("separation", 2)
	cabezukis_inner.add_child(_group_label("CABEZUKIS"))
	cabezukis_inner.add_child(_player_flow(normal, mine, not mine))
	vb.add_child(UIStyle.group_box(cabezukis_inner, 7))

	if not legendary.is_empty():
		var legend_inner := VBoxContainer.new()
		legend_inner.add_theme_constant_override("separation", 2)
		legend_inner.add_child(_group_label("LEGENDARIOS"))
		legend_inner.add_child(_player_flow(legendary, mine))
		vb.add_child(UIStyle.group_box(legend_inner, 7))
	return vb

func _group_label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", UIStyle.TITLE_COLOR)
	l.add_theme_font_override("font", UIStyle.spaced_font())
	return l

func _player_flow(players: Array, mine: bool, include_random: bool = false) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	if include_random:
		flow.add_child(_face_button("random", "Aleatorio", null, mine))
	for p in players:
		flow.add_child(_face_button(p.id, p.name, p.face, mine))
	return flow

func _face_button(id: String, pname: String, face: Texture2D, mine: bool) -> Button:
	var btn := Button.new()
	var btn_size := Vector2(66, 90)
	var tex_size := 44.0
	var dice_font := 30
	var label_font := 13
	btn.custom_minimum_size = btn_size
	var vb := VBoxContainer.new()
	vb.anchor_right = 1.0
	vb.anchor_bottom = 1.0
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(vb)
	if face != null:
		var tr := TextureRect.new()
		tr.texture = face
		tr.material = FaceUtil.circle_material()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(tex_size, tex_size)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		vb.add_child(tr)
	else:
		var q := Label.new()
		q.text = "🎲"
		q.add_theme_font_size_override("font_size", dice_font)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(q)
	var lbl := Label.new()
	lbl.text = pname
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", label_font)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lbl)
	btn.pressed.connect(func(): _select_player(mine, id))
	if mine:
		_my_buttons[id] = btn
	else:
		_rival_buttons[id] = btn
	return btn

# ---------------- Botones inferiores ----------------

func _bottom_bar() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 96)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Mismas medidas que el botón "¡A JUGAR!" de match_setup.gd (misma fila,
	# misma anchura/altura), para que Volver/CTA no salten de sitio ni de
	# tamaño entre las dos pantallas de preparación del partido.
	const NEXT_W := 380.0
	const NEXT_H := 92.0
	const BACK_W := 150.0
	const BACK_H := 54.0
	const GAP := 30.0

	var back := Button.new()
	back.text = "◀ Volver"
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.offset_right = -(NEXT_W / 2.0 + GAP)
	back.offset_left = back.offset_right - BACK_W
	back.offset_top = (NEXT_H - BACK_H) / 2.0
	back.offset_bottom = back.offset_top + BACK_H
	back.add_theme_font_size_override("font_size", 18)
	UIStyle.style_back(back)
	back.pressed.connect(func():
		GameState.play_nav_click()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	wrap.add_child(back)

	var next := Button.new()
	next.text = "Siguiente  ▶"
	next.anchor_left = 0.5
	next.anchor_right = 0.5
	next.offset_left = -NEXT_W / 2.0
	next.offset_right = NEXT_W / 2.0
	next.offset_top = 0.0
	next.offset_bottom = NEXT_H
	next.add_theme_font_size_override("font_size", 34)
	UIStyle.style_cta(next)
	next.pressed.connect(_go_next)
	wrap.add_child(next)

	return wrap

# ---------------- Selección ----------------

func _select_player(mine: bool, id: String) -> void:
	if mine:
		_my_id = id
	else:
		_rival_id = id
	var buttons := _my_buttons if mine else _rival_buttons
	for bid in buttons:
		UIStyle.style_thumb(buttons[bid], bid == id)
	_update_featured(mine, id)

func _go_next() -> void:
	GameState.play_nav_click()
	GameState.sel_my_id = _my_id
	GameState.sel_rival_id = _rival_id
	get_tree().change_scene_to_file("res://scenes/match_setup.tscn")
