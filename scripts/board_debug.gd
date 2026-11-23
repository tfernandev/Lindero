extends Node3D

const HexGeom := preload("res://scripts/hex_lib.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")

const KIND_NAME := {
	-1: "Laguna",
	0: "Madera",
	1: "Arcilla",
	2: "Grano",
	3: "Piedra",
	4: "Ovejas",
}

const OVERFLOW_SLACK := 3.0
const HEIGHT_BURIED := -2.0
const HEIGHT_FLOAT := 12.0
const LINE_Y := 4.0

var findings: Array = []
var _game = null
var _board = null

static func want_enabled() -> bool:
	if not OS.is_debug_build():
		return false
	for a in OS.get_cmdline_user_args():
		if a == "--debug-board":
			return true
	return false

func rebuild(game, board) -> void:
	_game = game
	_board = board
	for child in get_children():
		child.free()
	findings.clear()
	if game == null or board == null:
		return
	_draw_hexes(game, board)
	_draw_pieces(game, board)
	_print_report()

func _draw_hexes(game, board) -> void:
	var ok_mat := _line_mat(Color(0.2, 0.95, 0.85, 1.0))
	var err_mat := _line_mat(Color(1.0, 0.25, 0.18, 1.0))
	var aabb_mat := _line_mat(Color(0.95, 0.82, 0.2, 1.0))
	var vert_mesh := SphereMesh.new()
	vert_mesh.radius = 2.4
	vert_mesh.height = 4.8
	vert_mesh.radial_segments = 10
	vert_mesh.rings = 6
	var center_mesh := SphereMesh.new()
	center_mesh.radius = 3.2
	center_mesh.height = 6.4
	center_mesh.radial_segments = 10
	center_mesh.rings = 6
	var heights: Dictionary = {}
	for h in game.hexes:
		var q := int(h.q)
		var r := int(h.r)
		var kind := int(h.resource)
		var c2: Vector2 = HexGeom.hex_to_pixel(q, r)
		var at := Vector3(c2.x, LINE_Y, c2.y)
		var dress: Node3D = board.get_node_or_null("Dress_%d_%d" % [q, r])
		var mesh_box := AABB()
		var has_mesh := false
		if dress != null:
			mesh_box = _world_aabb(dress)
			has_mesh = mesh_box.size.length() > 0.01
		var flags: PackedStringArray = []
		if Dressing.PILOT_GLB.has(kind):
			var spec: Dictionary = Dressing.PILOT_GLB[kind]
			var path := String(spec.get("path", ""))
			if path != "" and not ResourceLoader.exists(path):
				flags.append("glb-ausente")
		if dress == null and Dressing.wants(kind, q, r):
			flags.append("sin-dressing")
		if has_mesh:
			var overflow := _mesh_overflow(dress, c2, Dressing.SCENERY_R)
			if overflow > OVERFLOW_SLACK:
				flags.append("fuera=%.1f" % overflow)
			if mesh_box.position.y < HEIGHT_BURIED:
				flags.append("enterrado")
			if mesh_box.position.y > board.TILE_Y + HEIGHT_FLOAT:
				flags.append("flotando")
			heights["%d,%d" % [q, r]] = mesh_box.position.y
		else:
			if kind >= 0:
				flags.append("sin-malla")
		var bad := not flags.is_empty()
		var rec := {
			"q": q,
			"r": r,
			"kind": kind,
			"name": KIND_NAME.get(kind, "?"),
			"number": int(h.number),
			"pos": Vector3(c2.x, board.TILE_Y, c2.y),
			"flags": flags,
			"aabb": mesh_box if has_mesh else AABB(),
		}
		findings.append(rec)
		_add_hex_outline(at, HexGeom.SIZE, err_mat if bad else ok_mat)
		for i in 6:
			var corner: Vector2 = HexGeom.corner(c2, i)
			_marker(Vector3(corner.x, LINE_Y + 0.6, corner.y), vert_mesh, err_mat if bad else ok_mat)
		_marker(at + Vector3(0, 1.2, 0), center_mesh, ok_mat)
		if has_mesh:
			_add_aabb(mesh_box, aabb_mat)
		if bad:
			_add_error_fill(Vector3(c2.x, board.TILE_Y + 0.8, c2.y))
		_label(at + Vector3(0, 18.0, 0), _tile_text(rec))
	_flag_height_jumps(game, heights)
	_flag_lattice(game)

