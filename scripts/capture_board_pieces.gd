extends SceneTree

const TableBoardScript := preload("res://scripts/table_board.gd")
const GameScript := preload("res://scripts/match.gd")

func _init() -> void:
	print("Capturando tablero con piezas de juego (caminos, poblados, granjas)...")
	
	var vp := SubViewport.new()
	vp.size = Vector2i(1280, 720)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_2X
	root.add_child(vp)
	
	var board = TableBoardScript.new()
	vp.add_child(board)
	
	var g = GameScript.new()
	g.new_game()
	
	# Cargar arte real del proyecto
	var terrains: Array[Texture2D] = []
	for name in ["terreno_madera", "terreno_arcilla", "terreno_grano", "terreno_piedra"]:
		terrains.append(load("res://art/%s.jpg" % name))
	var lagoon_tex = load("res://art/terreno_laguna.jpg")
	var sea_tex = load("res://art/mar_isla.jpg")
	var font := ThemeDB.fallback_font
	if ResourceLoader.exists("res://fonts/Nunito-Bold.ttf"):
		font = load("res://fonts/Nunito-Bold.ttf")
	
	board.bind(g, terrains, lagoon_tex, sea_tex, font)
	
	# Colocar poblados, granjas y caminos para ambos jugadores
	var ekeys: Array = g.edges.keys()
	var vkeys: Array = []
	for i in g.v_pos.size():
		vkeys.append(i)
	
	# Jugador 0 (Vos - Oro/Ámbar): 2 caminos, 1 poblado, 1 granja
	g.roads[ekeys[4]] = 0
	g.roads[ekeys[5]] = 0
	var ends0: Array = g.edges[ekeys[4]]
	var ends1: Array = g.edges[ekeys[5]]
	g.buildings[ends0[0]] = {"player": 0, "level": 1}
	g.buildings[ends1[1]] = {"player": 0, "level": 2}
	
	# Jugador 1 (Vecino - Azul Zafiro): 2 caminos, 2 poblados
	g.roads[ekeys[16]] = 1
	g.roads[ekeys[17]] = 1
	var ends2: Array = g.edges[ekeys[16]]
	var ends3: Array = g.edges[ekeys[17]]
	g.buildings[ends2[0]] = {"player": 1, "level": 1}
	g.buildings[ends3[1]] = {"player": 1, "level": 1}
	
	# Sincronizar piezas y clavijas de construcción
	board.sync(g, [ends0[1]], [ekeys[6]], [ends0[0]])
	
	board.fit_camera(1280.0 / 720.0)
	
	# Renderizar dos cuadros
	for i in 3:
		await process_frame
	
	var img := vp.get_texture().get_image()
	if img != null:
		img.save_png("res://tablero_con_piezas.png")
		print("Guardada captura: res://tablero_con_piezas.png (1280x720)")
	
	quit(0)
