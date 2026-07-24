class_name FieldArt
extends Node2D
## Decorado del campo dibujado por código. Tres variantes:
## "day" (estadio), "night" (estadio nocturno) y "photo" (foto del usuario
## de fondo con el césped y las porterías dibujados encima).

const W := 1280.0
const H := 720.0
const FLOOR_Y := 640.0
const GOAL_W := 100.0     # profundidad de la portería desde la pared (igual de ancha)
const CROSSBAR_Y := 405.0 # altura del larguero (misma anchura, ~1.8x más alta)
## Cuánto se hunde la base de la portería por debajo de la línea de suelo,
## para simular perspectiva/3D falso (como si el larguero se "clavara" en
## el campo en vez de quedar justo al ras del hitbox).
const SUBMERGE := 12.0

var field: Dictionary = {}
## Factor de escala de cada portería (power-up "agrandar portería rival");
## 1.0 = tamaño normal. La base queda siempre anclada al suelo y crece hacia
## arriba (larguero más alto), no hacia abajo.
var goal_scale_left := 1.0
var goal_scale_right := 1.0

func setup(f: Dictionary) -> void:
	field = f
	queue_redraw()

func set_goal_scale(left: bool, factor: float) -> void:
	if left:
		goal_scale_left = factor
	else:
		goal_scale_right = factor
	queue_redraw()

func _draw() -> void:
	var kind: String = field.get("kind", "day")
	match kind:
		"photo":
			_draw_photo()
			# Los escenarios empaquetados (bundled_fields) ya traen su propio
			# suelo ilustrado (césped, arena...); pintar encima el césped
			# genérico desentona. Las fotos que sube el usuario sí lo llevan,
			# porque son fotos sueltas sin campo dibujado.
			_draw_pitch(false, field.get("user", false))
		"night":
			_draw_night()
			_draw_pitch(true)
		_:
			_draw_day()
			_draw_pitch(false)

# ---------------- Fondos ----------------

func _draw_day() -> void:
	# Cielo en bandas
	draw_rect(Rect2(0, 0, W, 180), Color(0.45, 0.72, 0.95))
	draw_rect(Rect2(0, 180, W, 140), Color(0.52, 0.76, 0.96))
	draw_rect(Rect2(0, 320, W, 120), Color(0.6, 0.8, 0.97))
	# Sol
	draw_circle(Vector2(1120, 90), 46, Color(1.0, 0.92, 0.55))
	# Nubes
	for c in [Vector2(220, 100), Vector2(640, 70), Vector2(920, 130)]:
		draw_circle(c, 30, Color(1, 1, 1, 0.9))
		draw_circle(c + Vector2(30, 8), 24, Color(1, 1, 1, 0.9))
		draw_circle(c + Vector2(-28, 10), 22, Color(1, 1, 1, 0.9))
	_draw_stands(false)
	# Pared del estadio tras el campo
	draw_rect(Rect2(0, 444, W, FLOOR_Y - 444), Color(0.42, 0.58, 0.66))
	for i in 16:
		draw_rect(Rect2(i * 80.0, 444, 40, FLOOR_Y - 444), Color(0.46, 0.62, 0.7))

