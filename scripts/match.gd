extends Node2D
## Escena del partido: campo, balón, cabezudos, porterías, power-ups y HUD.

const W := 1280.0
const H := 720.0
const FLOOR_Y := 640.0
const GOAL_W := 100.0     # profundidad de la portería desde la pared (igual de ancha)
const CROSSBAR_Y := 405.0 # altura del larguero (misma anchura, ~1.8x más alta)

const P1_SPAWN := Vector2(320, FLOOR_Y - Head.RADIUS)
const P2_SPAWN := Vector2(W - 320, FLOOR_Y - Head.RADIUS)
const BALL_SPAWN := Vector2(W / 2.0, 220)

var ball: Ball
var p1_head: Head
var p2_head: Head
var p1_score := 0
var p2_score := 0
var time_left := 90.0
var sudden_death := false
var play_locked := false
var kick_mult := 1.0
var halftime_done := false
var in_halftime := false
var paused := false
var p1_defends_left := true
## Servidor: peer ids que ya confirmaron tener montada su propia copia de
## match.tscn (ver _rpc_client_match_ready), para no crear ball/heads (y
## arrancar así la réplica) hasta que ambos puedan recibirla.
var _ready_peer_ids: Dictionary = {}
## Servidor: true si un peer se ha ido antes de que la partida terminase
## normalmente (durante la espera de escena o a media partida). Corta la
## espera/el juego y devuelve el proceso al lobby (ver _on_peer_left) en vez
## de quedarse colgado hasta que alguien reinicie el proceso a mano.
var _match_aborted := false

var _effects: Dictionary = {}  # clave -> {time, node}
var _hud: CanvasLayer
var _score_label: Label
var _time_label: Label
## Botones/insignias del HUD: siempre relativos a "quién soy yo" en este
## peer, no a p1/p2 fijos -en online cualquiera de los dos puede ser el
## humano local de cada cliente-, ver _my_head()/_rival_head().
var _my_powerup_buttons: Array[Button] = []
var _rival_powerup_labels: Array[Label] = []
## Power-ups ya usados y todavía surtiendo efecto, por lado ("p1"/"p2") y
## hueco (índice igual al de _my_powerup_buttons cuando el lado es el mío):
## null si ese hueco no tiene nada activo ahora mismo. Independiente de
## held_powerups (que solo guarda lo NO usado aún): al activarse un hueco, el
## tipo se quita de held_powerups pero se guarda aquí con su duración para
## poder dibujar la cuenta atrás en el propio botón (ver _draw_powerup_clock).
## Se trackean los dos lados (no solo "el mío") porque en el servidor de una
## partida online la activación de cualquiera de los dos jugadores pasa por
## aquí; cada cliente solo dibuja el reloj de su propio lado.
var _active_powerup: Dictionary = {"p1": [null, null], "p2": [null, null]}
var _announce_label: Label
var _announce_time := 0.0
var _center_label: Label
var _end_panel: Control
var _halftime_panel: Control
var _halftime_player: AudioStreamPlayer
var _pause_panel: Control
var _pause_btn: Button
var _pause_audio: AudioStreamPlayer
var _p1_spawn := P1_SPAWN
var _p2_spawn := P2_SPAWN
var _fx: AudioStreamPlayer
var _crowd_audio: AudioStreamPlayer
var _goal_ovation: AudioStreamPlayer
var _countdown_audio: AudioStreamPlayer
var _post_audio: AudioStreamPlayer
var _post_sound_cooldown := 0.0
var _field_art: FieldArt
var _goal_front: GoalFront
## Tinte compartido con las porterías (mismo color de luz ambiente), pero
## mezclado más suave: balón y cabezudos deben seguir leyéndose bien de un
## vistazo aunque el escenario sea una foto oscura o muy saturada.
var _actor_tint := Color(1, 1, 1)
var _goal_shapes: Dictionary = {}      # "left"/"right" -> RectangleShape2D
var _goal_base_sizes: Dictionary = {}  # "left"/"right" -> Vector2 (tamaño normal)

# Controles táctiles: izquierda/derecha a la izquierda de la pantalla; a la
# derecha, disparo elevado y salto.
var _btn_left: TouchScreenButton
var _btn_right: TouchScreenButton
var _btn_kick_high: TouchScreenButton
var _btn_jump: TouchScreenButton
var _touch_state := {"dir": 0.0, "jump": false, "kick_high": false}
var _kick_high_was_pressed := false

func _ready() -> void:
	randomize()
	GameState.stop_menu_music()
	time_left = GameState.match_duration
	if GameState.p1.is_empty():
		GameState.p1 = PlayerDB.players[0]
	if GameState.p2.is_empty():
		GameState.p2 = PlayerDB.random_player(GameState.p1.id)
	_build_field()
	# Online: el servidor espera a que ambos clientes confirmen que ya
	# montaron su propia copia de la escena antes de crear ball/p1_head/
	# p2_head (y con ellos, los MultiplayerSynchronizer que empiezan a
	# replicar cada physics tick, sin más gate posible una vez existen). Si
	# el servidor los creara ya y algún cliente aún no tiene el nodo
	# equivalente, esos primeros paquetes de réplica se pierden y el
	# synchronizer se queda desincronizado el resto de la partida -no hay
	# reintento automático-.
	if Net.is_online() and Net.is_server():
		Net.peer_left.connect(_on_peer_left)
		while _ready_peer_ids.size() < 2 and not _match_aborted:
			await get_tree().create_timer(0.1).timeout
		if _match_aborted:
			return
	_build_actors()
	if Net.is_online() and not Net.is_server():
		rpc_id(1, "_rpc_client_match_ready")
	_build_hud()
	_build_touch_controls()
	_fx = AudioStreamPlayer.new()
	_fx.stream = SoundFactory.powerup_sound()
	add_child(_fx)

	# Ambiente de público de fondo durante todo el partido (descansos
	# incluidos, como en un estadio de verdad), bastante más bajo que el
	# resto de sonidos para no competir con golpeos/goles/anuncios.
	# -18dB +15% (-16.79) +45% (-13.56) +35% más (+20*log10(1.35) ≈ 2.61dB) = -10.95dB.
	var crowd_stream: AudioStream = load("res://audio/footballcroud.ogg")
	crowd_stream.loop = true
	_crowd_audio = AudioStreamPlayer.new()
	_crowd_audio.stream = crowd_stream
	_crowd_audio.volume_db = -10.95
	add_child(_crowd_audio)
	_crowd_audio.play()

	# Ovación de gol (recorte de goal.mp3, 5s con fundido de entrada/salida):
	# más baja que la voz propia de cada jugador al marcar (0dB, ver
	# play_goal_sound), un poco más alta que el público de fondo.
	# -9dB +15% (-7.79) +45% (-4.56) +35% más (+20*log10(1.35) ≈ 2.61dB) = -1.95dB.
	_goal_ovation = AudioStreamPlayer.new()
	_goal_ovation.stream = load("res://audio/goal_ovacion.ogg")
	_goal_ovation.volume_db = -1.95
	add_child(_goal_ovation)

	_countdown_audio = AudioStreamPlayer.new()
	add_child(_countdown_audio)

	_post_audio = AudioStreamPlayer.new()
	_post_audio.stream = load("res://audio/porteria.ogg")
	add_child(_post_audio)

	_pause_audio = AudioStreamPlayer.new()
	add_child(_pause_audio)

	_grant_powerups()
	_countdown_kickoff()

# ---------------- Construcción ----------------

