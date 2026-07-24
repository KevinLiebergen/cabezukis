extends Node
## Base de datos de escenarios/campos: empaquetados (res://bundled_fields)
## y fotos subidas por el usuario (user://fields).
## Cada campo es un Dictionary:
## { id, name, kind: "day"|"night"|"photo", texture: Texture2D|null, user: bool }

const USER_DIR := "user://fields"
const IMPORT_DIR := "user://import_fields"
const BUNDLED_DIR := "res://bundled_fields"

const IMAGE_EXTS := ["png", "jpg", "jpeg", "webp", "svg", "bmp"]

var fields: Array[Dictionary] = []

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(USER_DIR)
	DirAccess.make_dir_recursive_absolute(IMPORT_DIR)
	reload()

func reload() -> void:
	fields.clear()
	_load_bundled()
	_load_user()
	if fields.is_empty():
		# Último recurso si no hay ningún escenario de foto: estadio por código
		fields.append({"id": "estadio", "name": "Estadio", "kind": "day", "texture": null, "user": false})

func get_field(id: String) -> Dictionary:
	for f in fields:
		if f.id == id:
			return f
	return fields[0]

func _load_bundled() -> void:
	var dir := DirAccess.open(BUNDLED_DIR)
	if dir == null:
		return
	for sub in dir.get_directories():
		var folder := BUNDLED_DIR + "/" + sub
		var fdir := DirAccess.open(folder)
		if fdir == null:
			continue
		for f in fdir.get_files():
			var base := f.trim_suffix(".remap").trim_suffix(".import")
			if base.get_extension().to_lower() in IMAGE_EXTS:
				var res := load(folder + "/" + base)
				if res is Texture2D:
					fields.append({
						"id": "bundled_" + sub, "name": sub.replace("_", " ").capitalize(),
						"kind": "photo", "texture": res, "user": false,
					})
					break

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
		if img.load(folder + "/bg.png") != OK:
			continue
		fields.append({
			"id": sub, "name": meta.get("name", sub), "kind": "photo",
			"texture": ImageTexture.create_from_image(img), "user": true,
		})

## Añade un escenario a partir de una foto. Devuelve "" o un mensaje de error.
func add_field(fname: String, photo_path: String) -> String:
	fname = fname.strip_edges()
	if fname == "":
		return "Pon un nombre al escenario."
	if photo_path == "":
		return "Elige una foto."
	var img: Image = PlayerDB._load_image_any(photo_path)
	if img == null:
		return "No se pudo leer la imagen (usa PNG, JPG o WebP)."
	# Limitar tamaño manteniendo proporción
	var m := maxi(img.get_width(), img.get_height())
	if m > 1600:
		var s := 1600.0 / m
		img.resize(int(img.get_width() * s), int(img.get_height() * s), Image.INTERPOLATE_LANCZOS)
	var id := "field_" + str(Time.get_unix_time_from_system()) + "_" + str(randi() % 1000)
	var folder := USER_DIR + "/" + id
	DirAccess.make_dir_recursive_absolute(folder)
	if img.save_png(folder + "/bg.png") != OK:
		return "No se pudo guardar la imagen."
	var mf := FileAccess.open(folder + "/meta.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"name": fname}))
	mf.close()
	reload()
	return ""

func delete_field(id: String) -> void:
	var f := get_field(id)
	if not f.get("user", false):
		return
	var folder := USER_DIR + "/" + id
	var dir := DirAccess.open(folder)
	if dir != null:
		for file in dir.get_files():
			dir.remove(file)
	DirAccess.remove_absolute(folder)
	reload()

## Importa escenarios desde user://import_fields (una imagen = un campo).
func import_from_folder() -> int:
	var dir := DirAccess.open(IMPORT_DIR)
	if dir == null:
		return 0
	var count := 0
	var existing := fields.map(func(f): return String(f.name).to_lower())
	for f in dir.get_files():
		if not (f.get_extension().to_lower() in IMAGE_EXTS):
			continue
		var fname := f.get_basename().replace("_", " ")
		if fname.to_lower() in existing:
			continue
		if add_field(fname, IMPORT_DIR + "/" + f) == "":
			count += 1
	return count

func import_folder_os_path() -> String:
	return ProjectSettings.globalize_path(IMPORT_DIR)
