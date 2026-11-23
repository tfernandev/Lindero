extends Node3D

const HexGeom := preload("res://scripts/hex_lib.gd")
const Dressing := preload("res://scripts/hex_dressing.gd")
const DressingScene := preload("res://scenes/hex_dressing.tscn")
const BoardDebug := preload("res://scripts/board_debug.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const SeaShader := preload("res://shaders/water_sea.gdshader")
const LagoonShader := preload("res://shaders/water_lagoon.gdshader")
const TILE_Y := 3.2
const HEX_FIELD_Y := 3.2
const THICK := 3.2
const RIM_W := 2.4
const RIM_H := 0.12
const HEX_TILE := {
	0: "res://models/tiles/hex_madera.glb",
	1: "res://models/tiles/hex_arcilla.glb",
	2: "res://models/tiles/hex_grano.glb",
	3: "res://models/tiles/hex_piedra_v2.glb",  # original, tools/blender/hex_piedra.py
	4: "res://models/tiles/hex_ovejas.glb",
}
# Per-cell model variants ("q,r" -> GLB). Only the model changes: resource,
# number and rules stay those of match.gd. Applied only if the cell's resource
# matches, so a layout change can't put a quarry on a forest.
const HEX_TILE_AT := {
	"0,1": {"res": 3, "path": "res://models/tiles/hex_piedra_roca.glb"},  # tools/blender/hex_piedra_roca.py
}
# Mild sink so 3D relief sits just above the terrain well plate (not a tall step).
const HEX_SINK := {
	1: 10.5,
	2: 6.8,
	4: 5.2,
}
const TOKEN_RADIUS := 17.0
# Fixed deck heights — mesh sampling buried chips in sunk stamps.
const HEX_TOKEN_Y := {
	0: TILE_Y + 6.8,  # madera (disc draws over canopy)
	1: TILE_Y + 5.4,  # arcilla
	2: TILE_Y + 5.2,  # grano
	3: TILE_Y + 6.8,  # piedra
	4: TILE_Y + 5.4,  # ovejas
}
# World XZ from hex `at` to the stamped circle (tuned from board crops).
const HEX_TOKEN_OFF := {
	0: Vector2(0.0, 0.0),
	1: Vector2(2.0, 4.0),   # arcilla
	2: Vector2(0.0, 0.0),
	3: Vector2(0.0, 0.0),
	# ovejas: on well rim TR — nudge -X +Z into center
	4: Vector2(-8.0, 40.0),
}
const HEX_KEEP_PROPS := {}
const HEX_CLIP := {}
const HEX_BODY := {}
# Tiles authored for Lindero keep their own GLB materials (only "Side" gets the
# board wood). The older adapted tiles are repainted with the terrain albedo.
const HEX_OWN_MATS := {3: true}
const WOOD := Color("6a4a32")
const RIM := [
	Color("3d5c32"),
	Color("a85a38"),
	Color("c9a04a"),
	Color("6e6c68"),
	Color("5a7a40"),
]

var camera: Camera3D
var pieces: Node3D
var board_debug
var _bound_game
var _sun: DirectionalLight3D
var _cam_focus := Vector3.ZERO
var _cam_yaw := 0.0
var _cam_pitch := deg_to_rad(48.0)
var _cam_dist := 0.0
var _cam_base := 0.0
var hex_mat: Dictionary = {}
var hex_number: Dictionary = {}
var _terrains: Array[Texture2D] = []
var _kind_mat: Dictionary = {}
var mid := Vector3.ZERO
var span := Vector2(400, 400)
var _roof: ArrayMesh
var _granja_roof: ArrayMesh
var _planks: ArrayMesh
var _found: BoxMesh
var _walls: BoxMesh
var _win: BoxMesh
var _door: BoxMesh
var _chimney: BoxMesh
var _plaster: StandardMaterial3D
var _roof_wood: StandardMaterial3D
var _window_mat: StandardMaterial3D
var _player_mat: Array[StandardMaterial3D] = []
var _road_mat: Array[StandardMaterial3D] = []
var _player_wall: Array[StandardMaterial3D] = []
var _ghost_mat: StandardMaterial3D
var _peg_mesh: SphereMesh
var _bead: SphereMesh
var _peg_mat: StandardMaterial3D
var _peg_gold: StandardMaterial3D
var _lip_wood: StandardMaterial3D
var _pueblo_scene: PackedScene
var _piece_scenes: Dictionary = {}
var _side_wood: StandardMaterial3D
var _earth_mat: StandardMaterial3D
var _earth_bank_mat: StandardMaterial3D
var _grass_mat: StandardMaterial3D
var _path_mat: StandardMaterial3D
var _path_mesh: ArrayMesh
var _pad_mesh: CylinderMesh
var _tile_cut: Dictionary = {}
var _tile_clipper
var _kit_ready := false
var _mill_wood: StandardMaterial3D
var _mill_roof: StandardMaterial3D
var _mill_blades: StandardMaterial3D
var _hay_mat: StandardMaterial3D

func _ready() -> void:
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("142c26")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("f6ede0")
	env.ambient_light_energy = 0.38
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.02
	env_node.environment = env
	add_child(env_node)

	var sun := DirectionalLight3D.new()
	_sun = sun
	sun.rotation_degrees = Vector3(-48, -32, 0)
	sun.light_color = Color("fff0dc")
	sun.light_energy = 1.42
	sun.shadow_enabled = true
	sun.shadow_bias = 0.02
	sun.shadow_normal_bias = 0.6
	sun.shadow_blur = 1.15
	sun.directional_shadow_max_distance = 900.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-28, 148, 0)
	fill.light_color = Color("dcecf0")
	fill.light_energy = 0.28
	fill.shadow_enabled = false
	add_child(fill)

	_ensure_core()

func _ensure_core() -> void:
	if camera == null:
		camera = Camera3D.new()
		camera.fov = 28.0
		camera.current = true
		add_child(camera)
	if pieces == null:
		pieces = Node3D.new()
		pieces.name = "Pieces"
		add_child(pieces)
	if board_debug == null:
		board_debug = BoardDebug.new()
		board_debug.name = "BoardDebug"
		board_debug.visible = false
		add_child(board_debug)

