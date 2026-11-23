extends SceneTree

func _init() -> void:
	var path := "res://models/pilot/pilot_clay.glb"
	var packed := load(path) as PackedScene
	var inst := packed.instantiate() as Node3D
	
	# Obtener AABB
	var mi: MeshInstance3D = inst.get_child(0) as MeshInstance3D
	var aabb := mi.get_aabb()
	var center := aabb.get_center()
	var base_y := aabb.position.y
	var rot_y := PI * 0.5
	var target_r := 62.0
	
	# Medir max_r
	var max_r := 0.0
	var verts: PackedVector3Array = mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in verts:
		var p := v - Vector3(center.x, 0, center.z)
		p = p.rotated(Vector3.UP, rot_y)
		max_r = maxf(max_r, Vector2(p.x, p.z).length())
	
	var scl := target_r / max_r
	
	# Construir jerarquía
	var root := Node3D.new()
	var pivot := Node3D.new()
	pivot.name = "Pivot"
	pivot.rotation.y = rot_y
	root.add_child(pivot)
	
	inst.position = Vector3(-center.x * scl, -base_y * scl, -center.z * scl)
	inst.scale = Vector3(scl, scl, scl)
	pivot.add_child(inst)
	
	# Ahora medir los vértices resultantes respecto a root
	var final_min_r := INF
	var final_max_r := -INF
	var final_min_y := INF
	var final_max_y := -INF
	
	for v in verts:
		var world_v := pivot.transform * (inst.transform * v)
		var r := Vector2(world_v.x, world_v.z).length()
		final_max_r = maxf(final_max_r, r)
		final_min_r = minf(final_min_r, r)
		final_min_y = minf(final_min_y, world_v.y)
		final_max_y = maxf(final_max_y, world_v.y)
	
	print("RESULTADO JERARQUÍA:")
	print("  Radio máximo respecto al origen: %.3f (Target: %.3f)" % [final_max_r, target_r])
	print("  Base Y mínima: %.4f (debe ser 0.0000)" % final_min_y)
	print("  Altura Y máxima: %.4f" % final_max_y)
	
	if absf(final_max_r - target_r) > 0.01:
		push_error("Error en radio máximo")
		quit(1)
		return
	if absf(final_min_y) > 0.01:
		push_error("Error en base Y")
		quit(1)
		return
	
	print("JERARQUÍA Y TRANSFORMACIÓN 100% PERFECTA!")
	root.free()
	quit(0)
