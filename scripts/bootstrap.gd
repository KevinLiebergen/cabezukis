extends Node
## Punto de arranque real del proyecto (run/main_scene): decide entre
## abrir el menú normal o entrar en modo servidor dedicado headless según los
## argumentos de línea de comandos, y se descarta enseguida.
##
## Modo servidor: `--headless -- --server --port=9001` (el puerto es opcional,
## por defecto Net.DEFAULT_PORT). Los argumentos tras "--" se leen con
## OS.get_cmdline_user_args() para no chocar con las flags propias de Godot
## (--headless, --path, etc.), que usan get_cmdline_args().

func _ready() -> void:
	# Diferido: llamar a change_scene_to_file directamente desde el _ready()
	# de la escena inicial falla ("Parent node is busy...") porque el árbol
	# todavía se está montando en ese momento.
	var path := "res://scenes/server_boot.tscn" if "--server" in OS.get_cmdline_user_args() \
		else "res://scenes/main_menu.tscn"
	get_tree().change_scene_to_file.call_deferred(path)