func _draw_night() -> void:
	# Cielo nocturno
	draw_rect(Rect2(0, 0, W, 200), Color(0.05, 0.06, 0.16))
	draw_rect(Rect2(0, 200, W, 140), Color(0.08, 0.1, 0.22))
	draw_rect(Rect2(0, 340, W, 100), Color(0.11, 0.13, 0.26))
	# Estrellas (posiciones deterministas)
	for i in 40:
		var x := fmod(i * 173.7, W)
		var y := fmod(i * 89.3, 300.0)
		draw_circle(Vector2(x, y), 1.5 + fmod(i * 0.7, 1.5), Color(1, 1, 0.9, 0.8))
	# Luna
	draw_circle(Vector2(1100, 90), 38, Color(0.95, 0.95, 0.85))
	draw_circle(Vector2(1085, 80), 32, Color(0.05, 0.06, 0.16))
	_draw_stands(true)
	# Pared oscura
	draw_rect(Rect2(0, 444, W, FLOOR_Y - 444), Color(0.16, 0.2, 0.28))
	for i in 16:
		draw_rect(Rect2(i * 80.0, 444, 40, FLOOR_Y - 444), Color(0.19, 0.23, 0.31))
	# Torres de focos con conos de luz
	for tx in [180.0, 1100.0]:
		draw_rect(Rect2(tx - 6, 120, 12, 220), Color(0.3, 0.32, 0.36))
		draw_rect(Rect2(tx - 42, 96, 84, 34), Color(0.22, 0.24, 0.28))
		for i in 4:
			draw_circle(Vector2(tx - 30 + i * 20.0, 113), 8, Color(1, 1, 0.75))
		var cone := PackedVector2Array([
			Vector2(tx - 40, 112), Vector2(tx + 40, 112),
			Vector2(tx + 320, FLOOR_Y), Vector2(tx - 320, FLOOR_Y),
		])
		draw_colored_polygon(cone, Color(1, 1, 0.7, 0.10))

func _draw_photo() -> void:
	var tex: Texture2D = field.get("texture")
	if tex == null:
		_draw_day()
		return
	# Recorte tipo "cover": la foto llena todo el fondo manteniendo proporción
	var ts := tex.get_size()
	if ts.x <= 0 or ts.y <= 0:
		_draw_day()
		return
	var s := maxf(W / ts.x, H / ts.y)
	var draw_size := ts * s
	var offset := Vector2((W - draw_size.x) / 2.0, (H - draw_size.y) / 2.0)
	draw_texture_rect(tex, Rect2(offset, draw_size), false)
	# Velo suave para que se lean los cabezudos y el marcador
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.08))

func _draw_stands(night: bool) -> void:
	var base := Color(0.18, 0.16, 0.24) if night else Color(0.35, 0.3, 0.42)
	draw_rect(Rect2(0, 340, W, 100), base)
	for row in 3:
		for i in 40:
			var px := i * 33.0 + (13.0 if row % 2 == 1 else 0.0)
			var py := 355.0 + row * 28.0
			var head := Color(0.75, 0.62, 0.5, 0.5).lerp(
				Color(0.9, 0.4, 0.3, 0.5), fmod(px * 0.37 + py, 1.0))
			if night:
				head = head.darkened(0.4)
			draw_circle(Vector2(px, py), 9, head)
	# Valla
	draw_rect(Rect2(0, 428, W, 16), Color(0.12, 0.2, 0.35) if night else Color(0.2, 0.45, 0.7))

# ---------------- Césped y porterías ----------------

func _draw_pitch(night: bool, draw_grass: bool = true) -> void:
	if draw_grass:
		var grass := Color(0.12, 0.4, 0.17) if night else Color(0.16, 0.5, 0.2)
		var grass_edge := Color(0.2, 0.55, 0.24) if night else Color(0.25, 0.65, 0.28)
		var stripe := Color(0.15, 0.45, 0.2) if night else Color(0.19, 0.55, 0.23)
		draw_rect(Rect2(0, FLOOR_Y, W, H - FLOOR_Y), grass)
		draw_rect(Rect2(0, FLOOR_Y, W, 10), grass_edge)
		for i in 8:
			draw_rect(Rect2(i * 160.0, FLOOR_Y + 10, 80, H - FLOOR_Y), stripe)
	_draw_goal(true, night)
	_draw_goal(false, night)

## Portería con foto real (poste cercano + red en perspectiva). El poste
## cercano queda en x = GOAL_W (izquierda) o x = W - GOAL_W (derecha), justo
## donde match.gd coloca el larguero físico. GOAL_W deja sitio de sobra para
## la imagen entera (sin recortarla) y la base se dibuja SUBMERGE de más
## hacia abajo, hundida bajo la línea de suelo, para dar sensación de 3D.
##
## La imagen está partida en dos capas (ver goal_front.gd): esta, "_back"
## (red + poste lejano), se dibuja aquí en FieldArt, detrás del balón
## (z_index -10 en match.gd). La capa "_front" (poste cercano) la dibuja por
## separado GoalFront con z_index por delante del balón, para que el balón sí
## se vea "entrar" tras el poste cercano en vez de superponerse siempre.
static func _goal_back_texture() -> Texture2D:
	return preload("res://goals/porteria_back.png")