func _build_field() -> void:
	var f := FieldDB.get_field(GameState.field_id)
	var night: bool = f.get("kind", "day") == "night"
	_actor_tint = FieldArt.compute_actor_tint(f, night)

	var art := FieldArt.new()
	art.setup(f)
	art.z_index = -10
	add_child(art)
	_field_art = art
	# Poste cercano en capa aparte, por delante del balón (z_index 0) y las
	# cabezas: así el balón se ve entrar "detrás" del poste en vez de quedar
	# siempre por encima al marcar.
	var goal_front := GoalFront.new()
	goal_front.setup(f)
	goal_front.z_index = 1
	add_child(goal_front)
	_goal_front = goal_front
	_add_static_box(Rect2(-60, FLOOR_Y, W + 120, 120))          # suelo
	_add_static_box(Rect2(-60, -300, 60, H + 300))               # pared izq
	_add_static_box(Rect2(W, -300, 60, H + 300))                 # pared dcha
	_add_static_box(Rect2(-60, -300, W + 120, 60))               # techo
	_add_static_box(Rect2(0, CROSSBAR_Y - 12, GOAL_W, 12), true)       # larguero izq
	_add_static_box(Rect2(W - GOAL_W, CROSSBAR_Y - 12, GOAL_W, 12), true)  # larguero dcho
	_add_goal_sensor(Rect2(0, CROSSBAR_Y, 48, FLOOR_Y - CROSSBAR_Y), true)
	_add_goal_sensor(Rect2(W - 48, CROSSBAR_Y, 48, FLOOR_Y - CROSSBAR_Y), false)

## "is_post": marca los tramos de larguero (único elemento del marco de la
## portería con colisión física real; los postes verticales son solo
## dibujo, ver goal_front.gd) con el grupo "goal_post" para que Ball los
## distinga de suelo/paredes y avise con la señal touched_post (ver
## _on_body_entered en ball.gd) al sonar el "clang" de palo.
func _add_static_box(rect: Rect2, is_post: bool = false) -> void:
	var body := StaticBody2D.new()
	body.collision_layer = 1
	if is_post:
		body.add_to_group("goal_post")
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	body.position = rect.position + rect.size / 2.0
	body.add_child(cs)
	add_child(body)

func _add_goal_sensor(rect: Rect2, is_left: bool) -> void:
	var area := Area2D.new()
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := RectangleShape2D.new()
	shape.size = rect.size
	var cs := CollisionShape2D.new()
	cs.shape = shape
	area.position = rect.position + rect.size / 2.0
	area.add_child(cs)
	area.body_entered.connect(func(body): _on_goal(body, is_left))
	add_child(area)
	var key := "left" if is_left else "right"
	_goal_shapes[key] = shape
	_goal_base_sizes[key] = rect.size

func _build_actors() -> void:
	ball = Ball.new()
	ball.position = BALL_SPAWN
	ball.modulate = _actor_tint
	# Nombre fijo (por defecto Godot los numeraría "Ball", "Head", "Head2"...
	# igual en todos los peers ya que se crean en el mismo orden, pero fijarlo
	# a mano deja los NodePath del MultiplayerSynchronizer a prueba de
	# cualquier cambio futuro en ese orden).
	ball.name = "Ball"
	add_child(ball)
	# Solo en servidor/offline: en un cliente online la física del balón está
	# congelada (puro muñeco de red, ver _setup_online_actors) y esta señal
	# no tiene por qué disparar de forma fiable ni sincronizada con lo que ve
	# el rival -el sonido de golpeo en el cliente llega por RPC desde el
	# servidor, ver _apply_ball_contact_sound-.
	if not (Net.is_online() and not Net.is_server()):
		ball.touched_by_head.connect(func(head): head._on_ball_contact())
	ball.touched_post.connect(_on_ball_touched_post)

	p1_head = Head.new()
	p1_head.position = P1_SPAWN
	p1_head.name = "P1Head"
	p1_head.setup(GameState.p1, 1, false, ball, self)
	p1_head.tint = _actor_tint
	add_child(p1_head)

	p2_head = Head.new()
	p2_head.position = P2_SPAWN
	p2_head.name = "P2Head"
	# Online: p2 es un humano remoto, no la IA (ver _setup_online_actors).
	if Net.is_online():
		p2_head.setup(GameState.p2, -1, false, ball, self)
	else:
		p2_head.setup(GameState.p2, -1, true, ball, self, GameState.cpu_difficulty)
	p2_head.tint = _actor_tint
	add_child(p2_head)

	if Net.is_online():
		_setup_online_actors()

## Convierte a ball/p1_head/p2_head en objetos de red: el servidor sigue
## simulando exactamente igual que en local (única autoridad), y replica
## posición a los clientes vía MultiplayerSynchronizer. En el cliente, balón
## y cabezudos pasan a ser "muñecos": nada de física propia, solo dibujan la
## posición que llega por red (si no, competirían con la física local y
## todo iría a tirones).
func _setup_online_actors() -> void:
	_attach_sync(ball, ["global_position", "rotation"])
	_attach_sync(p1_head, ["global_position"])
	_attach_sync(p2_head, ["global_position"])
	if Net.is_server():
		p1_head.is_remote_human = true
		p2_head.is_remote_human = true
		p1_head.kicked.connect(func(): rpc("_apply_kick_anim", "p1"))
		p2_head.kicked.connect(func(): rpc("_apply_kick_anim", "p2"))
		p1_head.ball_contacted.connect(func(): rpc("_apply_ball_contact_sound", "p1"))
		p2_head.ball_contacted.connect(func(): rpc("_apply_ball_contact_sound", "p2"))
	else:
		ball.freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
		ball.freeze = true
		p1_head.set_physics_process(false)
		p2_head.set_physics_process(false)

func _attach_sync(node: Node, props: Array) -> void:
	node.set_multiplayer_authority(1)
	var cfg := SceneReplicationConfig.new()
	for p in props:
		cfg.add_property(NodePath(".:" + p))
	var sync := MultiplayerSynchronizer.new()
	# Nombre fijo a propósito: sin él, Godot le pone uno автоgenerado tipo
	# "@MultiplayerSynchronizer@37" basado en un contador global de nodos sin
	# nombre -que no tiene por qué llevar la cuenta igual en servidor y
	# cliente, ya que cada uno crea nodos distintos antes de este punto (HUD,
	# controles táctiles según is_touch_device, etc.)-. Con un nombre fijo el
	# NodePath ("Match/Ball/Sync"...) es idéntico en todos los peers.
	sync.name = "Sync"
	sync.replication_config = cfg
	node.add_child(sync)

## Reposiciona el balón preservando el "congelado" del cliente (Ball.reset_at
## siempre acaba con freeze=false, pensado para el servidor/modo local; en el
## cliente eso reactivaría su física local y empezaría a pelear con la
## posición que llega por red).
func _reset_ball(pos: Vector2) -> void:
	ball.reset_at(pos)
	if Net.is_online() and not Net.is_server():
		ball.freeze = true

## Replica en un cliente el gesto de chutar de un cabezudo remoto (el
## cliente no corre _physics_process para los cabezudos, así que esa
## animación nunca se dispararía por sí sola, ver _setup_online_actors).
@rpc("authority", "call_remote", "reliable")
func _apply_kick_anim(side: String) -> void:
	var head := p1_head if side == "p1" else p2_head
	head._play_kick_anim()

## Replica en un cliente el sonido de golpeo de un cabezudo remoto (chut
## conectado o cabeceo por proximidad): en el cliente la señal local del
## balón está desconectada a propósito (ver _build_actors), así que sin esto
## nunca sonaría.
@rpc("authority", "call_remote", "reliable")
func _apply_ball_contact_sound(side: String) -> void:
	var head := p1_head if side == "p1" else p2_head
	head.play_contact_sound()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_client_match_ready() -> void:
	_ready_peer_ids[multiplayer.get_remote_sender_id()] = true

## Servidor: un peer se ha desconectado antes de que la partida acabara
## normalmente (a media espera de escena o a media partida). Sin esto el
## proceso del servidor dedicado se queda colgado el resto de su vida (v0
## original: "hay que reiniciarlo a mano"), ignorando en silencio cualquier
## partida nueva -ver _rpc_start_match/_match_started en server_boot.gd-.
func _on_peer_left(_id: int) -> void:
	if play_locked:
		return
	play_locked = true
	_match_aborted = true
	get_tree().change_scene_to_file.call_deferred("res://scenes/server_boot.tscn")