func _flag_lattice(game) -> void:
	var expected := HexGeom.neighbor_distance()
	var seen := {}
	var lagoon := 0
	for h in game.hexes:
		var key := "%d,%d" % [int(h.q), int(h.r)]
		if seen.has(key):
			print("[board-debug] ERR duplicado %s" % key)
		seen[key] = true
		if int(h.resource) < 0:
			lagoon += 1
		var c0: Vector2 = HexGeom.hex_to_pixel(int(h.q), int(h.r))
		for n in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1)]:
			var nkey := "%d,%d" % [int(h.q) + n.x, int(h.r) + n.y]
			if not seen.has(nkey) and not _has_hex(game, int(h.q) + n.x, int(h.r) + n.y):
				continue
			if not _has_hex(game, int(h.q) + n.x, int(h.r) + n.y):
				continue
			var c1: Vector2 = HexGeom.hex_to_pixel(int(h.q) + n.x, int(h.r) + n.y)
			var dist := c0.distance_to(c1)
			if absf(dist - expected) > 0.05:
				print("[board-debug] ERR lattice (%s)->(%s) dist=%.3f expected=%.3f" % [key, nkey, dist, expected])
	print("[board-debug] lattice hexes=%d unique=%d laguna=%d neighbor=%.4f SIZE=%.1f apothem=%.4f" % [
		game.hexes.size(), seen.size(), lagoon, expected, HexGeom.SIZE, HexGeom.apothem()
	])
	if game.hexes.size() != 19:
		print("[board-debug] ERR count=%d (esperado 19)" % game.hexes.size())
	if lagoon != 1:
		print("[board-debug] ERR laguna=%d (esperado 1)" % lagoon)

func _has_hex(game, q: int, r: int) -> bool:
	for h in game.hexes:
		if int(h.q) == q and int(h.r) == r:
			return true
	return false

func _flag_height_jumps(game, heights: Dictionary) -> void:
	var neigh := [
		Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1),
		Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, -1),
	]
	for h in game.hexes:
		var key := "%d,%d" % [int(h.q), int(h.r)]
		if not heights.has(key):
			continue
		var y0: float = heights[key]
		for n in neigh:
			var nkey := "%d,%d" % [int(h.q) + n.x, int(h.r) + n.y]
			if not heights.has(nkey):
				continue
			var dy: float = absf(y0 - float(heights[nkey]))
			if dy > 8.0:
				for rec in findings:
					if int(rec.q) == int(h.q) and int(rec.r) == int(h.r):
						var flags: PackedStringArray = rec.flags
						var tag := "salto-y=%.1f" % dy
						if not flags.has(tag):
							flags.append(tag)
						rec.flags = flags
						break

func _draw_pieces(game, board) -> void:
	var road_mat := _line_mat(Color(1.0, 0.55, 0.1, 1.0))
	var build_mat := _line_mat(Color(0.95, 0.2, 0.85, 1.0))
	var num_mat := _line_mat(Color(0.95, 0.95, 0.2, 1.0))
	if game.roads != null:
		for ek in game.roads.keys():
			if not game.edges.has(ek):
				continue
			var ends: Array = game.edges[ek]
			var a: Vector2 = game.v_pos[int(ends[0])]
			var b: Vector2 = game.v_pos[int(ends[1])]
			_add_segment(Vector3(a.x, LINE_Y + 6.0, a.y), Vector3(b.x, LINE_Y + 6.0, b.y), road_mat)
			_label(Vector3((a.x + b.x) * 0.5, LINE_Y + 10.0, (a.y + b.y) * 0.5), "cam %s p%d" % [ek, int(game.roads[ek])])
	if game.buildings != null:
		for vkey in game.buildings.keys():
			var b: Dictionary = game.buildings[vkey]
			var p: Vector2 = game.v_pos[int(vkey)]
			var lvl := int(b.level)
			var kind := "puesto" if lvl < 2 else "granja"
			_marker(Vector3(p.x, LINE_Y + 8.0, p.y), _ball(4.0), build_mat)
			_label(Vector3(p.x, LINE_Y + 16.0, p.y), "%s v%s j%d" % [kind, vkey, int(b.player)])
	for h in game.hexes:
		var c2: Vector2 = HexGeom.hex_to_pixel(int(h.q), int(h.r))
		if int(h.number) <= 0:
			continue
		_marker(Vector3(c2.x, board.TILE_Y + 8.0, c2.y), _ball(2.0), num_mat)
		_label(Vector3(c2.x, board.TILE_Y + 12.0, c2.y), "#%d" % int(h.number))

