extends SceneTree

const DressingScript := preload("res://scripts/hex_dressing.gd")
const HexGeom := preload("res://scripts/hex_lib.gd")

func _init() -> void:
	print("=== VALIDACIÓN DE CALIDAD Y DISTRIBUCIÓN DE MINIATURAS ===")
	
	var kinds := {
		"BOSQUE": DressingScript.KIND_WOOD,
		"ARCILLA": DressingScript.KIND_CLAY,
		"TRIGO": DressingScript.KIND_GRAIN,
		"MONTAÑA": DressingScript.KIND_STONE,
		"PRADERA_OVEJAS": DressingScript.KIND_MEADOW,
		"LAGUNA": DressingScript.KIND_LAGOON,
	}
	
	var errors := 0
	
	for name in kinds.keys():
		var kind: int = kinds[name]
		print("\n--- Evaluando terreno: %s (kind=%d) ---" % [name, kind])
		
		var node = DressingScript.new()
		root.add_child(node)
		node.apply(kind, 0, 0)
		
		# Recorrer todos los elementos hijos (MultiMeshInstance3D, MeshInstance3D, etc.)
		var element_count := 0
		var min_r := 999.0
		var max_r := 0.0
		var shadow_count := 0
		
		var meshes: Array[MeshInstance3D] = []
		var multimeshes: Array[MultiMeshInstance3D] = []
		_gather(node, meshes, multimeshes)
		
		print("  Nodos MeshInstance3D directos: %d" % meshes.size())
		print("  Nodos MultiMeshInstance3D: %d" % multimeshes.size())
		
		# Medir MultiMeshes
		for mm_inst in multimeshes:
			var mm := mm_inst.multimesh
			if mm == null: continue
			if mm_inst.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				shadow_count += mm.instance_count
			var xf_array: Array = mm_inst.get_meta("xforms", [])
			for i in mm.instance_count:
				var xf: Transform3D = xf_array[i] if i < xf_array.size() else mm.get_instance_transform(i)
				var pos := Vector2(xf.origin.x, xf.origin.z)
				var r_dist := pos.length()
				if kind != DressingScript.KIND_LAGOON:
					min_r = minf(min_r, r_dist)
				max_r = maxf(max_r, r_dist)
				element_count += 1
		
		# Medir Meshes directas (como ovejas, muelles, botes, lecho)
		for mi in meshes:
			if mi.name == "Soil" or mi.name == "LagoonBed" or mi.name == "WaterSurface":
				continue
			var g_pos := _calc_local_to(node, mi)
			var r_dist := Vector2(g_pos.x, g_pos.z).length()
			if kind != DressingScript.KIND_LAGOON:
				min_r = minf(min_r, r_dist)
			max_r = maxf(max_r, r_dist)
			element_count += 1
			if mi.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON:
				shadow_count += 1
		
		print("  Elementos decorativos totales: %d" % element_count)
		print("  Elementos con sombras activas: %d" % shadow_count)
		var limit := DressingScript.SCENERY_R + 3.0
		print("  Radio máximo hacia bordes: %.2f (Límite SCENERY_R+3=%.1f)" % [max_r, limit])
		if kind == DressingScript.KIND_LAGOON:
			print("  Radio mínimo al centro: n/a (laguna)")
		elif DressingScript.PILOT_GLB.has(kind):
			print("  Radio mínimo al centro: %.2f (pozo central no se recorta: desgarraba el GLB)" % min_r)
		else:
			print("  Radio mínimo al centro: %.2f" % min_r)
		if max_r > limit:
			push_error("ERROR: Elementos invaden el borde exterior en %s (r=%.2f > %.1f)" % [name, max_r, limit])
			errors += 1
		
		if element_count == 0:
			push_error("ERROR: No se generaron elementos para %s" % name)
			errors += 1
		
		node.free()
	
	if errors > 0:
		print("\n>>> FALLARON %d PRUEBAS <<<" % errors)
		quit(1)
	else:
		print("\n>>> TODAS LAS PRUEBAS DE CALIDAD Y DISTRIBUCIÓN PASARON EXITOSAMENTE <<<")
		quit(0)

func _calc_local_to(root: Node3D, node: Node3D) -> Vector3:
	var pos := Vector3.ZERO
	var cur: Node = node
	while cur != null and cur != root:
		if cur is Node3D:
			pos += (cur as Node3D).position
		cur = cur.get_parent()
	return pos

func _gather(cur: Node, meshes: Array[MeshInstance3D], multimeshes: Array[MultiMeshInstance3D]) -> void:
	if cur is MeshInstance3D:
		meshes.append(cur)
	elif cur is MultiMeshInstance3D:
		multimeshes.append(cur)
	for child in cur.get_children():
		_gather(child, meshes, multimeshes)
