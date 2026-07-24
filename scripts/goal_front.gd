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
## Debe seguir siempre en sintonía con FieldArt.goal_shake_left/right (ver
## match.gd _on_ball_touched_post, que llama a ambos a la vez), para que el
## poste cercano tiemble junto con la red de la capa de detrás.
var goal_shake_left := Vector2.ZERO
var goal_shake_right := Vector2.ZERO

func setup(f: Dictionary) -> void:
	field = f
	queue_redraw()

func set_goal_scale(left: bool, factor: float) -> void:
	if left:
		goal_scale_left = factor
	else:
		goal_scale_right = factor
	queue_redraw()

## Mismo patrón que FieldArt.shake_goal (rápido la primera mitad, más lento y
## con menos amplitud la segunda): deben ir en sintonía porque son dos capas
## del mismo temblor visual.
func shake_goal(left: bool) -> void:
	var tw := create_tween()
	var amt := 18.0
	for i in 4:
		var off := Vector2(randf_range(-amt, amt), randf_range(-amt * 0.5, amt * 0.5))
		tw.tween_method(_set_goal_shake.bind(left), Vector2.ZERO, off, 0.02)
	for f: float in [0.55, 0.28]:
		var off: Vector2 = Vector2(randf_range(-amt, amt), randf_range(-amt * 0.5, amt * 0.5)) * f
		tw.tween_method(_set_goal_shake.bind(left), Vector2.ZERO, off, 0.05)
	tw.tween_method(_set_goal_shake.bind(left), Vector2.ZERO, Vector2.ZERO, 0.03)

func _set_goal_shake(v: Vector2, left: bool) -> void:
	if left:
		goal_shake_left = v
	else:
		goal_shake_right = v
	queue_redraw()

func _draw() -> void:
	_draw_post(true)
	_draw_post(false)

func _draw_post(left: bool) -> void:
	var tex := preload("res://goals/porteria_front.png")
	var floor_bottom := FieldArt.FLOOR_Y + FieldArt.SUBMERGE
	var factor := goal_scale_left if left else goal_scale_right
	var gh := (floor_bottom - FieldArt.CROSSBAR_Y) * factor
	# Igual que en FieldArt._draw_goal: el ancho no depende de "factor", solo
	# el alto, para que agrandar la portería no la desplace hacia atrás.
	var dst_w := FieldArt.goal_depth()
	var top_y := floor_bottom - gh
	var near_x: float = FieldArt.GOAL_W if left else FieldArt.W - FieldArt.GOAL_W
	var night: bool = field.get("kind", "day") == "night"
	var tint := FieldArt.compute_tint(field, night)
	var shake := goal_shake_left if left else goal_shake_right
	if left:
		draw_texture_rect(tex, Rect2(near_x - dst_w + shake.x, top_y + shake.y, dst_w, gh), false, tint)
	else:
		draw_set_transform(Vector2(near_x + dst_w, top_y) + shake, 0.0, Vector2(-1, 1))
		draw_texture_rect(tex, Rect2(0, 0, dst_w, gh), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
