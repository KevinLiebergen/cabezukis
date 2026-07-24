class_name UIStyle
## Estilos compartidos entre las pantallas de selección (personaje, y campo /
## balón / dificultad): todo lo seleccionado se marca igual, con un borde
## dorado fino + glow suave; lo no seleccionado queda apagado. Las tarjetas
## (bloques y botones) se dibujan a mano —StyleBoxFlat no soporta degradado
## ni sombra por capas— reutilizando draw_card()/rounded_rect_points(), igual
## que ya hacía paint_background() para el césped de fondo.

const GOLD := Color(1, 0.85, 0.2)
## Naranja usado para todos los títulos de ajuste (Campo/Balón/Dificultad):
## unifica el aspecto de las tres tarjetas aunque cada una conserve su color
## de acento en detalles menores.
const TITLE_COLOR := Color(0.95, 0.55, 0.25)

# Tarjeta "de item" (miniatura de balón/campo): un poco más oscura que la de
# sección para diferenciarse, y más clara si está apagada por hover.
const ITEM_TOP := Color(0.09, 0.19, 0.11, 0.9)
const ITEM_BOTTOM := Color(0.045, 0.12, 0.07, 0.9)
const ITEM_BORDER := Color(1, 1, 1, 0.07)

static var _spaced_font: FontVariation = null

## Fuente cartoon del proyecto con un poco más de espaciado entre letras,
## para los títulos y textos con peso (los Label normales ya usan la fuente
## por defecto del tema, definida en project.godot).
static func spaced_font() -> FontVariation:
	if _spaced_font == null:
		_spaced_font = FontVariation.new()
		_spaced_font.base_font = load("res://fonts/LilitaOne-Regular.ttf")
		_spaced_font.spacing_glyph = 2
	return _spaced_font

# ---------------- Primitivas de dibujo ----------------

## Puntos de un rectángulo con las cuatro esquinas redondeadas.
static func rounded_rect_points(rect: Rect2, radius: float, seg: int = 8) -> PackedVector2Array:
	var r := minf(radius, minf(rect.size.x, rect.size.y) * 0.5)
	var pts := PackedVector2Array()
	if r <= 0.5:
		pts.append(rect.position)
		pts.append(rect.position + Vector2(rect.size.x, 0))
		pts.append(rect.position + rect.size)
		pts.append(rect.position + Vector2(0, rect.size.y))
		return pts
	# Orden de recorrido del contorno (sentido horario en pantalla, y crece
	# hacia abajo): arriba-izq -> arriba-dcha -> abajo-dcha -> abajo-izq. Con
	# cualquier otro orden, dos esquinas no consecutivas quedan unidas por una
	# cuerda que atraviesa el rectángulo, y el polígono se autointersecta
	# (Godot no puede triangularlo: "Invalid polygon data").
	var centers := [
		rect.position + Vector2(r, r),
		rect.position + Vector2(rect.size.x - r, r),
		rect.position + Vector2(rect.size.x - r, rect.size.y - r),
		rect.position + Vector2(r, rect.size.y - r),
	]
	var starts := [PI, PI * 1.5, 0.0, PI * 0.5]
	for c in 4:
		var center: Vector2 = centers[c]
		var start: float = starts[c]
		for i in seg + 1:
			var ang := start + (PI * 0.5) * (float(i) / seg)
			pts.append(center + Vector2(cos(ang), sin(ang)) * r)
	return pts

