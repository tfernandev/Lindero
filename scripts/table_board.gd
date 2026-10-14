extends Node3D

const HexGeom := preload("res://scripts/hex_lib.gd")
const THICK := 16.0

var camera: Camera3D
var pieces: Node3D
var hex_mat: Dictionary = {}
var hex_number: Dictionary = {}
var mid := Vector3.ZERO
var span := Vector2(400, 400)
var _house: Mesh
var _roof: ArrayMesh
var _granja_roof: ArrayMesh

func _ready() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("102824")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f3e6cf")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -36, 0)
	sun.light_color = Color("fff3df")
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 0.6
	sun.directional_shadow_max_distance = 2200.0
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 140, 0)
	fill.light_color = Color("d7e4ea")
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)

	camera = Camera3D.new()
	camera.fov = 28.0
	camera.current = true
	add_child(camera)

	pieces = Node3D.new()
	pieces.name = "Pieces"
	add_child(pieces)

func bind(game, terrains: Array[Texture2D], lagoon: Texture2D, sea: Texture2D, font: Font) -> void:
	for child in get_children():
		if child == camera or child == pieces or child is WorldEnvironment or child is DirectionalLight3D:
			continue
		child.queue_free()
	hex_mat.clear()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for h in game.hexes:
		var c: Vector2 = HexGeom.hex_to_pixel(int(h.q), int(h.r))
		min_p = min_p.min(c - Vector2(HexGeom.SIZE, HexGeom.SIZE))
		max_p = max_p.max(c + Vector2(HexGeom.SIZE, HexGeom.SIZE))
	mid = Vector3((min_p.x + max_p.x) * 0.5, 0, (min_p.y + max_p.y) * 0.5)
	span = max_p - min_p
	_build_sea(sea)
	var top_mesh := _hex_top()
	var side_mesh := _hex_sides()
	var wood := _mat(Color("7a4e30"), null, 0.86)
	for h in game.hexes:
		var c: Vector2 = HexGeom.hex_to_pixel(int(h.q), int(h.r))
		var at := Vector3(c.x, 0, c.y)
		var res := int(h.resource)
		var tex: Texture2D = lagoon if res < 0 else terrains[res]
		var mat := _mat(Color.WHITE, tex, 0.82)
		var top := MeshInstance3D.new()
		top.mesh = top_mesh
		top.position = at
		top.material_override = mat
		top.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(top)
		var side := MeshInstance3D.new()
		side.mesh = side_mesh
		side.position = at
		side.material_override = wood
		side.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(side)
		var key := "%d,%d" % [int(h.q), int(h.r)]
		hex_mat[key] = mat
		hex_number[key] = int(h.number)
		if res >= 0:
			_token(at, int(h.number), font)
	_house = _box_mesh(Vector3(22, 16, 18))
	_roof = _roof_mesh(13.5, 11.5, 10.0)
	_granja_roof = _roof_mesh(15.5, 13.0, 11.0)
	fit_camera(1.6)

func fit_camera(aspect: float) -> void:
	var half := deg_to_rad(camera.fov * 0.5)
	var need := maxf(span.x * 0.48, span.y * 0.62 * maxf(aspect, 0.8) * 0.55)
	var dist := need / tan(half)
	var focus := Vector3(mid.x, THICK * 0.4, mid.z)
	camera.position = focus + Vector3(0, dist * 0.42, dist * 0.86)
	camera.look_at(focus, Vector3.UP)

func sync(game, pegs: Array, ghosts: Array, upgrades: Array) -> void:
	for child in pieces.get_children():
		child.free()
	for ek in game.roads.keys():
		var ends: Array = game.edges[ek]
		_road(game.v_pos[int(ends[0])], game.v_pos[int(ends[1])], int(game.roads[ek]), false)
	for vkey in game.buildings.keys():
		var b: Dictionary = game.buildings[vkey]
		_building(game.v_pos[int(vkey)], int(b.player), int(b.level) >= 2)
	for v in pegs:
		_peg(game.v_pos[int(v)], false)
	for v in upgrades:
		_peg(game.v_pos[int(v)], true)
	for ek in ghosts:
		var ends: Array = game.edges[String(ek)]
		_road(game.v_pos[int(ends[0])], game.v_pos[int(ends[1])], -1, true)
	mark(game.last_roll, -999, -999)

func mark(roll: int, hq: int, hr: int) -> void:
	for key in hex_mat.keys():
		var mat: StandardMaterial3D = hex_mat[key]
		var hot: bool = roll >= 2 and roll != 7 and int(hex_number.get(key, 0)) == roll
		var over: bool = key == "%d,%d" % [hq, hr]
		mat.emission_enabled = hot or over
		if hot:
			mat.emission = Color("e2b15a")
			mat.emission_energy_multiplier = 0.42
		elif over:
			mat.emission = Color("f0c36a")
			mat.emission_energy_multiplier = 0.16

func plane_hit(vp_pos: Vector2) -> Vector2:
	var origin := camera.project_ray_origin(vp_pos)
	var dir := camera.project_ray_normal(vp_pos)
	if absf(dir.y) < 0.0001:
		return Vector2(99999, 99999)
	var t := (THICK - origin.y) / dir.y
	if t < 0.0:
		return Vector2(99999, 99999)
	var p := origin + dir * t
	return Vector2(p.x, p.z)