func bind(game, terrains: Array[Texture2D], lagoon: Texture2D, sea: Texture2D, font: Font) -> void:
	_ensure_core()
	_bound_game = game
	_terrains = terrains
	_kind_mat.clear()
	for child in get_children():
		if child == camera or child == pieces or child == board_debug or child is WorldEnvironment or child is DirectionalLight3D:
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
	_prepare_kit()

	var hex_set := {}
	for h in game.hexes:
		hex_set["%d,%d" % [int(h.q), int(h.r)]] = true
	var neighbors := [
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(-1, 1),
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(1, -1),
	]
	var grout_mesh := _hex_floor_at(HexGeom.SIZE, TILE_Y - 0.22)
	var floor_mesh := _hex_floor_at(HexGeom.tile_radius(), TILE_Y)
	var rim_mesh := _hex_rim()
	var body_mesh := _hex_body(HexGeom.tile_radius(), TILE_Y - 0.1, TILE_Y + 3.6)
	var wood_mat := _mat(WOOD, null, 0.86)
	for h in game.hexes:
		var c: Vector2 = HexGeom.hex_to_pixel(int(h.q), int(h.r))
		var at := Vector3(c.x, 0, c.y)
		var res := int(h.resource)
		var mat := _tile_mat(res, lagoon, int(h.q), int(h.r))
		var grout := MeshInstance3D.new()
		grout.name = "Grout_%d_%d" % [int(h.q), int(h.r)]
		grout.mesh = grout_mesh
		grout.position = at
		grout.material_override = wood_mat
		grout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(grout)

		var coast_edges: Array[bool] = []
		for i in 6:
			var n_coord: Vector2i = Vector2i(int(h.q), int(h.r)) + (neighbors[i] as Vector2i)
			coast_edges.append(not hex_set.has("%d,%d" % [n_coord.x, n_coord.y]))

		var token_at := _add_hex_tile(res, at, mat, wood_mat, _tile_variant(int(h.q), int(h.r), res))
		if token_at.y < -900.0:
			var floor_inst := MeshInstance3D.new()
			floor_inst.name = "Floor_%d_%d" % [int(h.q), int(h.r)]
			floor_inst.mesh = floor_mesh
			floor_inst.position = at
			floor_inst.material_override = mat
			floor_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(floor_inst)

			var rim := MeshInstance3D.new()
			rim.name = "Rim_%d_%d" % [int(h.q), int(h.r)]
			rim.mesh = rim_mesh
			rim.position = at
			rim.material_override = wood_mat
			rim.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rim)

			var coast_mesh := _hex_coast(coast_edges)
			if coast_mesh.get_surface_count() > 0:
				var wall := MeshInstance3D.new()
				wall.name = "Coast_%d_%d" % [int(h.q), int(h.r)]
				wall.mesh = coast_mesh
				wall.position = at
				wall.material_override = wood_mat
				wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(wall)
			token_at = at + Vector3(0, TILE_Y, 0)
		else:
			if bool(HEX_BODY.get(res, false)):
				var body := MeshInstance3D.new()
				body.name = "Body_%d_%d" % [int(h.q), int(h.r)]
				body.mesh = body_mesh
				body.position = at
				body.material_override = mat
				body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(body)
			else:
				# Terrain well fills gaps; sunk GLBs sit just above it.
				var well := MeshInstance3D.new()
				well.name = "Well_%d_%d" % [int(h.q), int(h.r)]
				well.mesh = floor_mesh
				well.position = at
				well.material_override = mat
				well.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(well)

		var key := "%d,%d" % [int(h.q), int(h.r)]
		hex_mat[key] = mat
		hex_number[key] = int(h.number)
		var keep_props := not HEX_TILE.has(res) or bool(HEX_KEEP_PROPS.get(res, false))
		if keep_props and Dressing.wants(res, int(h.q), int(h.r)):
			var dress := DressingScene.instantiate()
			add_child(dress)
			var dress_y := HEX_FIELD_Y if HEX_TILE.has(res) else TILE_Y
			dress.position = at + Vector3(0, dress_y, 0)
			dress.apply(res, int(h.q), int(h.r))
		if res >= 0:
			_token(token_at, int(h.number), font)
	_lay_dirt_tracks(game)
	if _tile_clipper != null:
		_tile_clipper.free()
		_tile_clipper = null
	_dress_table()
	fit_camera(1.6)
	_refresh_debug()

func fit_camera(aspect: float) -> void:
	var half := deg_to_rad(camera.fov * 0.5)
	var sin_p := sin(_cam_pitch)
	var need_y := (span.y * 0.5 * sin_p + 36.0)
	var need_x := (span.x * 0.5 + 36.0) / maxf(aspect, 0.75)
	var need := maxf(need_y, need_x) * 1.08
	var fitted := need / tan(half)
	var ratio := 1.0 if _cam_base < 1.0 else _cam_dist / _cam_base
	_cam_base = fitted
	_cam_dist = clampf(fitted * ratio, fitted * 0.38, fitted * 2.5)
	_cam_focus = Vector3(mid.x, 3.4, mid.z - 10.0)
	_apply_camera()

func set_debug_visible(on: bool) -> void:
	if not OS.is_debug_build():
		on = false
	_ensure_core()
	if board_debug == null:
		return
	board_debug.visible = on
	Dressing.debug_log = on
	if on:
		_refresh_debug()

func toggle_debug() -> void:
	set_debug_visible(board_debug == null or not board_debug.visible)

func is_debug_visible() -> bool:
	return board_debug != null and board_debug.visible

func _refresh_debug() -> void:
	if board_debug == null or not board_debug.visible or _bound_game == null:
		return
	board_debug.rebuild(_bound_game, self)

func look_at_hex(q: int, r: int, dist_factor: float = 0.45) -> void:
	var c := HexGeom.hex_to_pixel(q, r)
	_cam_focus = Vector3(c.x, TILE_Y + 8.0, c.y)
	if _cam_base < 1.0:
		fit_camera(1.6)
	_cam_pitch = deg_to_rad(52.0)
	_cam_dist = clampf(_cam_base * dist_factor, _cam_base * 0.38, _cam_base * 2.5)
	_apply_camera()

func orbit(yaw_delta: float, pitch_delta: float) -> void:
	_cam_yaw += yaw_delta
	_cam_pitch = clampf(_cam_pitch + pitch_delta, deg_to_rad(25.0), deg_to_rad(75.0))
	_apply_camera()

func zoom_by(factor: float) -> void:
	if _cam_base < 1.0 or factor <= 0.0:
		return
	_cam_dist = clampf(_cam_dist * factor, _cam_base * 0.38, _cam_base * 2.5)
	_apply_camera()

func pan_focus(screen_delta: Vector2, view_size: Vector2) -> void:
	var scale := _cam_dist / maxf(view_size.y, 1.0) * 1.35
	var right := Vector3(cos(_cam_yaw), 0.0, -sin(_cam_yaw))
	var fwd := Vector3(-sin(_cam_yaw), 0.0, -cos(_cam_yaw))
	_cam_focus += (-right * screen_delta.x + fwd * screen_delta.y) * scale
	_cam_focus.x = clampf(_cam_focus.x, mid.x - span.x * 0.55, mid.x + span.x * 0.55)
	_cam_focus.z = clampf(_cam_focus.z, mid.z - span.y * 0.55, mid.z + span.y * 0.55)
	_apply_camera()