## Mapea el remitente de un RPC de input al cabezudo que controla.
func _head_for_sender() -> Head:
	var side := Net.side_for_peer(multiplayer.get_remote_sender_id())
	if side == "p1":
		return p1_head
	if side == "p2":
		return p2_head
	return null

## Cabezudo del humano que ve ESTE peer: en local siempre p1 (como hasta
## ahora); en online, el lado que el servidor le asignó a este cliente
## (Net.my_side()) -en el propio servidor (dedicado, sin lado) no se usa,
## solo lo consulta cada cliente para pintar su propia HUD.
func _my_head() -> Head:
	if Net.is_online() and Net.my_side() == "p2":
		return p2_head
	return p1_head

func _rival_head() -> Head:
	return p2_head if _my_head() == p1_head else p1_head

func _my_side_key() -> String:
	return "p1" if _my_head() == p1_head else "p2"

@rpc("any_peer", "call_remote", "unreliable_ordered")
func rpc_move_input(dir: float, jump: bool) -> void:
	var head := _head_for_sender()
	if head != null:
		head.net_set_move(dir, jump)

@rpc("any_peer", "call_remote", "reliable")
func rpc_kick_input(high: bool) -> void:
	var head := _head_for_sender()
	if head != null:
		head.net_queue_kick(high)

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	add_child(_hud)

	var top := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.45)
	style.set_corner_radius_all(14)
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	top.add_theme_stylebox_override("panel", style)
	top.anchor_left = 0.5
	top.anchor_right = 0.5
	top.position = Vector2(-260, 10)
	top.custom_minimum_size = Vector2(520, 0)
	_hud.add_child(top)
	var vb := VBoxContainer.new()
	top.add_child(vb)
	_score_label = Label.new()
	_score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score_label.add_theme_font_size_override("font_size", 30)
	vb.add_child(_score_label)

	# Aparte del marcador (no dentro de "top"/"vb"): anclado a todo el ancho
	# de la pantalla con anchor_left/right 0/1, para que quede centrado de
	# verdad en el centro real de la pantalla en cualquier resolución, en vez
	# de heredar el centrado del panel del marcador.
	_time_label = Label.new()
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_time_label.add_theme_font_size_override("font_size", 22)
	_time_label.add_theme_color_override("font_color", Color(1, 0.95, 0.6))
	_time_label.anchor_left = 0.0
	_time_label.anchor_right = 1.0
	_time_label.position.y = 52
	_hud.add_child(_time_label)

	_announce_label = Label.new()
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.add_theme_font_size_override("font_size", 34)
	_announce_label.add_theme_color_override("font_color", Color(1, 0.85, 0.2))
	_announce_label.add_theme_constant_override("outline_size", 10)
	_announce_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_announce_label.anchor_left = 0.0
	_announce_label.anchor_right = 1.0
	_announce_label.position.y = 110
	_hud.add_child(_announce_label)

	_center_label = Label.new()
	_center_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center_label.add_theme_font_size_override("font_size", 90)
	_center_label.add_theme_color_override("font_color", Color.WHITE)
	_center_label.add_theme_constant_override("outline_size", 18)
	_center_label.add_theme_color_override("font_outline_color", Color(0.8, 0.2, 0.1))
	_center_label.anchor_left = 0.0
	_center_label.anchor_right = 1.0
	_center_label.position.y = 260
	_center_label.visible = false
	_hud.add_child(_center_label)

	var menu_btn := Button.new()
	menu_btn.text = "Menú"
	menu_btn.position = Vector2(12, 12)
	menu_btn.add_theme_font_size_override("font_size", 20)
	menu_btn.pressed.connect(func():
		if Net.is_online():
			Net.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	_hud.add_child(menu_btn)

	_pause_btn = Button.new()
	_pause_btn.text = "⏸ Pausa"
	_pause_btn.position = Vector2(90, 12)
	_pause_btn.add_theme_font_size_override("font_size", 20)
	_pause_btn.pressed.connect(_request_pause)
	_hud.add_child(_pause_btn)

	# Power-ups del jugador humano (el mío en este peer: p1 en local siempre,
	# en online el lado que me haya asignado el servidor, ver _my_head()):
	# cada hueco ES el botón (icono del power-up que le tocó, tocarlo lo
	# activa directamente), en pequeño y arriba a la DERECHA -no del mismo
	# tamaño que los controles táctiles: ahí abajo son la acción principal y
	# necesitan ser grandes, aquí son un extra ocasional-, para poder
	# tocarlos con el pulgar derecho (el mismo que ya maneja disparo/salto)
	# sin soltar el movimiento con el izquierdo.
	const POWERUP_BTN_SIZE := 110.0
	const POWERUP_BTN_MARGIN := 12.0
	const POWERUP_BTN_GAP := 10.0
	for i in 2:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(POWERUP_BTN_SIZE, POWERUP_BTN_SIZE)
		btn.anchor_left = 1.0
		btn.anchor_right = 1.0
		# i=1 pegado al borde derecho, i=0 justo a su izquierda.
		var offset_from_edge := 1 - i
		var x := -POWERUP_BTN_MARGIN - POWERUP_BTN_SIZE - offset_from_edge * (POWERUP_BTN_SIZE + POWERUP_BTN_GAP)
		btn.position = Vector2(x, 12)
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 56)
		var idx := i
		btn.pressed.connect(func(): _request_activate_powerup_slot(idx))
		btn.draw.connect(func(): _draw_powerup_clock(btn, idx))
		_hud.add_child(btn)
		_my_powerup_buttons.append(btn)

	# Los del rival (la IA en local, el otro jugador humano en online) son
	# solo informativos, en pequeño arriba a la izquierda (debajo del botón
	# Menú): no hace falta que sean tocables ni que compitan por sitio con
	# los del humano local.
	for i in 2:
		var l2 := _make_powerup_badge()
		l2.position = Vector2(12 + i * 58, 66)
		_hud.add_child(l2)
		_rival_powerup_labels.append(l2)

	_update_score_hud()
	_update_powerup_hud()

func _make_powerup_badge() -> Label:
	var l := Label.new()
	l.custom_minimum_size = Vector2(50, 50)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 28)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.4)
	style.set_corner_radius_all(12)
	style.set_border_width_all(2)
	style.border_color = Color(1, 1, 1, 0.4)
	l.add_theme_stylebox_override("normal", style)
	return l

## Estilo de un hueco-botón de power-up del humano: tarjeta redondeada con
## borde y brillo del color propio del power-up (Powerup.COLORS), o gris
## apagado y desactivado si no hay ninguno en ese hueco.
func _style_powerup_button(btn: Button, color: Color, filled: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.05, 0.55) if filled else Color(0.05, 0.05, 0.05, 0.3)
	sb.set_corner_radius_all(20)
	sb.set_border_width_all(3)
	sb.border_color = color
	if filled:
		sb.shadow_color = Color(color.r, color.g, color.b, 0.5)
		sb.shadow_size = 8
	btn.add_theme_stylebox_override("normal", sb)
	var hov := sb.duplicate()
	hov.bg_color = Color(0.12, 0.12, 0.12, 0.7) if filled else sb.bg_color
	btn.add_theme_stylebox_override("hover", hov)
	btn.add_theme_stylebox_override("pressed", hov)
	# El hueco vacío y el ya-usado-y-activo se ponen "disabled" (no se puede
	# volver a tocar): sin esto, Godot pinta el stylebox "disabled" del tema
	# por defecto en vez del nuestro, que en este proyecto no está definido y
	# queda prácticamente invisible sobre fondos oscuros.
	btn.add_theme_stylebox_override("disabled", sb)
	btn.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.9 if filled else 0.5))

