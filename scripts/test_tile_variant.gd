extends SceneTree
# Valida la variante de casilla (HEX_TILE_AT) en el tablero real:
#   - se carga en la casilla pedida y solo ahí;
#   - ningún vértice sale de su hexágono (radio de loseta 82, celda 90);
#   - mismo pivote, ancho y base que la casilla original del mismo recurso;
#   - la roca no se acerca al disco de la ficha.
# Uso: godot --headless --path . -s res://scripts/test_tile_variant.gd

const TableBoardScript := preload("res://scripts/table_board.gd")
const GameScript := preload("res://scripts/match.gd")
const HexGeom := preload("res://scripts/hex_lib.gd")

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _ok(name: String, cond: bool, detail := "") -> void:
	print("[variante] %s %s %s" % ["ok" if cond else "FALLO", name, detail])
	if not cond:
		fails += 1

func _hex_dist(p: Vector2, radius: float) -> float:
	# pointy-top: apotema sobre X, puntas sobre Z
	var ax := absf(p.x)
	var ay := absf(p.y)
	return maxf(ax / (radius * sqrt(3.0) / 2.0), ax / (radius * sqrt(3.0)) + ay / radius)

func _measure(node: Node3D, center: Vector2) -> Dictionary:
	var hd := 0.0
	var hd_rock := 0.0
	var near_rock := INF
	var y0 := INF
	var y1 := -INF
	var minp := Vector2(INF, INF)
	var maxp := Vector2(-INF, -INF)
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		pending.append_array(n.get_children())
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var is_rock := String(mi.name).contains("Boulder") or String(mi.mesh.resource_name).contains("Boulder")
		var xf := mi.global_transform
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			for v in verts:
				var w := xf * v
				var p := Vector2(w.x, w.z) - center
				var d := _hex_dist(p, HexGeom.tile_radius())
				hd = maxf(hd, d)
				minp = minp.min(p)
				maxp = maxp.max(p)
				y0 = minf(y0, w.y)
				y1 = maxf(y1, w.y)
				if is_rock:
					hd_rock = maxf(hd_rock, d)
					near_rock = minf(near_rock, p.length())
	return {"hd": hd, "hd_rock": hd_rock, "near_rock": near_rock, "y0": y0, "y1": y1, "min": minp, "max": maxp}

func _tile_node(board: Node, path: String, center: Vector2) -> Node3D:
	for c in board.get_children():
		if c is Node3D and String(c.scene_file_path) == path:
			var n := c as Node3D
			var box_c := Vector2(n.global_position.x, n.global_position.z)
			if box_c.distance_to(center) < HexGeom.SIZE * 0.6:
				return n
	return null

func _run() -> void:
	var board = TableBoardScript.new()
	root.add_child(board)
	var g = GameScript.new()
	g.new_game()
	var terrains: Array[Texture2D] = []
	for n in ["terreno_madera", "terreno_arcilla", "terreno_grano", "terreno_piedra", "terreno_ovejas"]:
		terrains.append(load("res://art/%s.jpg" % n))
	board.bind(g, terrains, load("res://art/terreno_laguna.jpg"), load("res://art/mar_isla.jpg"), ThemeDB.fallback_font)
	await process_frame
	await process_frame

	for key in TableBoardScript.HEX_TILE_AT:
		var spec: Dictionary = TableBoardScript.HEX_TILE_AT[key]
		var qr: PackedStringArray = String(key).split(",")
		var q := int(qr[0])
		var r := int(qr[1])
		var res := int(spec["res"])
		var center: Vector2 = HexGeom.hex_to_pixel(q, r)
		var cell_res := -1
		for h in g.hexes:
			if int(h.q) == q and int(h.r) == r:
				cell_res = int(h.resource)
		_ok("casilla %s es del recurso %d" % [key, res], cell_res == res)
		var variant := _tile_node(board, String(spec["path"]), center)
		_ok("variante cargada en %s" % key, variant != null)
		if variant == null:
			continue
		var count := 0
		for c in board.get_children():
			if String(c.scene_file_path) == String(spec["path"]):
				count += 1
		_ok("variante usada una sola vez", count == 1, "(%d)" % count)
		# Casilla original del mismo recurso para comparar
		var orig: Node3D = null
		var orig_center := Vector2.ZERO
		for h in g.hexes:
			if int(h.resource) != res or (int(h.q) == q and int(h.r) == r):
				continue
			orig_center = HexGeom.hex_to_pixel(int(h.q), int(h.r))
			orig = _tile_node(board, String(TableBoardScript.HEX_TILE[res]), orig_center)
			if orig != null:
				break
		var mv := _measure(variant, center)
		print("[variante] medida variante: hex_dist=%.4f roca=%.4f roca_min_centro=%.1f y=[%.2f, %.2f] x=[%.1f, %.1f] z=[%.1f, %.1f]" % [
			mv.hd, mv.hd_rock, mv.near_rock, mv.y0, mv.y1, mv.min.x, mv.max.x, mv.min.y, mv.max.y])
		_ok("no sale de su loseta (radio 82)", mv.hd <= 1.003, "%.4f" % mv.hd)
		_ok("no invade vecinas (celda 90)", mv.hd * HexGeom.tile_radius() <= HexGeom.SIZE, "%.1f u" % (mv.hd * HexGeom.tile_radius()))
		_ok("roca dentro de la loseta", mv.hd_rock < 1.0, "%.4f" % mv.hd_rock)
		_ok("roca lejos de la ficha (disco %.0f u)" % TableBoardScript.TOKEN_RADIUS, mv.near_rock > TableBoardScript.TOKEN_RADIUS + 6.0, "%.1f u" % mv.near_rock)
		if orig != null:
			var mo := _measure(orig, orig_center)
			print("[variante] medida original: hex_dist=%.4f y=[%.2f, %.2f] x=[%.1f, %.1f] z=[%.1f, %.1f]" % [
				mo.hd, mo.y0, mo.y1, mo.min.x, mo.max.x, mo.min.y, mo.max.y])
			_ok("misma base que la original", absf(mv.y0 - mo.y0) < 0.05, "%.3f vs %.3f" % [mv.y0, mo.y0])
			_ok("mismo ancho que la original", absf((mv.max.x - mv.min.x) - (mo.max.x - mo.min.x)) < 0.5)
			_ok("mismo alto de punta a punta", absf((mv.max.y - mv.min.y) - (mo.max.y - mo.min.y)) < 0.5)
			_ok("mismo pivote (centrada)", absf(mv.min.y + mv.max.y) < 0.5 and absf(mv.min.x + mv.max.x) < 0.5)
	print("=== FIN VARIANTE fails=%d ===" % fails)
	quit(1 if fails > 0 else 0)