func _apply_camera() -> void:
	var flat := cos(_cam_pitch)
	var offset := Vector3(sin(_cam_yaw) * flat, sin(_cam_pitch), cos(_cam_yaw) * flat) * _cam_dist
	if camera != null:
		camera.position = _cam_focus + offset
		if camera.is_inside_tree():
			camera.look_at(_cam_focus, Vector3.UP)
		else:
			camera.look_at_from_position(camera.position, _cam_focus, Vector3.UP)
	if _sun != null:
		_sun.directional_shadow_max_distance = maxf(1100.0, _cam_dist * 1.5)

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
		var mat = hex_mat[key]
		if not (mat is StandardMaterial3D):
			continue
		var sm := mat as StandardMaterial3D
		var hot: bool = roll >= 2 and roll != 7 and int(hex_number.get(key, 0)) == roll
		var over: bool = key == "%d,%d" % [hq, hr]
		sm.emission_enabled = hot or over
		if hot:
			sm.emission = Color("e2b15a")
			sm.emission_energy_multiplier = 0.42
		elif over:
			sm.emission = Color("f0c36a")
			sm.emission_energy_multiplier = 0.16

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

## Viewport-local pixel of a hex center (for UI harvest FX).
func hex_screen_pos(q: int, r: int) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	var c := HexGeom.hex_to_pixel(q, r)
	var world := Vector3(c.x, TILE_Y + 10.0, c.y)
	return camera.unproject_position(world)

## Places the biome GLB. Returns world position for the number token (on the model circle).
## On failure returns Vector3(0, -999, 0).
func _tile_variant(q: int, r: int, res: int) -> String:
	var v: Dictionary = HEX_TILE_AT.get("%d,%d" % [q, r], {})
	if v.is_empty() or int(v["res"]) != res or not ResourceLoader.exists(String(v["path"])):
		return ""
	return String(v["path"])

