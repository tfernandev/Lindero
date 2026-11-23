extends SceneTree

const HexGeom := preload("res://scripts/hex_lib.gd")

func _init() -> void:
	print("=== VERIFICACIÓN MATEMÁTICA DE GEOMETRÍA HEXAGONAL ===")
	
	# 1. Verificar hexágono regular
	var corners: Array[Vector2] = []
	for i in 6:
		corners.append(HexGeom.corner(Vector2.ZERO, i))
	
	print("Vértices del hexágono (SIZE = %.1f):" % HexGeom.SIZE)
	for i in 6:
		print("  V%d: (%.3f, %.3f) - Distancia al centro: %.3f" % [i, corners[i].x, corners[i].y, corners[i].length()])
		if absf(corners[i].length() - HexGeom.SIZE) > 0.0001:
			push_error("Radio incorrecto en V%d" % i)
			quit(1)
			return

	# 2. Longitudes de los 6 lados
	print("\nLongitudes de los 6 lados:")
	for i in 6:
		var j := (i + 1) % 6
		var side_len := corners[i].distance_to(corners[j])
		print("  Lado %d-%d: %.4f" % [i, j, side_len])
		if absf(side_len - HexGeom.SIZE) > 0.0001:
			push_error("Lado %d-%d no mide %.1f: %.4f" % [i, j, HexGeom.SIZE, side_len])
			quit(1)
			return

	# 3. Ángulos interiores
	print("\nÁngulos interiores (deben ser 120.00°):")
	for i in 6:
		var prev := corners[(i + 5) % 6]
		var cur := corners[i]
		var next := corners[(i + 1) % 6]
		var v1 := (prev - cur).normalized()
		var v2 := (next - cur).normalized()
		var angle_deg := rad_to_deg(acos(clampf(v1.dot(v2), -1.0, 1.0)))
		print("  Ángulo en V%d: %.2f°" % [i, angle_deg])
		if absf(angle_deg - 120.0) > 0.01:
			push_error("Ángulo incorrecto en V%d: %.2f" % [i, angle_deg])
			quit(1)
			return

	# 4. Comprobación de encaje entre dos hexágonos vecinos
	# Vecino A en (0, 0) y Vecino B en (1, 0)
	var c_a := HexGeom.hex_to_pixel(0, 0)
	var c_b := HexGeom.hex_to_pixel(1, 0)
	var dist_centers := c_a.distance_to(c_b)
	var expected_dist := HexGeom.SIZE * sqrt(3.0)
	print("\nDistancia entre centros (0,0) y (1,0): %.4f (Esperada: %.4f)" % [dist_centers, expected_dist])
	if absf(dist_centers - expected_dist) > 0.0001:
		push_error("Distancia entre centros errónea")
		quit(1)
		return

	# Vértices de A y B en coordenadas globales
	var corners_a: Array[Vector2] = []
	var corners_b: Array[Vector2] = []
	for i in 6:
		corners_a.append(HexGeom.corner(c_a, i))
		corners_b.append(HexGeom.corner(c_b, i))

	# Buscar arista compartida entre A y B
	var shared_pts := 0
	for pa in corners_a:
		for pb in corners_b:
			if pa.distance_to(pb) < 0.001:
				shared_pts += 1
				print("  Punto coincidente A-B: (%.3f, %.3f)" % [pa.x, pa.y])

	print("Puntos compartidos entre vecinos: %d (deben ser exactamente 2)" % shared_pts)
	if shared_pts != 2:
		push_error("No comparten exactamente 2 vértices (1 arista)")
		quit(1)
		return

	print("\n>>> TODAS LAS COMPROBACIONES GEOMÉTRICAS DIERON 100% OK <<<")
	quit(0)
