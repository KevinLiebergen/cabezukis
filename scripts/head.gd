class_name Head
extends CharacterBody2D
## Un cabezudo: cabeza gigante con cara de foto + bota que chuta.
## Controlado por el jugador (teclado/táctil), por la IA, o por un jugador
## remoto en modo online (is_remote_human, ver net_set_move/net_queue_kick).

## Emitida cada vez que el pie hace el gesto de chutar (con balón al alcance
## o no, igual que _play_kick_anim): en modo online el servidor la usa para
## replicar la animación en los clientes, que no corren su propio
## _physics_process (ver match.gd _setup_online_actors).
signal kicked
## Emitida cada vez que suena el golpeo (chut conectado o cabeceo por
## proximidad, ver _on_ball_contact): en modo online solo se dispara de
## verdad en el servidor -_try_kick y el "header" corren dentro de
## _physics_process, desactivado en los clientes-, así que el servidor la
## usa para replicar el sonido a los clientes.
signal ball_contacted

const GRAVITY := 3000.0
const RADIUS := 42.0

## Ajustes de la IA por nivel de dificultad.
const CPU_DIFFICULTY := {
	"facil": {
		"speed_mult": 0.8,
		"reaction_min": 0.16,
		"reaction_var": 0.16,
		"predict": 0.04,
		"jump_chance": 0.32,
		"kick_chance": 0.32,
	},
	"media": {
		"speed_mult": 0.9,
		"reaction_min": 0.12,
		"reaction_var": 0.12,
		"predict": 0.08,
		"jump_chance": 0.44,
		"kick_chance": 0.41,
	},
	"dificil": {
		"speed_mult": 1.0,
		"reaction_min": 0.08,
		"reaction_var": 0.08,
		"predict": 0.12,
		"jump_chance": 0.55,
		"kick_chance": 0.5,
	},
}

var move_speed := 360.0
var jump_speed := -950.0
var kick_power := 1000.0
var facing := 1  # 1 = mira a la derecha (equipo izquierdo)
var is_cpu := false
## Solo relevante en el servidor de una partida online: el input no viene de
## Input/táctil local ni de la IA, sino de net_set_move()/net_queue_kick(),
## alimentados por los RPC de match.gd (rpc_move_input/rpc_kick_input).
var is_remote_human := false
var net_dir := 0.0
var net_jump := false
var _net_kick_queued := false
var _net_kick_high := false
var player_data: Dictionary = {}
var speed_mult := 1.0
var frozen := false
## Tinte de integración con el escenario (match.gd), para que el cabezudo se
## vea iluminado por la misma luz que el fondo. Se guarda aparte de
## "modulate" porque _physics_process ya usa modulate para el efecto de
## congelado; así se combinan en vez de pisarse.
var tint := Color(1, 1, 1)
## Power-ups en mano a la espera de ser usados (hasta 2 por tiempo). El
## humano los guarda y los activa cuando quiere con el botón de usar; la IA
## los gasta sola en momentos aleatorios.
var held_powerups: Array = []
var _cpu_cfg: Dictionary = CPU_DIFFICULTY["dificil"]

var _match: Node = null
var _ball: Ball = null
var _foot_pivot: Node2D
var _foot: Boot
var _face_sprite: Sprite2D
var _kick_cooldown := 0.0
## Ventana de tolerancia tras pulsar chutar: si el balón no está al alcance en
## ese instante exacto, el disparo queda "guardado" este tiempo y se intenta
## cada physics frame hasta que conecte o expire. Así no hace falta acertar
## el pixel/frame exacto para que el chut salga.
const KICK_BUFFER_TIME := 0.2
var _kick_buffer := 0.0
var _kick_buffer_high := false
var _sound_cooldown := 0.0
var _header_cooldown := 0.0
var _home_x := 0.0
var _audio: AudioStreamPlayer
var _fx_audio: AudioStreamPlayer
var _goal_audio: AudioStreamPlayer
var _cpu_timer := 0.0
var _cpu_dir := 0.0
var _cpu_wants_jump := false
var _team_color := Color(0.9, 0.15, 0.15)