## Cuenta atrás del power-up ya activo en ese hueco, dibujada sobre su
## propio icono como un sector de reloj que va tapando el botón (sin
## números): empieza sin nada oscurecido (recién activado) y el sector
## barre en sentido horario desde las 12 hasta tapar el círculo entero
## cuando el efecto expira, para que se lea de un vistazo cuánto queda.
func _draw_powerup_clock(btn: Button, idx: int) -> void:
	var active = _active_powerup[_my_side_key()][idx]
	if active == null:
		return
	var frac := 1.0 - clampf(active.time_left / active.duration, 0.0, 1.0)
	if frac <= 0.0:
		return
	var center: Vector2 = btn.size / 2.0
	var radius: float = btn.size.x * 0.5 - 4.0
	var start_angle := -PI / 2.0
	var end_angle := start_angle + TAU * frac
	var segs := maxi(2, int(ceil(48 * frac)) + 1)
	var pts := PackedVector2Array()
	pts.append(center)
	for i in segs:
		var t := float(i) / float(segs - 1)
		var ang := lerpf(start_angle, end_angle, t)
		pts.append(center + Vector2(cos(ang), sin(ang)) * radius)
	btn.draw_colored_polygon(pts, Color(0, 0, 0, 0.65))
	if frac < 0.999:
		btn.draw_line(center, center + Vector2(cos(end_angle), sin(end_angle)) * radius,
			Color(1, 1, 1, 0.75), 2.0)

func _update_powerup_hud() -> void:
	var my_head := _my_head()
	var my_active: Array = _active_powerup[_my_side_key()]
	for i in _my_powerup_buttons.size():
		var btn: Button = _my_powerup_buttons[i]
		var active = my_active[i]
		if active != null:
			# Ya usado y todavía activo: se ve igual que "guardado" (mismo
			# icono/color) pero sin poder volver a tocarlo, con la cuenta
			# atrás de _draw_powerup_clock encima.
			btn.text = Powerup.LABELS[active.type]
			btn.disabled = true
			_style_powerup_button(btn, Powerup.COLORS[active.type], true)
		elif i < my_head.held_powerups.size() and my_head.held_powerups[i] != -1:
			var type: int = my_head.held_powerups[i]
			btn.text = Powerup.LABELS[type]
			btn.disabled = false
			_style_powerup_button(btn, Powerup.COLORS[type], true)
		else:
			btn.text = ""
			btn.disabled = true
			_style_powerup_button(btn, Color(1, 1, 1, 0.25), false)
		btn.queue_redraw()
	_fill_powerup_badges(_rival_powerup_labels, _rival_head().held_powerups)

func _fill_powerup_badges(labels: Array[Label], held: Array) -> void:
	for i in labels.size():
		var style: StyleBoxFlat = labels[i].get_theme_stylebox("normal")
		if i < held.size():
			labels[i].text = Powerup.LABELS[held[i]]
			style.border_color = Powerup.COLORS[held[i]]
		else:
			labels[i].text = ""
			style.border_color = Color(1, 1, 1, 0.4)

## Tamaño/márgenes de los controles táctiles, en "dp" de diseño (unidades del
## canvas 1280x720 de match.gd, que Godot reescala entero a la pantalla real
## vía window/stretch/mode=canvas_items): lo más pequeño posible sin dejar de
## ser fácilmente pulsable, con margen de seguridad a los bordes y separación
## uniforme entre todos los botones para que ninguno se monte sobre otro.
##
## IMPORTANTE: los PNG de res://buttons/ son de 180x180 nativos. TouchScreen
## Button no tiene una propiedad de "tamaño"; dibuja la textura a su
## resolución nativa siempre, así que hace falta escalar el propio nodo
## (btn.scale, ver _make_touch_button) para que el dibujo en pantalla mida de
## verdad BTN_SIZE. Sin ese escalado los botones se quedan siempre a 180px
## reales por mucho que se cambie BTN_SIZE aquí, y con centros tan juntos
## como marca BTN_GAP acaban solapándose y saliéndose de la pantalla —tal
## cual el bug reportado.
const BTN_SIZE := 60.0
const BTN_SAFE_MARGIN := 24.0  # margen a los bordes de la pantalla (safe area)
## Hueco entre botones contiguos: bastante más que el tamaño del icono en sí,
## a propósito, para dejar sitio a una zona de toque bien más grande que el
## icono (ver BTN_TOUCH_SCALE) sin que las de dos botones vecinos lleguen a
## tocarse. Con solo 2+2 botones (ya no hay disparo raso) sobra hueco lateral
## de sitio para permitírselo.
const BTN_GAP := 50.0
## La zona de toque real (invisible) mide BTN_SIZE * este factor: más grande
## que el propio icono para que sea fácil acertar sin tener que agrandar el
## dibujo. Con BTN_GAP=50 deja ~20px de margen hasta la zona del vecino.
const BTN_TOUCH_SCALE := 1.5

const BTN_TEXTURES := {
	"left": "res://buttons/boton_izquierda.png",
	"right": "res://buttons/boton_derecha.png",
	"kick_high": "res://buttons/boton_disparoalto.png",
	"up": "res://buttons/boton_salto.png",
}

func _build_touch_controls() -> void:
	if not GameState.is_touch_device():
		return
	var layer := CanvasLayer.new()
	add_child(layer)
	# Tamaño real de la pantalla (no las constantes W/H de diseño): así el
	# layout se recalcula para la resolución/relación de aspecto de cada
	# móvil en vez de asumir siempre 1280x720, y los botones quedan pegados
	# a las esquinas de verdad tanto en pantallas pequeñas como grandes.
	var vp := get_viewport().get_visible_rect().size
	var y := vp.y - BTN_SIZE - BTN_SAFE_MARGIN

	# Grupo izquierdo (mover): esquina inferior izquierda.
	_btn_left = _make_touch_button("left", Vector2(BTN_SAFE_MARGIN, y))
	_btn_right = _make_touch_button("right", Vector2(BTN_SAFE_MARGIN + BTN_SIZE + BTN_GAP, y))

	# Grupo derecho (disparo alto, saltar): esquina inferior derecha,
	# calculado desde el borde derecho real hacia la izquierda.
	var jump_x := vp.x - BTN_SAFE_MARGIN - BTN_SIZE
	var kick_high_x := jump_x - BTN_GAP - BTN_SIZE
	_btn_kick_high = _make_touch_button("kick_high", Vector2(kick_high_x, y))
	_btn_jump = _make_touch_button("up", Vector2(jump_x, y))
	for b in [_btn_left, _btn_right, _btn_kick_high, _btn_jump]:
		layer.add_child(b)

func _make_touch_button(kind: String, pos: Vector2) -> TouchScreenButton:
	var btn := TouchScreenButton.new()
	var tex: Texture2D = load(BTN_TEXTURES[kind])
	btn.texture_normal = tex
	btn.position = pos
	btn.passby_press = true
	# El PNG se dibuja siempre a su resolución nativa (tex.get_width()): para
	# que en pantalla mida BTN_SIZE de verdad hay que escalar el nodo. El
	# shape se define en unidades LOCALES (antes de este escalado, en el
	# mismo espacio que la textura nativa) para que, tras aplicarse el mismo
	# escalado, la zona de toque real en pantalla acabe midiendo BTN_SIZE *
	# BTN_TOUCH_SCALE — bastante más grande que el icono pero sin llegar a
	# tocar la zona del botón vecino (ver BTN_GAP).
	var native_size: float = tex.get_width()
	var base_scale := BTN_SIZE / native_size
	btn.scale = Vector2.ONE * base_scale
	# Feedback de "pulsado": un pelín más grande (+2%) y más claro (+5%), en
	# vez de una textura aparte generada con Image.get_image()/set_pixel en
	# tiempo de ejecución -esa vía dependía de poder leer la textura de
	# vuelta a la CPU, algo que en Android puede fallar según cómo quede
	# comprimida la textura al exportar (aunque en el editor/PC no dé ningún
	# error), y podía dejar el botón a medio construir-. scale/modulate no
	# necesitan leer la imagen, así que funcionan igual en cualquier
	# plataforma.
	btn.pressed.connect(func():
		btn.scale = Vector2.ONE * (base_scale * 1.02)
		btn.modulate = Color(1.05, 1.05, 1.05))
	btn.released.connect(func():
		btn.scale = Vector2.ONE * base_scale
		btn.modulate = Color.WHITE)
	var shape := RectangleShape2D.new()
	shape.size = Vector2.ONE * (native_size * BTN_TOUCH_SCALE)
	btn.shape = shape
	btn.shape_centered = true
	btn.shape_visible = false
	return btn

