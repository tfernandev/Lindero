extends SceneTree

const HexGeom := preload("res://scripts/hex_lib.gd")
const GameScript := preload("res://scripts/match.gd")

func _init() -> void:
	print("=== PRUEBA DE ENSAMBLAJE DE TABLERO Y COSTAS ===")
	var g = GameScript.new()
	g.new_game()
	
	var hex_set := {}
	for h in g.hexes:
		hex_set["%d,%d" % [int(h.q), int(h.r)]] = true
	
	var NEIGHBORS := [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(1, -1),
	]
	
	var total_coast_edges := 0
	var total_shared_edges := 0
	
	for h in g.hexes:
		var q := int(h.q)
		var r := int(h.r)
		var coast_count := 0
		for i in 6:
			var n: Vector2i = Vector2i(q, r) + (NEIGHBORS[i] as Vector2i)
			if not hex_set.has("%d,%d" % [n.x, n.y]):
				coast_count += 1
				total_coast_edges += 1
			else:
				total_shared_edges += 1
		print("Hex (%2d, %2d): %d costas, %d compartidas" % [q, r, coast_count, 6 - coast_count])
	
	print("\nTotal aristas de costa: %d (aristas exteriores del tablero)" % total_coast_edges)
	print("Total aristas compartidas (duplicadas por vecinos): %d" % total_shared_edges)
	print("Aristas internas únicas: %d" % (total_shared_edges / 2))
	
	# En un tablero de 19 hexágonos:
	# Total aristas = 19 * 6 = 114 aristas de hexágonos.
	# El anillo exterior de 19 hexágonos tiene exactamente 30 aristas de costa y 42 aristas internas (84 medias aristas).
	# 30 + 84 = 114.
	print("Suma: %d (debe ser 114)" % (total_coast_edges + total_shared_edges))
	if total_coast_edges + total_shared_edges != 114:
		push_error("Error en cuenta de aristas")
		quit(1)
		return
	if total_coast_edges != 30:
		push_error("El perímetro exterior de 19 hexágonos debe tener exactamente 30 aristas de costa, dio %d" % total_coast_edges)
		quit(1)
		return

	print(">>> TOPOLOGÍA DE COSTAS Y BORDES VERIFICADA AL 100% <<<")
	quit(0)