func setup(data: Dictionary, face_dir: int, cpu: bool, ball: Ball, match_node: Node, difficulty: String = "dificil") -> void:
	player_data = data
	facing = face_dir
	is_cpu = cpu
	_ball = ball
	_match = match_node
	_team_color = Color(0.9, 0.15, 0.15) if face_dir > 0 else Color(0.15, 0.3, 0.9)
	if is_cpu:
		_cpu_cfg = CPU_DIFFICULTY.get(difficulty, CPU_DIFFICULTY["dificil"])
		move_speed *= _cpu_cfg.speed_mult

## Movimiento continuo recibido por red (servidor de una partida online).
func net_set_move(dir: float, jump: bool) -> void:
	net_dir = dir
	net_jump = jump

## Chut recibido por red: se consume (una vez) en el siguiente _physics_process.
func net_queue_kick(high: bool) -> void:
	_net_kick_queued = true
	_net_kick_high = high

func _ready() -> void:
	_home_x = global_position.x
	collision_layer = 4
	# Sin el bit 4 (otros cabezudos): que dos cabezudos se solapen un poco al
	# disputar el balón no pasaba nada, pero al empujarse como cuerpos
	# cinemáticos independientes a veces "reventaban" la superposición y uno
	# salía disparado verticalmente. Mejor que se puedan cruzar un poco.
	# Tampoco colisiona físicamente con el balón (bit 2): al empujarlo de
	# frente, move_and_slide lo trataba como una rampa curva y "trepaba" por
	# él, dando un salto involuntario al driblar. El contacto con el balón
	# se detecta aparte, por proximidad, sólo para el cabeceo.
	collision_mask = 1
	floor_snap_length = 8.0

	var shape := CircleShape2D.new()
	shape.radius = RADIUS
	var cs := CollisionShape2D.new()
	cs.shape = shape
	add_child(cs)

	# Pie/bota que chuta: se añade ANTES que la cara para que quede detrás de
	# ella (la cara tapa la parte de arriba del pie, como una cabeza real
	# apoyada sobre el pie de apoyo, en vez de quedar el pie suelto debajo).
	_foot_pivot = Node2D.new()
	_foot_pivot.position = Vector2(0, RADIUS * 0.3)
	add_child(_foot_pivot)
	_foot = Boot.new()
	_foot.color = _team_color
	_foot.scale = Vector2(facing * 1.35, 1.35)
	_foot_pivot.add_child(_foot)

	_face_sprite = Sprite2D.new()
	_face_sprite.texture = player_data.face
	_face_sprite.material = FaceUtil.circle_material()
	var tex_w: float = player_data.face.get_width()
	_face_sprite.scale = Vector2.ONE * (RADIUS * 2.0 / tex_w)
	_face_sprite.flip_h = facing < 0
	add_child(_face_sprite)

	_audio = AudioStreamPlayer.new()
	if player_data.audio != null:
		_audio.stream = player_data.audio
	else:
		_audio.stream = SoundFactory.kick_sound()
	add_child(_audio)

	_fx_audio = AudioStreamPlayer.new()
	_fx_audio.stream = SoundFactory.jump_sound()
	_fx_audio.volume_db = -8.0
	add_child(_fx_audio)

	if player_data.get("goal_audio") != null:
		_goal_audio = AudioStreamPlayer.new()
		_goal_audio.stream = player_data.goal_audio
		add_child(_goal_audio)

## Suena al marcar gol este cabezudo (si tiene audio de gol).
func play_goal_sound() -> void:
	if _goal_audio != null:
		_goal_audio.play()

## Cambio de campo en el descanso: nuevo lado y nueva dirección de ataque.
func set_side(home_x: float, dir: int) -> void:
	facing = dir
	_home_x = home_x
	_face_sprite.flip_h = facing < 0
	_foot_pivot.rotation = 0.0
	_foot.scale = Vector2(facing * 1.35, 1.35)

