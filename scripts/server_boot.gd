extends Node
## Arranque del servidor dedicado headless: abre el puerto ENet indicado por
## --port= (o Net.DEFAULT_PORT) la primera vez, espera a que los dos
## jugadores confirmen "Listo" con su cabezuki elegido (ver
## online_lobby.gd/Net.rpc_player_ready) y arranca la partida él solo.
##
## v0 sin elegir campo/balón entre los dos -eso exigiría su propia pantalla
## de selección sincronizada, dejado para más adelante-, esos van fijos
## (el primer campo bundled, balón "trionda").
##
## Al terminar una partida (fin normal o alguien desconectado a medias, ver
## match.gd: _apply_end_match / _on_peer_left) match.gd recarga esta escena
## para volver a aceptar jugadores sin reiniciar el proceso entero -por eso
## _ready() solo abre el servidor ENet la primera vez (Net.is_online() ya
## sería true en un recarga), si no cada recarga cerraría y volvería a crear
## la conexión, tirando también al peer que hubiera seguido conectado.

const FIELD_BALL_STYLE := "trionda"
const MATCH_DURATION := 60.0

var _match_started := false
var _picks: Dictionary = {}  # peer_id -> char_id ("Listo" confirmado)

func _ready() -> void:
	if not Net.is_online():
		var port := Net.DEFAULT_PORT
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--port="):
				port = a.substr(7).to_int()
		var err := Net.start_server(port)
		if err != OK:
			push_error("No se pudo abrir el servidor en el puerto %d (%s)" % [port, error_string(err)])
			get_tree().quit(1)
			return
		print("Servidor Cabezukis escuchando en el puerto %d (UDP)" % port)
	else:
		print("Lobby listo para la siguiente partida.")
	Net.peer_joined.connect(_on_peer_joined)
	Net.peer_left.connect(_on_peer_left)
	Net.player_ready.connect(_on_player_ready)

func _on_peer_joined(id: int) -> void:
	print("Peer conectado: id=%d lado=%s" % [id, Net.side_for_peer(id)])

func _on_peer_left(id: int) -> void:
	print("Peer desconectado: id=%d" % id)
	_picks.erase(id)

func _on_player_ready(peer_id: int, char_id: String) -> void:
	if _match_started or Net.side_for_peer(peer_id) == "":
		return
	print("Jugador listo: id=%d lado=%s cabezuki=%s" % [peer_id, Net.side_for_peer(peer_id), char_id])
	_picks[peer_id] = char_id
	var p1_peer := Net.peer_for_side("p1")
	var p2_peer := Net.peer_for_side("p2")
	if _picks.has(p1_peer) and _picks.has(p2_peer):
		_start_match(_picks[p1_peer], _picks[p2_peer])

func _start_match(p1_char_id: String, p2_char_id: String) -> void:
	_match_started = true
	GameState.p1 = PlayerDB.get_player(p1_char_id)
	GameState.p2 = PlayerDB.get_player(p2_char_id)
	GameState.field_id = FieldDB.fields[0].id
	GameState.ball_style = FIELD_BALL_STYLE
	GameState.match_duration = MATCH_DURATION
	print("Arrancando partida: %s vs %s en %s" % [GameState.p1.name, GameState.p2.name, GameState.field_id])
	Net.rpc("rpc_start_match", GameState.p1.id, GameState.p2.id,
		GameState.field_id, GameState.ball_style, GameState.match_duration)
	get_tree().change_scene_to_file("res://scenes/match.tscn")
