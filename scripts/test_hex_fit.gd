extends SceneTree

const HexGeom := preload("res://scripts/hex_lib.gd")

func _init() -> void:
	print("=== PRUEBA DE AJUSTE GEOMÉTRICO DETERMINISTA DE MODELOS ===")
	
	var models := {
		"wood": {"path": "res://models/pilot/pilot_wood.glb", "flat_topped": false},
		"clay": {"path": "res://models/pilot/pilot_clay.glb", "flat_topped": true},
		"sheep": {"path": "res://models/pilot/pilot_sheep.glb", "flat_topped": false},
		"pueblo": {"path": "res://models/pilot/pilot_pueblo.glb", "flat_topped": true},
	}
	
	# Radio máximo permitido para el contenido decorativo dentro del zócalo (R <= 62.0)
	# para que el apotema (R * sqrt(3)/2 = 53.7) no toque el bisel de madera (R_rim = 76.0)
	var TARGET_RADIUS := 62.0
	
	for name in models.keys():
		var info: Dictionary = models[name]
		var packed := load(info["path"]) as PackedScene
		if packed == null:
			print("No se pudo cargar %s" % info["path"])
			continue
		var inst := packed.instantiate() as Node3D
		
		# Calcular AABB del modelo original
		var aabb := _calc_aabb(inst)
		var center := aabb.get_center()
		var base_y := aabb.position.y
		
		# Rotación correctiva si es flat-topped
		var rot_y := deg_to_rad(90.0) if bool(info["flat_topped"]) else 0.0
		
		# Medir radio máximo en XZ alrededor del centro geométrico
		var max_r := 0.0
		var meshes: Array[MeshInstance3D] = []
		_gather_meshes(inst, meshes)
		for mi in meshes:
			var m := mi.mesh
			if m == null: continue
			for s in m.get_surface_count():
				var verts: PackedVector3Array = m.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
				for v in verts:
					# Aplicar rotación y centrado
					var p := v - Vector3(center.x, 0, center.z)
					if rot_y != 0.0:
						p = p.rotated(Vector3.UP, rot_y)
					var r := Vector2(p.x, p.z).length()
					max_r = maxf(max_r, r)
		
		var scale_factor := TARGET_RADIUS / max_r
		var final_height := aabb.size.y * scale_factor
		
		print("\nModelo: %s" % name)
		print("  Radio original: %.2f -> Escala uniforme: %.4f" % [max_r, scale_factor])
		print("  Radio resultante: %.2f (Límite: %.2f)" % [max_r * scale_factor, TARGET_RADIUS])
		print("  Altura Y resultante: %.2f" % final_height)
		print("  Rotación Y correctiva: %.1f°" % rad_to_deg(rot_y))
		
		if max_r * scale_factor > TARGET_RADIUS + 0.01:
			push_error("El radio excede el límite permitido")
		
		inst.free()
	
	print("\n>>> TEST DE AJUSTE DETERMINISTA COMPLETADO EXITOSAMENTE <<<")
	quit(0)

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