## Caché del color medio de cada escenario de foto (para no releer/escalar la
## imagen en cada redibujado): la base de todos los tintes de integración
## (porterías, balón, cabezudos), para que todos compartan el mismo "tono de
## luz ambiente" y se sientan iluminados por la misma escena.
static var _avg_color_cache: Dictionary = {}

static func _field_avg_color(f: Dictionary) -> Color:
	var fid: String = f.get("id", "")
	if _avg_color_cache.has(fid):
		return _avg_color_cache[fid]
	var avg := Color(1, 1, 1)
	var tex: Texture2D = f.get("texture")
	if tex != null:
		var img := tex.get_image()
		if img != null:
			img = img.duplicate()
			if img.is_compressed():
				img.decompress()
			img.resize(1, 1, Image.INTERPOLATE_LANCZOS)
			avg = img.get_pixel(0, 0)
	_avg_color_cache[fid] = avg
	return avg

## Tono (cálido/frío) del escenario, normalizado a brillo máximo: se queda
## solo con la "dirección de color" del promedio de la foto (p.ej. naranja
## cálido o azul frío) sin su luminosidad, para que al mezclarlo con blanco
## nunca oscurezca ni aclare el resultado, solo le dé matiz. Balón,
## porterías y cabezudos deben mantener su luminosidad estándar; solo el
## tono cambia según la escena.
static func _field_tone(f: Dictionary) -> Color:
	var avg := _field_avg_color(f)
	var v: float = maxf(avg.r, maxf(avg.g, avg.b))
	if v <= 0.001:
		return Color(1, 1, 1)
	return Color(avg.r / v, avg.g / v, avg.b / v)

## Tinte para la portería: mezcla fuerte (55%) hacia el tono del escenario.
## Al usar _field_tone (brillo ya normalizado) en vez del color medio en
## bruto, cualquier mezcla con blanco mantiene el canal máximo en 1.0 —no
## oscurece la red aunque la foto sea muy oscura.
static func compute_tint(f: Dictionary, night: bool) -> Color:
	if f.get("kind", "") != "photo":
		return Color(1, 1, 1)
	return Color(1, 1, 1).lerp(_field_tone(f), 0.55)

## Tinte para balón y cabezudos: mismo principio, mezcla más suave (32%)
## para que el tono se note sin desviar demasiado los colores propios del
## balón/la piel. La luminosidad siempre queda estándar (ver _field_tone).
static func compute_actor_tint(f: Dictionary, night: bool) -> Color:
	if f.get("kind", "") != "photo":
		return Color(1, 1, 1)
	return Color(1, 1, 1).lerp(_field_tone(f), 0.32)

func _draw_goal(left: bool, night: bool = false) -> void:
	var tex := _goal_back_texture()
	var ts := tex.get_size()
	var floor_bottom := FLOOR_Y + SUBMERGE
	var factor := goal_scale_left if left else goal_scale_right
	var gh := (floor_bottom - CROSSBAR_Y) * factor
	var scale := gh / ts.y
	var dst_w := ts.x * scale
	var top_y := floor_bottom - gh
	# El poste queda siempre en el borde derecho de la imagen fuente.
	var near_x := GOAL_W if left else W - GOAL_W
	var tint := compute_tint(field, night)

	# Sombra de contacto en la base del poste cercano: ancla la portería al
	# suelo del escenario en vez de dejarla flotando encima.
	draw_set_transform(Vector2(near_x, floor_bottom), 0.0, Vector2(1, 0.35))
	draw_circle(Vector2.ZERO, 16, Color(0, 0, 0, 0.28))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if left:
		draw_texture_rect(tex, Rect2(near_x - dst_w, top_y, dst_w, gh), false, tint)
	else:
		# Portería derecha: espejo horizontal.
		draw_set_transform(Vector2(near_x + dst_w, top_y), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(0, 0, dst_w, gh), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
