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
## Antes 42 (100%): 80% del tamaño original, en sintonía con la pelota
## (Ball.BASE_RADIUS) y las porterías (match.gd/field_art.gd FLOOR_Y,
## CROSSBAR_Y, GOAL_W) más pequeñas, dejando hueco abajo en pantalla para
## agrandar los controles táctiles.
const RADIUS := 33.6
## Antes 1.35 (100%): la escala del pie/bota no dependía de RADIUS, así que al
## encoger la cabeza un 20% hacía falta encogerla también a mano para que
## siga en proporción (1.35 * 0.8).
const FOOT_SCALE := 1.08

## Ajustes de la IA por nivel de dificultad.
## speed_mult SIEMPRE a tope (1.0, la misma velocidad que el jugador) en los
## tres niveles a propósito -antes "facil"/"media" corrían más lento, pero
## eso se sentía como un hándicap artificial ("se mueve como a cámara lenta")
## en vez de una IA peor de verdad. Lo único que cambia entre niveles es
## reaction_min/var (cuánto tarda en darse cuenta de hacia dónde hay que ir,
## ver _cpu_think) y predict (cuánto anticipa hacia dónde va el balón según su
## velocidad): así en fácil llega tarde y mal colocada aunque corra a la
## misma velocidad que tú, y en difícil llega igual de rápido pero antes y
## mejor situada -diferencia de habilidad, no de físico-. jump_chance y
## kick_chance se dejan iguales en los tres para no mezclar un segundo eje de
## dificultad aparte. "dificil" se baja un poco también (antes 0.08/0.08/0.12)
## para que los tres niveles sean divertidos según la habilidad de cada
## jugador, no solo el más flojo.
const CPU_DIFFICULTY := {
	"facil": {
		"speed_mult": 1.0,
		"reaction_min": 0.30,
		"reaction_var": 0.22,
		"predict": 0.0,
		"jump_chance": 0.45,
		"kick_chance": 0.42,
	},
	"media": {
		"speed_mult": 1.0,
		"reaction_min": 0.18,
		"reaction_var": 0.14,
		"predict": 0.05,
		"jump_chance": 0.45,
		"kick_chance": 0.42,
	},
	"dificil": {
		"speed_mult": 1.0,
		"reaction_min": 0.10,
		"reaction_var": 0.10,
		"predict": 0.10,
		"jump_chance": 0.45,
		"kick_chance": 0.42,
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
## Bloqueo por recibir 3 patadas seguidas del rival (ver _check_kick_hit_rival):
## mismo bloqueo de input que "frozen" (reutiliza esa rama en _physics_process),
## pero con tinte rojo en vez de azul.
var stunned := false
var _stun_timer := 0.0
const STUN_HITS := 3
const STUN_DURATION := 3.0
## Las 3 patadas tienen que conectar en menos de este tiempo entre una y la
## siguiente; si se tarda más, la racha se corta (ver _check_kick_hit_rival).
const STREAK_WINDOW := 5.0
var _kick_hit_streak := 0
var _streak_timer := 0.0
## Cooldown propio del gesto de chutar (anim + _check_kick_hit_rival), aparte
## de _kick_cooldown (que solo se activa si el chut conecta con el balón, ver
## _try_kick): sin esto, la IA -que reevalúa "quiero chutar" cada frame de
## física, a diferencia del humano (is_action_just_pressed, una vez por
## pulsación)- repetía el gesto y la comprobación de impacto en cada frame
## mientras el balón no conectara, acumulando sin querer 3 golpes "seguidos"
## en lo que parecía una sola patada.
const GESTURE_COOLDOWN := 0.35
var _gesture_cooldown := 0.0
## El otro cabezudo de la partida, asignado por match.gd tras crear ambos (ver
## _build_actors): usado para el empuje al chocar (match.gd
## _resolve_head_collision) y para detectar patadas que conectan
## (_check_kick_hit_rival).
var rival: Head = null
## Tinte de integración con el escenario (match.gd), para que el cabezudo se
## vea iluminado por la misma luz que el fondo. Se guarda aparte de
## "modulate" porque _physics_process ya usa modulate para el efecto de
## congelado; así se combinan en vez de pisarse.
var tint := Color(1, 1, 1)
## Power-ups repartidos al empezar la parte (hasta 3, ver
## match.gd POWERUPS_PER_HALF): el array NUNCA se vacía ni se acorta al
## usarlos -antes sí, y por eso el hueco "desaparecía" en vez de quedarse
## marcado como usado-, así que held_powerups[i] siempre dice qué power-up
## era ese hueco, se haya usado o no. Ver used_powerups para saber cuáles ya
## se gastaron.
var held_powerups: Array = []
## Un bool por hueco de held_powerups, en el mismo índice: true si ya se
## activó. El humano los guarda y los activa cuando quiere con el botón de
## usar; la IA los gasta sola en momentos aleatorios.
var used_powerups: Array = []
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
var _punch_audio: AudioStreamPlayer
var _ball_hit_audio: AudioStreamPlayer
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
	# Sin el bit 4 (otros cabezudos) en la máscara: dejar que move_and_slide
	# resuelva la colisión entre dos CharacterBody2D independientes "reventaba"
	# la superposición y uno salía disparado verticalmente. El choque entre
	# cabezudos se resuelve a mano en match.gd _resolve_head_collision (solo
	# posición, sin tocar velocidad), enganchado a physics_frame para correr
	# después de que ambos cabezudos ya se hayan movido este frame -si cada
	# Head se separase a sí mismo en su propio _physics_process, el padre
	# (Match) procesa antes que los hijos y cada empuje usaría la posición del
	# rival un frame antigua, dejando un solape estable bajo presión constante
	# (p. ej. la IA persiguiendo el balón a través del rival) en vez de
	# separarlos del todo.
	# Tampoco colisiona físicamente con el balón (bit 2): al empujarlo de
	# frente, move_and_slide lo trataba como una rampa curva y "trepaba" por
	# él, dando un salto involuntario al driblar. El contacto con el balón
	# se detecta aparte, por proximidad, sólo para el cabeceo.
	# Bit 8: tramo diagonal del fondo de la red (GOAL_BACKSTOP_LAYER), que
	# también lleva el balón (choca con ella igual que el cabezudo). Bit 16:
	# extensión vertical sin límite de altura por encima de ese tramo
	# (GOAL_JUMP_WALL_LAYER), que evita saltar por encima estando ya dentro
	# de la portería -el balón NO la lleva, ver ball.gd y el comentario de
	# GOAL_JUMP_WALL_LAYER en match.gd-.
	collision_mask = 1 | 8 | 16
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
	_foot.scale = Vector2(facing * FOOT_SCALE, FOOT_SCALE)
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

	_punch_audio = AudioStreamPlayer.new()
	_punch_audio.stream = load("res://audio/punch.ogg")
	add_child(_punch_audio)

	_ball_hit_audio = AudioStreamPlayer.new()
	_ball_hit_audio.stream = load("res://audio/golpeopelota.ogg")
	add_child(_ball_hit_audio)

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
	_foot.scale = Vector2(facing * FOOT_SCALE, FOOT_SCALE)

func _physics_process(delta: float) -> void:
	_kick_cooldown = maxf(0.0, _kick_cooldown - delta)
	_gesture_cooldown = maxf(0.0, _gesture_cooldown - delta)
	_sound_cooldown = maxf(0.0, _sound_cooldown - delta)
	_header_cooldown = maxf(0.0, _header_cooldown - delta)
	if stunned:
		_stun_timer -= delta
		if _stun_timer <= 0.0:
			stunned = false
	if _kick_hit_streak > 0:
		_streak_timer -= delta
		if _streak_timer <= 0.0:
			_kick_hit_streak = 0
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
	# "stunned" (3 patadas seguidas, ver start_stun) es aparte del sistema de
	# power-ups de match.gd -no pasa por RPC-, así que su tinte sí se sigue
	# fijando aquí, localmente.
	if stunned:
		modulate = tint * Color(1.25, 0.7, 0.7)
	elif not frozen:
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

	# Empuje al balón por proximidad (sin colisión física entre cabeza y
	# balón, ver ball.gd collision_mask): con cooldown para no acumular
	# impulso mientras dura el contacto.
	if _header_cooldown <= 0.0 and _ball != null:
		var to_ball := _ball.global_position - global_position
		var dist := to_ball.length()
		# Si el rival TAMBIÉN está a la vez al alcance del balón, es un
		# apretón de verdad (los dos tocándolo o arrastrándolo juntos) y de
		# eso ya se encarga aparte match.gd (_resolve_ball_tunnel, con su
		# propio escape hacia arriba acorde a la velocidad de cierre): si
		# aquí CADA cabezudo aplicara además su propio empujón individual,
		# los dos empujones se pisaban entre sí y el resultado era errático
		# -daba pie al balón "atravesando" a uno de los dos en el forcejeo-.
		var rival_also_in_range := rival != null and rival.global_position.distance_to(_ball.global_position) < RADIUS + _ball.radius - 2.0
		if dist < RADIUS + _ball.radius - 2.0 and not rival_also_in_range:
			_header_cooldown = 0.12
			# Empuje SIEMPRE hacia fuera de la cabeza (dirección real hacia
			# el balón), no fijo a "facing": si no, un balón que llega rápido
			# de frente en la MISMA dirección hacia la que mira el cabezudo
			# solo sumaba velocidad en vez de rebotar, y el balón terminaba
			# atravesando al cabezudo sin más -bug reportado: "atraviesa mi
			# jugador la pelota y no la impacta"-. Con un poco de arriba para
			# que se sienta a cabezazo y no un choque plano, y con fuerza
			# acorde a lo rápido que venga el balón (suave si viene despacio,
			# fuerte si viene disparado) en vez de un empuje siempre igual.
			# Solo el lado horizontal real (no el vertical, que varía con
			# cada bote del balón y daba empujes demasiado desiguales de un
			# frame a otro, dejando a veces muy poca separación horizontal
			# -dejaba alcanzar y atravesar al cabezudo que se acercaba-).
			#
			# El hitbox es el mismo círculo (RADIUS) en toda la cabeza -no hay
			# ninguna zona con una forma de contacto distinta-, pero antes esta
			# línea sí que reaccionaba distinto según la zona: usaba signf(x),
			# que da +1 o -1 en seco en cuanto to_ball.x cruza 0. Un balón que
			# cae casi justo encima (arriba/coronilla) tiene to_ball.x
			# oscilando muy cerca de 0 de un frame a otro por el propio rebote
			# redondo de la cabeza, así que signf() lo mandaba entero a un lado
			# y al frame siguiente entero al otro -bug reportado: "por la parte
			# de arriba... rebota raro"-. clampf en vez de signf da un empuje
			# horizontal que crece poco a poco según el balón se aparta del
			# centro, en vez de invertirse de golpe: cerca de la coronilla sale
			# casi recto hacia arriba (cabezazo de verdad) y solo se inclina
			# del todo a un lado cuando el contacto ya es realmente lateral.
			var away := Vector2(clampf(to_ball.x / RADIUS, -1.0, 1.0), 0.0)
			var header_dir := (away + Vector2(0.0, -0.5)).normalized()
			var incoming := maxf(0.0, -_ball.linear_velocity.dot(away))
			var push_speed := clampf(230.0 + incoming * 0.6, 230.0, 520.0)
			# Solo suma la carrera del cabezudo si va en la MISMA dirección
			# que el empuje: si no, cuando el balón toca por detrás (pelo,
			# nuca -no la cara- mientras el cabezudo corre hacia delante, en
			# dirección contraria a "away"), esta carry restaba en vez de
			# sumar y el empujón salía flojo/errático solo en esa zona
			# -bug reportado: "en el pelo y la parte de atrás actúa raro,
			# como que no rebota igual"-.
			var carry := away * maxf(0.0, velocity.x * away.x) * 0.3
			_ball.apply_central_impulse((header_dir * push_speed + carry).limit_length(560.0))
			# Antes esto llegaba por la señal touched_by_head del balón (su
			# propia colisión física nativa con la cabeza, ver body_entered en
			# ball.gd), que ya no existe: el sonido de golpeo se dispara aquí
			# directamente, en el mismo punto que ya decide "hay contacto".
			_on_ball_contact()

	if wants_kick:
		# El pie se mueve SIEMPRE que se pulsa chutar (si no está en cooldown
		# de un chut anterior), aunque el balón no esté al alcance todavía:
		# si el gesto de chutar no diera nunca ninguna respuesta visible
		# cuando el balón está lejos, el botón se siente "roto" (justo lo que
		# se reportó: "solo funciona si el balón está cerca"). El impacto
		# real sobre el balón sigue exigiendo alcance, ver _try_kick.
		if _gesture_cooldown <= 0.0:
			_gesture_cooldown = GESTURE_COOLDOWN
			_play_kick_anim()
			kicked.emit()
			_check_kick_hit_rival()
		_kick_buffer = KICK_BUFFER_TIME
		_kick_buffer_high = wants_jump or touch_high
	if _kick_buffer > 0.0:
		_kick_buffer -= delta
		if _try_kick(_kick_buffer_high):
			_kick_buffer = 0.0

	if wants_use and used_powerups.has(false) and _match != null:
		_match.activate_powerup(self)

func _play_kick_anim() -> void:
	var tw := create_tween()
	tw.tween_property(_foot_pivot, "rotation", deg_to_rad(-100.0) * facing, 0.08)
	tw.tween_property(_foot_pivot, "rotation", 0.0, 0.18)

## Detecta si la patada que se acaba de lanzar conecta con el rival (igual de
## alcance/orientación que _try_kick con el balón, pero contra su cuerpo). Un
## golpe que no llega a conectar corta la racha, igual que tardar más de
## STREAK_WINDOW en conectar el siguiente; 3 conectados a tiempo dejan al
## rival bloqueado (ver start_stun). Esto es aparte del empuje de match.gd
## _resolve_head_collision: los choques normales (sin chutar) no cuentan
## como patada.
func _check_kick_hit_rival() -> void:
	if rival == null:
		return
	var to_rival := rival.global_position - global_position
	var reach := RADIUS * 2.0 + 20.0
	if to_rival.length() < reach and to_rival.x * facing > -10.0:
		_kick_hit_streak += 1
		_streak_timer = STREAK_WINDOW
		rival.receive_kick_hit()
		if _kick_hit_streak >= STUN_HITS:
			_kick_hit_streak = 0
			rival.start_stun()
	else:
		_kick_hit_streak = 0

## Impacto de una patada rival que conecta: vibra la cara y suena el golpe.
## El bloqueo en sí (start_stun) es un paso aparte, solo a la 3ª seguida.
func receive_kick_hit() -> void:
	_punch_audio.play()
	var tw := create_tween()
	for i in 3:
		var offset := Vector2(randf_range(-11.0, 11.0), randf_range(-11.0, 11.0))
		tw.tween_property(_face_sprite, "position", offset, 0.03)
	tw.tween_property(_face_sprite, "position", Vector2.ZERO, 0.03)

## Bloqueo por 3 patadas seguidas del rival: mismo bloqueo de input que el
## power-up de congelar (ver "frozen" en _physics_process), tinte rojo en vez
## de azul, y con su propia duración fija (no depende de match.gd).
func start_stun() -> void:
	stunned = true
	_stun_timer = STUN_DURATION

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
		_ball_hit_audio.play()
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
	_ball_hit_audio.play()

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