## Dibuja una tarjeta moderna sobre "node" (cualquier CanvasItem en medio de
## su draw()): relleno en degradado vertical (color por vértice), borde fino
## y sombra suave en capas descendentes; opcionalmente un glow exterior
## (para el estado seleccionado). Godot no soporta degradado ni blur real en
## StyleBoxFlat, así que se dibuja a mano con las primitivas de CanvasItem.
static func draw_card(node: CanvasItem, rect: Rect2, radius: float,
		top_color: Color, bottom_color: Color, border_color: Color,
		border_width: float = 2.0, shadow_alpha: float = 0.3,
		glow_color: Color = Color(0, 0, 0, 0)) -> void:
	if shadow_alpha > 0.0:
		for i in range(4, 0, -1):
			var grow: float = i * 2.0
			var off := Vector2(0, i * 1.6)
			var a: float = shadow_alpha * (1.0 - float(i - 1) / 4.0) * 0.5
			var srect := Rect2(rect.position - Vector2(grow, grow) + off, rect.size + Vector2(grow, grow) * 2.0)
			node.draw_colored_polygon(rounded_rect_points(srect, radius + grow), Color(0, 0, 0, a))
	if glow_color.a > 0.0:
		for i in range(3, 0, -1):
			var grow2: float = i * 3.0
			var a2: float = glow_color.a * (1.0 - float(i - 1) / 3.0)
			var grect := Rect2(rect.position - Vector2(grow2, grow2), rect.size + Vector2(grow2, grow2) * 2.0)
			node.draw_colored_polygon(rounded_rect_points(grect, radius + grow2), Color(glow_color.r, glow_color.g, glow_color.b, a2))
	var pts := rounded_rect_points(rect, radius)
	var colors := PackedColorArray()
	for p in pts:
		var t := clampf((p.y - rect.position.y) / maxf(rect.size.y, 1.0), 0.0, 1.0)
		colors.append(top_color.lerp(bottom_color, t))
	node.draw_polygon(pts, colors)
	if border_width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		node.draw_polyline(closed, border_color, border_width, true)

# ---------------- Botones-miniatura (cara/balón/campo) ----------------

## Aplica el estilo "seleccionado" (tarjeta con borde dorado fino + glow
## suave, sin ser exagerado) o el apagado (tarjeta neutra, contenido a media
## luz) a cualquier botón-miniatura. Sustituye los StyleBoxFlat por una
## tarjeta dibujada a mano en el propio "draw" del botón, así soporta
## degradado; el estado se guarda en metadata para que el callback (que solo
## se conecta una vez) siempre lea el valor vigente.
static func style_thumb(btn: Button, selected: bool) -> void:
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	btn.set_meta("ui_selected", selected)
	if not btn.has_meta("ui_thumb_wired"):
		btn.set_meta("ui_thumb_wired", true)
		var empty := StyleBoxEmpty.new()
		for state in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(state, empty)
		btn.draw.connect(func(): _draw_thumb(btn))
	if selected:
		btn.scale = Vector2(1.06, 1.06)
		btn.modulate = Color(1, 1, 1, 1)
		btn.z_index = 5
	else:
		btn.scale = Vector2.ONE
		btn.modulate = Color(0.6, 0.6, 0.6, 1)
		btn.z_index = 0
	btn.queue_redraw()

static func _draw_thumb(btn: Button) -> void:
	var selected: bool = btn.get_meta("ui_selected", false)
	var rect := Rect2(Vector2.ZERO, btn.size)
	if selected:
		draw_card(btn, rect, 16.0, ITEM_TOP.lightened(0.05), ITEM_BOTTOM.lightened(0.05),
			GOLD, 2.5, 0.35, Color(GOLD.r, GOLD.g, GOLD.b, 0.3))
	else:
		draw_card(btn, rect, 16.0, ITEM_TOP, ITEM_BOTTOM, ITEM_BORDER, 1.5, 0.22)

# ---------------- Tarjeta de sección (Campo/Balón/Dificultad) ----------------

## Tarjeta de sección con título grande centrado sobre su contenido: mismo
## fondo casi transparente con esquinas redondeadas que las cajas de grupo
## de player_select.gd (group_box), para que las dos pantallas de
## preparación del partido compartan un único lenguaje visual de "caja".
static func option_block(title: String, content: Control) -> PanelContainer:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)

	var title_lbl := Label.new()
	title_lbl.text = title
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", TITLE_COLOR)
	title_lbl.add_theme_font_override("font", spaced_font())
	vb.add_child(title_lbl)

	vb.add_child(content)
	return group_box(vb, 16, 20.0)

