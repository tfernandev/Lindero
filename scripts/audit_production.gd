extends SceneTree
# Auditoría windowed: menú, mapa, HUD, resoluciones, FPS, debug del tablero.

const OUT := "res://debug_captures"
const Game := preload("res://scripts/match.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")

var fails := 0
var notes: PackedStringArray = PackedStringArray()

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== AUDITORÍA PRODUCCIÓN MÓVIL ===")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_2X

	change_scene_to_file("res://scenes/menu.tscn")
	await _settle()
	var menu := current_scene
	_ok("menú carga", menu != null)
	_shot("audit_menu.png")
	if menu != null and menu.has_method("_on_play"):
		menu._on_play()
		await _settle_long()
	var main := current_scene
	_ok("partida carga", main != null and main.get("game") != null)
	if main == null:
		_finish()
		return

	var plate: Rect2 = main._plate_rect()
	var view := root.get_visible_rect().size
	_ok("mapa > 55% ancho", plate.size.x >= view.x * 0.55)
	_ok("mapa > 50% alto", plate.size.y >= view.y * 0.50)
	_ok("HUD sin columna", main._hud_width(view) < 8.0)

	if main.table != null:
		main.table.set_debug_visible(true)
		await _settle()
		_shot("audit_tablero_debug.png")
		var findings: Array = []
		if main.table.board_debug != null:
			findings = main.table.board_debug.findings
		var bad := 0
		for rec in findings:
			var flags: PackedStringArray = rec.flags
			if flags.is_empty():
				continue
			bad += 1
			print("[audit] HEX (%s,%s) %s %s" % [rec.q, rec.r, rec.name, " ".join(flags)])
			if flags.has("glb-ausente") or flags.has("sin-dressing") or flags.has("sin-malla"):
				fails += 1
		print("[audit] hallazgos debug=%d / 19" % bad)
		main.table.set_debug_visible(false)
		await _settle()
	_shot("audit_tablero.png")
	await _perf("idle 1280x720", 45)

	for sz in [Vector2i(1600, 720), Vector2i(2336, 1080), Vector2i(720, 1280)]:
		DisplayServer.window_set_size(sz)
		root.size = sz
		await _settle()
		if is_instance_valid(main) and main.has_method("_on_resized"):
			main._on_resized()
		await _settle()
		if not is_instance_valid(main):
			break
		var p: Rect2 = main._plate_rect()
		print("[audit] %dx%d plate=%.0fx%.0f" % [sz.x, sz.y, p.size.x, p.size.y])
		_ok("%dx%d mapa usable" % [sz.x, sz.y], p.size.x >= 200.0 and p.size.y >= 200.0)
		_shot("audit_%dx%d.png" % [sz.x, sz.y])
		await _perf("%dx%d" % [sz.x, sz.y], 20)

	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await _settle()

	if is_instance_valid(main):
		await _drive_setup(main)
	await _settle()
	_shot("audit_fundacion.png")
	if int(main.game.phase) == Game.Phase.ROLL:
		main.hud.roll_pressed.emit()
		await _settle()
		_shot("audit_dados.png")
	if main.hud != null:
		main.hud.dock_btns["mano"].pressed.emit()
		await _settle()
		_shot("audit_mano.png")
		main.hud.dock_btns["build"].pressed.emit()
		await _settle()
		_shot("audit_construir.png")
		main.hud.close_sheets()
		await _settle()

	if main.has_method("_on_menu"):
		main._on_menu()
		await _settle()
		_ok("vuelta al menú", current_scene != null and String(current_scene.scene_file_path).ends_with("menu.tscn"))
		_shot("audit_menu_vuelta.png")

	_finish()

func _drive_setup(main) -> void:
	var g = main.game
	var guard := 0
	while int(g.phase) != Game.Phase.ROLL and guard < 12:
		guard += 1
		var p := int(g.current_player)
		if p != 0:
			await _wait_ai(main)
			continue
		if int(g.phase) == Game.Phase.SETUP_SETTLEMENT:
			var v: int = int(g.choose_setup_vertex(0))
			main._after(g.place_settlement(0, v))
		else:
			var ek: String = String(g.choose_setup_road(0))
			main._after(g.place_road(0, ek))
		await process_frame

func _wait_ai(main) -> void:
	var n := 0
	while n < 400 and is_instance_valid(main) and (bool(main.ai_running) or int(main.game.current_player) != 0):
		await process_frame
		n += 1
	if n >= 400:
		print("[audit] FALLO timeout IA")
		fails += 1

func _perf(label: String, frames: int) -> void:
	var fps_min := 999.0
	var fps_acc := 0.0
	var draw_acc := 0.0
	var n := 0
	# Engine.get_frames_per_second() is a 1 s rolling average, so right after a
	# scene load or resize it reported the loading stall (~12 fps). Warm up,
	# then time each frame ourselves.
	for i in 30:
		await process_frame
	var last := Time.get_ticks_usec()
	for i in frames:
		await process_frame
		var now := Time.get_ticks_usec()
		var fps := 1_000_000.0 / maxf(float(now - last), 1.0)
		last = now
		fps_min = minf(fps_min, fps)
		fps_acc += fps
		draw_acc += float(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		n += 1
	var nodes := int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var mem := float(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)) / (1024.0 * 1024.0)
	print("[perf] %s fps_avg=%.1f fps_min=%.1f draw=%.0f nodos=%d vram=%.1fMB" % [
		label, fps_acc / maxf(float(n), 1.0), fps_min, draw_acc / maxf(float(n), 1.0), nodes, mem
	])
	notes.append("%s fps_avg=%.1f min=%.1f" % [label, fps_acc / maxf(float(n), 1.0), fps_min])

func _ok(name: String, cond: bool) -> void:
	if cond:
		print("[audit] ok %s" % name)
	else:
		print("[audit] FALLO %s" % name)
		fails += 1

func _settle() -> void:
	for i in 8:
		await process_frame
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw

func _settle_long() -> void:
	for i in 24:
		await process_frame
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw

func _shot(file_name: String) -> void:
	var tex := root.get_texture()
	var img: Image = null
	if tex != null:
		img = tex.get_image()
	if img == null:
		print("[audit] FALLO captura %s" % file_name)
		fails += 1
		return
	img.save_png("%s/%s" % [OUT, file_name])
	print("[audit] captura %s %dx%d" % [file_name, img.get_width(), img.get_height()])

func _finish() -> void:
	print("=== FIN AUDITORÍA fails=%d ===" % fails)
	quit(1 if fails > 0 else 0)
