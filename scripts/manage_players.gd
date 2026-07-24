extends Control
## Gestión de jugadores: lista, alta con foto+audio, borrado e importación.

var _name_edit: LineEdit
var _photo_path := ""
var _audio_path := ""
var _goal_audio_path := ""
var _photo_btn: Button
var _audio_btn: Button
var _goal_btn: Button
var _status: Label
var _list_box: VBoxContainer
var _preview: TextureRect

func _ready() -> void:
	UIStyle.add_screen_background(self)

	var root := VBoxContainer.new()
	root.anchor_right = 1.0
	root.anchor_bottom = 1.0
	root.offset_left = 30
	root.offset_right = -30
	root.offset_top = 12
	root.offset_bottom = -12
	root.add_theme_constant_override("separation", 8)
	add_child(root)

	var top := HBoxContainer.new()
	root.add_child(top)
	var back := Button.new()
	back.text = "◀ Volver"
	back.add_theme_font_size_override("font_size", 24)
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	top.add_child(back)
	var title := Label.new()
	title.text = "  Jugadores"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.9, 0.3))
	top.add_child(title)

	var cols := HBoxContainer.new()
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("separation", 24)
	root.add_child(cols)

	# --- Columna izquierda: lista ---
	var sc := ScrollContainer.new()
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_stretch_ratio = 1.1
	cols.add_child(sc)
	_list_box = VBoxContainer.new()
	_list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_box.add_theme_constant_override("separation", 6)
	sc.add_child(_list_box)

	# --- Columna derecha: formulario de alta ---
	var form := VBoxContainer.new()
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	form.add_theme_constant_override("separation", 10)
	cols.add_child(form)

	var flabel := Label.new()
	flabel.text = "Añadir jugador nuevo"
	flabel.add_theme_font_size_override("font_size", 28)
	form.add_child(flabel)

	_name_edit = LineEdit.new()
	_name_edit.placeholder_text = "Nombre del jugador"
	_name_edit.add_theme_font_size_override("font_size", 24)
	_name_edit.custom_minimum_size = Vector2(0, 52)
	form.add_child(_name_edit)

	var photo_row := HBoxContainer.new()
	photo_row.add_theme_constant_override("separation", 12)
	form.add_child(photo_row)
	_photo_btn = Button.new()
	_photo_btn.text = "📷  Elegir foto de la cara"
	_photo_btn.add_theme_font_size_override("font_size", 22)
	_photo_btn.custom_minimum_size = Vector2(0, 56)
	_photo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_photo_btn.pressed.connect(_pick_photo)
	photo_row.add_child(_photo_btn)
	_preview = TextureRect.new()
	_preview.custom_minimum_size = Vector2(72, 72)
	_preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_preview.material = FaceUtil.circle_material()
	photo_row.add_child(_preview)

	_audio_btn = Button.new()
	_audio_btn.text = "🔊  Elegir sonido de golpeo (opcional)"
	_audio_btn.add_theme_font_size_override("font_size", 22)
	_audio_btn.custom_minimum_size = Vector2(0, 56)
	_audio_btn.pressed.connect(_pick_audio)
	form.add_child(_audio_btn)

	_goal_btn = Button.new()
	_goal_btn.text = "🎉  Elegir sonido de gol (opcional)"
	_goal_btn.add_theme_font_size_override("font_size", 22)
	_goal_btn.custom_minimum_size = Vector2(0, 56)
	_goal_btn.pressed.connect(_pick_goal_audio)
	form.add_child(_goal_btn)

	var save := Button.new()
	save.text = "💾  Guardar jugador"
	save.add_theme_font_size_override("font_size", 26)
	save.custom_minimum_size = Vector2(0, 62)
	save.pressed.connect(_save)
	form.add_child(save)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 20)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	form.add_child(_status)

	form.add_child(HSeparator.new())
	var imp_label := Label.new()
	imp_label.text = "También puedes copiar archivos a la carpeta de importación y pulsar el botón. Convención: nombre.jpg + nombre_golpe.ogg + nombre_gol.ogg"
	imp_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	imp_label.add_theme_font_size_override("font_size", 18)
	form.add_child(imp_label)
	var imp_path := Label.new()
	imp_path.text = PlayerDB.import_folder_os_path()
	imp_path.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
	imp_path.add_theme_font_size_override("font_size", 15)
	imp_path.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
	form.add_child(imp_path)
	var imp_btn := Button.new()
	imp_btn.text = "📂  Importar desde la carpeta"
	imp_btn.add_theme_font_size_override("font_size", 22)
	imp_btn.pressed.connect(_import_folder)
	form.add_child(imp_btn)

	_refresh_list()

