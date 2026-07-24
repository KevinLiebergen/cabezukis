class_name BallStyles
## Diseños de balón dibujados por código. Todos se dibujan alrededor del
## origen con radio r, así giran con el cuerpo y escalan con los power-ups.

const STYLES := ["trionda", "jabulani", "roteiro", "clasico", "reventao"]
const NAMES := {
	"trionda": "Trionda '26",
	"jabulani": "Jabulani '10",
	"roteiro": "Roteiro '04",
	"clasico": "Clásico",
	"reventao": "Reventao",
}

## Fotos reales (fondo recortado) de cada balón.
const TEXTURES := {
	"trionda": preload("res://balls/trionda.png"),
	"jabulani": preload("res://balls/jabulani.png"),
	"roteiro": preload("res://balls/roteiro.png"),
	"clasico": preload("res://balls/clasico.png"),
	"reventao": preload("res://balls/reventao.png"),
}

static func draw_ball(ci: CanvasItem, style: String, r: float) -> void:
	if TEXTURES.has(style):
		ci.draw_texture_rect(TEXTURES[style], Rect2(-r, -r, r * 2.0, r * 2.0), false)
		return
	# Estilo desconocido (p.ej. un settings.json corrupto): dibujo de respaldo.
	_trionda(ci, r)
	_apply_sphere_shading(ci, r)
	ci.draw_arc(Vector2.ZERO, r - 1.0, 0, TAU, 48, Color(0.12, 0.12, 0.14), 2.5)

## Da volumen esférico a cualquier diseño plano: oscurece el borde (AO),
## añade una sombra direccional abajo-derecha y un brillo especular
## arriba-izquierda, simulando una luz cenital sin salir del estilo vectorial.
static func _apply_sphere_shading(ci: CanvasItem, r: float) -> void:
	# Oscurecido sutil de todo el borde (contacto con el aire/ambient occlusion).
	ci.draw_arc(Vector2.ZERO, r * 0.93, 0, TAU, 48, Color(0.0, 0.0, 0.0, 0.10), r * 0.14)
	# Sombra direccional más marcada en el cuadrante opuesto a la luz.
	ci.draw_arc(Vector2(r * 0.04, r * 0.06), r * 0.9, PI * 0.05, PI * 0.95, 28, Color(0.0, 0.0, 0.0, 0.22), r * 0.32)
	# Halo de brillo suave (luz difusa) arriba a la izquierda, en varias capas
	# para fingir un degradado sin gradients reales.
	var hl := Vector2(-r * 0.33, -r * 0.4)
	var layers := [
		[0.34, 0.08], [0.24, 0.14], [0.16, 0.20], [0.09, 0.28],
	]
	for layer in layers:
		ci.draw_circle(hl, r * layer[0], Color(1.0, 1.0, 1.0, layer[1]))
	# Punto de brillo especular, más pequeño y definido.
	ci.draw_circle(hl + Vector2(-r * 0.04, -r * 0.05), r * 0.05, Color(1.0, 1.0, 1.0, 0.55))

## Mundial 2026: blanco con triángulos rojo, verde y azul.
static func _trionda(ci: CanvasItem, r: float) -> void:
	ci.draw_circle(Vector2.ZERO, r, Color.WHITE)
	var colors := [Color(0.85, 0.15, 0.2), Color(0.1, 0.55, 0.3), Color(0.15, 0.3, 0.75)]
	for i in 3:
		var a := -PI / 2.0 + TAU * i / 3.0
		var tri := PackedVector2Array([
			Vector2.from_angle(a) * r * 0.12,
			Vector2.from_angle(a + 0.85) * r * 0.82,
			Vector2.from_angle(a - 0.85) * r * 0.82,
		])
		ci.draw_colored_polygon(tri, colors[i])
	for i in 3:
		var a := -PI / 2.0 + TAU * i / 3.0 + PI / 3.0
		ci.draw_circle(Vector2.from_angle(a) * r * 0.58, r * 0.07, Color(0.95, 0.78, 0.25))

## Icono clicable de balón para los selectores.
class BallIcon extends Control:
	var style := "trionda"

	func _init(s: String) -> void:
		style = s
		custom_minimum_size = Vector2(72, 72)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_set_transform(size / 2.0, 0.0, Vector2.ONE)
		BallStyles.draw_ball(self, style, minf(size.x, size.y) / 2.0 - 4.0)