## Caja "de grupo" casi transparente: solo para agrupar visualmente varias
## tarjetas bajo una misma etiqueta (p.ej. "CABEZUKIS"/"LEGENDARIOS"), sin
## competir con el relleno propio de las tarjetas de item que contiene.
static func group_box(content: Control, pad: int = 10, radius: float = 14.0) -> PanelContainer:
	var pc := PanelContainer.new()
	pc.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var bg := Control.new()
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.draw.connect(func(): draw_card(bg, Rect2(Vector2.ZERO, bg.size), radius,
		Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.02), Color(1, 1, 1, 0.12), 1.5, 0.0))
	pc.add_child(bg)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", pad)
	margin.add_theme_constant_override("margin_bottom", pad)
	pc.add_child(margin)
	margin.add_child(content)
	return pc

## Título grande de pantalla ("SELECCIONA EL PERSONAJE", etc.): más peso por
## sombra suave que por contorno negro grueso.
static func screen_title(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 34)
	l.add_theme_font_override("font", spaced_font())
	l.add_theme_color_override("font_color", Color(1, 0.92, 0.55))
	l.add_theme_constant_override("outline_size", 3)
	l.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.02, 0.6))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 4)
	return l

# ---------------- Botones principales ----------------

## Traslada el texto nativo de un botón (si lo tiene) a una Label hija
## centrada y lo vacía. Necesario porque la tarjeta con degradado se dibuja
## en el "draw" del botón, que se ejecuta DESPUÉS del texto nativo del propio
## botón (por eso el texto nativo quedaría tapado); una Label hija, en
## cambio, siempre se dibuja después de su padre, así que queda encima.
## Se llama de forma perezosa desde el propio "draw" (no al aplicar el
## estilo): así da igual si el llamador pone btn.text antes o después de
## style_cta()/style_back() —de lo contrario, ponerlo después dejaría el
## botón sin texto, un error fácil de cometer y difícil de notar a simple
## vista (el botón se ve "bien", solo que vacío).
static func _migrate_native_text(btn: Button, font_size: int, color: Color) -> void:
	if btn.has_meta("ui_text_migrated"):
		return
	btn.set_meta("ui_text_migrated", true)
	if btn.text == "":
		return
	var lbl := Label.new()
	lbl.text = btn.text
	btn.text = ""
	lbl.anchor_right = 1.0
	lbl.anchor_bottom = 1.0
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_font_override("font", spaced_font())
	lbl.add_theme_color_override("font_color", color)
	btn.add_child(lbl)

## Botón grande "¡A JUGAR!": degradado naranja, sombra pronunciada, y
## animación de hover (+5%) y pulsación (-4%) vía Tween sobre btn.scale.
## "label_font_size" permite botones más compactos (p.ej. el menú principal)
## sin perder el mismo estilo/color exacto.
static func style_cta(btn: Button, label_font_size: int = 32) -> void:
	btn.set_meta("ui_cta_font_size", label_font_size)
	# Marca este botón como "de navegación principal" para que GameState le
	# ponga el sonido de menubuttons.ogg en vez del clic genérico (ver
	# play_click/_play_click_if_menu): Jugar/Gestionar jugadores/Escenarios,
	# Siguiente y ¡A JUGAR! pasan todos por aquí.
	btn.set_meta("ui_nav_sound", true)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	btn.add_theme_color_override("font_pressed_color", Color(1, 0.96, 0.85))
	btn.add_theme_color_override("font_shadow_color", Color(0.35, 0.15, 0, 0.6))
	btn.add_theme_constant_override("shadow_offset_x", 0)
	btn.add_theme_constant_override("shadow_offset_y", 3)
	btn.add_theme_font_override("font", spaced_font())
	btn.clip_contents = false
	btn.pivot_offset = btn.custom_minimum_size / 2.0
	btn.draw.connect(func(): _draw_cta(btn))
	var base_scale := Vector2.ONE
	btn.mouse_entered.connect(func():
		btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK) \
			.tween_property(btn, "scale", base_scale * 1.05, 0.14))
	btn.mouse_exited.connect(func():
		btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_SINE) \
			.tween_property(btn, "scale", base_scale, 0.16))
	btn.button_down.connect(func():
		btn.create_tween().set_ease(Tween.EASE_OUT).tween_property(btn, "scale", base_scale * 0.96, 0.06))
	btn.button_up.connect(func():
		var target := base_scale * 1.05 if btn.get_global_rect().has_point(btn.get_global_mouse_position()) else base_scale
		btn.create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK).tween_property(btn, "scale", target, 0.12))

