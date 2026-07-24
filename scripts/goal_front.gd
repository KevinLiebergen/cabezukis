class_name GoalFront
extends Node2D
## Poste cercano de cada portería, en una capa aparte de FieldArt con
## z_index por delante del balón y los cabezudos (ver match.gd): así cuando
## el balón/cabezudo entra a portería pasa "por detrás" de este poste en vez
## de superponerse siempre por encima, dando sensación real de profundidad.
## La red y el poste lejano siguen dibujándose en FieldArt, detrás del balón,
## como antes.
##
## porteria_front.png NO es una copia de la portería completa: es la misma
## imagen que porteria_back.png con todo excepto la franja vertical del
## poste cercano (aprox. x=535-616 del original, ver goals/porteria.png)
## vuelto transparente. Si se regenera desde una porteria.png nueva hay que
## recortar de nuevo esa franja; si se deja la imagen completa, el poste
## "cercano" vuelve a dibujar TODA la red por delante de cabezudos y balón,
## tapándolos por completo en vez de solo asomar el poste.

var field: Dictionary = {}
## Debe seguir siempre al mismo factor que FieldArt.goal_scale_left/right
## (power-up "agrandar portería rival"), para que el poste cercano crezca en
## sintonía con el larguero y la red de la capa de detrás.
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
	_draw_post(true)
	_draw_post(false)

func _draw_post(left: bool) -> void:
	var tex := preload("res://goals/porteria_front.png")
	var ts := tex.get_size()
	var floor_bottom := FieldArt.FLOOR_Y + FieldArt.SUBMERGE
	var factor := goal_scale_left if left else goal_scale_right
	var gh := (floor_bottom - FieldArt.CROSSBAR_Y) * factor
	var scale := gh / ts.y
	var dst_w := ts.x * scale
	var top_y := floor_bottom - gh
	var near_x: float = FieldArt.GOAL_W if left else FieldArt.W - FieldArt.GOAL_W
	var night: bool = field.get("kind", "day") == "night"
	var tint := FieldArt.compute_tint(field, night)
	if left:
		draw_texture_rect(tex, Rect2(near_x - dst_w, top_y, dst_w, gh), false, tint)
	else:
		draw_set_transform(Vector2(near_x + dst_w, top_y), 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(0, 0, dst_w, gh), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
