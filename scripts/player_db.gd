extends Node
## Base de datos de cabezukis: empaquetados (res://bundled_players)
## y creados por el usuario (user://players). Cada jugador es un Dictionary:
## { id, name, builtin: bool, user: bool, face: Texture2D,
##   audio: AudioStream|null (golpeo), goal_audio: AudioStream|null (gol) }

const USER_DIR := "user://players"
const IMPORT_DIR := "user://import"
const BUNDLED_DIR := "res://bundled_players"

const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "svg", "bmp"]
const AUDIO_EXTS := ["ogg", "mp3", "wav"]

var players: Array[Dictionary] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	DirAccess.make_dir_recursive_absolute(IMPORT_DIR)
	reload()

func reload() -> void:
	players.clear()
	_load_bundled()
	_load_user()

func get_player(id: String) -> Dictionary:
	for p in players:
		if p.id == id:
			return p
	return players[0] if players.size() > 0 else {}

func random_player(exclude_id: String = "") -> Dictionary:
	var pool := players.filter(func(p): return p.id != exclude_id)
	if pool.is_empty():
		pool = players
	return pool[randi() % pool.size()]

# ---------- Empaquetados en el APK (res://bundled_players/<nombre>/) ----------

func _load_bundled() -> void:
	var dir := DirAccess.open(BUNDLED_DIR)
	if dir == null:
		return
	for sub in dir.get_directories():
		var folder := BUNDLED_DIR + "/" + sub
		var face: Texture2D = null
		var audio: AudioStream = null
		var goal_audio: AudioStream = null
		var fdir := DirAccess.open(folder)
		if fdir == null:
			continue
		for f in fdir.get_files():
			# En builds exportadas los archivos aparecen como .import/.remap
			var base := f.trim_suffix(".remap").trim_suffix(".import")
			var ext := base.get_extension().to_lower()
			var path := folder + "/" + base
			if face == null and ext in IMAGE_EXTS:
				var res := load(path)
				if res is Texture2D:
					face = res
			elif ext in AUDIO_EXTS:
				# gol.ogg / goal.ogg suena al marcar; el resto, al golpear
				var is_goal := base.get_basename().to_lower().begins_with("gol")
				if is_goal and goal_audio == null:
					var res := load(path)
					if res is AudioStream:
						goal_audio = res
				elif not is_goal and audio == null:
					var res := load(path)
					if res is AudioStream:
						audio = res
		if face != null:
			players.append({
				"id": "bundled_" + sub, "name": sub.replace("_", " ").capitalize(),
				"builtin": false, "user": false, "face": face,
				"audio": audio, "goal_audio": goal_audio,
			})

# ---------- Creados por el usuario (user://players/<id>/) ----------

func _load_user() -> void:
	var dir := DirAccess.open(USER_DIR)
	if dir == null:
		return
	for sub in dir.get_directories():
		var folder := USER_DIR + "/" + sub
		var meta_path := folder + "/meta.json"
		if not FileAccess.file_exists(meta_path):
			continue
		var meta = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
		if typeof(meta) != TYPE_DICTIONARY:
			continue
		var img := Image.new()
		if img.load(folder + "/face.png") != OK:
			continue
		var audio: AudioStream = null
		if meta.has("audio") and meta.audio != "":
			audio = _load_audio_file(folder + "/" + meta.audio)
		var goal_audio: AudioStream = null
		if meta.has("goal_audio") and meta.goal_audio != "":
			goal_audio = _load_audio_file(folder + "/" + meta.goal_audio)
		players.append({
			"id": sub, "name": meta.get("name", sub), "builtin": false, "user": true,
			"face": ImageTexture.create_from_image(img), "audio": audio,
			"goal_audio": goal_audio,
		})

func _load_audio_file(path: String) -> AudioStream:
	var ext := path.get_extension().to_lower()
	match ext:
		"wav":
			return AudioStreamWAV.load_from_file(path)
		"mp3":
			var s := AudioStreamMP3.new()
			s.data = FileAccess.get_file_as_bytes(path)
			return s if s.data.size() > 0 else null
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
	return null