static func _draw_cta(btn: Button) -> void:
	_migrate_native_text(btn, btn.get_meta("ui_cta_font_size", 32), Color(1, 1, 1))
	var rect := Rect2(Vector2.ZERO, btn.size)
	draw_card(btn, rect, 24.0, Color(1.0, 0.72, 0.25), Color(0.95, 0.5, 0.06),
		Color(0.55, 0.28, 0.02, 0.8), 2.0, 0.42)

## Botón discreto "Volver": tarjeta plana verde oscuro, sin relieve, para no
## competir con el CTA.
static func style_back(btn: Button) -> void:
	btn.set_meta("ui_nav_sound", true)
	btn.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("hover", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("pressed", StyleBoxEmpty.new())
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	btn.add_theme_color_override("font_color", Color(0.75, 0.82, 0.78, 0.9))
	btn.add_theme_color_override("font_hover_color", Color(0.88, 0.93, 0.9))
	btn.add_theme_font_override("font", spaced_font())
	btn.draw.connect(func():
		_migrate_native_text(btn, 18, Color(0.75, 0.82, 0.78, 0.9))
		draw_card(btn, Rect2(Vector2.ZERO, btn.size), 14.0,
			Color(0.09, 0.16, 0.11, 0.75), Color(0.05, 0.1, 0.07, 0.75),
			Color(1, 1, 1, 0.06), 1.5, 0.16))

static var _blur_shader: Shader = null

## Difumina un poco la foto de fondo (shader de desenfoque en caja sobre su
## propia textura) para las pantallas con muchas opciones encima, donde el
## detalle de la foto compite con tarjetas y botones.
static func _blur_material() -> ShaderMaterial:
	if _blur_shader == null:
		_blur_shader = Shader.new()
		_blur_shader.code = """
shader_type canvas_item;
uniform float blur_amount : hint_range(0.0, 10.0) = 3.0;

void fragment() {
	vec2 texel = TEXTURE_PIXEL_SIZE * blur_amount;
	vec4 sum = texture(TEXTURE, UV) * 0.25;
	sum += texture(TEXTURE, UV + vec2(-texel.x, -texel.y)) * 0.0625;
	sum += texture(TEXTURE, UV + vec2(0.0, -texel.y)) * 0.125;
	sum += texture(TEXTURE, UV + vec2(texel.x, -texel.y)) * 0.0625;
	sum += texture(TEXTURE, UV + vec2(-texel.x, 0.0)) * 0.125;
	sum += texture(TEXTURE, UV + vec2(texel.x, 0.0)) * 0.125;
	sum += texture(TEXTURE, UV + vec2(-texel.x, texel.y)) * 0.0625;
	sum += texture(TEXTURE, UV + vec2(0.0, texel.y)) * 0.125;
	sum += texture(TEXTURE, UV + vec2(texel.x, texel.y)) * 0.0625;
	COLOR = sum;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = _blur_shader
	return mat

## Fondo compartido de todas las pantallas de menú (principal, selección de
## personaje, campo/balón/dificultad, gestión de jugadores/escenarios): la
## foto de la pista (menu/fondo_menu.png) con un velo oscuro para que el
## texto y las tarjetas se lean bien encima. Mismo fondo en todas para que
## no haya saltos al pasar de una pantalla a otra. "blur": para las pantallas
## con muchas tarjetas/opciones encima (selección de personaje, campo/balón/
## dificultad), donde el detalle de la foto molesta más que en el menú
## principal o las de gestión.
static func add_screen_background(parent: Control, blur: bool = false) -> void:
	var bg := TextureRect.new()
	bg.texture = preload("res://menu/fondo_menu.png")
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if blur:
		bg.material = _blur_material()
	parent.add_child(bg)
	var veil := ColorRect.new()
	veil.color = Color(0, 0, 0, 0.4)
	veil.anchor_right = 1.0
	veil.anchor_bottom = 1.0
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(veil)
