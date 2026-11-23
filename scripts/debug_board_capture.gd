extends SceneTree
# Capturas GPU: no usar --headless (el renderer dummy devuelve textura null).

const TableBoardScript := preload("res://scripts/table_board.gd")
const GameScript := preload("res://scripts/match.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")

const OUT_DIR := "res://debug_captures"

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== CAPTURA DEBUG TABLERO ===")
	print("[captura] display=%s adapter=%s" % [
		DisplayServer.get_name(),
		RenderingServer.get_video_adapter_name(),
	])
	Dressing.debug_log = true
	var abs_dir := ProjectSettings.globalize_path(OUT_DIR)
	DirAccess.make_dir_recursive_absolute(abs_dir)

	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_2X

	var board = TableBoardScript.new()
	root.add_child(board)

	var g = GameScript.new()
	g.new_game()

	var terrains: Array[Texture2D] = []
	for tex_name in ["terreno_madera", "terreno_arcilla", "terreno_grano", "terreno_piedra", "terreno_ovejas"]:
		terrains.append(load("res://art/%s.jpg" % tex_name))
	var lagoon_tex = load("res://art/terreno_laguna.jpg")
	var sea_tex = load("res://art/mar_isla.jpg")
	var font := ThemeDB.fallback_font
	if ResourceLoader.exists("res://fonts/Nunito-Bold.ttf"):
		font = load("res://fonts/Nunito-Bold.ttf")

	board.bind(g, terrains, lagoon_tex, sea_tex, font)

	var ekeys: Array = g.edges.keys()
	var ends0: Array = g.edges[ekeys[4]]
	var ends1: Array = g.edges[ekeys[5]]
	g.roads[ekeys[4]] = 0
	g.roads[ekeys[5]] = 0
	g.buildings[ends0[0]] = {"player": 0, "level": 1}
	g.buildings[ends1[1]] = {"player": 0, "level": 2}
	g.roads[ekeys[16]] = 1
	g.roads[ekeys[17]] = 1
	var ends2: Array = g.edges[ekeys[16]]
	var ends3: Array = g.edges[ekeys[17]]
	g.buildings[ends2[0]] = {"player": 1, "level": 1}
	g.buildings[ends3[1]] = {"player": 1, "level": 1}
	board.sync(g, [ends0[1]], [ekeys[6]], [ends0[0]])
	board.fit_camera(1280.0 / 720.0)

	await _settle()
	_shot(root, "tablero_juego.png")

	board.set_debug_visible(true)
	await _settle()
	_shot(root, "tablero_debug.png")

	var closeups := [
		{"file": "piedra_0m2.png", "q": 0, "r": -2},
		{"file": "piedra_0p1.png", "q": 0, "r": 1},
		{"file": "piedra_m2p2.png", "q": -2, "r": 2},
		{"file": "piedra_2m2.png", "q": 2, "r": -2},
		{"file": "ovejas_m2p1.png", "q": -2, "r": 1},
		{"file": "arcilla_m1m1.png", "q": -1, "r": -1},
		{"file": "madera_0m1.png", "q": 0, "r": -1},
		{"file": "grano_0p2.png", "q": 0, "r": 2},
		{"file": "laguna_00.png", "q": 0, "r": 0},
		{"file": "borde_costa.png", "q": 2, "r": 0},
	]
	for shot in closeups:
		board.look_at_hex(int(shot.q), int(shot.r), 0.42)
		await _settle()
		_shot(root, String(shot.file))

	board.fit_camera(1280.0 / 720.0)
	board.set_debug_visible(false)
	await _settle()
	_shot(root, "tablero_juego_off.png")

	if board.board_debug != null:
		print("[captura] hallazgos=%d" % board.board_debug.findings.size())
		for rec in board.board_debug.findings:
			var flags: PackedStringArray = rec.flags
			if flags.is_empty():
				continue
			print("[captura] ERR (%d,%d) %s %s" % [rec.q, rec.r, rec.name, " ".join(flags)])
	print("=== FIN CAPTURA ===")
	quit(0)

func _settle() -> void:
	for i in 8:
		await process_frame
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw

func _shot(vp: Viewport, file_name: String) -> void:
	var tex := vp.get_texture()
	var img: Image = null
	if tex != null:
		img = tex.get_image()
	if img == null:
		print("[captura] FALLO %s (imagen null tex=%s)" % [file_name, tex])
		return
	var path := "%s/%s" % [OUT_DIR, file_name]
	var err := img.save_png(path)
	print("[captura] %s err=%d size=%dx%d" % [path, err, img.get_width(), img.get_height()])