## Copia y valida un audio dentro de folder. Devuelve {"file": nombre} o {"err": mensaje}.
func _store_audio(folder: String, src_path: String, out_base: String) -> Dictionary:
	var bytes := FileAccess.get_file_as_bytes(src_path)
	if bytes.size() == 0:
		return {"err": "No se pudo leer el audio."}
	var ext := _detect_audio_ext(bytes, src_path)
	if ext == "":
		return {"err": "Formato de audio no soportado (usa OGG, MP3 o WAV)."}
	var fname := out_base + "." + ext
	var f := FileAccess.open(folder + "/" + fname, FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	# Validar que Godot puede decodificarlo (p. ej. los .ogg de WhatsApp
	# son Opus, no Vorbis, y no suenan)
	var test := _load_audio_file(folder + "/" + fname)
	if test == null or test.get_length() <= 0.0:
		DirAccess.remove_absolute(folder + "/" + fname)
		return {"err": "El audio no se pudo decodificar. Si es un .ogg de WhatsApp es Opus: conviértelo a OGG Vorbis, MP3 o WAV."}
	return {"file": fname}

func _remove_player_dir(folder: String) -> void:
	var dir := DirAccess.open(folder)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
	DirAccess.remove_absolute(folder)

## Añade un jugador copiando la foto y los audios al almacenamiento de la app.
## Devuelve "" si todo fue bien, o un mensaje de error.
func add_player(pname: String, face_path: String, audio_path: String,
		goal_audio_path: String = "") -> String:
	pname = pname.strip_edges()
	if pname == "":
		return "Pon un nombre al jugador."
	if face_path == "":
		return "Elige una foto para la cara."
	var img := _load_image_any(face_path)
	if img == null:
		return "No se pudo leer la imagen (usa PNG, JPG o WebP)."
	# Recorte cuadrado centrado + reescalado
	var side := mini(img.get_width(), img.get_height())
	var ox := (img.get_width() - side) / 2
	var oy := (img.get_height() - side) / 2
	img = img.get_region(Rect2i(ox, oy, side, side))
	if side > 512:
		img.resize(512, 512, Image.INTERPOLATE_LANCZOS)
	var id := "user_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	var folder := USER_DIR + "/" + id
	DirAccess.make_dir_recursive_absolute(folder)
	if img.save_png(folder + "/face.png") != OK:
		return "No se pudo guardar la imagen."
	var audio_file := ""
	if audio_path != "":
		var res := _store_audio(folder, audio_path, "sound")
		if res.has("err"):
			_remove_player_dir(folder)
			return "Audio de golpeo: " + res.err
		audio_file = res.file
	var goal_file := ""
	if goal_audio_path != "":
		var res := _store_audio(folder, goal_audio_path, "goal")
		if res.has("err"):
			_remove_player_dir(folder)
			return "Audio de gol: " + res.err
		goal_file = res.file
	var meta := {"name": pname, "audio": audio_file, "goal_audio": goal_file}
	var mf := FileAccess.open(folder + "/meta.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify(meta))
	mf.close()
	reload()
	return ""

func delete_player(id: String) -> void:
	var p := get_player(id)
	if p.is_empty() or not p.user:
		return
	_remove_player_dir(USER_DIR + "/" + id)
	reload()

## Importa jugadores desde user://import: cada imagen <nombre>.png/jpg crea un
## jugador, y si existe <nombre>.ogg/mp3/wav se usa como su sonido.
## Devuelve cuántos se importaron.
func import_from_folder() -> int:
	var dir := DirAccess.open(IMPORT_DIR)
	if dir == null:
		return 0
	var count := 0
	var existing_names := players.map(func(p): return String(p.name).to_lower())
	for f in dir.get_files():
		var ext := f.get_extension().to_lower()
		if not (ext in IMAGE_EXTS):
			continue
		var pname := f.get_basename().replace("_", " ")
		if pname.to_lower() in existing_names:
			continue
		var audio_path := _find_audio(f.get_basename(), ["", "_golpe"])
		var goal_path := _find_audio(f.get_basename(), ["_gol"])
		if add_player(pname, IMPORT_DIR + "/" + f, audio_path, goal_path) == "":
			count += 1
	return count

## Busca en la carpeta de importación un audio "base+sufijo.ext" para
## cualquiera de los sufijos y extensiones soportados.
func _find_audio(base: String, suffixes: Array) -> String:
	for suffix in suffixes:
		for aext in AUDIO_EXTS:
			var cand: String = IMPORT_DIR + "/" + base + suffix + "." + aext
			if FileAccess.file_exists(cand):
				return cand
	return ""

func import_folder_os_path() -> String:
	return ProjectSettings.globalize_path(IMPORT_DIR)

# ---------- Ayudas de carga ----------

func _load_image_any(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.size() < 12:
		return null
	var img := Image.new()
	var err := ERR_FILE_UNRECOGNIZED
	if bytes[0] == 0x89 and bytes[1] == 0x50:
		err = img.load_png_from_buffer(bytes)
	elif bytes[0] == 0xFF and bytes[1] == 0xD8:
		err = img.load_jpg_from_buffer(bytes)
	elif bytes.slice(8, 12).get_string_from_ascii() == "WEBP":
		err = img.load_webp_from_buffer(bytes)
	else:
		# Último intento por extensión
		err = img.load_png_from_buffer(bytes)
		if err != OK:
			err = img.load_jpg_from_buffer(bytes)
	return img if err == OK else null

func _detect_audio_ext(bytes: PackedByteArray, path: String) -> String:
	if bytes.slice(0, 4).get_string_from_ascii() == "OggS":
		return "ogg"
	if bytes.slice(0, 4).get_string_from_ascii() == "RIFF":
		return "wav"
	if bytes.slice(0, 3).get_string_from_ascii() == "ID3" or (bytes[0] == 0xFF and (bytes[1] & 0xE0) == 0xE0):
		return "mp3"
	var ext := path.get_extension().to_lower()
	return ext if ext in AUDIO_EXTS else ""
