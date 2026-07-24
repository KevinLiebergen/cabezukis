extends Node
## Herramienta temporal de desarrollo: captura una escena y sale.

func _ready() -> void:
	var scene := OS.get_environment("SHOT_SCENE")
	var out := OS.get_environment("SHOT_OUT")
	var wait := float(OS.get_environment("SHOT_WAIT")) if OS.get_environment("SHOT_WAIT") != "" else 2.0
	print("SHOT_START scene=", scene, " out=", out)
	if OS.get_environment("SHOT_IMPORT_FIELDS") == "1":
		print("SHOT_IMPORTED_FIELDS ", FieldDB.import_from_folder())
	if OS.get_environment("SHOT_BALL") != "":
		GameState.ball_style = OS.get_environment("SHOT_BALL")
	if OS.get_environment("SHOT_FIELD") != "":
		GameState.field_id = OS.get_environment("SHOT_FIELD")
		if FieldDB.get_field(GameState.field_id).id != GameState.field_id:
			GameState.field_id = FieldDB.fields[-1].id
			print("SHOT_FIELD_FALLBACK ", GameState.field_id)
	if OS.get_environment("SHOT_TEST_IMPORT") == "1":
		print("IMPORTED_PLAYERS ", PlayerDB.import_from_folder())
		for p in PlayerDB.players:
			print("PLAYER name=", p.name, " hit=", p.audio != null,
				" goal=", p.get("goal_audio") != null)
	if OS.get_environment("SHOT_P1_NAME") != "":
		for p in PlayerDB.players:
			if p.name == OS.get_environment("SHOT_P1_NAME"):
				GameState.p1 = p
	if OS.get_environment("SHOT_DURATION") != "":
		GameState.match_duration = float(OS.get_environment("SHOT_DURATION"))
	if OS.get_environment("SHOT_HT_AUDIO") == "1":
		SoundFactory.goal_sound().save_to_wav("user://halftime.wav")
	var tree := get_tree()
	var packed: PackedScene = load("res://scenes/%s.tscn" % scene)
	tree.root.add_child.call_deferred(packed.instantiate())
	if OS.get_environment("SHOT_HALFTIME") == "1":
		await _halftime_test(tree, out)
		return
	if OS.get_environment("SHOT_GOAL_VIEW") == "1":
		# Coloca a los dos cabezudos dentro de sus respectivas porterías (uno
		# pegado a la boca, otro más metido, detrás del poste cercano) para
		# comprobar de un vistazo la profundidad portería/red/poste sin
		# esperar a que la jugada llegue ahí sola.
		await tree.create_timer(1.0).timeout
		var gm = tree.root.get_node("Match")
		gm.play_locked = true
		gm.p1_head.global_position = Vector2(90, 598)
		gm.p1_head.velocity = Vector2.ZERO
		gm.p2_head.global_position = Vector2(1230, 598)
		gm.p2_head.velocity = Vector2.ZERO
		gm.ball.reset_at(Vector2(90, 560))
		await tree.create_timer(0.3).timeout
		var gimg := tree.root.get_texture().get_image()
		print("SHOT_SAVED err=", gimg.save_png(out), " path=", out)
		tree.quit()
		return
	if OS.get_environment("SHOT_FORCE_GOAL") == "1":
		await tree.create_timer(3.0).timeout
		var m = tree.root.get_node("Match")
		m.ball.reset_at(Vector2(1240, 560))
		await tree.create_timer(2.0).timeout
		print("SHOT_FORCED_GOAL score=", m.p1_score, "-", m.p2_score,
			" goal_player_ok=", m.p1_head._goal_audio != null)
		tree.quit()
		return
	if OS.get_environment("SHOT_POWERUPS") == "1":
		await tree.create_timer(2.5).timeout
		var mm = tree.root.get_node("Match")
		mm.ball.freeze = true
		mm.p1_head.held_powerups = [Powerup.Type.FREEZE, Powerup.Type.SUPER_KICK]
		mm.p2_head.held_powerups = [Powerup.Type.BIG_BALL, Powerup.Type.SPEED]
		mm._update_powerup_hud()
		await tree.create_timer(0.5).timeout
		var pimg := tree.root.get_texture().get_image()
		print("SHOT_SAVED err=", pimg.save_png(out), " path=", out)
		tree.quit()
		return
	if OS.get_environment("SHOT_POWERUP_CLOCK") == "1":
		# Activa un power-up del humano de verdad (no solo lo deja "en mano")
		# para comprobar la cuenta atrás en forma de reloj sobre el botón:
		# una captura recién activado y otra a mitad de la duración.
		await tree.create_timer(1.0).timeout
		var pm = tree.root.get_node("Match")
		pm.p1_head.held_powerups = [Powerup.Type.FREEZE, Powerup.Type.SUPER_KICK]
		pm._update_powerup_hud()
		pm._activate_powerup_slot(pm.p1_head, 0)
		await tree.create_timer(0.4).timeout
		var img1 := tree.root.get_texture().get_image()
		print("SHOT_SAVED err=", img1.save_png(out), " path=", out)
		var dur: float = pm.FREEZE_DURATION
		await tree.create_timer(dur * 0.8).timeout
		var out2 := OS.get_environment("SHOT_OUT2")
		if out2 != "":
			var img2 := tree.root.get_texture().get_image()
			print("SHOT_SAVED err=", img2.save_png(out2), " path=", out2)
		tree.quit()
		return
	if OS.get_environment("SHOT_NAV_PLAY_CHECK") == "1":
		await tree.create_timer(1.0).timeout
		GameState.play_nav_click()
		await tree.create_timer(0.05).timeout
		print("NAV_CLICK playing=", GameState._nav_click_player.playing if GameState._nav_click_player else "no_player",
			" stream=", GameState._nav_click_player.stream if GameState._nav_click_player else "no_player",
			" length=", GameState._nav_click_player.stream.get_length() if GameState._nav_click_player and GameState._nav_click_player.stream else -1.0)
		tree.quit()
		return
	if OS.get_environment("SHOT_NAV_SOUND_CHECK") == "1":
		await tree.create_timer(1.0).timeout
		var sm = tree.root.get_node("PlayerSelect")
		var next_btn: Button = null
		var thumb_btn: Button = null
		var stack: Array = [sm]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is Label and String(cur.text).begins_with("Siguiente") and cur.get_parent() is Button:
				next_btn = cur.get_parent()
			if cur is Label and String(cur.text) == "Alfonsuki" and cur.get_parent() is Container:
				# La label del nombre está dentro del VBox del botón-miniatura.
				var p := cur.get_parent()
				while p != null and not (p is Button):
					p = p.get_parent()
				if p is Button:
					thumb_btn = p
			stack.append_array(cur.get_children())
		print("next_btn nav_sound=", next_btn.has_meta("ui_nav_sound") if next_btn else "not_found")
		print("thumb_btn nav_sound=", thumb_btn.has_meta("ui_nav_sound") if thumb_btn else "not_found")
		tree.quit()
		return
	if OS.get_environment("SHOT_NAV_CLICK_CHECK") == "1":
		# ¿Los botones Volver/Siguiente/¡A JUGAR! (player_select, match_setup)
		# disparan ya el clic global de GameState al pulsarlos de verdad?
		await tree.create_timer(1.0).timeout
		var nm = tree.root.get_node("PlayerSelect")
		# Busca el botón "Siguiente": style_cta migra el texto nativo del
		# Button a una Label hija en su primer draw(), así que puede que ya
		# no esté en btn.text para cuando miremos - se busca por cualquiera
		# de los dos sitios.
		var next_btn: Button = null
		var stack: Array = [nm]
		while not stack.is_empty():
			var cur: Node = stack.pop_back()
			if cur is Button and String(cur.text).begins_with("Siguiente"):
				next_btn = cur
			elif cur is Label and String(cur.text).begins_with("Siguiente") and cur.get_parent() is Button:
				next_btn = cur.get_parent()
			stack.append_array(cur.get_children())
		print("FOUND next_btn=", next_btn)
		if next_btn != null:
			# Comprobación estructural (sin emitir pressed de verdad: eso
			# dispararía la navegación real de _go_next y cambiaría de
			# escena en mitad del test): ¿está GameState enganchado a la
			# señal pressed de este botón?
			var conns := next_btn.pressed.get_connections()
			var hooked := false
			for c in conns:
				if c.callable.get_object() == GameState:
					hooked = true
			print("Siguiente conexiones=", conns.size(), " GameState_hooked=", hooked)
		tree.quit()
		return
	if OS.get_environment("SHOT_AUDIO_CHECK") == "1":
		# Countdown: al arrancar la escena ya está en pleno _countdown_kickoff.
		await tree.create_timer(0.3).timeout
		var am = tree.root.get_node("Match")
		print("COUNTDOWN playing=", am._countdown_audio.playing,
			" stream=", am._countdown_audio.stream)
		# Poste: coloca el balón encima del larguero izquierdo y déjalo caer.
		am.play_locked = true
		am.ball.freeze = false
		am.ball.global_position = Vector2(30, 380)
		am.ball.linear_velocity = Vector2.ZERO
		for i in 6:
			await tree.create_timer(0.1).timeout
			print("  t=", (i + 1) * 0.1, " ball_pos=", am.ball.global_position,
				" vel=", am.ball.linear_velocity, " post_cd=", am._post_sound_cooldown)
		print("POST cooldown=", am._post_sound_cooldown, " ball_y=", am.ball.global_position.y)
		# Clic de menú: simula pulsar un botón real de GameState (usa el
		# propio _click_player que crea play_click on demand).
		GameState.play_click()
		await tree.create_timer(0.05).timeout
		print("CLICK playing=", GameState._click_player.playing if GameState._click_player else null)
		tree.quit()
		return
	if OS.get_environment("SHOT_HEADER_SOUND") == "1":
		# Comprueba si el cabeceo (por proximidad, sin pulsar chutar) dispara
		# ya el sonido de contacto con el balón vía la señal touched_by_head.
		await tree.create_timer(1.0).timeout
		var hm = tree.root.get_node("Match")
		hm.play_locked = false
		hm.p1_head.global_position = Vector2(400, 598)
		hm.p1_head.velocity = Vector2.ZERO
		hm.ball.reset_at(Vector2(430, 598))
		var before: float = hm.p1_head._sound_cooldown
		print("BEFORE header: sound_cooldown=", before)
		await tree.create_timer(0.3).timeout
		print("AFTER header: sound_cooldown=", hm.p1_head._sound_cooldown,
			" dist=", hm.p1_head.global_position.distance_to(hm.ball.global_position))
		tree.quit()
		return
	if OS.get_environment("SHOT_CROWD_CHECK") == "1":
		await tree.create_timer(1.0).timeout
		var cm = tree.root.get_node("Match")
		print("CROWD playing=", cm._crowd_audio.playing,
			" volume_db=", cm._crowd_audio.volume_db,
			" loop=", cm._crowd_audio.stream.loop,
			" stream=", cm._crowd_audio.stream)
		tree.quit()
		return
	if OS.get_environment("SHOT_GOAL_POWERUP") == "1":
		# Activa un power-up de verdad en el humano y luego fuerza un gol:
		# el power-up debe seguir contando su tiempo normal después, no
		# reiniciarse/cancelarse por el saque tras el gol.
		await tree.create_timer(1.0).timeout
		var gp = tree.root.get_node("Match")
		gp.play_locked = false
		gp.p1_head.held_powerups = [Powerup.Type.SUPER_KICK]
		gp._update_powerup_hud()
		gp._activate_powerup_slot(gp.p1_head, 0)
		await tree.create_timer(0.5).timeout
		var time_before: float = gp._p1_active_powerup[0].time_left
		var kick_mult_before: float = gp.kick_mult
		print("BEFORE GOAL: active=", gp._p1_active_powerup[0] != null,
			" time_left=", time_before, " kick_mult=", kick_mult_before)
		gp.play_locked = false
		gp._on_goal(gp.ball, true)
		await tree.create_timer(1.9).timeout
		print("SCORE AFTER GOAL: ", gp.p1_score, "-", gp.p2_score,
			" play_locked=", gp.play_locked)
		await tree.create_timer(0.3).timeout
		var active_after = gp._p1_active_powerup[0]
		print("AFTER GOAL+KICKOFF: active=", active_after != null,
			" time_left=", (active_after.time_left if active_after != null else -1.0),
			" kick_mult=", gp.kick_mult)
		tree.quit()
		return
	if OS.get_environment("SHOT_BTN_DEBUG") == "1":
		# Necesita SHOT_FORCE_TOUCH=1 también, si no _build_touch_controls no
		# llega a crear los botones.
		await tree.create_timer(1.0).timeout
		var dm = tree.root.get_node("Match")
		for entry in [["left", dm._btn_left], ["right", dm._btn_right],
				["kick_high", dm._btn_kick_high], ["jump", dm._btn_jump]]:
			var name: String = entry[0]
			var b: TouchScreenButton = entry[1]
			if b == null:
				print("BTN ", name, " = NULL")
				continue
			print("BTN ", name, " pos=", b.position, " global_pos=", b.global_position,
				" scale=", b.scale, " shape_size=", (b.shape as RectangleShape2D).size,
				" shape_centered=", b.shape_centered, " tex=", b.texture_normal,
				" tex_size=", b.texture_normal.get_size() if b.texture_normal else null,
				" visible=", b.visible, " in_tree=", b.is_inside_tree())
		tree.quit()
		return
	if OS.get_environment("SHOT_BTN_TAP") == "1":
		await tree.create_timer(1.0).timeout
		var tm = tree.root.get_node("Match")
		tm.play_locked = false
		tm.p1_head.global_position = Vector2(1086, 636)
		tm.p1_head.velocity = Vector2.ZERO
		# Balón lejos a propósito: para comprobar que el pie igualmente
		# responde (animación) aunque no llegue a conectar.
		tm.ball.reset_at(Vector2(200, 300))
		await tree.create_timer(0.1).timeout
		var before_cd: float = tm.p1_head._kick_cooldown
		var before_rot: float = tm.p1_head._foot_pivot.rotation
		var pos: Vector2 = tm._btn_kick_high.global_position
		print("TAP_AT ", pos, " head=", tm.p1_head.global_position, " ball=", tm.ball.global_position)
		var down := InputEventScreenTouch.new()
		down.index = 0
		down.pressed = true
		down.position = pos
		Input.parse_input_event(down)
		await tree.create_timer(0.03).timeout
		print("IS_PRESSED after touch down:", tm._btn_kick_high.is_pressed(),
			" btn_scale=", tm._btn_kick_high.scale, " btn_modulate=", tm._btn_kick_high.modulate)
		await tree.create_timer(0.04).timeout
		print("FOOT rotation mid-anim (should be != 0):", tm.p1_head._foot_pivot.rotation)
		var up := InputEventScreenTouch.new()
		up.index = 0
		up.pressed = false
		up.position = pos
		Input.parse_input_event(up)
		await tree.create_timer(0.05).timeout
		print("AFTER RELEASE: btn_scale=", tm._btn_kick_high.scale, " btn_modulate=", tm._btn_kick_high.modulate)
		await tree.create_timer(0.3).timeout
		print("AFTER TAP (ball far, should NOT connect): cooldown ", before_cd, "->", tm.p1_head._kick_cooldown,
			" foot_rot_before=", before_rot, " foot_rot_after=", tm.p1_head._foot_pivot.rotation)
		tree.quit()
		return
	if OS.get_environment("SHOT_DRIVE") == "1":
		await _drive(tree, wait)
	else:
		await tree.create_timer(wait).timeout
	print("SHOT_TIMER_DONE")
	var match_node := tree.root.get_node_or_null("Match")
	if match_node != null:
		print("SHOT_STATE score=", match_node.p1_score, "-", match_node.p2_score,
			" ball=", match_node.ball.global_position.round(),
			" p1=", match_node.p1_head.global_position.round(),
			" p2=", match_node.p2_head.global_position.round())
	var img := tree.root.get_texture().get_image()
	var err := img.save_png(out)
	print("SHOT_SAVED err=", err, " path=", out)
	tree.quit()