func _physics_process(delta: float) -> void:
	_kick_cooldown = maxf(0.0, _kick_cooldown - delta)
	_sound_cooldown = maxf(0.0, _sound_cooldown - delta)
	_header_cooldown = maxf(0.0, _header_cooldown - delta)
	if _match != null and _match.play_locked:
		velocity = Vector2.ZERO
		return

	var dir := 0.0
	var wants_jump := false
	var wants_kick := false
	var wants_use := false
	# La zona táctil de disparo fuerza la elevación directamente,
	# independientemente de si "saltar" está pulsado (a diferencia del
	# teclado, donde mantener salto + chutar es lo que da el disparo
	# elevado).
	var touch_high := false
	# El tinte de congelado (activo/reset) lo fija match.gd en el momento de
	# la transición (ver _apply_powerup_effect/_expire_effect), replicado vía
	# RPC a todos los peers: en un cliente online esta función nunca corre
	# para las cabezas remotas (set_physics_process(false), ver
	# match.gd _setup_online_actors), así que fijarlo aquí cada frame nunca
	# llegaría a pintarse ahí. Aquí solo queda anular el input mientras dura.
	if not frozen:
		modulate = tint
		if is_cpu:
			_cpu_think(delta)
			dir = _cpu_dir
			wants_jump = _cpu_wants_jump
			wants_kick = _cpu_wants_kick()
		elif is_remote_human:
			dir = net_dir
			wants_jump = net_jump
			if _net_kick_queued:
				wants_kick = true
				touch_high = _net_kick_high
				_net_kick_queued = false
		else:
			dir = Input.get_axis("move_left", "move_right")
			wants_jump = Input.is_action_pressed("jump")
			wants_kick = Input.is_action_just_pressed("kick")
			wants_use = Input.is_action_just_pressed("use_powerup")
			if _match != null:
				var t: Dictionary = _match.get_touch_input()
				dir += t.dir
				dir = clampf(dir, -1.0, 1.0)
				wants_jump = wants_jump or t.jump
				if t.kick_high:
					wants_kick = true
					touch_high = true

	velocity.x = dir * move_speed * speed_mult
	velocity.y += GRAVITY * delta
	if is_on_floor() and wants_jump:
		velocity.y = jump_speed
		_fx_audio.play()
	move_and_slide()

	# Empuje al balón por proximidad (ya no hay colisión física entre cabeza y
	# balón): un cabeceo suave y previsible hacia donde mira el cabezudo, no
	# un rebote caótico. Con cooldown para no acumular impulso mientras dura
	# el contacto, y sin la velocidad vertical del salto (si no, cada cabeceo
	# en el aire salía disparado hacia arriba).
	if _header_cooldown <= 0.0 and _ball != null:
		var dist := global_position.distance_to(_ball.global_position)
		if dist < RADIUS + _ball.radius - 2.0:
			_header_cooldown = 0.12
			var header := Vector2(facing, -0.4).normalized() * 230.0
			var carry := Vector2(velocity.x, 0.0) * 0.3
			_ball.apply_central_impulse((header + carry).limit_length(380.0))

	if wants_kick:
		# El pie se mueve SIEMPRE que se pulsa chutar (si no está en cooldown
		# de un chut anterior), aunque el balón no esté al alcance todavía:
		# si el gesto de chutar no diera nunca ninguna respuesta visible
		# cuando el balón está lejos, el botón se siente "roto" (justo lo que
		# se reportó: "solo funciona si el balón está cerca"). El impacto
		# real sobre el balón sigue exigiendo alcance, ver _try_kick.
		if _kick_cooldown <= 0.0:
			_play_kick_anim()
			kicked.emit()
		_kick_buffer = KICK_BUFFER_TIME
		_kick_buffer_high = wants_jump or touch_high
	if _kick_buffer > 0.0:
		_kick_buffer -= delta
		if _try_kick(_kick_buffer_high):
			_kick_buffer = 0.0

	if wants_use and not held_powerups.is_empty() and _match != null:
		_match.activate_powerup(self)

