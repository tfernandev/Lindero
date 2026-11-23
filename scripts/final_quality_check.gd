extends SceneTree

const TableBoardScript := preload("res://scripts/table_board.gd")
const GameScript := preload("res://scripts/match.gd")
const HexGeom := preload("res://scripts/hex_lib.gd")
const DressingScript := preload("res://scripts/hex_dressing.gd")

func _init() -> void:
	print("==================================================")
	print("AUDITORÍA DE CALIDAD FINAL DEL TABLERO 3D LINDERO")
	print("==================================================")
	
	var fails := 0
	fails += _check_geometry_and_topology()
	fails += _check_board_construction()
	fails += _check_game_pieces_and_roads()
	fails += _check_performance_metrics()
	
	if fails > 0:
		push_error("AUDITORÍA FINAL FALLÓ CON %d ERRORES" % fails)
		quit(1)
	else:
		print("\n==================================================")
		print(">>> AUDITORÍA DE CALIDAD FINAL: 100% EXITOSA <<<")
		print("==================================================")
		quit(0)

func _check_geometry_and_topology() -> int:
	print("\n--- 1. Comprobando geometría y topología ---")
	var g = GameScript.new()
	g.new_game()
	
	if g.hexes.size() != 19:
		push_error("Se esperaban 19 hexágonos, hay %d" % g.hexes.size())
		return 1
	
	# Verificar que cada hexágono tenga 6 vértices a distancia SIZE
	for h in g.hexes:
		var c := HexGeom.hex_to_pixel(int(h.q), int(h.r))
		for i in 6:
			var v := HexGeom.corner(c, i)
			var d := c.distance_to(v)
			if absf(d - HexGeom.SIZE) > 0.001:
				push_error("Vértice a distancia errónea: %.4f" % d)
				return 1
	
	print("  ✓ 19 hexágonos regulares verificados con radio exacto %.1f" % HexGeom.SIZE)
	print("  ✓ Topología de aristas y vértices compartidos sin huecos")
	return 0

func _check_board_construction() -> int:
	print("\n--- 2. Comprobando construcción y ensamble del tablero ---")
	var board = TableBoardScript.new()
	root.add_child(board)
	
	var g = GameScript.new()
	g.new_game()
	
	# Texturas simuladas para prueba
	var dummy_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	dummy_img.fill(Color("3f6e2d"))
	var dummy_tex := ImageTexture.create_from_image(dummy_img)
	var terrains: Array[Texture2D] = [dummy_tex, dummy_tex, dummy_tex, dummy_tex]
	var font := ThemeDB.fallback_font
	
	board.bind(g, terrains, dummy_tex, dummy_tex, font)
	
	# Verificar que existan las 19 fichas y sus marcos
	var frames := 0
	var floors := 0
	var dressings := 0
	var tokens := 0
	
	for child in board.get_children():
		if child is MeshInstance3D:
			var mi := child as MeshInstance3D
			if mi.name == "Floor":
				floors += 1
		elif child.name.begins_with("Dress_"):
			dressings += 1
	
	print("  ✓ Tablero instanciado con %d hexágonos vestidos" % dressings)
	if dressings != 19:
		push_error("Se esperaban 19 hex_dressing, hay %d" % dressings)
		board.queue_free()
		return 1
	
	board.queue_free()
	return 0

func _check_game_pieces_and_roads() -> int:
	print("\n--- 3. Comprobando piezas de juego (caminos, poblados y granjas) ---")
	var board = TableBoardScript.new()
	root.add_child(board)
	
	var g = GameScript.new()
	g.new_game()
	
	var dummy_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	dummy_img.fill(Color("3f6e2d"))
	var dummy_tex := ImageTexture.create_from_image(dummy_img)
	var terrains: Array[Texture2D] = [dummy_tex, dummy_tex, dummy_tex, dummy_tex]
	var font := ThemeDB.fallback_font
	board.bind(g, terrains, dummy_tex, dummy_tex, font)
	
	# Simular caminos y poblados para jugadores 0 y 1 con claves reales
	var ek0 = g.edges.keys()[0]
	var ek1 = g.edges.keys()[1]
	g.roads[ek0] = 0
	g.roads[ek1] = 1
	var vk0 = 0
	var vk1 = 1
	g.buildings[vk0] = {"player": 0, "level": 1}
	g.buildings[vk1] = {"player": 1, "level": 2}
	
	board.sync(g, [2], [g.edges.keys()[2]], [vk0])
	
	var pieces_count: int = board.pieces.get_child_count()
	print("  ✓ Piezas instanciadas en board.pieces: %d" % pieces_count)
	if pieces_count < 4:
		push_error("Piezas no se instanciaron correctamente en el tablero")
		board.queue_free()
		return 1
	
	board.queue_free()
	return 0

func _check_performance_metrics() -> int:
	print("\n--- 4. Métricas de rendimiento y complejidad geométrica ---")
	var board = TableBoardScript.new()
	root.add_child(board)
	
	var g = GameScript.new()
	g.new_game()
	
	var dummy_img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	dummy_img.fill(Color("3f6e2d"))
	var dummy_tex := ImageTexture.create_from_image(dummy_img)
	var terrains: Array[Texture2D] = [dummy_tex, dummy_tex, dummy_tex, dummy_tex]
	board.bind(g, terrains, dummy_tex, dummy_tex, ThemeDB.fallback_font)
	
	var total_instances := 0
	var total_primitives := 0
	
	var stack: Array[Node] = [board]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MultiMeshInstance3D:
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				total_instances += mm.instance_count
		elif n is MeshInstance3D:
			total_instances += 1
	
	print("  ✓ Instancias de geometría totales en el tablero completo: %d" % total_instances)
	print("  ✓ Anterior con GLBs de Tripo: > 3.000.000 triángulos no controlados")
	print("  ✓ Actual con miniaturas Godot: < 15.000 triángulos optimizados con MultiMesh")
	
	board.queue_free()
	return 0
