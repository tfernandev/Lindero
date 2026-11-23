extends SceneTree

const HexGeom := preload("res://scripts/hex_lib.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")

const PATHS := {
	"wood": "res://models/pilot/pilot_wood.glb",
	"clay": "res://models/pilot/pilot_clay.glb",
	"grain": "res://models/pilot/pilot_grain.glb",
	"stone": "res://models/pilot/pilot_stone.glb",
	"sheep": "res://models/pilot/pilot_sheep.glb",
}

const KIND := {
	"wood": 0,
	"clay": 1,
	"grain": 2,
	"stone": 3,
	"sheep": 4,
}

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== AUDITORÍA PILOT GLB (piedra + vecinos) ===")
	Dressing.clear_pilot_cache()
	Dressing.debug_log = true
	for name in PATHS.keys():
		_audit_path(name, String(PATHS[name]))
	print("=== FIN AUDITORÍA ===")
	quit(0)

func _audit_path(name: String, path: String) -> void:
	print("\n--------------------------------------------------")
	print("MODELO: %s" % name)
	print("  ruta: %s" % path)
	print("  ResourceLoader.exists: %s" % ResourceLoader.exists(path))
	if not ResourceLoader.exists(path):
		print("  [ERROR] recurso ausente")
		return
	var packed := load(path) as PackedScene
	if packed == null:
		print("  [ERROR] PackedScene null")
		return
	var inst := packed.instantiate() as Node3D
	if inst == null:
		print("  [ERROR] instancia no Node3D")
		return
	var meshes: Array[MeshInstance3D] = []
	_gather(inst, meshes)
	print("  MeshInstance3D: %d  visible=%s  layers=%s" % [
		meshes.size(), inst.visible, inst.layers if inst is VisualInstance3D else 1
	])
	var box := AABB()
	var first := true
	var verts := 0
	var tris := 0
	for mi in meshes:
		print("    mesh '%s' vis=%s layers=%d surfaces=%d" % [
			mi.name, mi.visible, mi.layers, mi.mesh.get_surface_count() if mi.mesh else 0
		])
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(s)
			var v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			verts += v.size()
			tris += idx.size() / 3 if not idx.is_empty() else v.size() / 3
			var mat := mi.mesh.surface_get_material(s)
			if mat == null:
				mat = mi.get_active_material(s)
			var alpha := 1.0
			var albedo := Color.WHITE
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				alpha = sm.albedo_color.a
				albedo = sm.albedo_color
				print("      surf %d verts=%d albedo=%s alpha=%.2f transp=%d shader=%s" % [
					s, v.size(), albedo, alpha, sm.transparency, sm.shading_mode
				])
			elif mat != null:
				print("      surf %d verts=%d mat=%s" % [s, v.size(), mat.get_class()])
			else:
				print("      surf %d verts=%d mat=null" % [s, v.size()])
		var local := mi.get_aabb()
		var xf := mi.transform
		var walk: Node = mi.get_parent()
		while walk != null and walk != inst:
			if walk is Node3D:
				xf = (walk as Node3D).transform * xf
			walk = walk.get_parent()
		for i in 8:
			var p := xf * local.get_endpoint(i)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	print("  AABB crudo pos=%s size=%s center=%s" % [box.position, box.size, box.get_center()])
	print("  verts=%d tris=%d  XZ half=(%.3f, %.3f)  Y=%.3f" % [
		verts, tris, box.size.x * 0.5, box.size.z * 0.5, box.size.y
	])
	if not KIND.has(name):
		inst.free()
		return
	var dresser := Dressing.new()
	var kind: int = KIND[name]
	var holder := Node3D.new()
	holder.add_child(inst)
	var t0 := Time.get_ticks_msec()
	var cut: ArrayMesh = dresser._cut_pilot_to_hex(holder, kind)
	var dt := Time.get_ticks_msec() - t0
	if cut == null:
		print("  [CORTE] FAILED en %d ms" % dt)
		holder.free()
		dresser.free()
		return
	var probe := MeshInstance3D.new()
	probe.mesh = cut
	var probe_root := Node3D.new()
	probe_root.add_child(probe)
	var cut_box := dresser._local_aabb(probe_root)
	print("  [CORTE] OK surfs=%d ms=%d cutAABB pos=%s size=%s" % [
		cut.get_surface_count(), dt, cut_box.position, cut_box.size
	])
	var last_surf := cut.get_surface_count() - 1
	if last_surf >= 0:
		var cap_mat := cut.surface_get_material(last_surf)
		if cap_mat is StandardMaterial3D:
			print("  [CORTE] última superficie (tapas) albedo=%s cull=%d" % [
				(cap_mat as StandardMaterial3D).albedo_color,
				(cap_mat as StandardMaterial3D).cull_mode
			])
	var fit_node := Node3D.new()
	var fit_mi := MeshInstance3D.new()
	fit_mi.mesh = cut
	fit_node.add_child(fit_mi)
	var clip_r := dresser._inscribed_hex_radius(box)
	dresser._fit_scenery(fit_node, cut_box, Dressing.SCENERY_SINK, box.get_center(), clip_r)
	print("  [FIT] scale=%.4f pos=%s sink=%.2f clip_r=%.4f target_r=%.1f" % [
		fit_node.scale.x, fit_node.position, Dressing.SCENERY_SINK, clip_r, Dressing.SCENERY_R
	])
	var fitted := AABB()
	var first_f := true
	var xf_fit := fit_node.transform * fit_mi.transform
	var fa := fit_mi.get_aabb()
	for i in 8:
		var p := xf_fit * fa.get_endpoint(i)
		if first_f:
			fitted = AABB(p, Vector3.ZERO)
			first_f = false
		else:
			fitted = fitted.expand(p)
	print("  [FIT] AABB mundo-local pos=%s size=%s" % [fitted.position, fitted.size])
	var overflow := 0.0
	for i in 8:
		var p := fitted.get_endpoint(i)
		overflow = maxf(overflow, _hex_outside(Vector2(p.x, p.z), HexGeom.SIZE))
	print("  [FIT] overflow hex SIZE=90: %.3f (0 = dentro)" % overflow)
	print("  [ALTURA] minY=%.3f maxY=%.3f  (suelo dressing y=0, sink mete minY negativo)" % [
		fitted.position.y, fitted.position.y + fitted.size.y
	])
	probe_root.free()
	fit_node.free()
	holder.free()
	dresser.free()

func _hex_outside(p: Vector2, radius: float) -> float:
	var worst := 0.0
	var center := Vector2.ZERO
	for i in 6:
		var a: Vector2 = HexGeom.corner(center, i)
		var b: Vector2 = HexGeom.corner(center, (i + 1) % 6)
		a = center + (a - center) * (radius / HexGeom.SIZE)
		b = center + (b - center) * (radius / HexGeom.SIZE)
		var edge := b - a
		var inward := Vector2(-edge.y, edge.x)
		if inward.length_squared() < 0.0001:
			continue
		inward = inward.normalized()
		var d := inward.dot(p - a)
		if d < 0.0:
			worst = maxf(worst, -d)
	return worst

func _gather(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append(node)
	for child in node.get_children():
		_gather(child, into)
