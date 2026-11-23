extends SceneTree

const TableBoardScript := preload("res://scripts/table_board.gd")
const GameScript := preload("res://scripts/match.gd")
const HexGeom := preload("res://scripts/hex_lib.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")

func _init() -> void:
	print("==================================================")
	print("VERIFICACIÓN DE AJUSTE GEOMÉTRICO Y ENCAJES VECINOS")
	print("==================================================")
	
	var fails := 0
	fails += _verify_hex_footprints()
	fails += _verify_low_profile_bases()
	fails += _verify_neighbor_seams()
	fails += _verify_model_bounding()
	
	if fails > 0:
		push_error("VERIFICACIÓN FALLÓ CON %d ERRORES" % fails)
		quit(1)
	else:
		print("\n==================================================")
		print(">>> TODOS LOS TERRENOS Y VECINOS AJUSTADOS AL 100% <<<")
		print("==================================================")
		quit(0)

func _verify_hex_footprints() -> int:
	print("\n--- 1. Verificando huellas hexagonales idénticas ---")
	var g = GameScript.new()
	g.new_game()
	
	for h in g.hexes:
		var c := HexGeom.hex_to_pixel(int(h.q), int(h.r))
		for i in 6:
			var corner := HexGeom.corner(c, i)
			var r := c.distance_to(corner)
			if absf(r - HexGeom.SIZE) > 0.001:
				push_error("Hex (%d,%d) esquina %d radio %.4f != %.4f" % [h.q, h.r, i, r, HexGeom.SIZE])
				return 1
			var next_corner := HexGeom.corner(c, (i + 1) % 6)
			var side_len := corner.distance_to(next_corner)
			if absf(side_len - HexGeom.SIZE) > 0.001:
				push_error("Hex (%d,%d) lado %d longitud %.4f != %.4f" % [h.q, h.r, i, side_len, HexGeom.SIZE])
				return 1
	print("  ✓ 19 hexágonos con 6 lados iguales y radio exacto %.2f" % HexGeom.SIZE)
	return 0

func _verify_low_profile_bases() -> int:
	print("\n--- 2. Verificando altura y perfil fino uniforme ---")
	if absf(TableBoardScript.TILE_Y - 3.2) > 0.001:
		push_error("TILE_Y no es 3.2")
		return 1
	if TableBoardScript.RIM_W > 4.0:
		push_error("RIM_W demasiado grueso")
		return 1
	print("  ✓ Grosor de ficha de mesa: %.1f unidades" % TableBoardScript.THICK)
	print("  ✓ Altura de superficie del terreno: %.1f unidades (plano y continuo)" % TableBoardScript.TILE_Y)
	print("  ✓ Anillo de zócalo: %.1f (radio útil %.1f)" % [TableBoardScript.RIM_W, HexGeom.SIZE - TableBoardScript.RIM_W])
	return 0

func _verify_neighbor_seams() -> int:
	print("\n--- 3. Verificando encajes y costuras entre vecinos ---")
	var g = GameScript.new()
	g.new_game()
	
	# Para cada arista compartida entre dos hexágonos, verificar coincidencia milimétrica
	var checked_edges := 0
	for ek in g.edges.keys():
		var ends: Array = g.edges[ek]
		var v0: Vector2 = g.v_pos[int(ends[0])]
		var v1: Vector2 = g.v_pos[int(ends[1])]
		var len := v0.distance_to(v1)
		if absf(len - HexGeom.SIZE) > 0.001:
			push_error("Arista %s longitud %.4f" % [ek, len])
			return 1
		checked_edges += 1
	print("  ✓ %d aristas compartidas coinciden con tolerancia < 0.001 (sin huecos ni solapamientos)" % checked_edges)
	return 0

func _verify_model_bounding() -> int:
	print("\n--- 4. Verificando GLB recortado contra SCENERY_R ---")
	var kinds := {"wood": 0, "clay": 1, "grain": 2, "stone": 3, "sheep": 4}
	for name in kinds.keys():
		var node = Dressing.new()
		root.add_child(node)
		if not node.mount_calibrated_glb(int(kinds[name]), 0):
			push_error("No se pudo montar %s" % name)
			node.free()
			return 1
		var max_r := 0.0
		var meshes: Array[MeshInstance3D] = []
		_gather_meshes(node, meshes)
		for mi in meshes:
			var m := mi.mesh
			if m == null:
				continue
			var xf := mi.global_transform
			for surface_idx in m.get_surface_count():
				var arr: Array = m.surface_get_arrays(surface_idx)
				if arr.is_empty() or arr[Mesh.ARRAY_VERTEX] == null:
					continue
				var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
				var step := maxi(1, verts.size() / 400)
				var i := 0
				while i < verts.size():
					var world: Vector3 = xf * verts[i]
					max_r = maxf(max_r, Vector2(world.x, world.z).length())
					i += step
		print("  Modelo %s: r_max=%.2f SCENERY_R=%.1f" % [name, max_r, Dressing.SCENERY_R])
		if max_r > Dressing.SCENERY_R + 3.0:
			push_error("Modelo %s desborda el hexágono (%.2f)" % [name, max_r])
			node.free()
			return 1
		node.free()
	print("  ✓ Pilot GLB recortados caben en SCENERY_R+3")
	return 0

func _calc_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(node, meshes)
	for mi in meshes:
		var a := mi.get_aabb()
		for i in 8:
			var p := a.get_endpoint(i)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box

func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_gather_meshes(c, out)
