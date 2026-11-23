extends SceneTree

const HexGeom := preload("res://scripts/hex_lib.gd")
const GameScript := preload("res://scripts/match.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")
const TableBoardScript := preload("res://scripts/table_board.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== TEST GEOMETRÍA TABLERO LINDERO ===")
	var fails := 0
	var g = GameScript.new()
	g.new_game()

	if g.hexes.size() != 19:
		print("FAIL count=%d expected 19" % g.hexes.size())
		fails += 1
	else:
		print("OK 19 casillas")

	var seen := {}
	var counts := {-1: 0, 0: 0, 1: 0, 2: 0, 3: 0, 4: 0}
	var lagoon_at := Vector2i(999, 999)
	for h in g.hexes:
		var key := "%d,%d" % [int(h.q), int(h.r)]
		if seen.has(key):
			print("FAIL duplicado %s" % key)
			fails += 1
		seen[key] = true
		var kind := int(h.resource)
		counts[kind] = int(counts.get(kind, 0)) + 1
		if kind < 0:
			lagoon_at = Vector2i(int(h.q), int(h.r))
		if not GameScript.TILE_DEF.has(key):
			print("FAIL hex %s no está en TILE_DEF" % key)
			fails += 1
		else:
			var def: Array = GameScript.TILE_DEF[key]
			if int(def[0]) != kind or int(def[1]) != int(h.number):
				print("FAIL %s resource/number divergió de TILE_DEF" % key)
				fails += 1

	if lagoon_at != Vector2i(0, 0):
		print("FAIL laguna en %s expected (0,0)" % lagoon_at)
		fails += 1
	else:
		print("OK laguna central (0,0)")

	print("recursos laguna=%d madera=%d arcilla=%d grano=%d piedra=%d ovejas=%d" % [
		counts[-1], counts[0], counts[1], counts[2], counts[3], counts[4]
	])
	if counts[-1] != 1 or counts[0] != 5 or counts[1] != 4 or counts[2] != 3 or counts[3] != 4 or counts[4] != 2:
		print("FAIL conteo de terrenos distinto a TILE_DEF")
		fails += 1
	else:
		print("OK distribución TILE_DEF intacta")

	var expected := HexGeom.neighbor_distance()
	var neigh := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]
	var lattice_ok := 0
	var lattice_bad := 0
	for h in g.hexes:
		var c0: Vector2 = HexGeom.hex_to_pixel(int(h.q), int(h.r))
		for n in neigh:
			var nq: int = int(h.q) + int(n.x)
			var nr: int = int(h.r) + int(n.y)
			if not seen.has("%d,%d" % [nq, nr]):
				continue
			var c1: Vector2 = HexGeom.hex_to_pixel(nq, nr)
			var dist := c0.distance_to(c1)
			if absf(dist - expected) > 0.05:
				print("FAIL lattice (%d,%d)->(%d,%d) dist=%.4f expected=%.4f" % [h.q, h.r, nq, nr, dist, expected])
				lattice_bad += 1
				fails += 1
			else:
				lattice_ok += 1
	print("OK lattice pares=%d dist=%.4f SIZE=%.1f apothem=%.4f TILE_Y=%.2f" % [
		lattice_ok, expected, HexGeom.SIZE, HexGeom.apothem(), TableBoardScript.TILE_Y
	])
	if lattice_bad > 0:
		print("FAIL %d aristas con distancia incorrecta" % lattice_bad)

	print("SCENERY_R=%.1f RIM=%.1f WELL=%.1f SINK=%.2f" % [
		Dressing.SCENERY_R, HexGeom.SIZE - Dressing.SCENERY_R, Dressing.TOKEN_WELL_R, Dressing.SCENERY_SINK
	])
	if Dressing.SCENERY_R >= HexGeom.SIZE:
		print("FAIL SCENERY_R cubre el vértice de construcción")
		fails += 1
	if TableBoardScript.RIM_W > 4.0:
		print("FAIL RIM_W=%.1f demasiado grueso" % TableBoardScript.RIM_W)
		fails += 1

	var corners_ok := true
	for i in 6:
		var p := HexGeom.corner(Vector2.ZERO, i)
		if absf(p.length() - HexGeom.SIZE) > 0.001:
			corners_ok = false
	if corners_ok:
		print("OK hexágono regular pointy-top radio=SIZE")
	else:
		print("FAIL vértices no están a SIZE")
		fails += 1

	for kind in Dressing.PILOT_GLB.keys():
		var spec: Dictionary = Dressing.PILOT_GLB[kind]
		var path := String(spec.get("path", ""))
		if path == "" or not ResourceLoader.exists(path):
			print("FAIL GLB ausente kind=%s path=%s" % [kind, path])
			fails += 1
		else:
			print("OK GLB kind=%s %s" % [kind, path])
	if not ResourceLoader.exists("res://models/pilot/pilot_pueblo.glb"):
		print("FAIL falta pilot_pueblo.glb (puestos/granjas)")
		fails += 1
	else:
		print("OK pilot_pueblo.glb")

	print("=== RESULTADO fails=%d ===" % fails)
	quit(1 if fails > 0 else 0)