# ---------------- Bucle ----------------

func _physics_process(_delta: float) -> void:
	# El padre procesa antes que los hijos: preparamos el input táctil aquí
	if _btn_left != null:
		var dir := 0.0
		if _btn_left.is_pressed():
			dir -= 1.0
		if _btn_right.is_pressed():
			dir += 1.0
		var kick_high_pressed := _btn_kick_high.is_pressed()
		_touch_state = {
			"dir": dir,
			"jump": _btn_jump.is_pressed(),
			"kick_high": kick_high_pressed and not _kick_high_was_pressed,
		}
		_kick_high_was_pressed = kick_high_pressed
	if Net.is_online() and not Net.is_server():
		_send_local_input()

func get_touch_input() -> Dictionary:
	return _touch_state

## Cliente online: captura el input propio (teclado/táctil, igual que el
## humano local de siempre) y se lo manda al servidor en vez de aplicarlo a
## un Head local -el propio cabezudo del jugador es, en su pantalla, tan
## "muñeco" como el del rival, ver _setup_online_actors-.
func _send_local_input() -> void:
	var dir := Input.get_axis("move_left", "move_right")
	var wants_jump := Input.is_action_pressed("jump")
	var wants_kick := Input.is_action_just_pressed("kick")
	var touch_high := false
	var t: Dictionary = get_touch_input()
	dir += t.dir
	dir = clampf(dir, -1.0, 1.0)
	wants_jump = wants_jump or t.jump
	if t.kick_high:
		wants_kick = true
		touch_high = true
	rpc_id(1, "rpc_move_input", dir, wants_jump)
	if wants_kick:
		rpc_id(1, "rpc_kick_input", wants_jump or touch_high)
	if Input.is_action_just_pressed("use_powerup"):
		rpc_id(1, "rpc_request_activate_powerup_oldest")

func _process(delta: float) -> void:
	# El servidor suspende _ready() en un await mientras espera a que los dos
	# clientes confirmen la escena (ver el bucle "while _ready_peer_ids.size()
	# < 2" más arriba); durante esa espera el nodo ya está en el árbol y
	# _process se sigue llamando cada frame, pero _build_hud()/_build_actors()
	# todavía no se han ejecutado -_hud, _time_label, ball, etc. son null-.
	# Sin este guard, _update_time_hud() petaba con "Invalid assignment... on
	# a base object of type 'Nil'" en cada frame de esa espera, dejando el
	# proceso del servidor en un estado roto para el resto de partidas.
	if _hud == null:
		return
	_post_sound_cooldown = maxf(0.0, _post_sound_cooldown - delta)
	if _announce_time > 0.0:
		_announce_time -= delta
		if _announce_time <= 0.0:
			_announce_label.text = ""
	if play_locked:
		return
	# Reloj: corre igual en todos los peers (arranca/pausa a la vez en todos
	# porque play_locked se replica como parte de los _apply_* de kickoff/gol/
	# descanso/fin, ver más abajo), así el cliente ve el tiempo bajar sin
	# tener que esperar una foto periódica del servidor.
	if not sudden_death:
		time_left = maxf(0.0, time_left - delta)
	_update_time_hud()
	# Caducidad de efectos: corre igual en todos los peers, mismo motivo que
	# el reloj de arriba -la activación (ver _apply_activate_powerup_slot) ya
	# replicó tipo y duración a todos, así que cada peer puede contar la
	# cuenta atrás y expirar el efecto por su cuenta sin esperar un RPC de
	# "ya expiró" del servidor.
	for key in _effects.keys().duplicate():
		_effects[key].time -= delta
		if _effects[key].time <= 0.0:
			_expire_effect(key)
	# Cuenta atrás de los power-ups ya usados por cualquiera de los dos
	# lados (ver _draw_powerup_clock): cuando se agota, el hueco vuelve a
	# quedar vacío. Solo se redibuja el botón si el lado es el mío en este
	# peer -el rival no tiene reloj visual, solo se le ve el tipo (badge)-.
	for side in _active_powerup.keys():
		var arr: Array = _active_powerup[side]
		for i in arr.size():
			var active = arr[i]
			if active == null:
				continue
			active.time_left -= delta
			if active.time_left <= 0.0:
				arr[i] = null
				_update_powerup_hud()
			if side == _my_side_key():
				_my_powerup_buttons[i].queue_redraw()
	# A partir de aquí, solo decisiones: quién gana el saque de medio tiempo,
	# cuándo se acaba el tiempo... eso lo decide únicamente el servidor (u
	# offline, el propio proceso local); el cliente se entera de todo por
	# RPC, nunca lo calcula por su cuenta.
	if Net.is_online() and not Net.is_server():
		return
	if not sudden_death:
		if not halftime_done and time_left <= GameState.match_duration / 2.0:
			_start_halftime()
			return
		if time_left <= 0.0:
			_on_time_up()

# ---------------- Goles y final ----------------

## "Clang" al golpear el larguero (único tramo de la portería con colisión
## física real, ver _add_static_box/goal_post). Con cooldown propio para que
## un balón que quede rebotando/apoyado en él no dispare el sonido en bucle.
func _on_ball_touched_post() -> void:
	if _post_sound_cooldown > 0.0:
		return
	_post_sound_cooldown = 0.3
	_post_audio.play()

func _on_goal(body: Node, left_goal: bool) -> void:
	if not (body is Ball) or play_locked:
		return
	# Online: el balón congelado del cliente también dispara este sensor por
	# su cuenta (el Area2D detecta el cuerpo aunque lo mueva el synchronizer,
	# no la física local) -si no se corta aquí, cliente y servidor contarían
	# el gol cada uno por su lado-. Solo decide el servidor; el cliente se
	# entera por _apply_goal.
	if Net.is_online() and not Net.is_server():
		return
	# Marca el equipo que ataca esa portería (depende del lado tras el descanso)
	var p1_scored := left_goal != p1_defends_left
	if Net.is_online():
		rpc("_apply_goal", p1_scored)
	else:
		_apply_goal(p1_scored)
	if sudden_death or (time_left <= 0.0):
		_end_match()
		return
	await get_tree().create_timer(1.8).timeout
	_kickoff("")

## Parte "cosmética" de un gol (marcador, sonidos, aviso en pantalla):
## idéntica en el servidor y en cada cliente -en online llega por RPC desde
## _on_goal, ver arriba-, por eso vive separada de la decisión de si el gol
## cuenta o no.
@rpc("authority", "call_local", "reliable")
func _apply_goal(p1_scored: bool) -> void:
	play_locked = true
	if p1_scored:
		p1_score += 1
	else:
		p2_score += 1
	_update_score_hud()
	var scorer_head := p1_head if p1_scored else p2_head
	scorer_head.play_goal_sound()
	_goal_ovation.play()
	_show_center("¡GOOOL de %s!" % scorer_head.player_data.name, 1.6)

