extends SceneTree

const HexGeom := preload("res://scripts/hex_lib.gd")

func _init() -> void:
	print("=== AUDITORÍA TÉCNICA DE MODELOS GLB Y GEOMETRÍA DE LINDERO ===")
	
	var models := {
		"pilot_sheep": "res://models/pilot/pilot_sheep.glb",
		"pilot_clay": "res://models/pilot/pilot_clay.glb",
		"pilot_wood": "res://models/pilot/pilot_wood.glb",
		"pilot_grain": "res://models/pilot/pilot_grain.glb",
		"pilot_stone": "res://models/pilot/pilot_stone.glb",
		"pilot_pueblo": "res://models/pilot/pilot_pueblo.glb",
	}
	
	for name in models.keys():
		var path: String = models[name]
		print("\n--------------------------------------------------")
		print("MODELO: %s (%s)" % [name, path])
		if not ResourceLoader.exists(path):
			print("  [ERROR] No existe el recurso")
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			print("  [ERROR] No se pudo cargar PackedScene")
			continue
		var inst := packed.instantiate() as Node3D
		if inst == null:
			print("  [ERROR] No se pudo instanciar Node3D")
			continue
		
		_audit_node(inst)
		_test_pilot_cut(inst, name)
		inst.free()
	
	print("\n--------------------------------------------------")
	print("AUDITORÍA DE MODELOS TRIPO EN TMP:")
	var tmp_models := {
		"tripo_forest": "c:/Users/Usuario/source/JuegosMobile/tmp/lindero-forest-hex/tripo-out/forest-hex-a3ae9c5b/model.glb",
		"tripo_arcilla": "c:/Users/Usuario/source/JuegosMobile/tmp/lindero-hex-crops/tripo-out/arcilla-sq-85006c1a/model.glb",
		"tripo_grano": "c:/Users/Usuario/source/JuegosMobile/tmp/lindero-hex-crops/tripo-out/grano-sq-e4a78a5a/model.glb",
		"tripo_madera": "c:/Users/Usuario/source/JuegosMobile/tmp/lindero-hex-crops/tripo-out/madera-sq-74692473/model.glb",
		"tripo_piedra": "c:/Users/Usuario/source/JuegosMobile/tmp/lindero-hex-crops/tripo-out/piedra-sq-84dd73eb/model.glb",
	}
	for name in tmp_models.keys():
		var p: String = tmp_models[name]
		print("\nTMP MODELO: %s" % name)
		var gltf := GLTFDocument.new()
		var state := GLTFState.new()
		var err := gltf.append_from_file(p, state)
		if err != OK:
			print("  [ERROR] No se pudo parsear GLTF: %d" % err)
			continue
		var node := gltf.generate_scene(state) as Node3D
		if node != null:
			_audit_node(node)
			node.free()
	
	print("\n=== FIN DE AUDITORÍA ===")
	quit(0)

func _audit_node(root: Node3D) -> void:
	var meshes: Array[MeshInstance3D] = []
	_gather_meshes(root, meshes)
	print("  MeshInstances encontradas: %d" % meshes.size())
	
	var total_verts := 0
	var total_tris := 0
	var total_aabb := AABB()
	var first_aabb := true
	
	for mi in meshes:
		var m := mi.mesh
		if m == null:
			continue
		print("    - Mesh: '%s' (surfaces: %d)" % [mi.name, m.get_surface_count()])
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var inds: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var v_count := verts.size()
			var t_count := inds.size() / 3 if not inds.is_empty() else v_count / 3
			total_verts += v_count
			total_tris += t_count
			var mat := mi.get_active_material(s)
			var mat_name := mat.resource_name if mat != null else "null"
			print("      Surf %d: %d verts, %d tris, mat: %s" % [s, v_count, t_count, mat_name])
		var aabb := mi.get_aabb()
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		for i in 8:
			var p := xf * aabb.get_endpoint(i)
			if first_aabb:
				total_aabb = AABB(p, Vector3.ZERO)
				first_aabb = false
			else:
				total_aabb = total_aabb.expand(p)
	
	print("  AABB Total: Pos %s, Size %s" % [total_aabb.position, total_aabb.size])
	print("  Centro AABB: %s" % total_aabb.get_center())
	print("  Extensión XZ: Min r=%.2f, Max r=%.2f, Aspecto X/Z=%.3f" % [
		minf(total_aabb.size.x, total_aabb.size.z) * 0.5,
		maxf(total_aabb.size.x, total_aabb.size.z) * 0.5,
		total_aabb.size.x / maxf(0.001, total_aabb.size.z)
	])
	
	# Inspeccionar forma de la base en los vértices más bajos (15% inferior de Y)
	var low_y_cutoff: float = total_aabb.position.y + total_aabb.size.y * 0.15
	var base_pts: Array[Vector2] = []
	for mi in meshes:
		var m := mi.mesh
		if m == null: continue
		var xf := root.global_transform.affine_inverse() * mi.global_transform
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				var wp := xf * v
				if wp.y <= low_y_cutoff:
					base_pts.append(Vector2(wp.x, wp.z))
	
	if not base_pts.is_empty():
		var center_xz := Vector2(total_aabb.get_center().x, total_aabb.get_center().z)
		var rad_min := INF
		var rad_max := -INF
		var rad_sum := 0.0
		# Muestrear radio en 12 sectores angulares (cada 30 grados)
		var sector_rad: Array[float] = []
		sector_rad.resize(12)
		for i in 12: sector_rad[i] = 0.0
		for p in base_pts:
			var d := (p - center_xz).length()
			rad_min = minf(rad_min, d)
			rad_max = maxf(rad_max, d)
			rad_sum += d
			var ang := posmod(rad_to_deg(atan2(p.y - center_xz.y, p.x - center_xz.x)), 360.0)
			var sec := int(ang / 30.0) % 12
			sector_rad[sec] = maxf(sector_rad[sec], d)
		
		print("  Geometría de la base (Y <= %.2f, %d puntos):" % [low_y_cutoff, base_pts.size()])
		print("    Radio base: min=%.2f, max=%.2f, promedio=%.2f, ratio max/min=%.2f" % [
			rad_min, rad_max, rad_sum / base_pts.size(), rad_max / maxf(0.001, rad_min)
		])
		var sec_str := ""
		for i in 12:
			sec_str += "%d°:%.1f " % [i * 30, sector_rad[i]]
		print("    Radios por sector (30°): %s" % sec_str)

func _gather_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_gather_meshes(c, out)

func _test_pilot_cut(node: Node3D, name: String) -> void:
	var Dressing: GDScript = load("res://scripts/hex_dressing.gd")
	var dresser = Dressing.new()
	var kind := -1
	match name:
		"pilot_wood": kind = 0
		"pilot_clay": kind = 1
		"pilot_grain": kind = 2
		"pilot_stone": kind = 3
		"pilot_sheep": kind = 4
		"pilot_pueblo": kind = -1
	var t0 := Time.get_ticks_msec()
	var cut: ArrayMesh = dresser._cut_pilot_to_hex(node, kind)
	var dt := Time.get_ticks_msec() - t0
	if cut == null:
		print("  [CORTE CSG TEST]: FAILED (retornó null) en %d ms" % dt)
	else:
		var surfs := cut.get_surface_count()
		var v_count := 0
		for s in surfs:
			v_count += (cut.surface_get_arrays(s)[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
		print("  [CORTE CSG TEST]: OK (%d superficies, %d verts) en %d ms" % [surfs, v_count, dt])
	dresser.free()