func _refresh_list() -> void:
	for c in _list_box.get_children():
		c.queue_free()
	for p in PlayerDB.players:
		var row := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(1, 1, 1, 0.08)
		style.set_corner_radius_all(10)
		style.content_margin_left = 10
		style.content_margin_right = 10
		style.content_margin_top = 6
		style.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", style)
		_list_box.add_child(row)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		row.add_child(hb)
		var tr := TextureRect.new()
		tr.texture = p.face
		tr.material = FaceUtil.circle_material()
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tr.custom_minimum_size = Vector2(64, 64)
		hb.add_child(tr)
		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)
		var name_l := Label.new()
		name_l.text = p.name
		name_l.add_theme_font_size_override("font_size", 24)
		vb.add_child(name_l)
		var tag := Label.new()
		var kind := "integrado"
		if p.user:
			kind = "tuyo"
		elif not p.builtin:
			kind = "del APK"
		var audio_info := "  ·  🔊" if p.audio != null else "  ·  sin golpe"
		audio_info += "  ·  🎉" if p.get("goal_audio") != null else "  ·  sin gol"
		tag.text = kind + audio_info
		tag.add_theme_font_size_override("font_size", 16)
		tag.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		vb.add_child(tag)
		if p.user:
			var del := Button.new()
			del.text = "🗑"
			del.add_theme_font_size_override("font_size", 24)
			var pid: String = p.id
			del.pressed.connect(func():
				PlayerDB.delete_player(pid)
				_refresh_list())
			hb.add_child(del)

func _pick_photo() -> void:
	_pick_file(PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Imágenes"]), func(path):
		_photo_path = path
		_photo_btn.text = "📷  " + path.get_file()
		var img := PlayerDB._load_image_any(path)
		if img != null:
			_preview.texture = ImageTexture.create_from_image(img))

func _pick_audio() -> void:
	_pick_file(PackedStringArray(["*.ogg, *.mp3, *.wav ; Audio"]), func(path):
		_audio_path = path
		_audio_btn.text = "🔊  " + path.get_file())

func _pick_goal_audio() -> void:
	_pick_file(PackedStringArray(["*.ogg, *.mp3, *.wav ; Audio"]), func(path):
		_goal_audio_path = path
		_goal_btn.text = "🎉  " + path.get_file())

func _pick_file(filters: PackedStringArray, on_picked: Callable) -> void:
	if DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("Elegir archivo", "", "", false,
			DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, filters,
			func(status: bool, paths: PackedStringArray, _idx: int):
				if status and paths.size() > 0:
					on_picked.call(paths[0]))
	else:
		var dlg := FileDialog.new()
		dlg.access = FileDialog.ACCESS_FILESYSTEM
		dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		dlg.filters = filters
		dlg.use_native_dialog = true
		add_child(dlg)
		dlg.file_selected.connect(func(path): on_picked.call(path))
		dlg.close_requested.connect(func(): dlg.queue_free())
		dlg.popup_centered(Vector2i(900, 600))

func _save() -> void:
	var err := PlayerDB.add_player(_name_edit.text, _photo_path, _audio_path, _goal_audio_path)
	if err == "":
		_status.add_theme_color_override("font_color", Color(0.5, 1, 0.5))
		_status.text = "✔ Jugador \"%s\" guardado." % _name_edit.text.strip_edges()
		_name_edit.text = ""
		_photo_path = ""
		_audio_path = ""
		_goal_audio_path = ""
		_photo_btn.text = "📷  Elegir foto de la cara"
		_audio_btn.text = "🔊  Elegir sonido de golpeo (opcional)"
		_goal_btn.text = "🎉  Elegir sonido de gol (opcional)"
		_preview.texture = null
		_refresh_list()
	else:
		_status.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
		_status.text = "✖ " + err

func _import_folder() -> void:
	var n := PlayerDB.import_from_folder()
	_status.add_theme_color_override("font_color", Color(0.5, 1, 0.5) if n > 0 else Color(1, 0.8, 0.4))
	_status.text = "Importados %d jugadores nuevos." % n
	_refresh_list()
