class_name Ball
extends RigidBody2D
## Balón de fútbol con velocidad limitada y radio variable (power-ups).

signal touched_post
## Emitida al chocar con la barrera diagonal del fondo de la red (ver
## match.gd GOAL_BACKSTOP_LAYER/_add_goal_backstop): es el propio "gol", no
## solo un choque -antes había un sensor aparte en la boca de la portería,
## pero eso contaba el gol antes de que el balón llegase a entrar de verdad.
signal touched_goal_net(is_left: bool)

## Antes 28 (100%): 80% del tamaño original, en sintonía con los cabezudos
## (Head.RADIUS) y las porterías más pequeñas (ver match.gd/field_art.gd).
const BASE_RADIUS := 22.4
## Antes 1300, luego 950 (demasiado lenta), luego 1100 (demasiado rápida de
## vuelta). 1050 queda entre medias, más lenta que 1100 sin caer tanto como
## los 950.
const MAX_SPEED := 1050.0
const BASE_BOUNCE := 0.78

var radius := BASE_RADIUS
var _shape: CircleShape2D

func _ready() -> void:
	mass = 1.0
	gravity_scale = 1.0
	# Antes 0.15: MAX_SPEED solo topa el pico de velocidad, pero casi ningún
	# golpe llega a tocar ese techo -así que bajarlo apenas se nota "en
	# general"-. Lo que de verdad rige cuánto tiempo se pasa la bola rodando
	# rápido después de cualquier golpe (chut, cabeceo, rebote) es la
	# fricción: más alta hace que pierda velocidad antes y se sienta más
	# controlable, sin tocar la fuerza del primer impacto.
	linear_damp = 0.4
	angular_damp = 0.6
	contact_monitor = true
	max_contacts_reported = 6
	# Sin esto, un balón pequeño y rápido apretado entre dos cabezudos que
	# avanzan a la vez (ambos corriendo hacia él desde lados opuestos) podía
	# "atravesar" a uno de los dos: el motor de físicas, sin detección
	# continua, a veces no encuentra una posición válida sin solaparse contra
	# ambos cuerpos cinemáticos a la vez y deja pasar el balón de largo en su
	# lugar.
	continuous_cd = RigidBody2D.CCD_MODE_CAST_SHAPE
	collision_layer = 2
	# mundo y (bit 8) el tope diagonal del fondo de la red -mismo hitbox
	# contra el que choca el cabezudo, ver match.gd GOAL_BACKSTOP_LAYER/
	# _add_goal_backstop-: antes el balón atravesaba la red sin chocar porque
	# esa capa era solo para cabezudos.
	#
	# SIN el bit 4 (cabezudos) a propósito: dejar que el motor de físicas
	# resuelva el choque balón-cabeza como colisión física normal (rebote
	# elástico, bounce=0.78) SUMABA su propio impulso al del cabeceo
	# programado en head.gd (_header_cooldown), y los dos a la vez daban un
	# empujón desproporcionado en el primer contacto -bug reportado: "cuando
	# contacto la bola de frente sin dar patada a veces va hacia arriba o
	# actúa raro"-. El contacto con la cabeza se sigue detectando aparte, por
	# proximidad (igual que el cabeceo en sí, ver head.gd), así que el sonido
	# de golpeo sigue sonando igual -ver _on_ball_contact llamado desde ahí
	# en vez de desde touched_by_head/body_entered-.
	collision_mask = 1 | 8
	var mat := PhysicsMaterial.new()
	mat.bounce = BASE_BOUNCE
	mat.friction = 0.4
	physics_material_override = mat
	_shape = CircleShape2D.new()
	_shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	add_child(cs)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("goal_post"):
		touched_post.emit()
	elif body.is_in_group("goal_backstop_left"):
		touched_goal_net.emit(true)
	elif body.is_in_group("goal_backstop_right"):
		touched_goal_net.emit(false)

func set_radius(r: float) -> void:
	radius = r
	_shape.radius = r
	queue_redraw()

func set_bounciness(b: float) -> void:
	physics_material_override.bounce = b

func reset_at(pos: Vector2) -> void:
	freeze = true
	global_position = pos
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = false
	sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if state.linear_velocity.length() > MAX_SPEED:
		state.linear_velocity = state.linear_velocity.normalized() * MAX_SPEED

func _draw() -> void:
	BallStyles.draw_ball(self, GameState.ball_style, radius)

func _process(_delta: float) -> void:
	queue_redraw()