func _add_hex_tile(res: int, at: Vector3, top_mat: Material, side_mat: Material, variant := "") -> Vector3:
	if not HEX_TILE.has(res):
		return Vector3(0, -999, 0)
	var packed := _packed_piece(variant if variant != "" else String(HEX_TILE[res]))
	if packed == null:
		return Vector3(0, -999, 0)
	var node := packed.instantiate() as Node3D
	if node == null:
		return Vector3(0, -999, 0)
	add_child(node)
	node.position = at
	var sink_y := float(HEX_SINK.get(res, 0.0))
	var placed: Node3D = node
	if bool(HEX_CLIP.get(res, false)):
		var cut := _ensure_tile_cut(res, node)
		if cut != null:
			var spec: Dictionary = _tile_cut[res]
			node.queue_free()
			var mi := MeshInstance3D.new()
			mi.name = "TileCut_%d" % res
			mi.mesh = cut
			var ins := float(spec["ins"])
			var center: Vector3 = spec["center"]
			var y0 := float(spec["y0"])
			var fitted := HexGeom.tile_radius() / maxf(ins, 0.001)
			mi.scale = Vector3(fitted, fitted, fitted)
			mi.position = at + Vector3(-center.x * fitted, -y0 * fitted - sink_y, -center.z * fitted)
			mi.material_override = top_mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)
			placed = mi
			return _token_on_stamp(res, placed, at)
	# Fit from terrain meshes only so mills/hay don't shift the hex plate off `at`.
	var box := _node_aabb(node, true)
	var radius := maxf(box.size.x, box.size.z) * 0.5
	var fitted := 1.0
	if radius > 0.001:
		fitted = HexGeom.tile_radius() / radius
		var center := box.get_center()
		node.scale = Vector3(fitted, fitted, fitted)
		node.position = at + Vector3(-center.x * fitted, -box.position.y * fitted - sink_y, -center.z * fitted)
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for child in n.get_children():
			pending.append(child)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var label := String(mi.name)
		if mi.mesh != null:
			label += " " + str(mi.mesh.resource_name)
		if res == 2:
			_style_grain_mill(mi, label, top_mat, side_mat)
		elif label.contains("Side"):
			_apply_mesh_mat(mi, side_mat)
		elif HEX_OWN_MATS.has(res) and label.contains("Boulder"):
			pass  # scanned rock (Poly Haven, CC0): keeps its own textured material
		elif HEX_OWN_MATS.has(res) and top_mat is StandardMaterial3D:
			# Own tiles are UV'd 0..1 from above over the same painting; reuse the
			# board's terrain material (project-imported texture, anisotropic
			# filtering, same tint) so they match the other tiles exactly.
			var own := (top_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			own.uv1_scale = Vector3.ONE
			own.uv1_offset = Vector3.ZERO
			_apply_mesh_mat(mi, own)
		else:
			_apply_mesh_mat(mi, top_mat)
	return _token_on_stamp(res, placed, at)

## World position of the number chip on the stamped circle.
func _token_on_stamp(res: int, _root: Node3D, at: Vector3) -> Vector3:
	var off: Vector2 = HEX_TOKEN_OFF.get(res, Vector2.ZERO)
	var y := float(HEX_TOKEN_Y.get(res, TILE_Y + 5.0))
	return Vector3(at.x + off.x, y, at.z + off.y)

func _apply_mesh_mat(mi: MeshInstance3D, mat: Material) -> void:
	mi.material_override = mat
	if mi.mesh == null:
		return
	for i in mi.mesh.get_surface_count():
		mi.set_surface_override_material(i, mat)

func _style_grain_mill(mi: MeshInstance3D, label: String, top_mat: Material, side_mat: Material) -> void:
	_ensure_mill_mats()
	if label.contains("Blades"):
		_apply_mesh_mat(mi, _mill_blades)
	elif label.contains("MillRoof"):
		_apply_mesh_mat(mi, _mill_roof)
	elif label.contains("Mill"):
		_apply_mesh_mat(mi, _mill_wood)
	elif label.contains("Hay"):
		_apply_mesh_mat(mi, _hay_mat)
	elif label.contains("Dirt"):
		_apply_mesh_mat(mi, _mat(Color("7a5530"), null, 0.94))
	elif label.contains("Side"):
		_apply_mesh_mat(mi, side_mat)
	else:
		_apply_mesh_mat(mi, top_mat)

func _ensure_mill_mats() -> void:
	if _mill_wood != null:
		return
	var wood_tex := load("res://art/props/molino_madera.jpg") as Texture2D
	var roof_tex := load("res://art/props/molino_tejas.jpg") as Texture2D
	var sail_tex := load("res://art/props/molino_lona.jpg") as Texture2D
	var hay_tex := load("res://art/props/fardo_paja.jpg") as Texture2D
	# Prefer extracted GLB maps if art/props failed to import for some reason.
	if wood_tex == null:
		wood_tex = load("res://models/tiles/hex_grano_molino_madera.jpg") as Texture2D
	if roof_tex == null:
		roof_tex = load("res://models/tiles/hex_grano_molino_tejas.jpg") as Texture2D
	if sail_tex == null:
		sail_tex = load("res://models/tiles/hex_grano_molino_lona.jpg") as Texture2D
	if hay_tex == null:
		hay_tex = load("res://models/tiles/hex_grano_fardo_paja.jpg") as Texture2D
	# Warm tint * texture so the mill reads as timber at board distance.
	_mill_wood = _mat(Color("c9955c"), wood_tex, 0.76)
	_mill_wood.uv1_scale = Vector3(2.4, 2.4, 2.4)
	_mill_roof = _mat(Color("d47848"), roof_tex, 0.70)
	_mill_roof.uv1_scale = Vector3(1.8, 1.8, 1.8)
	_mill_blades = _mat(Color("efe2c4"), sail_tex, 0.62)
	_mill_blades.uv1_scale = Vector3(1.5, 1.5, 1.5)
	# Haystack / grain mound opposite the mill.
	_hay_mat = _mat(Color("e8c86a"), hay_tex, 0.88)
	_hay_mat.uv1_scale = Vector3(2.0, 2.0, 2.0)

func _ensure_tile_cut(res: int, source: Node3D) -> ArrayMesh:
	if _tile_cut.has(res):
		return _tile_cut[res].get("mesh") as ArrayMesh
	if _tile_clipper == null:
		_tile_clipper = Dressing.new()
	var box := _node_aabb(source)
	var center := box.get_center()
	var ins := minf(box.size.z * 0.5, box.size.x / sqrt(3.0))
	if ins < 0.001:
		return null
	var cut: ArrayMesh = _tile_clipper.cut_to_hex(source, center, ins)
	if cut == null or cut.get_surface_count() == 0:
		return null
	_tile_cut[res] = {
		"mesh": cut,
		"center": center,
		"ins": ins,
		"y0": box.position.y,
	}
	return cut


func _token(pad_at: Vector3, number: int, font: Font) -> void:
	# Compact chip stacked clear of terrain — own underlay + raised disc.
	var base_y := pad_at.y + 1.15
	var cx := pad_at.x
	var cz := pad_at.z
	var r := TOKEN_RADIUS

	var under := MeshInstance3D.new()
	var under_cyl := CylinderMesh.new()
	under_cyl.top_radius = r + 2.0
	under_cyl.bottom_radius = r + 2.3
	under_cyl.height = 0.85
	under_cyl.radial_segments = 28
	under_cyl.rings = 0
	under.mesh = under_cyl
	under.position = Vector3(cx, base_y - 0.15, cz)
	under.material_override = _token_mat(Color("5c4030"), 0.82)
	under.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	under.sorting_offset = 2.0
	add_child(under)

	var bezel := MeshInstance3D.new()
	var bezel_cyl := CylinderMesh.new()
	bezel_cyl.top_radius = r + 0.85
	bezel_cyl.bottom_radius = r + 1.15
	bezel_cyl.height = 0.40
	bezel_cyl.radial_segments = 28
	bezel_cyl.rings = 0
	bezel.mesh = bezel_cyl
	bezel.position = Vector3(cx, base_y + 0.28, cz)
	var bezel_mat := _token_mat(Color("6a4a32"), 0.78)
	bezel.material_override = bezel_mat
	bezel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	bezel.sorting_offset = 2.2
	add_child(bezel)

	var collar := MeshInstance3D.new()
	var collar_cyl := CylinderMesh.new()
	collar_cyl.top_radius = r + 0.35
	collar_cyl.bottom_radius = r + 0.55
	collar_cyl.height = 0.22
	collar_cyl.radial_segments = 28
	collar_cyl.rings = 0
	collar.mesh = collar_cyl
	collar.position = Vector3(cx, base_y + 0.46, cz)
	collar.material_override = _token_mat(Color("c9a04a"), 0.55)
	collar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	collar.sorting_offset = 2.4
	add_child(collar)

	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = r
	cyl.bottom_radius = r
	cyl.height = 0.22
	cyl.radial_segments = 28
	cyl.rings = 0
	disc.mesh = cyl
	disc.position = Vector3(cx, base_y + 0.60, cz)
	disc.material_override = _token_mat(Color("fbf8f0"), 0.40)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	disc.sorting_offset = 2.6
	add_child(disc)

	var label := Label3D.new()
	label.text = str(number)
	label.font = font
	# Bigger raster + smaller pixel_size = crisper digits at phone size.
	label.font_size = 96
	label.pixel_size = 0.118
	var is_hot := (number == 6 or number == 8)
	label.modulate = Color("c02626") if is_hot else Color("18120e")
	label.outline_size = 8
	label.outline_modulate = Color("fbf8f0")
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.no_depth_test = true
	label.render_priority = 12
	label.rotation_degrees = Vector3(-90, 0, 0)
	label.position = Vector3(cx, base_y + 0.78, cz - 2.2)
	add_child(label)

	var count := HexGeom.pips(number)
	if count > 0:
		# Pips sit on their own row under the digits (they used to touch the
		# glyph baseline and read as ".9", ".8").
		var gap := 2.7
		var start := -float(count - 1) * gap * 0.5
		for i in count:
			var pip := MeshInstance3D.new()
			var ball := SphereMesh.new()
			ball.radius = 0.85
			ball.height = 1.7
			ball.radial_segments = 10
			ball.rings = 6
			pip.mesh = ball
			pip.position = Vector3(cx + start + float(i) * gap, base_y + 0.76, cz + 6.6)
			pip.material_override = _token_mat(label.modulate, 0.40)
			pip.sorting_offset = 2.8
			add_child(pip)

func _packed_piece(path: String) -> PackedScene:
	if _piece_scenes.has(path):
		return _piece_scenes[path]
	if not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	_piece_scenes[path] = packed
	return packed


func _add_piece_glb(root: Node3D, path: String, heft: float) -> bool:
	var packed := _packed_piece(path)
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	root.add_child(node)
	var box := _node_aabb(node)
	var radius := maxf(box.size.x, box.size.z) * 0.5
	if radius < 0.001:
		return true
	var fitted := 14.5 * heft / radius
	var center := box.get_center()
	node.scale = Vector3(fitted, fitted, fitted)
	node.position = Vector3(-center.x * fitted, -box.position.y * fitted, -center.z * fitted)
	return true


func _add_pueblo(root: Node3D, heft: float = 1.0) -> bool:
	var path := "res://models/pilot/pilot_pueblo.glb"
	if _pueblo_scene == null:
		if not ResourceLoader.exists(path):
			return false
		_pueblo_scene = load(path) as PackedScene
	if _pueblo_scene == null:
		return false
	var node := _pueblo_scene.instantiate() as Node3D
	if node == null:
		return false
	root.add_child(node)
	var box := _node_aabb(node)
	var radius := maxf(box.size.x, box.size.z) * 0.5
	if radius < 0.001:
		return true
	var fitted := 9.0 * heft / radius
	var center := box.get_center()
	node.scale = Vector3(fitted, fitted, fitted)
	node.position = Vector3(-center.x * fitted, -box.position.y * fitted, -center.z * fitted)
	return true


func _tint_piece(root: Node3D, player: int) -> void:
	var who := 0 if player <= 0 else 1
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for child in n.get_children():
			pending.append(child)
		if not (n is MeshInstance3D):
			continue
		var mi := n as MeshInstance3D
		var label := String(mi.name)
		if mi.mesh != null:
			label += " " + str(mi.mesh.resource_name)
		if label.contains("Roof") or label.contains("Techo"):
			mi.material_override = _player_mat[who]
		elif label.contains("Base") or label.contains("Wood") or label.contains("Madera"):
			mi.material_override = _lip_wood
		else:
			# Walls carry the player color too (lighter) so a piece reads as
			# "orange" or "blue" from the whole silhouette, not just a roof.
			mi.material_override = _player_wall[who]

func _node_aabb(root: Node3D, terrain_only: bool = false) -> AABB:
	var box := AABB()
	var first := true
	var pending: Array[Node] = [root]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for child in n.get_children():
			pending.append(child)
		if not (n is MeshInstance3D) or (n as MeshInstance3D).mesh == null:
			continue
		var mi := n as MeshInstance3D
		var label := String(mi.name)
		if terrain_only and (label.contains("Mill") or label.contains("Blades") or label.contains("MillRoof") or label.contains("Hay")):
			continue
		var local := mi.get_aabb()
		var xf := mi.global_transform
		var base := root.global_transform.affine_inverse() * xf
		for i in 8:
			var p := base * local.get_endpoint(i)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box

func _building(p: Vector2, player: int, farm: bool) -> void:
	var root := Node3D.new()
	root.position = Vector3(p.x, THICK, p.y)
	pieces.add_child(root)
	var piece_path := "res://models/pieces/ciudad.glb" if farm else "res://models/pieces/pueblo.glb"
	if _add_piece_glb(root, piece_path, 1.38 if farm else 1.0):
		_tint_piece(root, player)
		return
	if _add_pueblo(root, 1.38 if farm else 1.0):
		return
	var who := 0 if player <= 0 else 1
	var s := 1.18 if farm else 1.0
	var found_h := 1.2
	var wall_h := 8.4 * (1.1 if farm else 1.0)
	_part(root, _found, Vector3(0, found_h * 0.5, 0), Vector3(16.4 * s, found_h, 12.6 * s), _plaster, false)
	_part(root, _walls, Vector3(0, found_h + wall_h * 0.5, 0), Vector3(14.0 * s, wall_h, 10.6 * s), _plaster, true)
	var roof_y := found_h + wall_h
	var roof_mat: Material = _roof_wood if farm else _player_mat[who]
	_part(root, _granja_roof if farm else _roof, Vector3(0, roof_y, 0), Vector3.ONE, roof_mat, true)
	var face_z := 10.6 * s * 0.5
	_part(root, _win, Vector3(-2.7 * s, found_h + wall_h * 0.62, face_z), Vector3(1.7, 1.9, 0.45), _window_mat, false)
	_part(root, _win, Vector3(2.7 * s, found_h + wall_h * 0.62, face_z), Vector3(1.7, 1.9, 0.45), _window_mat, false)
	_part(root, _door, Vector3(0, found_h + 1.7, face_z), Vector3(2.3, 3.4, 0.4), _player_mat[who], false)
	if not farm:
		return
	var cx := 3.4
	var ry := 6.6 * (1.0 - absf(cx) / 9.6)
	_part(root, _chimney, Vector3(cx, roof_y + ry + 1.3, -1.6), Vector3(1.7, 3.2, 1.7), _roof_wood, true)
	_part(root, _chimney, Vector3(cx, roof_y + ry + 3.05, -1.6), Vector3(2.15, 0.7, 2.15), _player_mat[who], false)

func _road(a: Vector2, b: Vector2, owner: int, ghost: bool) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 1.0:
		return
	var span_len := length * (0.78 if ghost else 0.66)
	var midp := Vector3((a.x + b.x) * 0.5, THICK, (a.y + b.y) * 0.5)
	var yaw := -atan2(delta.y, delta.x)
	var paint: Material = _ghost_mat if ghost else _road_mat[0 if owner <= 0 else 1]
	if _add_camino(midp, yaw, span_len, paint, ghost):
		return
	var inst := MeshInstance3D.new()
	inst.mesh = _planks
	inst.position = midp
	inst.rotation = Vector3(0, yaw, 0)
	inst.scale = Vector3(span_len, 0.55 if ghost else 1.0, 0.7 if ghost else 1.0)
	inst.material_override = paint
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pieces.add_child(inst)


func _add_camino(midp: Vector3, yaw: float, span_len: float, paint: Material, ghost: bool) -> bool:
	var packed := _packed_piece("res://models/pieces/camino.glb")
	if packed == null:
		return false
	var node := packed.instantiate() as Node3D
	if node == null:
		return false
	pieces.add_child(node)
	var box := _node_aabb(node)
	var native_len := maxf(box.size.x, 0.001)
	var native_h := maxf(box.size.y, 0.001)
	var native_w := maxf(box.size.z, 0.001)
	var sy := (0.55 if ghost else 1.0) * (4.2 / native_h)
	var sz := (0.7 if ghost else 1.0) * (13.0 / native_w)
	var sx := span_len / native_len
	var center := box.get_center()
	node.scale = Vector3(sx, sy, sz)
	node.rotation = Vector3(0, yaw, 0)
	var local_off := Vector3(-center.x * sx, -box.position.y * sy, -center.z * sz)
	node.position = midp + local_off.rotated(Vector3.UP, yaw)
	var pending: Array[Node] = [node]
	while not pending.is_empty():
		var n: Node = pending.pop_back()
		for child in n.get_children():
			pending.append(child)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			mi.material_override = paint
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	return true

func _peg(p: Vector2, gold: bool) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = _peg_mesh
	inst.position = Vector3(p.x, THICK + 4.6, p.y)
	inst.material_override = _peg_gold if gold else _peg_mat
	pieces.add_child(inst)

func _build_sea(_sea: Texture2D) -> void:
	var inst := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(span.x + 3500.0, span.y + 3500.0)
	plane.subdivide_width = 64
	plane.subdivide_depth = 64
	inst.mesh = plane
	inst.position = Vector3(mid.x, -0.3, mid.z)
	var mat := ShaderMaterial.new()
	mat.shader = SeaShader
	mat.set_shader_parameter("island_origin", mid)
	var reach := maxf(span.x, span.y) * 0.48
	mat.set_shader_parameter("shore_start", reach)
	mat.set_shader_parameter("shore_band", 70.0)
	mat.set_shader_parameter("calm", 1.0 if UiTheme.reduce_motion else 0.0)
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)