func _token(at: Vector3, number: int, font: Font) -> void:
	var key_at := at
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 13.0
	cyl.bottom_radius = 13.0
	cyl.height = 1.4
	disc.mesh = cyl
	disc.position = key_at + Vector3(0, THICK + 0.8, 0)
	disc.material_override = _mat(Color("f6f1e4"), null, 0.7)
	add_child(disc)
	var label := Label3D.new()
	label.text = str(number)
	label.font = font
	label.font_size = 64
	label.pixel_size = 0.16
	label.modulate = Color("b42318") if number == 6 or number == 8 else Color("241c16")
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = disc.position + Vector3(0, 2.2, 0)
	label.outline_size = 0
	add_child(label)
	var count := HexGeom.pips(number)
	if count > 0:
		var gap := 3.1
		var start := -float(count - 1) * gap * 0.5
		for i in count:
			var pip := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 1.15
			ball.height = 2.3
			pip.mesh = ball
			pip.position = disc.position + Vector3(start + float(i) * gap, 1.15, 7.2)
			pip.material_override = _mat(label.modulate, null, 0.55)
			add_child(pip)

func _building(p: Vector2, player: int, farm: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, THICK, p.y)
	pieces.add_child(root)
	var body := MeshInstance3D.new()
	body.mesh = _house
	body.position = Vector3(0, 8.2 if not farm else 9.0, 0)
	if farm:
		body.scale = Vector3(1.12, 1.05, 1.12)
	body.material_override = _mat(Color("e7d7be"), null, 0.78)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)
	var roof := MeshInstance3D.new()
	roof.mesh = _granja_roof if farm else _roof
	roof.position = Vector3(0, 16.4 if not farm else 18.2, 0)
	roof.material_override = _mat(Color("8d4032") if not farm else Color("6e4a28"), null, 0.8)
	roof.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(roof)
	var seal := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 3.2
	cyl.bottom_radius = 3.4
	cyl.height = 1.2
	seal.mesh = cyl
	seal.position = Vector3(5.5, 0.7, 6.0)
	var col: Color = Color("e39b3b") if player == 0 else Color("3d6fdb")
	seal.material_override = _mat(col, null, 0.45)
	root.add_child(seal)

func _road(a: Vector2, b: Vector2, owner: int, ghost: bool) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 1.0:
		return
	var inst := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(length * 0.92, 2.6 if not ghost else 1.3, 9.0 if not ghost else 5.5)
	inst.mesh = box
	inst.position = Vector3((a.x + b.x) * 0.5, THICK + box.size.y * 0.5, (a.y + b.y) * 0.5)
	inst.rotation = Vector3(0, -atan2(delta.y, delta.x), 0)
	var tint := Color("c4b49a")
	if owner == 0:
		tint = Color("e0b36a")
	elif owner == 1:
		tint = Color("8eadd4")
	var mat := _mat(tint, null, 0.72)
	if ghost:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.97, 0.94, 0.88, 0.45)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pieces.add_child(inst)

func _peg(p: Vector2, gold: bool) -> void:
	var inst := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 4.6
	ball.height = 9.2
	inst.mesh = ball
	inst.position = Vector3(p.x, THICK + 4.6, p.y)
	inst.material_override = _mat(Color("f0c36a") if gold else Color("f6f1e4"), null, 0.4)
	pieces.add_child(inst)

func _build_sea(sea: Texture2D) -> void:
	var inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(span.x + 2200.0, span.y + 1800.0)
	inst.mesh = plane
	inst.position = Vector3(mid.x, -0.8, mid.z)
	inst.material_override = _mat(Color.WHITE, sea, 0.94)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)

func _mat(color: Color, tex: Texture2D, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = tex
	mat.roughness = rough
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	return mat

func _hex_top() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = []
	for i in 6:
		var c := HexGeom.corner(Vector2.ZERO, i)
		corners.append(Vector3(c.x, THICK, c.y))
	var center := Vector3(0, THICK, 0)
	for i in 6:
		var j := (i + 1) % 6
		_face(st, center, corners[i], corners[j], Vector3.UP, true)
	return st.commit()

func _hex_sides() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var c := HexGeom.corner(Vector2.ZERO, i)
		var d := HexGeom.corner(Vector2.ZERO, (i + 1) % 6)
		var top_a := Vector3(c.x, THICK, c.y)
		var top_b := Vector3(d.x, THICK, d.y)
		var bot_a := Vector3(c.x, 0, c.y)
		var bot_b := Vector3(d.x, 0, d.y)
		var n := Vector3(c.x + d.x, 0, c.y + d.y).normalized()
		_face(st, top_a, bot_a, bot_b, n, false)
		_face(st, top_a, bot_b, top_b, n, false)
	return st.commit()

func _box_mesh(size: Vector3) -> Mesh:
	var box := BoxMesh.new()
	box.size = size
	return box

func _roof_mesh(hw: float, hd: float, rise: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var a := Vector3(-hw, 0, -hd)
	var b := Vector3(hw, 0, -hd)
	var c := Vector3(hw, 0, hd)
	var d := Vector3(-hw, 0, hd)
	var p1 := Vector3(0, rise, -hd)
	var p2 := Vector3(0, rise, hd)
	_face(st, a, b, p1, (b - a).cross(p1 - a).normalized(), false)
	_face(st, c, d, p2, (d - c).cross(p2 - c).normalized(), false)
	_face(st, d, a, p1, (a - d).cross(p1 - d).normalized(), false)
	_face(st, p1, p2, d, (p2 - p1).cross(d - p1).normalized(), false)
	_face(st, b, c, p2, (c - b).cross(p2 - b).normalized(), false)
	_face(st, p2, p1, b, (p1 - p2).cross(b - p2).normalized(), false)
	return st.commit()

func _face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, normal: Vector3, uv_top: bool) -> void:
	for p in [a, b, c]:
		st.set_normal(normal)
		if uv_top:
			st.set_uv(Vector2(p.x / (HexGeom.SIZE * 2.0) + 0.5, p.z / (HexGeom.SIZE * 2.0) + 0.5))
		else:
			st.set_uv(Vector2(p.x * 0.02, p.y * 0.02))
		st.add_vertex(p)
