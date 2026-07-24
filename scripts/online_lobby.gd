extends Control
## Sala de espera online: elige tu cabezuki (solo "bundled", los que vienen
## con el juego -ver CLAUDE.md, v1 online no soporta fotos propias del
## usuario todavía) y confirma "Listo". El servidor arranca la partida en
## cuanto los dos jugadores han confirmado; campo/balón/duración siguen
## fijos por ahora (ver server_boot.gd).

var _status: Label
var _buttons: Dictionary = {}
var _featured_face: TextureRect
var _name_label: Label
var _ready_btn: Button
var _selected_id := ""
var _confirmed := false

func _ready() -> void:
	UIStyle.add_screen_background(self, true)
	Net.server_disconnected.connect(_on_disconnected)
	Net.peer_joined.connect(func(_id): _refresh_status())
	Net.peer_left.connect(func(_id): _refresh_status())
	Net.side_assigned.connect(func(_side): _refresh_status())
	Net.match_starting.connect(_on_match_starting)

	var margin := MarginContainer.new()
	margin.anchor_right = 1.0
	margin.anchor_bottom = 1.0
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var main_vb := VBoxContainer.new()
	main_vb.add_theme_constant_override("separation", 14)
	margin.add_child(main_vb)

	main_vb.add_child(UIStyle.screen_title("ELIGE TU CABEZUKI"))

	var top_spacer := Control.new()
	top_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vb.add_child(top_spacer)

	main_vb.add_child(_featured())

	var pick_gap := Control.new()
	pick_gap.custom_minimum_size = Vector2(0, 12)
	main_vb.add_child(pick_gap)

	var bundled: Array = PlayerDB.players.filter(func(p): return not p.user)
	main_vb.add_child(_player_groups(bundled))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	main_vb.add_child(_status)

	var bottom_spacer := Control.new()
	bottom_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vb.add_child(bottom_spacer)

	main_vb.add_child(_bottom_bar())

	if bundled.size() > 0:
		_select(bundled[0].id)
	_refresh_status()

# ---------------- Retrato + selección ----------------

func _featured() -> Control:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	vb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var portrait := PanelContainer.new()
	portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	portrait.custom_minimum_size = Vector2(104, 104)
	var fsb := StyleBoxFlat.new()
	fsb.set_corner_radius_all(52)
	fsb.bg_color = Color(0.15, 0.13, 0.04, 0.9)
	fsb.set_border_width_all(4)
	fsb.border_color = UIStyle.GOLD
	fsb.shadow_color = Color(UIStyle.GOLD.r, UIStyle.GOLD.g, UIStyle.GOLD.b, 0.55)
	fsb.shadow_size = 12
	portrait.add_theme_stylebox_override("panel", fsb)
	vb.add_child(portrait)

	var center := CenterContainer.new()
	portrait.add_child(center)
	_featured_face = TextureRect.new()
	_featured_face.custom_minimum_size = Vector2(88, 88)
	_featured_face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_featured_face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_featured_face.material = FaceUtil.circle_material()
	_featured_face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(_featured_face)

	_name_label = Label.new()
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 20)
	vb.add_child(_name_label)

	return vb

## Mismo criterio que player_select.gd: los nombres de LEGENDARY_NAMES van a
## su propio grupo "LEGENDARIOS", separado de la plantilla normal
## "CABEZUKIS" (por ahora, solo La Matriarca).
const LEGENDARY_NAMES := ["La Matriarca"]

func _player_groups(bundled: Array) -> VBoxContainer:
	var normal := bundled.filter(func(p): return not (p.name in LEGENDARY_NAMES))
	var legendary := bundled.filter(func(p): return p.name in LEGENDARY_NAMES)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)

	var cabezukis_inner := VBoxContainer.new()
	cabezukis_inner.add_theme_constant_override("separation", 2)
	cabezukis_inner.add_child(_group_label("CABEZUKIS"))
	cabezukis_inner.add_child(_player_flow(normal))
	vb.add_child(UIStyle.group_box(cabezukis_inner, 7))

	if not legendary.is_empty():
		var legend_inner := VBoxContainer.new()
		legend_inner.add_theme_constant_override("separation", 2)
		legend_inner.add_child(_group_label("LEGENDARIOS"))
		legend_inner.add_child(_player_flow(legendary))
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