func _tile_mat(res: int, lagoon: Texture2D, q: int = 0, r: int = 0) -> Material:
	var base := _kind_base(res, lagoon)
	if base is ShaderMaterial:
		var wet := (base as ShaderMaterial).duplicate() as ShaderMaterial
		wet.set_shader_parameter("calm", 1.0 if UiTheme.reduce_motion else 0.0)
		return wet
	var mat := base.duplicate() as StandardMaterial3D
	var ox := float(absi(q * 17 + r * 29) % 80) / 200.0
	var oy := float(absi(q * 13 + r * 41) % 80) / 200.0
	mat.uv1_offset = Vector3(ox, oy, 0.0)
	mat.uv1_scale = Vector3(0.86, 0.86, 0.86)
	return mat

func _kind_base(res: int, lagoon: Texture2D) -> Material:
	if _kind_mat.has(res):
		return _kind_mat[res]
	var rough := 0.86
	if res == 0:
		rough = 0.76
	elif res == 1:
		rough = 0.80
	elif res == 2:
		rough = 0.78
	elif res == 3:
		rough = 0.70
	elif res == 4:
		rough = 0.82
	var mat: Material
	if res < 0:
		var wet := ShaderMaterial.new()
		wet.shader = LagoonShader
		wet.set_shader_parameter("albedo_tex", lagoon)
		wet.set_shader_parameter("calm", 1.0 if UiTheme.reduce_motion else 0.0)
		mat = wet
	elif res >= 0 and res < _terrains.size() and _terrains[res] != null:
		mat = _mat(Color.WHITE, _terrains[res], rough)
	elif res >= 0 and res < RIM.size():
		mat = _mat(WOOD.lerp(RIM[res], 0.35), null, 0.88)
	else:
		mat = _mat(WOOD, null, 0.86)
	_kind_mat[res] = mat
	return mat