## Saque inicial: cuenta atrás 3, 2, 1, ¡A JUGAR! con los cabezudos y el
## balón ya colocados pero el juego bloqueado. Con "intro_msg" (usado al
## empezar la segunda parte) se muestra antes un aviso breve y luego la
## misma cuenta atrás, para que ambos saques se sientan igual.
##
## Online: solo el servidor decide cuándo se saca (entry point con guarda);
## el cuerpo real (_apply_countdown_kickoff) se replica a los clientes por
## RPC para que vean la misma cuenta atrás, ver el patrón general al final
## del archivo.
func _countdown_kickoff(intro_msg: String = "") -> void:
	if Net.is_online() and not Net.is_server():
		return
	if Net.is_online():
		rpc("_apply_countdown_kickoff", intro_msg)
	else:
		_apply_countdown_kickoff(intro_msg)

@rpc("authority", "call_local", "reliable")
func _apply_countdown_kickoff(intro_msg: String = "") -> void:
	play_locked = true
	_clear_effects()
	_reset_ball(BALL_SPAWN)
	p1_head.global_position = _p1_spawn
	p1_head.velocity = Vector2.ZERO
	p2_head.global_position = _p2_spawn
	p2_head.velocity = Vector2.ZERO
	_center_label.visible = true
	if intro_msg != "":
		_center_label.text = intro_msg
		_pop_center_label()
		await get_tree().create_timer(1.3).timeout
	for n in ["3", "2", "1"]:
		_center_label.text = n
		_pop_center_label()
		_countdown_audio.stream = SoundFactory.countdown_tick_sound()
		_countdown_audio.play()
		await get_tree().create_timer(0.7).timeout
	_center_label.text = "¡A JUGAR!"
	_pop_center_label()
	_countdown_audio.stream = load("res://audio/silbato.ogg")
	_countdown_audio.play()
	await get_tree().create_timer(0.9).timeout
	_center_label.visible = false
	play_locked = false

## Saque tras un gol: a diferencia de _countdown_kickoff/_start_halftime,
## NO limpia los power-ups activos -que un power-up siga contando su tiempo
## normal aunque acaben de marcar un gol es el comportamiento pedido-, solo
## coloca de nuevo balón y cabezudos.
func _kickoff(msg: String) -> void:
	if Net.is_online() and not Net.is_server():
		return
	if Net.is_online():
		rpc("_apply_kickoff", msg)
	else:
		_apply_kickoff(msg)

@rpc("authority", "call_local", "reliable")
func _apply_kickoff(msg: String) -> void:
	play_locked = true
	_reset_ball(BALL_SPAWN)
	p1_head.global_position = _p1_spawn
	p1_head.velocity = Vector2.ZERO
	p2_head.global_position = _p2_spawn
	p2_head.velocity = Vector2.ZERO
	if msg != "":
		_show_center(msg, 1.2)
	await get_tree().create_timer(1.0).timeout
	_center_label.visible = false
	play_locked = false

# ---------------- Descanso y cambio de campo ----------------

func _start_halftime() -> void:
	if Net.is_online() and not Net.is_server():
		return
	if Net.is_online():
		rpc("_apply_start_halftime")
		# Sin botón manual de "Segunda parte" online (ver _apply_start_halftime):
		# con dos jugadores remotos no hay un único mando compartido para esa
		# decisión, así que el servidor la toma solo, tras una pausa fija.
		get_tree().create_timer(3.0).timeout.connect(_second_half)
	else:
		_apply_start_halftime()

@rpc("authority", "call_local", "reliable")
func _apply_start_halftime() -> void:
	halftime_done = true
	in_halftime = true
	play_locked = true
	_clear_effects()
	_reset_ball(BALL_SPAWN)
	ball.freeze = true
	# Música del descanso (si el usuario subió una)
	var stream: AudioStream = GameState.halftime_stream()
	if stream != null:
		_halftime_player = AudioStreamPlayer.new()
		_halftime_player.stream = stream
		add_child(_halftime_player)
		_halftime_player.play()
	# Pantalla de descanso
	_halftime_panel = ColorRect.new()
	_halftime_panel.color = Color(0, 0, 0, 0.6)
	_halftime_panel.anchor_right = 1.0
	_halftime_panel.anchor_bottom = 1.0
	_hud.add_child(_halftime_panel)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.position = Vector2(-260, -110)
	vb.custom_minimum_size = Vector2(520, 0)
	vb.add_theme_constant_override("separation", 22)
	_halftime_panel.add_child(vb)
	var title := Label.new()
	title.text = "PITI TIME"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	vb.add_child(title)
	var score := Label.new()
	score.text = "%s  %d - %d  %s" % [GameState.p1.name, p1_score, p2_score, GameState.p2.name]
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 30)
	vb.add_child(score)
	var go := Button.new()
	go.custom_minimum_size = Vector2(0, 84)
	UIStyle.style_cta(go)
	if Net.is_online():
		go.text = "Empezando..."
		go.disabled = true
	else:
		go.text = "▶  Segunda parte"
		go.pressed.connect(_second_half)
	vb.add_child(go)

func _second_half() -> void:
	if Net.is_online() and not Net.is_server():
		return
	if not in_halftime:
		return
	if Net.is_online():
		rpc("_apply_second_half")
	else:
		_apply_second_half()

@rpc("authority", "call_local", "reliable")
func _apply_second_half() -> void:
	in_halftime = false
	if _halftime_player != null:
		_halftime_player.stop()
		_halftime_player.queue_free()
		_halftime_player = null
	if _halftime_panel != null:
		_halftime_panel.queue_free()
		_halftime_panel = null
	_swap_sides()
	# En el cliente el balón se queda congelado (puro muñeco de red, ver
	# _setup_online_actors): _apply_countdown_kickoff más abajo ya se encarga
	# de reafirmarlo tras reposicionarlo con _reset_ball.
	if not (Net.is_online() and not Net.is_server()):
		ball.freeze = false
	_grant_powerups()
	_apply_countdown_kickoff("¡SEGUNDA PARTE!\n¡Cambio de campo!")

func _swap_sides() -> void:
	var tmp := _p1_spawn
	_p1_spawn = _p2_spawn
	_p2_spawn = tmp
	p1_defends_left = not p1_defends_left
	p1_head.set_side(_p1_spawn.x, 1 if _p1_spawn.x < W / 2.0 else -1)
	p2_head.set_side(_p2_spawn.x, 1 if _p2_spawn.x < W / 2.0 else -1)

func _on_time_up() -> void:
	if Net.is_online() and not Net.is_server():
		return
	if p1_score == p2_score:
		if Net.is_online():
			rpc("_apply_sudden_death")
		else:
			_apply_sudden_death()
	else:
		_end_match()

@rpc("authority", "call_local", "reliable")
func _apply_sudden_death() -> void:
	sudden_death = true
	_show_center("¡MUERTE SÚBITA!", 2.0)
	_announce("El próximo gol gana")

func _end_match() -> void:
	if Net.is_online() and not Net.is_server():
		return
	if Net.is_online():
		rpc("_apply_end_match")
	else:
		_apply_end_match()

@rpc("authority", "call_local", "reliable")
func _apply_end_match() -> void:
	play_locked = true
	var msg: String
	if p1_score == p2_score:
		msg = "Empate"
	elif Net.is_online():
		# Cada peer ve el resultado desde su propio lado, no desde el de p1
		# (a diferencia del modo local, donde el humano siempre es p1).
		var i_won := (p1_score > p2_score) == (Net.my_side() == "p1")
		msg = "¡HAS GANADO! 🏆" if i_won else "Has perdido..."
	elif p1_score > p2_score:
		msg = "¡HAS GANADO! 🏆"
	else:
		msg = "Ha ganado %s..." % GameState.p2.name
	_show_end_panel(msg)
	# El servidor dedicado no tiene UI que pulsar: en cuanto termina la
	# partida, vuelve él solo al lobby para poder aceptar la siguiente sin que
	# alguien tenga que reiniciar el proceso a mano (ver server_boot.gd).
	if Net.is_server():
		get_tree().change_scene_to_file.call_deferred("res://scenes/server_boot.tscn")