func _play_kick_anim() -> void:
	var tw := create_tween()
	tw.tween_property(_foot_pivot, "rotation", deg_to_rad(-100.0) * facing, 0.08)
	tw.tween_property(_foot_pivot, "rotation", 0.0, 0.18)

## Con "saltar" pulsado a la vez que el chut sale un disparo alto (para
## picarla por encima del rival); sin él, un disparo raso, rápido y pegado
## al suelo, pensado para tirar a puerta desde lejos. Devuelve true si el
## chut conectó (balón al alcance): así el llamador sabe si debe seguir
## reintentando durante la ventana de tolerancia (ver _kick_buffer) o si ya
## puede darlo por hecho.
func _try_kick(high: bool) -> bool:
	if _kick_cooldown > 0.0:
		return false
	var to_ball := _ball.global_position - global_position
	var reach := RADIUS + _ball.radius + 58.0
	var in_front := to_ball.x * facing > -15.0
	if to_ball.length() < reach and in_front and to_ball.y > -RADIUS:
		_kick_cooldown = 0.45
		var elevation := -1.3 if high else -0.3
		var kick_dir := Vector2(facing, elevation).normalized()
		_ball.apply_central_impulse(kick_dir * kick_power * _match.kick_mult)
		_on_ball_contact()
		return true
	return false

## Llamado también por la señal del balón al chocar con la cabeza.
func _on_ball_contact() -> void:
	if _sound_cooldown <= 0.0:
		_sound_cooldown = 0.35
		_audio.play()
		ball_contacted.emit()

## Reproduce el sonido de golpeo sin pasar por _sound_cooldown: pensado para
## el cliente online al recibir _apply_ball_contact_sound. En el cliente
## _physics_process está desactivado (ver match.gd _setup_online_actors), así
## que _sound_cooldown nunca vuelve a bajar de 0.35 por su cuenta -llamar a
## _on_ball_contact() ahí dejaría sonar el golpeo solo una vez en toda la
## partida-. El ritmo real ya lo decidió el servidor al emitir ball_contacted
## (esa sí respeta el cooldown), aquí solo hay que reproducirlo.
func play_contact_sound() -> void:
	_audio.play()

# ---------------- IA ----------------

func _cpu_think(delta: float) -> void:
	_cpu_timer -= delta
	if _cpu_timer > 0.0:
		return
	_cpu_timer = _cpu_cfg.reaction_min + randf() * _cpu_cfg.reaction_var  # tiempo de reacción
	var bp := _ball.global_position
	var my := global_position
	var defending := (bp.x - _home_x) * facing < 0  # balón detrás de mi posición base
	var target_x: float
	# Persigue el balón salvo que esté muy metido en el rincón del rival
	var chase := (facing < 0 and bp.x > 1280.0 * 0.28) or (facing > 0 and bp.x < 1280.0 * 0.72)
	if chase or absf(bp.x - my.x) < 300.0 or defending:
		# Colocarse ligeramente detrás del balón para golpearlo hacia el rival
		target_x = bp.x - facing * (30.0 + _ball.radius * 0.5)
		# Predicción simple del movimiento del balón
		target_x += _ball.linear_velocity.x * _cpu_cfg.predict
	else:
		target_x = _home_x
	var diff := target_x - my.x
	_cpu_dir = signf(diff) if absf(diff) > 14.0 else 0.0
	# Saltar si el balón está por encima y cerca
	_cpu_wants_jump = false
	if is_on_floor() and bp.y < my.y - 40.0 and absf(bp.x - my.x) < 160.0 and randf() < _cpu_cfg.jump_chance:
		_cpu_wants_jump = true

func _cpu_wants_kick() -> bool:
	var to_ball := _ball.global_position - global_position
	var reach := RADIUS + _ball.radius + 50.0
	if to_ball.length() < reach and to_ball.x * facing > -10.0:
		return randf() < _cpu_cfg.kick_chance
	return false
