extends Node
## Autoload que gestiona la conexión de red (ENet/UDP): crear servidor o
## cliente, y saber quién es "p1"/"p2". No es un bus de mensajes de
## gameplay -los RPC de partido viven en match.gd y se llaman directamente
## sobre sus propios nodos-, solo la fontanería de la conexión.
##
## El servidor ENet siempre tiene peer id 1; el primer cliente en conectar se
## asigna a "p1" y el segundo a "p2" (determinístico, sin negociación). El
## servidor es quien decide y avisa a cada cliente de su lado por RPC, ya que
## el orden de conexión solo lo conoce él.

signal connection_succeeded
signal connection_failed
signal server_disconnected
signal peer_joined(id: int)
signal peer_left(id: int)
## Emitida en el cliente cuando el servidor le confirma su lado ("p1"/"p2"),
## con algo de retraso de red respecto a connection_succeeded: quien pinte UI
## dependiente de my_side() debe esperar esta señal en vez de asumir que ya
## está disponible justo tras conectar.
signal side_assigned(side: String)
## Emitida en el cliente cuando el servidor arranca la partida (los dos
## lados ya están conectados). server_boot.gd la dispara por RPC; el propio
## servidor no la necesita, resuelve GameState y cambia de escena localmente.
signal match_starting(p1_id: String, p2_id: String, field_id: String, ball_style: String, duration: float)
## Emitida en el SERVIDOR cuando un cliente confirma "Listo" con el cabezuki
## elegido (ver online_lobby.gd). Vive aquí por el mismo motivo que
## rpc_start_match: durante el lobby, servidor y cliente están en escenas
## distintas (server_boot.tscn / online_lobby.tscn).
signal player_ready(peer_id: int, char_id: String)

const DEFAULT_PORT := 9001
## Servidor propio del usuario: fijo a propósito, para que online_connect.gd
## se conecte directo sin pedir ni mostrar la IP en pantalla.
const DEFAULT_SERVER_IP := "157.230.104.200"

var _side_by_peer: Dictionary = {}  # int (peer id) -> "p1"/"p2", solo en servidor
var _peer_order: Array = []
var _my_side := ""  # solo relevante en clientes, asignado por el servidor
## Godot pone un OfflineMultiplayerPeer por defecto en multiplayer_peer
## (nunca es null, ni siquiera sin llamar nunca a start_server/start_client),
## así que "hay sesión online" hay que llevarlo aparte -is_online() NO puede
## mirar solo multiplayer_peer != null, siempre daría true-.
var _online := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(func(): connection_succeeded.emit())
	multiplayer.connection_failed.connect(func():
		stop()
		connection_failed.emit())
	multiplayer.server_disconnected.connect(func():
		stop()
		server_disconnected.emit())

func start_server(port: int = DEFAULT_PORT, max_clients: int = 2) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, max_clients)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_online = true
	return OK

func start_client(address: String, port: int = DEFAULT_PORT) -> Error:
	stop()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	_online = true
	return OK

func stop() -> void:
	if _online:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	_online = false
	_side_by_peer.clear()
	_peer_order.clear()
	_my_side = ""

func is_online() -> bool:
	return _online

func is_server() -> bool:
	return is_online() and multiplayer.is_server()

## "" si no soy un jugador (servidor dedicado o desconectado); "p1"/"p2" para
## el cliente correspondiente, asignado por el servidor al conectar.
func my_side() -> String:
	return _my_side

func side_for_peer(id: int) -> String:
	return _side_by_peer.get(id, "")

func peer_for_side(side: String) -> int:
	for id in _side_by_peer:
		if _side_by_peer[id] == side:
			return id
	return -1

func _on_peer_connected(id: int) -> void:
	if is_server():
		_peer_order.append(id)
		var side := "p1" if _peer_order.size() == 1 else "p2"
		_side_by_peer[id] = side
		rpc_id(id, "_rpc_assign_side", side)
	peer_joined.emit(id)

func _on_peer_disconnected(id: int) -> void:
	_peer_order.erase(id)
	_side_by_peer.erase(id)
	peer_left.emit(id)

@rpc("authority", "call_remote", "reliable")
func _rpc_assign_side(side: String) -> void:
	_my_side = side
	side_assigned.emit(side)

## Vive en Net (no en match.gd) a propósito: durante el lobby, servidor y
## clientes están en escenas distintas (server_boot.tscn vs online_lobby.tscn),
## así que un RPC dirigido a un nodo de esa escena no llegaría -los paths no
## coinciden entre peers-. Net, al ser autoload, sí existe con el mismo path
## en todos.
@rpc("authority", "call_remote", "reliable")
func rpc_start_match(p1_id: String, p2_id: String, field_id: String, ball_style: String, duration: float) -> void:
	match_starting.emit(p1_id, p2_id, field_id, ball_style, duration)

@rpc("any_peer", "call_remote", "reliable")
func rpc_player_ready(char_id: String) -> void:
	player_ready.emit(multiplayer.get_remote_sender_id(), char_id)
