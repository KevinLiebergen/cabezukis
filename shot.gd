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
		gm.p1_head.global_position = Vector2(52, 566.4)
		gm.p1_head.velocity = Vector2.ZERO
		gm.p2_head.global_position = Vector2(1228, 566.4)
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
	if OS.get_environment("SHOT_GOAL_CORNER_TEST") == "1":
		# Reproduce la captura del usuario: portería izquierda agrandada,
		# balón cerca del poste (x=100, dentro de la zona nueva pero fuera de
		# donde llegaba la línea diagonal antigua) y arriba (y=320, solo
		# alcanzable con la portería agrandada). Debe marcar gol.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m._set_goal_enlarged(true, true)
		await tree.create_timer(0.1).timeout
		m.ball.reset_at(Vector2(100, 320))
		m.ball.linear_velocity = Vector2.ZERO
		await tree.create_timer(0.3).timeout
		print("GOAL_CORNER_TEST score=", m.p1_score, "-", m.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_GOAL_MOUTH_CONTROL_TEST") == "1":
		# Control aparte (partida limpia, sin gol previo que bloquee con
		# play_locked): justo en la boca (x=145, muy pegado al poste en 150)
		# NO debería marcar -si esto también contase, habríamos vuelto al bug
		# de "gol antes de que el balón entre".
		await tree.create_timer(1.0).timeout
		var m2 = tree.root.get_node("Match")
		m2.play_locked = false
		m2._set_goal_enlarged(true, true)
		await tree.create_timer(0.1).timeout
		m2.ball.reset_at(Vector2(145, 320))
		m2.ball.linear_velocity = Vector2.ZERO
		await tree.create_timer(0.3).timeout
		print("MOUTH_CONTROL score=", m2.p1_score, "-", m2.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_BALL_PINCH_TEST") == "1":
		# Fuerza el apretón de verdad (posición directa, no input/IA, para que
		# los dos avancen exactamente a la vez y no gane uno por reaccionar
		# antes): balón fijo en medio, cada cabezudo avanzando hacia él y
		# hacia el otro a la misma velocidad. Si el balón "atraviesa" a
		# alguno, acabará fuera del segmento [p1, p2] (por delante de p1 o
		# por detrás de p2) en vez de quedar siempre entre los dos.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(560, 566.4)
		m.p1_head.velocity = Vector2.ZERO
		m.p2_head.global_position = Vector2(720, 566.4)
		m.p2_head.velocity = Vector2.ZERO
		m.ball.reset_at(Vector2(640, 566.4))
		m.ball.linear_velocity = Vector2.ZERO
		var breached := false
		# 360px/s es move_speed real (velocidad máxima normal de un
		# cabezudo); 7.2px cada 0.02s equivale a eso, no a un valor
		# artificialmente alto.
		for i in 60:
			m.p1_head.global_position.x += 7.2
			m.p1_head.velocity = Vector2.ZERO
			m.p2_head.global_position.x -= 7.2
			m.p2_head.velocity = Vector2.ZERO
			await tree.create_timer(0.02).timeout
			var p1x: float = m.p1_head.global_position.x
			var p2x: float = m.p2_head.global_position.x
			var bpos: Vector2 = m.ball.global_position
			var combined: float = Head.RADIUS + m.ball.radius
			var d1: float = bpos.distance_to(m.p1_head.global_position)
			var d2: float = bpos.distance_to(m.p2_head.global_position)
			# Atravesón de verdad: el balón queda MÁS CERCA del centro de un
			# cabezudo que el radio combinado (solapado de verdad), no solo
			# "más allá en x" -eso podría ser un escape legítimo hacia arriba.
			if (d1 < combined and bpos.x < p1x) or (d2 < combined and bpos.x > p2x):
				breached = true
			print("t=", (i + 1) * 0.02, " p1x=", p1x, " ball=", bpos,
				" p2x=", p2x, " d1=", d1, " d2=", d2, " combined=", combined,
				" breached=", breached)
		tree.quit()
		return
	if OS.get_environment("SHOT_SINGLE_CONTACT_TEST") == "1":
		# Un solo cabezudo tocando el balón de frente (cabeceo normal), el
		# otro congelado (frozen, no play_locked -así el cabeceo por
		# proximidad de head.gd sigue activo, ver el "return" temprano ahí
		# si play_locked-) y lejos: solo debe actuar el cabeceo normal
		# (impulso hacia delante y un poco hacia arriba, suave, sin picos),
		# bug reportado: "cuando contacto la bola de frente sin dar patada a
		# veces va hacia arriba o actúa raro".
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p2_head.frozen = true
		m.p2_head.global_position = Vector2(1100, 566.4)
		m.p1_head.global_position = Vector2(700, 566.4)
		m.ball.reset_at(Vector2(850, 566.4))
		m.ball.linear_velocity = Vector2(-260, 0)
		for i in 40:
			await tree.create_timer(1.0 / 60.0).timeout
			print("t=", "%.3f" % ((i + 1) / 60.0), " pf=", Engine.get_physics_frames(),
				" ball=", m.ball.global_position,
				" vel=", m.ball.linear_velocity, " ang_vel=", m.ball.angular_velocity,
				" p1=", m.p1_head.global_position,
				" p2=", m.p2_head.global_position,
				" contacts=", m.ball.get_contact_count())
		tree.quit()
		return
	if OS.get_environment("SHOT_HEADER_SIDE_TEST") == "1":
		# Compara el empuje del cabeceo cuando el balón llega rodando (no
		# teletransportado -eso metía al balón ya solapado antes de que
		# head.gd llegara a mirarlo siquiera, falseando la prueba-) por
		# DELANTE (cara) vs por DETRÁS (pelo/nuca) mientras p1 corre hacia
		# delante, para comprobar que ya no sale más flojo/errático por
		# detrás -bug reportado: "en el pelo y la parte de atrás actúa raro,
		# no rebota igual"-.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p2_head.frozen = true
		m.p2_head.global_position = Vector2(1150, 566.4)
		Input.action_press("move_right")
		# Cara (delante, facing=+1 -> derecha): balón llega rodando desde la
		# derecha, hacia la cara de p1.
		m.p1_head.global_position = Vector2(500, 566.4)
		m.ball.reset_at(Vector2(750, 566.4))
		m.ball.linear_velocity = Vector2(-260, 0)
		await tree.create_timer(0.6).timeout
		print("FRONT ball_vel=", m.ball.linear_velocity, " speed=", m.ball.linear_velocity.length())
		Input.action_release("move_right")
		# Pelo/nuca (detrás, opuesto a facing +1): p1 camina hacia atrás
		# (move_left, velocity.x < 0) directamente sobre un balón que llega
		# rodando por su lado izquierdo -contacto real por detrás con
		# velocidad propia distinta de cero, para probar el "carry"-.
		Input.action_press("move_left")
		m.p1_head.global_position = Vector2(900, 566.4)
		m.ball.reset_at(Vector2(750, 566.4))
		m.ball.linear_velocity = Vector2(300, 0)
		await tree.create_timer(0.6).timeout
		print("BACK ball_vel=", m.ball.linear_velocity, " speed=", m.ball.linear_velocity.length())
		Input.action_release("move_left")
		tree.quit()
		return
	if OS.get_environment("SHOT_RUNTHROUGH_TEST") == "1":
		# Reproduce "mi jugador atraviesa la pelota": p1 quieto, balón lanzado
		# hacia él a velocidad real de disparo (kick_power). Si ballx termina
		# claramente MÁS ALLÁ de p1x (la ha cruzado) sin apartarse, es el bug.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p2_head.frozen = true
		m.p2_head.global_position = Vector2(1150, 566.4)
		m.p1_head.global_position = Vector2(700, 566.4)
		m.ball.reset_at(Vector2(300, 566.4))
		m.ball.linear_velocity = Vector2(950, 0)
		var contacted := false
		var passed := false
		for i in 60:
			await tree.create_timer(1.0 / 60.0).timeout
			if m.p1_head.global_position.distance_to(m.ball.global_position) < Head.RADIUS + m.ball.radius:
				contacted = true
			if m.ball.global_position.x > m.p1_head.global_position.x + 40.0:
				passed = true
			print("t=", "%.3f" % ((i + 1) / 60.0),
				" p1x=", "%.1f" % m.p1_head.global_position.x,
				" ballx=", "%.1f" % m.ball.global_position.x,
				" ball_vel=", m.ball.linear_velocity,
				" contacted=", contacted, " passed=", passed)
		tree.quit()
		return
	if OS.get_environment("SHOT_ENLARGED_CROSSBAR_TEST") == "1":
		# Portería izquierda agrandada: un disparo raso que apunta justo a la
		# altura del larguero (ahora también subido) debe rebotar sin marcar,
		# no colarse por donde se ve el larguero más alto.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m._set_goal_enlarged(true, true)
		await tree.create_timer(0.1).timeout
		# top_y agrandado ≈295.8; el larguero físico ocupa top_y-12..top_y,
		# así que 290 cae justo dentro de esa franja.
		m.p1_head.global_position = Vector2(640, 566.4)
		m.p2_head.global_position = Vector2(900, 566.4)
		# Cae en vertical justo encima del larguero (franja top_y-12..top_y,
		# ≈283.8..295.8 agrandado), dentro de su ancho horizontal (x<GOAL_W):
		# debe rebotar en él, no colarse ni marcar.
		m.ball.reset_at(Vector2(100, 250))
		m.ball.linear_velocity = Vector2(0, 300)
		for i in 20:
			await tree.create_timer(0.05).timeout
			print("t=", (i + 1) * 0.05, " ball=", m.ball.global_position.round(),
				" vel=", m.ball.linear_velocity.round(),
				" score=", m.p1_score, "-", m.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_NORMAL_CROSSBAR_TEST") == "1":
		# Portería SIN agrandar: un disparo que cae justo encima del larguero
		# debe rebotar sin marcar -bug reportado: "a veces da al larguero y se
		# detecta como gol, y rebota igual que si no lo fuera", tanto en
		# tamaño normal como agrandado-. CROSSBAR_Y=414.4, larguero físico
		# ocupa 402.4..414.4 en x<GOAL_W=150.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(640, 566.4)
		m.p2_head.global_position = Vector2(900, 566.4)
		m.ball.reset_at(Vector2(100, 250))
		m.ball.linear_velocity = Vector2(0, 300)
		for i in 20:
			await tree.create_timer(0.05).timeout
			print("t=", (i + 1) * 0.05, " ball=", m.ball.global_position.round(),
				" vel=", m.ball.linear_velocity.round(),
				" score=", m.p1_score, "-", m.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_COUNTDOWN_BALL_TEST") == "1":
		# El balón no debería moverse (BALL_SPAWN=(640,220), caería por
		# gravedad si no está congelado) durante el "3, 2, 1", solo soltarse
		# con "¡A JUGAR!".
		await tree.create_timer(0.1).timeout
		var m = tree.root.get_node("Match")
		for i in 35:
			await tree.create_timer(0.1).timeout
			print("t=", (i + 1) * 0.1, " ball=", m.ball.global_position.round(),
				" freeze=", m.ball.freeze, " label=", m._center_label.text)
		tree.quit()
		return
	if OS.get_environment("SHOT_PAUSE_MOVE_TEST") == "1":
		# ¿Se mueve el rival (CPU) de verdad mientras está en pausa?
		await tree.create_timer(2.0).timeout
		var m = tree.root.get_node("Match")
		m._apply_pause()
		var p2_start: Vector2 = m.p2_head.global_position
		var p1_start: Vector2 = m.p1_head.global_position
		print("PAUSED paused=", m.paused, " play_locked=", m.play_locked,
			" p2_start=", p2_start, " p1_start=", p1_start)
		for i in 20:
			await tree.create_timer(0.1).timeout
			print("t=", (i + 1) * 0.1, " p2=", m.p2_head.global_position,
				" p2_vel=", m.p2_head.velocity,
				" moved=", m.p2_head.global_position.distance_to(p2_start))
		tree.quit()
		return
	if OS.get_environment("SHOT_PAUSE_POWERUP_TEST") == "1":
		# Fuerza un retraso corto de power-up de la IA y pausa justo antes de
		# que cumpla: mientras dure la pausa no debería activarse (bug
		# reportado: la IA seguía gastando power-ups en pausa). Al reanudar,
		# sí debería activarse enseguida.
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m._cpu_powerup_delays[m.p2_head] = [1.0]
		await tree.create_timer(0.5).timeout
		m._apply_pause()
		print("PAUSED used_before=", m.p2_head.used_powerups)
		await tree.create_timer(2.0).timeout
		print("DURING_PAUSE used=", m.p2_head.used_powerups,
			" delays_left=", m._cpu_powerup_delays.get(m.p2_head))
		m._apply_resume()
		await tree.create_timer(1.5).timeout
		print("AFTER_RESUME used=", m.p2_head.used_powerups)
		tree.quit()
		return
	if OS.get_environment("SHOT_POWERUPS") == "1":
		await tree.create_timer(2.5).timeout
		var mm = tree.root.get_node("Match")
		mm.ball.freeze = true
		mm.p1_head.held_powerups = [Powerup.Type.FREEZE, Powerup.Type.SUPER_KICK]
		mm.p1_head.used_powerups = [false, false]
		mm.p2_head.held_powerups = [Powerup.Type.BIG_BALL, Powerup.Type.SPEED]
		mm.p2_head.used_powerups = [false, false]
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
		pm.p1_head.used_powerups = [false, false]
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
		# Tras expirar del todo (ya no solo al 80%): el hueco usado debe
		# seguir viéndose (icono en gris), no desaparecer/vaciarse. Bastante
		# margen extra porque el cronómetro del power-up no corre mientras
		# play_locked esté activo (p.ej. la cuenta atrás de saque inicial).
		await tree.create_timer(dur + 3.0).timeout
		print("AFTER_EXPIRY btn_text=", pm._p1_powerup_buttons[0].text,
			" btn_disabled=", pm._p1_powerup_buttons[0].disabled,
			" active_slot0=", pm._p1_active_powerup[0],
			" used0=", pm.p1_head.used_powerups[0],
			" mini_row_count=", pm._p1_mini_row.get_child_count())
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
	if OS.get_environment("SHOT_POST_SHAKE_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var sm = tree.root.get_node("Match")
		sm.play_locked = true
		sm.ball.freeze = false
		sm.ball.global_position = Vector2(30, 380)
		sm.ball.linear_velocity = Vector2(200, 0)
		await tree.create_timer(0.06).timeout
		var simg := tree.root.get_texture().get_image()
		print("SHOT_SAVED err=", simg.save_png(out), " path=", out)
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
		gp.p1_head.used_powerups = [false]
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
	if OS.get_environment("SHOT_BALL_STUCK_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(400, 566.4)
		m.p2_head.global_position = Vector2(900, 566.4)
		# Justo encima del larguero izquierdo, en reposo -el caso reportado
		# de "se queda atascado encima de la portería".
		m.ball.reset_at(Vector2(75, 380))
		for i in 20:
			await tree.create_timer(0.1).timeout
			print("t=", (i + 1) * 0.1, " ball=", m.ball.global_position.round(),
				" vel=", m.ball.linear_velocity.round(), " stuck_timer=", m._ball_stuck_timer)
		tree.quit()
		return
	if OS.get_environment("SHOT_GOAL_JUMP_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		# Empieza justo a la entrada de la portería (fuera del tope) y salta
		# repetidamente mientras avanza hacia el fondo, a ver si consigue
		# "pasar por encima" del tope y aterrizar detrás.
		m.p1_head.global_position = Vector2(160, 566.4)
		m.p1_head.velocity = Vector2.ZERO
		m.ball.reset_at(Vector2(640, 100))
		Input.action_press("move_left")
		for i in 40:
			if i % 5 == 0:
				Input.action_press("jump")
			else:
				Input.action_release("jump")
			await tree.create_timer(0.1).timeout
			print("t=", (i + 1) * 0.1, " p1=", m.p1_head.global_position.round())
		Input.action_release("move_left")
		Input.action_release("jump")
		print("expected_backstop_x=", m.GOAL_W - FieldArt.goal_depth())
		tree.quit()
		return
	if OS.get_environment("SHOT_HIGH_MISS_ENLARGED_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m._set_goal_enlarged(true, true)
		await tree.create_timer(0.1).timeout
		# Por encima incluso de la boca agrandada (top_y≈296 con factor 1.6):
		# debería seguir siendo fuera, no gol.
		m.p1_head.global_position = Vector2(640, 566.4)
		m.p2_head.global_position = Vector2(900, 566.4)
		m.ball.reset_at(Vector2(220, 200))
		m.ball.linear_velocity = Vector2(-1400, 0)
		for i in 16:
			await tree.create_timer(0.05).timeout
			print("t=", (i + 1) * 0.05, " ball=", m.ball.global_position.round(),
				" score=", m.p1_score, "-", m.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_HIGH_MISS_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(640, 566.4)
		m.p2_head.global_position = Vector2(900, 566.4)
		# Muy por encima del larguero (CROSSBAR_Y=414.4), rumbo a la
		# portería izquierda: debería salir por fuera, arriba, sin marcar.
		m.ball.reset_at(Vector2(300, 150))
		m.ball.linear_velocity = Vector2(-700, 0)
		for i in 16:
			await tree.create_timer(0.05).timeout
			print("t=", (i + 1) * 0.05, " ball=", m.ball.global_position.round(),
				" vel=", m.ball.linear_velocity.round(), " score=", m.p1_score, "-", m.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_BALL_NET_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(640, 566.4)
		m.p2_head.global_position = Vector2(900, 566.4)
		# Balón lanzado a ras de suelo, rápido, directo a la portería
		# izquierda (dentro de la boca, bien por debajo del larguero).
		m.ball.reset_at(Vector2(400, 580))
		m.ball.linear_velocity = Vector2(-1200, 0)
		for i in 20:
			await tree.create_timer(0.05).timeout
			print("t=", (i + 1) * 0.05, " ball=", m.ball.global_position.round(),
				" vel=", m.ball.linear_velocity.round(), " score=", m.p1_score, "-", m.p2_score)
		tree.quit()
		return
	if OS.get_environment("SHOT_GOAL_BACKSTOP_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(140, 566.4)
		m.p1_head.velocity = Vector2.ZERO
		m.ball.reset_at(Vector2(640, 100))
		Input.action_press("move_left")
		for i in 20:
			await tree.create_timer(0.1).timeout
			print("t=", (i + 1) * 0.1, " p1_x=", m.p1_head.global_position.x)
		Input.action_release("move_left")
		print("goal_depth=", FieldArt.goal_depth(), " expected_backstop_x=", m.GOAL_W - FieldArt.goal_depth())
		var bimg := tree.root.get_texture().get_image()
		print("SHOT_SAVED err=", bimg.save_png(out), " path=", out)
		tree.quit()
		return
	if OS.get_environment("SHOT_GOAL_ENLARGE_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m._set_goal_enlarged(true, true)
		await tree.create_timer(0.1).timeout
		# y=330 queda por encima de la boca normal (sin agrandar llega hasta
		# CROSSBAR_Y=414.4) pero dentro de la boca agrandada de verdad -zona
		# que ANTES del fix quedaba sin sensor-. Se lanza con velocidad (no
		# se teletransporta encima) porque la línea de gol ahora está en la
		# boca (Area2D body_entered solo dispara al entrar cruzándola).
		m.ball.reset_at(Vector2(250, 330))
		m.ball.freeze = false
		m.ball.linear_velocity = Vector2(-600, 0)
		await tree.create_timer(0.5).timeout
		print("GOAL_ENLARGE_TEST score=", m.p1_score, "-", m.p2_score,
			" ball_y=", m.ball.global_position.y)
		tree.quit()
		return
	if OS.get_environment("SHOT_PUNCH_TEST") == "1":
		await tree.create_timer(1.0).timeout
		var m = tree.root.get_node("Match")
		m.play_locked = false
		m.p1_head.global_position = Vector2(600, 598)
		m.p1_head.velocity = Vector2.ZERO
		m.p2_head.global_position = Vector2(620, 598)
		m.p2_head.velocity = Vector2.ZERO
		m.ball.reset_at(Vector2(640, 300))
		for i in 10:
			await tree.create_timer(0.1).timeout
			print("PUSH frame=", i, " dist=", m.p1_head.global_position.distance_to(m.p2_head.global_position),
				" min_esperado=", Head.RADIUS * 2.0)
		m.p1_head.global_position = Vector2(600, 598)
		m.p2_head.global_position = Vector2(660, 598)
		m.p1_head.facing = 1
		for i in 3:
			m.p1_head._check_kick_hit_rival()
			await tree.create_timer(0.05).timeout
			print("HIT ", i + 1, " streak=", m.p1_head._kick_hit_streak,
				" p2_stunned=", m.p2_head.stunned)
		print("FINAL p2_stunned=", m.p2_head.stunned, " modulate=", m.p2_head.modulate,
			" STUN_DURATION=", Head.STUN_DURATION, " stun_timer=", m.p2_head._stun_timer,
			" play_locked=", m.play_locked)
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
	# _apply_second_half encadena _apply_countdown_kickoff con mensaje (1.3s
	# de intro + 3,2,1 + "¡A JUGAR!" ≈ 4.3s de play_locked): hasta que no pasa
	# todo eso, _update_time_hud no vuelve a llamarse y el rótulo se queda
	# congelado en "PITI TIME" -no es un bug, es lo mismo que pasa al empezar
	# el partido-. Se espera aquí lo que falta para comprobar que después sí
	# cambia a "P2 ...".
	await tree.create_timer(3.0).timeout
	print("SHOT_TIME_LABEL after second half countdown: ", match_node._time_label.text)
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