func _show_end_panel(msg: String) -> void:
	_end_panel = ColorRect.new()
	_end_panel.color = Color(0, 0, 0, 0.65)
	_end_panel.anchor_right = 1.0
	_end_panel.anchor_bottom = 1.0
	_hud.add_child(_end_panel)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.position = Vector2(-220, -140)
	vb.custom_minimum_size = Vector2(440, 0)
	vb.add_theme_constant_override("separation", 18)
	_end_panel.add_child(vb)
	var title := Label.new()
	title.text = msg
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 46)
	vb.add_child(title)
	var score := Label.new()
	score.text = "%s  %d - %d  %s" % [GameState.p1.name, p1_score, p2_score, GameState.p2.name]
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score.add_theme_font_size_override("font_size", 28)
	vb.add_child(score)
	# "Revancha" recarga la escena tal cual, lo que no tiene sentido online
	# (no vuelve a montar la conexión ni el reparto de lados): en ese modo
	# solo queda volver al menú.
	if not Net.is_online():
		var again := Button.new()
		again.text = "🔁  Revancha"
		again.add_theme_font_size_override("font_size", 30)
		again.pressed.connect(func(): get_tree().reload_current_scene())
		vb.add_child(again)
	var menu := Button.new()
	menu.text = "🏠  Menú principal"
	menu.add_theme_font_size_override("font_size", 30)
	menu.pressed.connect(func():
		if Net.is_online():
			Net.stop()
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	vb.add_child(menu)

# ---------------- Pausa ----------------

## Botón de pausa del HUD (local y online). Online: cualquiera de los dos
## puede pedirla, pero solo el servidor decide de verdad y lo replica, igual
## que el resto de transiciones del partido (ver _rpc_request_pause).
func _request_pause() -> void:
	if paused or in_halftime:
		return
	if Net.is_online():
		rpc_id(1, "_rpc_request_pause")
	else:
		_apply_pause()

func _request_resume() -> void:
	if not paused:
		return
	if Net.is_online():
		rpc_id(1, "_rpc_request_resume")
	else:
		_apply_resume()

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_pause() -> void:
	if paused or in_halftime:
		return
	rpc("_apply_pause")

@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_resume() -> void:
	if not paused:
		return
	rpc("_apply_resume")

@rpc("authority", "call_local", "reliable")
func _apply_pause() -> void:
	paused = true
	play_locked = true
	ball.freeze = true
	_pause_btn.visible = false
	_pause_audio.stream = GameState.halftime_stream()
	_pause_audio.play()
	_pause_panel = ColorRect.new()
	_pause_panel.color = Color(0, 0, 0, 0.6)
	_pause_panel.anchor_right = 1.0
	_pause_panel.anchor_bottom = 1.0
	_hud.add_child(_pause_panel)
	var vb := VBoxContainer.new()
	vb.anchor_left = 0.5
	vb.anchor_top = 0.5
	vb.anchor_right = 0.5
	vb.anchor_bottom = 0.5
	vb.position = Vector2(-200, -90)
	vb.custom_minimum_size = Vector2(400, 0)
	vb.add_theme_constant_override("separation", 22)
	_pause_panel.add_child(vb)
	var title := Label.new()
	title.text = "PAUSA"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	vb.add_child(title)
	var resume := Button.new()
	resume.text = "▶  Reanudar"
	resume.custom_minimum_size = Vector2(0, 76)
	UIStyle.style_cta(resume)
	resume.pressed.connect(_request_resume)
	vb.add_child(resume)

@rpc("authority", "call_local", "reliable")
func _apply_resume() -> void:
	paused = false
	play_locked = false
	# El balón del cliente online se queda congelado siempre (puro muñeco de
	# red, ver _setup_online_actors): solo el servidor -o el modo local- lo
	# reactiva de verdad.
	if not (Net.is_online() and not Net.is_server()):
		ball.freeze = false
	_pause_audio.stop()
	_pause_btn.visible = true
	if _pause_panel != null:
		_pause_panel.queue_free()
		_pause_panel = null

# ---------------- Power-ups ----------------

const POWERUP_DURATION := 14.0
const FREEZE_DURATION := 5.0
const POWERUPS_PER_HALF := 2

## Nada de iconos flotando por el campo: al empezar cada tiempo, cada
## jugador recibe de golpe 2 power-ups aleatorios en su casilla (como un
## sorteo de mano). El humano decide cuándo usarlos con el botón de
## power-up; la IA no tiene criterio para elegir el momento, así que se los
## gasta sola en algún punto aleatorio de ese tiempo.
## Función de decisión (patrón igual que _countdown_kickoff/_start_halftime/
## etc.): solo corre en el servidor o en local offline, nunca en un cliente
## online -el sorteo usa randi(), si cada peer lo hiciera por su cuenta cada
## uno acabaría con tipos distintos-. Sortea y replica el resultado real vía
## _apply_grant_powerups.
func _grant_powerups() -> void:
	if Net.is_online() and not Net.is_server():
		return
	var p1_types := _roll_powerup_types()
	var p2_types := _roll_powerup_types()
	if Net.is_online():
		rpc("_apply_grant_powerups", p1_types, p2_types)
	else:
		_apply_grant_powerups(p1_types, p2_types)

func _roll_powerup_types() -> Array:
	var types := []
	for i in POWERUPS_PER_HALF:
		types.append(Powerup.Type.values()[randi() % Powerup.Type.size()])
	return types

@rpc("authority", "call_local", "reliable")
func _apply_grant_powerups(p1_types: Array, p2_types: Array) -> void:
	p1_head.held_powerups = p1_types
	p2_head.held_powerups = p2_types
	if p1_head.is_cpu:
		_schedule_cpu_powerups(p1_head)
	if p2_head.is_cpu:
		_schedule_cpu_powerups(p2_head)
	_active_powerup = {"p1": [null, null], "p2": [null, null]}
	_update_powerup_hud()

func _schedule_cpu_powerups(head: Head) -> void:
	var half_len: float = GameState.match_duration / 2.0
	for i in POWERUPS_PER_HALF:
		var delay := randf_range(4.0, maxf(5.0, half_len - 4.0))
		get_tree().create_timer(delay).timeout.connect(func():
			if not head.held_powerups.is_empty():
				activate_powerup(head)
		)

## Usa el power-up más antiguo que el cabezudo tiene guardado (si tiene
## alguno): lo usa la IA (nunca elige hueco concreto) y también el atajo de
## teclado "usar power-up" del humano local offline (tampoco elige hueco,
## coge el primero disponible; en online ese atajo pasa por
## rpc_request_activate_powerup_oldest más abajo, no por aquí). El humano
## tocando directamente un botón concreto pasa por _activate_powerup_slot
## con el índice de ESE hueco.
func activate_powerup(head: Head) -> void:
	if not head.is_cpu:
		for i in head.held_powerups.size():
			if head.held_powerups[i] != -1:
				_activate_powerup_slot(head, i)
				return
		return
	if head.held_powerups.is_empty():
		return
	var type: int = head.held_powerups.pop_front()
	var rival := p2_head if head == p1_head else p1_head
	_apply_powerup_effect(type, head, rival)

## Activa el power-up de un hueco concreto: valida y decide (patrón igual
## que el resto del archivo -ver _apply_goal etc.-), replicando vía
## _apply_activate_powerup_slot en online. Solo lo usa el humano (el hueco
## solo tiene sentido para sus dos botones tocables): en vez de quitarlo de
## held_powerups (que desplazaría el resto y desalinearía los botones fijos),
## lo marca con -1 ("ya usado, hueco vacío hasta el próximo tiempo") y guarda
## su tipo/duración en _active_powerup para dibujar la cuenta atrás en el
## propio botón (ver _draw_powerup_clock) hasta que el efecto expira.
func _activate_powerup_slot(head: Head, idx: int) -> void:
	if idx < 0 or idx >= head.held_powerups.size():
		return
	if head.held_powerups[idx] == -1:
		return
	var side := "p1" if head == p1_head else "p2"
	if Net.is_online():
		rpc("_apply_activate_powerup_slot", side, idx)
	else:
		_apply_activate_powerup_slot(side, idx)

@rpc("authority", "call_local", "reliable")
func _apply_activate_powerup_slot(side: String, idx: int) -> void:
	var head := p1_head if side == "p1" else p2_head
	if idx < 0 or idx >= head.held_powerups.size():
		return
	var type: int = head.held_powerups[idx]
	if type == -1:
		return
	head.held_powerups[idx] = -1
	var dur := _powerup_duration(type)
	_active_powerup[side][idx] = {"type": type, "duration": dur, "time_left": dur}
	_update_powerup_hud()
	_apply_powerup_effect(type, head, p2_head if head == p1_head else p1_head)

## Pulsación del botón propio de la HUD: en online quien decide de verdad es
## el servidor (ver _activate_powerup_slot), así que el cliente solo pide
## permiso por RPC; offline se aplica directo, igual que siempre.
func _request_activate_powerup_slot(idx: int) -> void:
	if Net.is_online():
		rpc_id(1, "rpc_request_activate_powerup_slot", idx)
	else:
		_activate_powerup_slot(_my_head(), idx)

@rpc("any_peer", "call_remote", "reliable")
func rpc_request_activate_powerup_slot(idx: int) -> void:
	var head := _head_for_sender()
	if head != null:
		_activate_powerup_slot(head, idx)

## Atajo de teclado "usar power-up" de un cliente online, enviado desde
## _send_local_input: el camino de head.gd (wants_use, activate_powerup)
## nunca se ejecuta ahí porque el cliente tiene la física de las cabezas
## desactivada (ver _setup_online_actors), así que hay que capturarlo aparte
## y pedírselo al servidor igual que el resto del input online.
@rpc("any_peer", "call_remote", "reliable")
func rpc_request_activate_powerup_oldest() -> void:
	var head := _head_for_sender()
	if head == null:
		return
	for i in head.held_powerups.size():
		if head.held_powerups[i] != -1:
			_activate_powerup_slot(head, i)
			return

func _powerup_duration(type: Powerup.Type) -> float:
	return FREEZE_DURATION if type == Powerup.Type.FREEZE else POWERUP_DURATION

func _apply_powerup_effect(type: Powerup.Type, who: Head, rival: Head) -> void:
	_fx.play()
	match type:
		Powerup.Type.BIG_BALL:
			ball.set_radius(Ball.BASE_RADIUS * 1.7)
			_set_effect("ball_size", POWERUP_DURATION)
			_announce("¡PELOTA GIGANTE!")
		Powerup.Type.BIG_GOAL:
			# Agranda la portería RIVAL (la que ataca "who"), no la propia:
			# who defiende un lado según p1_defends_left/facing, así que el
			# lado que ataca es el contrario al que defiende.
			var who_defends_left: bool = p1_defends_left if who == p1_head else not p1_defends_left
			var target_left := not who_defends_left
			var side_key := "left" if target_left else "right"
			_set_goal_enlarged(target_left, true)
			_set_effect("goal_enlarge_" + side_key, POWERUP_DURATION)
			_announce("¡Portería agrandada para %s!" % who.player_data.name)
		Powerup.Type.BOUNCY:
			ball.set_bounciness(1.02)
			_set_effect("bouncy", POWERUP_DURATION)
			_announce("¡SÚPER REBOTE!")
		Powerup.Type.LOW_GRAVITY:
			ball.gravity_scale = 0.35
			_set_effect("low_grav", POWERUP_DURATION)
			_announce("¡Gravedad lunar!")
		Powerup.Type.SPEED:
			who.speed_mult = 1.55
			_set_effect("speed", POWERUP_DURATION, who)
			_announce("¡Turbo para %s!" % who.player_data.name)
		Powerup.Type.FREEZE:
			rival.frozen = true
			# El tinte lo fija aquí (no en Head._physics_process) porque en
			# un cliente online las cabezas no corren su propio
			# _physics_process (ver _setup_online_actors): esta función sí
			# llega a todos los peers vía _apply_activate_powerup_slot.
			rival.modulate = rival.tint * Color(0.6, 0.8, 1.4)
			_set_effect("freeze", FREEZE_DURATION, rival)
			_announce("¡%s congelado!" % rival.player_data.name)
		Powerup.Type.SUPER_KICK:
			kick_mult = 1.6
			_set_effect("super_kick", POWERUP_DURATION)
			_announce("¡CHUT BRUTAL!")

const GOAL_ENLARGE_FACTOR := 1.6

## Agranda (o revierte) la portería de un lado: el dibujo (FieldArt +
## GoalFront) crece hacia arriba manteniendo la base anclada al suelo, y el
## sensor de gol crece con ella para que de verdad sea más fácil marcar.
func _set_goal_enlarged(left: bool, enlarged: bool) -> void:
	var factor := GOAL_ENLARGE_FACTOR if enlarged else 1.0
	_field_art.set_goal_scale(left, factor)
	_goal_front.set_goal_scale(left, factor)
	var key := "left" if left else "right"
	var shape: RectangleShape2D = _goal_shapes[key]
	shape.size = _goal_base_sizes[key] * factor

func _set_effect(key: String, duration: float, node: Node = null) -> void:
	if _effects.has(key):
		_expire_effect(key)
	_effects[key] = {"time": duration, "node": node}

func _expire_effect(key: String) -> void:
	var node = _effects[key].node
	_effects.erase(key)
	match key:
		"ball_size":
			ball.set_radius(Ball.BASE_RADIUS)
		"bouncy":
			ball.set_bounciness(Ball.BASE_BOUNCE)
		"low_grav":
			ball.gravity_scale = 1.0
		"speed":
			if node != null:
				node.speed_mult = 1.0
		"freeze":
			if node != null:
				node.frozen = false
				node.modulate = node.tint
		"super_kick":
			kick_mult = 1.0
		"goal_enlarge_left":
			_set_goal_enlarged(true, false)
		"goal_enlarge_right":
			_set_goal_enlarged(false, false)

func _clear_effects() -> void:
	for key in _effects.keys().duplicate():
		_expire_effect(key)

# ---------------- HUD helpers ----------------

func _update_score_hud() -> void:
	_score_label.text = "%s   %d - %d   %s" % [GameState.p1.name, p1_score, p2_score, GameState.p2.name]

func _update_time_hud() -> void:
	if sudden_death:
		_time_label.text = "MUERTE SÚBITA"
	else:
		var m := int(time_left) / 60
		var s := int(time_left) % 60
		_time_label.text = "%d:%02d" % [m, s]

func _announce(text: String) -> void:
	_announce_label.text = text
	_announce_time = 2.2

func _show_center(text: String, duration: float) -> void:
	_center_label.text = text
	_center_label.visible = true
	_pop_center_label()
	var tw := create_tween()
	tw.tween_interval(duration)
	tw.tween_callback(func(): _center_label.visible = false)

## Animación de "pop" (entra pequeño y desvanecido, rebota a tamaño normal):
## para el gol, la cuenta atrás y demás avisos grandes de centro de pantalla.
func _pop_center_label() -> void:
	_center_label.pivot_offset = _center_label.size / 2.0
	_center_label.scale = Vector2(0.4, 0.4)
	_center_label.modulate.a = 0.0
	var tw := create_tween()
	tw.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_center_label, "scale", Vector2(1.12, 1.12), 0.22)
	tw.parallel().tween_property(_center_label, "modulate:a", 1.0, 0.15)
	tw.tween_property(_center_label, "scale", Vector2.ONE, 0.1)
