class_name Boot
extends Node2D
## Pie que golpea el balón: foto real (cabezuki_assets/objetos/zapatilla1.png)
## en vez de un dibujo por código. Apunta a la derecha por defecto; head.gd
## la invierte con scale.x = -1 para el lado izquierdo, igual que antes.

var color: Color = Color(0.9, 0.15, 0.15):
	set(value):
		color = value
		if _sprite != null:
			_sprite.modulate = Color(1, 1, 1).lerp(value, 0.22)

var _sprite: Sprite2D

func _ready() -> void:
	_sprite = Sprite2D.new()
	_sprite.texture = preload("res://boots/zapatilla1.png")
	# Esta ilustración ya trae los dedos a la derecha (talón/tobillo a la
	# izquierda), así que no hace falta espejo como con la foto anterior.
	_sprite.scale = Vector2(0.055, 0.055)
	# Pegada al pivote (que ahora está más arriba y detrás de la cara): el
	# lienzo trae bastante margen transparente alrededor del pie, así que se
	# compensa un poco en X/Y para que quede bien superpuesta bajo la cara en
	# vez de colgando suelta.
	_sprite.position = Vector2(20, 18)
	_sprite.modulate = Color(1, 1, 1).lerp(color, 0.22)
	add_child(_sprite)