func _rim_mat(res: int, lagoon: Texture2D, terrains: Array[Texture2D]) -> StandardMaterial3D:
	return _tile_mat(res, lagoon)

func _mat(color: Color, tex: Texture2D, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.albedo_texture = tex
	mat.roughness = rough
	mat.metallic = 0.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return mat

## Number chips always read above terrain props (forest canopy, rock lips).
func _token_mat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := _mat(color, null, rough)
	mat.no_depth_test = true
	mat.render_priority = 10
	return mat

func _dirt_tex(ruts: bool) -> ImageTexture:
	var w := 256
	var h := 128 if ruts else 256
	var img := Image.create(w, h, false, Image.FORMAT_RGB8)
	var n1 := FastNoiseLite.new()
	n1.seed = 17 if ruts else 44
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.042
	n1.fractal_type = FastNoiseLite.FRACTAL_FBM
	n1.fractal_octaves = 5
	var n2 := FastNoiseLite.new()
	n2.seed = 91 if ruts else 63
	n2.frequency = 0.13
	var packed := Color("e0c084")
	var dark := Color("b07a3c")
	var rut_col := Color("8a5424")
	var grass := Color("7a9440")
	for y in h:
		var v := float(y) / float(maxi(h - 1, 1))
		var from_c := absf(v - 0.5) * 2.0
		for x in w:
			var soil := n1.get_noise_2d(float(x), float(y))
			var grit := n2.get_noise_2d(float(x) * 2.2, float(y) * 2.2)
			var col := packed.lerp(dark, 0.22 + soil * 0.22)
			col = col.lerp(Color("f0d9a0"), clampf(grit * 0.18 + 0.08, 0.0, 0.3))
			if ruts:
				var rut := exp(-pow((v - 0.38) / 0.05, 2.0))
				rut += exp(-pow((v - 0.62) / 0.05, 2.0))
				col = col.lerp(rut_col, clampf(rut * 0.58, 0.0, 0.65))
				if from_c > 0.58:
					var g := smoothstep(0.58, 1.0, from_c)
					col = col.lerp(grass, g * (0.78 + grit * 0.1))
			elif grit > 0.55:
				col = col.lerp(Color("c9a66a"), 0.22)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _grass_tex() -> ImageTexture:
	var img := Image.create(256, 256, false, Image.FORMAT_RGB8)
	var n1 := FastNoiseLite.new()
	n1.seed = 21
	n1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n1.frequency = 0.055
	n1.fractal_type = FastNoiseLite.FRACTAL_FBM
	n1.fractal_octaves = 4
	var n2 := FastNoiseLite.new()
	n2.seed = 8
	n2.frequency = 0.16
	var lush := Color("6f8f3a")
	var dry := Color("8aa34a")
	var shade := Color("4e6a28")
	for y in 256:
		for x in 256:
			var wave := n1.get_noise_2d(float(x), float(y))
			var blade := n2.get_noise_2d(float(x) * 1.8, float(y) * 1.8)
			var col := lush.lerp(dry, clampf(0.5 + wave * 0.45, 0.0, 1.0))
			col = col.lerp(shade, clampf(0.18 - blade * 0.2, 0.0, 0.35))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

func _lay_dirt_tracks(game) -> void:
	if game == null or _path_mesh == null:
		return
	var channel := HexGeom.TILE_INSET * sqrt(3.0)
	var width := channel * 0.72
	var pad_r := channel * 0.58
	var path_y := TILE_Y - 0.04
	for ek in game.edges.keys():
		var ends: Array = game.edges[ek]
		var a: Vector2 = game.v_pos[int(ends[0])]
		var b: Vector2 = game.v_pos[int(ends[1])]
		var delta := b - a
		var length := delta.length()
		if length < 1.0:
			continue
		var inst := MeshInstance3D.new()
		inst.name = "DirtPath_%s" % String(ek)
		inst.mesh = _path_mesh
		inst.position = Vector3((a.x + b.x) * 0.5, path_y, (a.y + b.y) * 0.5)
		inst.rotation = Vector3(0, -atan2(delta.y, delta.x), 0)
		inst.scale = Vector3(length * 0.78, 1.6, width)
		inst.material_override = _path_mat
		inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(inst)
	for i in game.v_pos.size():
		var p: Vector2 = game.v_pos[i]
		var pad := MeshInstance3D.new()
		pad.name = "DirtPad_%d" % i
		pad.mesh = _pad_mesh
		pad.position = Vector3(p.x, path_y + 0.06, p.y)
		pad.scale = Vector3(pad_r, 0.55, pad_r)
		pad.material_override = _earth_mat
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)