## Espera al descanso, lo captura, reanuda y captura el cambio de campo.
func _halftime_test(tree: SceneTree, out: String) -> void:
	var match_node = null
	var guard := 0
	while guard < 300:
		match_node = tree.root.get_node_or_null("Match")
		if match_node != null and match_node.in_halftime:
			break
		await tree.create_timer(0.2).timeout
		guard += 1
	print("SHOT_HALFTIME_REACHED playing_music=", match_node._halftime_player != null \
		and match_node._halftime_player.playing)
	await tree.create_timer(0.5).timeout
	tree.root.get_texture().get_image().save_png(out)
	print("SHOT_SAVED ", out)
	match_node._second_half()
	await tree.create_timer(2.5).timeout
	print("SHOT_STATE2 p1=", match_node.p1_head.global_position.round(),
		" facing=", match_node.p1_head.facing,
		" p2=", match_node.p2_head.global_position.round(),
		" facing2=", match_node.p2_head.facing,
		" p1_defends_left=", match_node.p1_defends_left)
	var out2 := OS.get_environment("SHOT_OUT2")
	if out2 != "":
		tree.root.get_texture().get_image().save_png(out2)
		print("SHOT_SAVED ", out2)
	tree.quit()

## Simula al jugador humano: correr hacia el balón, saltar y chutar en bucle.
func _drive(tree: SceneTree, total: float) -> void:
	var elapsed := 0.0
	while elapsed < total:
		Input.action_press("move_right")
		await tree.create_timer(1.2).timeout
		Input.action_release("move_right")
		Input.action_press("jump")
		await tree.create_timer(0.3).timeout
		Input.action_release("jump")
		Input.action_press("kick")
		await tree.create_timer(0.1).timeout
		Input.action_release("kick")
		Input.action_press("move_left")
		await tree.create_timer(0.8).timeout
		Input.action_release("move_left")
		elapsed += 2.4