func _player_flow(players: Array) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flow.alignment = FlowContainer.ALIGNMENT_CENTER
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 6)
	for p in players:
		flow.add_child(_face_button(p.id, p.name, p.face))
	return flow

func _face_button(id: String, pname: String, face: Texture2D) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(66, 90)
	var vb := VBoxContainer.new()
	vb.anchor_right = 1.0
	vb.anchor_bottom = 1.0
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	btn.add_child(vb)
	var tr := TextureRect.new()
	tr.texture = face
	tr.material = FaceUtil.circle_material()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.custom_minimum_size = Vector2(44, 44)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(tr)
	var lbl := Label.new()
	lbl.text = pname
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(lbl)
	btn.pressed.connect(func(): _select(id))
	_buttons[id] = btn
	return btn

func _select(id: String) -> void:
	if _confirmed:
		return
	_selected_id = id
	for bid in _buttons:
		UIStyle.style_thumb(_buttons[bid], bid == id)
	var p := PlayerDB.get_player(id)
	_featured_face.texture = p.face
	_name_label.text = p.name

# ---------------- Botones inferiores ----------------

func _bottom_bar() -> Control:
	var wrap := Control.new()
	wrap.custom_minimum_size = Vector2(0, 96)
	wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	const READY_W := 300.0
	const READY_H := 84.0
	const BACK_W := 150.0
	const BACK_H := 54.0
	const GAP := 24.0

	var back := Button.new()
	back.text = "◀ Salir"
	back.anchor_left = 0.5
	back.anchor_right = 0.5
	back.offset_right = -(READY_W / 2.0 + GAP)
	back.offset_left = back.offset_right - BACK_W
	back.offset_top = (READY_H - BACK_H) / 2.0
	back.offset_bottom = back.offset_top + BACK_H
	UIStyle.style_back(back)
	back.pressed.connect(func():
		Net.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	wrap.add_child(back)

	_ready_btn = Button.new()
	_ready_btn.text = "Listo ▶"
	_ready_btn.anchor_left = 0.5
	_ready_btn.anchor_right = 0.5
	_ready_btn.offset_left = -READY_W / 2.0
	_ready_btn.offset_right = READY_W / 2.0
	_ready_btn.offset_top = 0.0
	_ready_btn.offset_bottom = READY_H
	_ready_btn.add_theme_font_size_override("font_size", 30)
	UIStyle.style_cta(_ready_btn)
	_ready_btn.pressed.connect(_on_ready_pressed)
	wrap.add_child(_ready_btn)

	return wrap

func _on_ready_pressed() -> void:
	if _confirmed or _selected_id == "":
		return
	_confirmed = true
	_ready_btn.disabled = true
	for bid in _buttons:
		_buttons[bid].disabled = true
	Net.rpc_id(1, "rpc_player_ready", _selected_id)
	_refresh_status()

# ---------------- Estado ----------------

func _refresh_status() -> void:
	var side := Net.my_side()
	if side == "":
		_status.text = "Conectado. Esperando confirmación del servidor..."
	elif _confirmed:
		_status.text = "Listo. Esperando al rival..."
	else:
		_status.text = "Eres el jugador %s. Elige tu cabezuki y pulsa Listo." % ("1" if side == "p1" else "2")

func _on_disconnected() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _on_match_starting(p1_id: String, p2_id: String, field_id: String, ball_style: String, duration: float) -> void:
	GameState.p1 = PlayerDB.get_player(p1_id)
	GameState.p2 = PlayerDB.get_player(p2_id)
	GameState.field_id = field_id
	GameState.ball_style = ball_style
	GameState.match_duration = duration
	get_tree().change_scene_to_file("res://scenes/match.tscn")