func _dirt_path_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cols: Array[Vector2] = [
		Vector2(-0.50, 0.00),
		Vector2(-0.34, 0.10),
		Vector2(-0.16, 0.16),
		Vector2(0.00, 0.18),
		Vector2(0.16, 0.16),
		Vector2(0.34, 0.10),
		Vector2(0.50, 0.00),
	]
	var segs := 6
	for i in segs:
		var x0 := float(i) / float(segs) - 0.5
		var x1 := float(i + 1) / float(segs) - 0.5
		var u0 := (x0 + 0.5) * 2.4
		var u1 := (x1 + 0.5) * 2.4
		for c in range(cols.size() - 1):
			var z0: float = cols[c].x
			var y0: float = cols[c].y
			var z1: float = cols[c + 1].x
			var y1: float = cols[c + 1].y
			var v0 := z0 + 0.5
			var v1 := z1 + 0.5
			var a := Vector3(x0, y0, z0)
			var b := Vector3(x1, y0, z0)
			var c1 := Vector3(x1, y1, z1)
			var d := Vector3(x0, y1, z1)
			_path_face(st, a, b, c1, Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1))
			_path_face(st, a, c1, d, Vector2(u0, v0), Vector2(u1, v1), Vector2(u0, v1))
	var left: Vector2 = cols[0]
	var right: Vector2 = cols[cols.size() - 1]
	for i in segs:
		var x0 := float(i) / float(segs) - 0.5
		var x1 := float(i + 1) / float(segs) - 0.5
		var u0 := (x0 + 0.5) * 2.4
		var u1 := (x1 + 0.5) * 2.4
		var a := Vector3(x0, left.y, left.x)
		var b := Vector3(x0, -0.22, left.x)
		var c1 := Vector3(x1, -0.22, left.x)
		var d := Vector3(x1, left.y, left.x)
		_path_face(st, a, b, c1, Vector2(u0, 0.0), Vector2(u0, 0.12), Vector2(u1, 0.12))
		_path_face(st, a, c1, d, Vector2(u0, 0.0), Vector2(u1, 0.12), Vector2(u1, 0.0))
		a = Vector3(x0, right.y, right.x)
		b = Vector3(x1, right.y, right.x)
		c1 = Vector3(x1, -0.22, right.x)
		d = Vector3(x0, -0.22, right.x)
		_path_face(st, a, b, c1, Vector2(u0, 1.0), Vector2(u1, 1.0), Vector2(u1, 0.88))
		_path_face(st, a, c1, d, Vector2(u0, 1.0), Vector2(u1, 0.88), Vector2(u0, 0.88))
	return st.commit()

func _path_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var normal := (b - a).cross(c - a)
	if normal.length_squared() < 0.000001:
		normal = Vector3.UP
	else:
		normal = normal.normalized()
	st.set_normal(normal)
	st.set_uv(ua)
	st.add_vertex(a)
	st.set_normal(normal)
	st.set_uv(ub)
	st.add_vertex(b)
	st.set_normal(normal)
	st.set_uv(uc)
	st.add_vertex(c)

func _hex_frame(coast_edges: Array[bool] = []) -> ArrayMesh:
	return _hex_coast(coast_edges)

func _hex_rim() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var outer := HexGeom.SIZE
	var inner := HexGeom.tile_radius()
	var y0 := TILE_Y - 0.14
	var y1 := TILE_Y + RIM_H
	for i in 6:
		var c0 := HexGeom.corner_at(Vector2.ZERO, i, outer)
		var c1 := HexGeom.corner_at(Vector2.ZERO, (i + 1) % 6, outer)
		var d0 := HexGeom.corner_at(Vector2.ZERO, i, inner)
		var d1 := HexGeom.corner_at(Vector2.ZERO, (i + 1) % 6, inner)
		var o0 := Vector3(c0.x, y1, c0.y)
		var o1 := Vector3(c1.x, y1, c1.y)
		var i0 := Vector3(d0.x, y1, d0.y)
		var i1 := Vector3(d1.x, y1, d1.y)
		_face(st, i0, o0, o1, Vector3.UP, false)
		_face(st, i0, o1, i1, Vector3.UP, false)
		var n := Vector3(c0.x + c1.x, 0, c0.y + c1.y).normalized()
		var o0b := Vector3(c0.x, y0, c0.y)
		var o1b := Vector3(c1.x, y0, c1.y)
		_face(st, o0, o0b, o1b, n, false)
		_face(st, o0, o1b, o1, n, false)
	return st.commit()