func _tile_text(rec: Dictionary) -> String:
	var flags: PackedStringArray = rec.flags
	var extra := ""
	if not flags.is_empty():
		extra = "\n!" + " ".join(flags)
	var p: Vector3 = rec.pos
	return "(%d,%d) %s\nn=%d\n(%.0f,%.0f,%.0f)%s" % [
		rec.q, rec.r, rec.name, rec.number, p.x, p.y, p.z, extra,
	]

func _print_report() -> void:
	print("[board-debug] %d hexágonos" % findings.size())
	var errors := 0
	for rec in findings:
		var flags: PackedStringArray = rec.flags
		if flags.is_empty():
			continue
		errors += 1
		print("[board-debug] ERR (%d,%d) %s n=%d %s" % [rec.q, rec.r, rec.name, rec.number, " ".join(flags)])
	print("[board-debug] errores=%d" % errors)
	for kind in Dressing.last_reports.keys():
		print("[board-debug] mount kind=%s %s" % [kind, Dressing.last_reports[kind]])

func _add_hex_outline(at: Vector3, radius: float, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	for i in 6:
		var a: Vector2 = HexGeom.corner(Vector2(at.x, at.z), i)
		var b: Vector2 = HexGeom.corner(Vector2(at.x, at.z), (i + 1) % 6)
		st.add_vertex(Vector3(a.x, at.y, a.y))
		st.add_vertex(Vector3(b.x, at.y, b.y))
	_commit_lines(st, mat)

func _add_aabb(box: AABB, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	var p := box.position
	var s := box.size
	var pts: Array[Vector3] = [
		p,
		p + Vector3(s.x, 0, 0),
		p + Vector3(s.x, 0, s.z),
		p + Vector3(0, 0, s.z),
		p + Vector3(0, s.y, 0),
		p + Vector3(s.x, s.y, 0),
		p + Vector3(s.x, s.y, s.z),
		p + Vector3(0, s.y, s.z),
	]
	var edges := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	for i in range(0, edges.size(), 2):
		st.add_vertex(pts[edges[i]])
		st.add_vertex(pts[edges[i + 1]])
	_commit_lines(st, mat)

func _add_segment(a: Vector3, b: Vector3, mat: Material) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_LINES)
	st.add_vertex(a)
	st.add_vertex(b)
	_commit_lines(st, mat)

func _add_error_fill(at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var y := at.y
	for i in 6:
		var a: Vector2 = HexGeom.corner(Vector2(at.x, at.z), i)
		var b: Vector2 = HexGeom.corner(Vector2(at.x, at.z), (i + 1) % 6)
		st.add_vertex(Vector3(at.x, y, at.z))
		st.add_vertex(Vector3(a.x, y, a.y))
		st.add_vertex(Vector3(b.x, y, b.y))
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.15, 0.1, 0.32)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mi.material_override = mat
	add_child(mi)

func _commit_lines(st: SurfaceTool, mat: Material) -> void:
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = mat
	add_child(mi)

func _marker(at: Vector3, mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = at
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

func _label(at: Vector3, text: String) -> void:
	var lb := Label3D.new()
	lb.text = text
	lb.position = at
	lb.font_size = 28
	lb.pixel_size = 0.18
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.outline_size = 10
	lb.modulate = Color(1, 1, 1, 1)
	lb.outline_modulate = Color(0, 0, 0, 0.9)
	lb.no_depth_test = true
	add_child(lb)

func _line_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	return mat

func _ball(radius: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 8
	m.rings = 4
	return m

func _world_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	for mi in meshes:
		if not mi.is_visible_in_tree():
			continue
		var local := mi.get_aabb()
		for i in 8:
			var p := mi.global_transform * local.get_endpoint(i)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box

func _collect(node: Node, into: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		into.append(node)
	for child in node.get_children():
		_collect(child, into)

func _mesh_overflow(root: Node3D, center: Vector2, radius: float) -> float:
	var worst := 0.0
	var meshes: Array[MeshInstance3D] = []
	_collect(root, meshes)
	for mi in meshes:
		if mi.mesh == null or not mi.is_visible_in_tree():
			continue
		for s in mi.mesh.get_surface_count():
			var verts: PackedVector3Array = mi.mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			if verts.is_empty():
				continue
			var step := maxi(1, verts.size() / 500)
			for i in range(0, verts.size(), step):
				var p := mi.global_transform * verts[i]
				worst = maxf(worst, _hex_outside(Vector2(p.x, p.z), center, radius))
	return worst

func _hex_outside(p: Vector2, center: Vector2, radius: float) -> float:
	var worst := 0.0
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