func _hex_coast(coast_edges: Array[bool] = []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var any := false
	for i in 6:
		if i >= coast_edges.size() or not coast_edges[i]:
			continue
		any = true
		var c0 := HexGeom.corner(Vector2.ZERO, i)
		var c1 := HexGeom.corner(Vector2.ZERO, (i + 1) % 6)
		var n := Vector3(c0.x + c1.x, 0, c0.y + c1.y).normalized()
		var top_a := Vector3(c0.x, TILE_Y + RIM_H, c0.y)
		var top_b := Vector3(c1.x, TILE_Y + RIM_H, c1.y)
		var bot_a := Vector3(c0.x, 0.0, c0.y)
		var bot_b := Vector3(c1.x, 0.0, c1.y)
		_face(st, top_a, bot_a, bot_b, n, false)
		_face(st, top_a, bot_b, top_b, n, false)
	if not any:
		return ArrayMesh.new()
	return st.commit()

func _hex_body(radius: float, y0: float, y1: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top: Array[Vector3] = []
	var bot: Array[Vector3] = []
	for i in 6:
		var c := HexGeom.corner_at(Vector2.ZERO, i, radius)
		top.append(Vector3(c.x, y1, c.y))
		bot.append(Vector3(c.x, y0, c.y))
	var top_c := Vector3(0, y1, 0)
	for i in 6:
		var j := (i + 1) % 6
		_face(st, top_c, top[i], top[j], Vector3.UP, true)
		var n := Vector3(top[i].x + top[j].x, 0, top[i].z + top[j].z).normalized()
		_face(st, top[i], bot[i], bot[j], n, false)
		_face(st, top[i], bot[j], top[j], n, false)
	return st.commit()

func _hex_floor() -> ArrayMesh:
	return _hex_floor_at(HexGeom.tile_radius(), TILE_Y)

func _hex_floor_at(radius: float, y: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var corners: Array[Vector3] = []
	for i in 6:
		var c := HexGeom.corner_at(Vector2.ZERO, i, radius)
		corners.append(Vector3(c.x, y, c.y))
	var center := Vector3(0, y, 0)
	for i in 6:
		var j := (i + 1) % 6
		_face(st, center, corners[i], corners[j], Vector3.UP, true)
	return st.commit()

func _hex_lip() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var c := HexGeom.corner(Vector2.ZERO, i)
		var d := HexGeom.corner(Vector2.ZERO, (i + 1) % 6)
		var n := Vector3(c.x + d.x, 0, c.y + d.y).normalized()
		var top_a := Vector3(c.x, THICK, c.y)
		var top_b := Vector3(d.x, THICK, d.y)
		var lip_a := Vector3(c.x, THICK - 2.0, c.y)
		var lip_b := Vector3(d.x, THICK - 2.0, d.y)
		_face(st, top_a, lip_a, lip_b, n, false)
		_face(st, top_a, lip_b, top_b, n, false)
	return st.commit()

func _hex_sides() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := (HexGeom.SIZE - 1.35) / HexGeom.SIZE
	for i in 6:
		var c := HexGeom.corner(Vector2.ZERO, i)
		var d := HexGeom.corner(Vector2.ZERO, (i + 1) % 6)
		var n := Vector3(c.x + d.x, 0, c.y + d.y).normalized()
		var lip_a := Vector3(c.x, THICK - 2.0, c.y)
		var lip_b := Vector3(d.x, THICK - 2.0, d.y)
		var mid_a := Vector3(c.x * k, THICK - 4.4, c.y * k)
		var mid_b := Vector3(d.x * k, THICK - 4.4, d.y * k)
		var bot_a := Vector3(c.x * k, 0.0, c.y * k)
		var bot_b := Vector3(d.x * k, 0.0, d.y * k)
		var bevel_n := (n + Vector3.DOWN * 0.65).normalized()
		_face(st, lip_a, mid_a, mid_b, bevel_n, false)
		_face(st, lip_a, mid_b, lip_b, bevel_n, false)
		_face(st, mid_a, bot_a, bot_b, n, false)
		_face(st, mid_a, bot_b, mid_b, n, false)
	return st.commit()

func _prepare_kit() -> void:
	if _kit_ready:
		return
	_found = BoxMesh.new()
	_found.size = Vector3.ONE
	_walls = BoxMesh.new()
	_walls.size = Vector3.ONE
	_win = BoxMesh.new()
	_win.size = Vector3.ONE
	_door = BoxMesh.new()
	_door.size = Vector3.ONE
	_chimney = BoxMesh.new()
	_chimney.size = Vector3.ONE
	_roof = _roof_mesh(8.2, 6.6, 5.4)
	_granja_roof = _roof_mesh(9.6, 7.6, 6.6)
	_planks = _plank_mesh()
	_plaster = _mat(Color("efe4d2"), null, 0.86)
	_roof_wood = _mat(Color("6b4030"), null, 0.82)
	_window_mat = _mat(Color("2a2420"), null, 0.55)
	_lip_wood = _mat(Color("583c28"), null, 0.62)
	_side_wood = _mat(Color("362216"), null, 0.82)
	_player_mat = [_mat(Color("d97706"), null, 0.58), _mat(Color("2563eb"), null, 0.58)]
	_road_mat = [_mat(Color("d97706"), null, 0.72), _mat(Color("2563eb"), null, 0.72)]
	_player_wall = [_mat(Color("f2b25c"), null, 0.62), _mat(Color("6f9cf2"), null, 0.62)]
	_ghost_mat = _mat(Color(0.96, 0.94, 0.90, 0.45), null, 0.7)
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_peg_mesh = SphereMesh.new()
	_peg_mesh.radius = 4.6
	_peg_mesh.height = 9.2
	# Default 64x32 = ~4k tris per peg; ~54 pegs were half the frame.
	_peg_mesh.radial_segments = 16
	_peg_mesh.rings = 8
	_bead = SphereMesh.new()
	_bead.radius = 1.0
	_bead.height = 2.0
	_bead.radial_segments = 10
	_bead.rings = 6
	_peg_mat = _mat(Color("f8f5ed"), null, 0.38)
	_peg_gold = _mat(Color("f0c36a"), null, 0.38)
	_earth_mat = _mat(Color.WHITE, _dirt_tex(false), 0.94)
	_earth_mat.uv1_scale = Vector3(2.4, 2.4, 2.4)
	_earth_bank_mat = _mat(Color("b08a52"), _dirt_tex(false), 0.9)
	_grass_mat = _mat(Color.WHITE, _grass_tex(), 0.88)
	_grass_mat.uv1_scale = Vector3(2.8, 2.8, 2.8)
	_path_mat = _mat(Color.WHITE, _dirt_tex(true), 0.91)
	_path_mesh = _dirt_path_mesh()
	_pad_mesh = CylinderMesh.new()
	_pad_mesh.top_radius = 1.0
	_pad_mesh.bottom_radius = 1.12
	_pad_mesh.height = 0.42
	_pad_mesh.radial_segments = 12
	_kit_ready = true

func _part(root: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, mat: Material, shadow: bool) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	inst.scale = scl
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(inst)

func _plank_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var z := (float(i) - 1.0) * 2.15
		_solid(st, Vector3(0, 0.8, z), Vector3(1.0, 1.6, 1.65))
	return st.commit()

func _solid(st: SurfaceTool, c: Vector3, s: Vector3) -> void:
	var x := s.x * 0.5
	var y := s.y * 0.5
	var z := s.z * 0.5
	var a := c + Vector3(-x, -y, -z)
	var b := c + Vector3(x, -y, -z)
	var c1 := c + Vector3(x, -y, z)
	var d := c + Vector3(-x, -y, z)
	var e := c + Vector3(-x, y, -z)
	var f := c + Vector3(x, y, -z)
	var g := c + Vector3(x, y, z)
	var h := c + Vector3(-x, y, z)
	_face(st, e, f, g, Vector3.UP, false)
	_face(st, e, g, h, Vector3.UP, false)
	_face(st, d, h, g, Vector3(0, 0, 1), false)
	_face(st, d, g, c1, Vector3(0, 0, 1), false)
	_face(st, b, c1, g, Vector3(1, 0, 0), false)
	_face(st, b, g, f, Vector3(1, 0, 0), false)
	_face(st, a, e, h, Vector3(-1, 0, 0), false)
	_face(st, a, h, d, Vector3(-1, 0, 0), false)
	_face(st, a, b, f, Vector3(0, 0, -1), false)
	_face(st, a, f, e, Vector3(0, 0, -1), false)

func _dress_table() -> void:
	pass

func _off_board(dir: Vector3) -> Vector3:
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var origin := Vector2(mid.x, mid.z)
	var need := 0.0
	for child in get_children():
		if not child is Node3D or child.name == "TableDress" or child == pieces:
			continue
		var body := child as Node3D
		var rel := Vector2(body.position.x, body.position.z) - origin
		need = maxf(need, rel.dot(Vector2(flat.x, flat.z)) + HexGeom.SIZE + 16.0)
	return mid + flat * need

func _boat(parent: Node3D, at: Vector3) -> void:
	_prop(parent, _found, at + Vector3(0, 1.5, 0), Vector3(30, 2.6, 11), _roof_wood, true)
	_prop(parent, _chimney, at + Vector3(-2, 6.4, 0), Vector3(0.7, 9, 0.7), _side_wood, false)

func _buoy(parent: Node3D, at: Vector3) -> void:
	_prop(parent, _chimney, at + Vector3(0, 3.2, 0), Vector3(2.2, 6.2, 2.2), _lip_wood, false)
	_prop(parent, _bead, at + Vector3(0, 7.2, 0), Vector3(2.6, 2.6, 2.6), _player_mat[0], false)

func _crate(parent: Node3D, at: Vector3) -> void:
	_prop(parent, _found, at + Vector3(0, 0.4, 0), Vector3(12, 0.6, 9), _side_wood, false)
	_prop(parent, _found, at + Vector3(0, 3.4, 0), Vector3(7.5, 5.4, 6.2), _roof_wood, true)

func _prop(parent: Node3D, mesh: Mesh, pos: Vector3, scl: Vector3, mat: Material, shadow: bool) -> void:
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	inst.position = pos
	inst.scale = scl
	inst.material_override = mat
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(inst)

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
