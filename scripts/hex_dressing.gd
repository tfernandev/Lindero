extends Node3D

const HexGeom := preload("res://scripts/hex_lib.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

# Recursos de Lindero y terrenos
const KIND_LAGOON := -1
const KIND_WOOD := 0
const KIND_CLAY := 1
const KIND_GRAIN := 2
const KIND_STONE := 3
const KIND_MEADOW := 4

# Relieve de Tripo sobre la base hexagonal de Godot.
# El suelo pintado cubre el hexágono; los GLB se agrupan en el centro.
# Tiles: models/tiles/hex_*.glb + pilot_* (table_board / mount_calibrated_glb).
const PLACE_PROPS := true
const SCENERY_R := HexGeom.SIZE - HexGeom.TILE_INSET - 6.0
const PROP_R := 46.0
const PROP_R_KIND := {
	KIND_GRAIN: 36.0,
}
const SCENERY_SINK := 0.35
const TOKEN_WELL_R := 17.0
const PLATE_CUT := 0.12
# Caras del recorte hexagonal: mismo color que el zócalo del terreno, no terracota.
const CAP := {
	KIND_WOOD: Color("3d5c32"),
	KIND_CLAY: Color("a85a38"),
	KIND_GRAIN: Color("c9a04a"),
	KIND_STONE: Color("6e6c68"),
	KIND_MEADOW: Color("5a7a40"),
	KIND_LAGOON: Color("2a5c58"),
}
const PILOT_GLB := {
	KIND_WOOD: {
		"path": "res://models/pilot/pilot_wood.glb",
		"rot_y": 0.0,
	},
	KIND_CLAY: {
		"path": "res://models/pilot/pilot_clay.glb",
		"rot_y": 1.5707963,
	},
	KIND_GRAIN: {
		"path": "res://models/pilot/pilot_grain.glb",
		"rot_y": 0.0,
	},
	KIND_MEADOW: {
		"path": "res://models/pilot/pilot_sheep.glb",
		"rot_y": 0.0,
	},
	KIND_STONE: {
		"path": "res://models/pilot/pilot_stone.glb",
		"rot_y": 0.0,
	},
}

static var _pilot_mesh: Dictionary = {}
static var _pilot_box: Dictionary = {}
static var _pilot_clip: Dictionary = {}
static var debug_log := false
static var last_reports: Dictionary = {}

static var _ready_kit := false
static var _trunk: CylinderMesh
static var _stem: CylinderMesh
static var _ball: SphereMesh
static var _cobble: SphereMesh
static var _box: BoxMesh
static var _cone: CylinderMesh
static var _soil: ArrayMesh
static var _water: ArrayMesh
static var _tuft: ArrayMesh
static var _tuft_dry: ArrayMesh
static var _tuft_card: ArrayMesh

# Materiales con paleta curada y natural
static var _bark: StandardMaterial3D
static var _leaf: StandardMaterial3D
static var _leaf_deep: StandardMaterial3D
static var _leaf_light: StandardMaterial3D
static var _bush_mat: StandardMaterial3D
static var _rock: StandardMaterial3D
static var _rock_dark: StandardMaterial3D
static var _rock_pale: StandardMaterial3D
static var _rock_moss: StandardMaterial3D
static var _grass_deep: StandardMaterial3D
static var _vein: StandardMaterial3D
static var _straw: StandardMaterial3D
static var _head: StandardMaterial3D
static var _bale: StandardMaterial3D
static var _band: StandardMaterial3D
static var _clay: StandardMaterial3D
static var _brick: StandardMaterial3D
static var _grass: StandardMaterial3D
static var _blade_mat: StandardMaterial3D
static var _blade_dry: StandardMaterial3D
static var _card_mat: StandardMaterial3D
static var _petal_gold: StandardMaterial3D
static var _petal_cream: StandardMaterial3D
static var _petal_rose: StandardMaterial3D
static var _wool: StandardMaterial3D
static var _sheep_dark: StandardMaterial3D
static var _water_mat: StandardMaterial3D
static var _soil_wood: StandardMaterial3D
static var _soil_grain: StandardMaterial3D
static var _soil_stone: StandardMaterial3D
static var _soil_clay: StandardMaterial3D
static var _soil_meadow: StandardMaterial3D
static var _sand: StandardMaterial3D

const PROP_KIT := {
	KIND_WOOD: "res://models/props/bosque_grupo_partes.glb",
	KIND_STONE: "res://models/props/piedra_grupo_partes.glb",
	KIND_CLAY: "res://models/props/arcilla_grupo_partes.glb",
	KIND_MEADOW: "res://models/props/oveja.glb", # CC BY Kinga Kroliczek
	KIND_GRAIN: "res://models/props/paca_heno.glb", # CC BY ThomasWhalley
}

# Solo los kits con viento=true se mecen (las rocas no)
const KIT_WIND := {
	KIND_WOOD: true,
}

# Un GLB = un objeto: copiar varios en el hex en vez de inflar uno solo.
const KIT_COPIES := {
	KIND_MEADOW: 5,
	KIND_GRAIN: 3,
}

# Partes sueltas (Tripo). No desplazar meshes de una oveja/paca o se desarma.
const KIT_LOOSE_PARTS := {
	KIND_WOOD: true,
	KIND_STONE: true,
	KIND_CLAY: true,
}

static var _kit_packed: Dictionary = {}
static var _kit_requested: Dictionary = {}

var _pending_path := ""
var _pending_kind := 0
var _pending_q := 0
var _pending_r := 0

# Viento suave en las partes del kit (respeta Calma / reduce_motion)
var _sway: Array[Dictionary] = []
var _sway_t := 0.0

static func wants(kind: int, _q: int, _r: int) -> bool:
	if kind == KIND_LAGOON:
		return true
	return PLACE_PROPS and PROP_KIT.has(kind) and FileAccess.file_exists(String(PROP_KIT[kind]))

func apply(kind: int, q: int, r: int) -> void:
	name = "Dress_%d_%d" % [q, r]
	if _queue_prop_kit(kind, q, r):
		return
	if kind == KIND_LAGOON:
		_ensure_kit()
		_lagoon(q, r)

func _enter_tree() -> void:
	if _pending_path != "":
		set_process(true)

func _queue_prop_kit(kind: int, q: int, r: int) -> bool:
	if not PROP_KIT.has(kind):
		return false
	var path := String(PROP_KIT[kind])
	if not FileAccess.file_exists(path):
		return false
	if _kit_packed.has(path) and _kit_packed[path] != null:
		return _mount_kit(_kit_packed[path] as PackedScene, kind, q, r)
	_pending_path = path
	_pending_kind = kind
	_pending_q = q
	_pending_r = r
	if not bool(_kit_requested.get(path, false)):
		_kit_requested[path] = true
		var err := ResourceLoader.load_threaded_request(path)
		if err != OK and ResourceLoader.exists(path):
			var packed := load(path) as PackedScene
			_kit_packed[path] = packed
			_pending_path = ""
			return packed != null and _mount_kit(packed, kind, q, r)
	set_process(true)
	return true

func _process(dt: float) -> void:
	if _pending_path != "":
		_poll_pending()
	_tick_sway(dt)
	if _pending_path == "" and _sway.is_empty():
		set_process(false)

func _poll_pending() -> void:
	if _kit_packed.has(_pending_path) and _kit_packed[_pending_path] != null:
		var ready: PackedScene = _kit_packed[_pending_path]
		_pending_path = ""
		_mount_kit(ready, _pending_kind, _pending_q, _pending_r)
		return
	var status := ResourceLoader.load_threaded_get_status(_pending_path)
	if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
		return
	if status == ResourceLoader.THREAD_LOAD_LOADED:
		if not _kit_packed.has(_pending_path):
			_kit_packed[_pending_path] = ResourceLoader.load_threaded_get(_pending_path)
		var packed: PackedScene = _kit_packed.get(_pending_path, null) as PackedScene
		_pending_path = ""
		if packed != null:
			_mount_kit(packed, _pending_kind, _pending_q, _pending_r)
		return
	_pending_path = ""

func _tick_sway(dt: float) -> void:
	if _sway.is_empty():
		return
	if UiTheme.reduce_motion:
		for s in _sway:
			var mi: MeshInstance3D = s["mi"]
			if is_instance_valid(mi):
				mi.rotation = s["base"]
		return
	_sway_t += dt
	for s in _sway:
		var mi: MeshInstance3D = s["mi"]
		if not is_instance_valid(mi):
			continue
		var base: Vector3 = s["base"]
		var ph: float = s["phase"]
		var amp: float = s["amp"]
		var a := sin(_sway_t * 1.05 + ph) * amp + sin(_sway_t * 2.35 + ph * 1.7) * amp * 0.35
		var b := cos(_sway_t * 0.85 + ph) * amp * 0.6
		mi.rotation = Vector3(base.x + b, base.y, base.z + a)

func _mount_kit(packed: PackedScene, kind: int, q: int, r: int) -> bool:
	if packed == null:
		return false
	var copies := maxi(1, int(KIT_COPIES.get(kind, 1)))
	var kit := Node3D.new()
	kit.name = "PropKit"
	add_child(kit)
	var first := _instance_prop(packed)
	if first == null:
		kit.queue_free()
		return false
	kit.add_child(first)
	if copies > 1:
		var one_box := _local_aabb(first)
		var one_r := maxf(one_box.size.x, one_box.size.z) * 0.5
		if one_r < 0.001:
			one_r = 0.5
		var ring := one_r * 1.35
		for c in copies:
			var node: Node3D = first if c == 0 else _instance_prop(packed)
			if node == null:
				continue
			if c > 0:
				kit.add_child(node)
			var ang := TAU * float(c) / float(copies) + _u(q, r, 11) * 0.35
			var rad := ring * (1.12 + _u(q, r, 21 + c) * 0.16)
			var s := 0.94 + _u(q, r, 41 + c) * 0.12
			node.scale = Vector3(s, s, s)
			node.rotation.y = _u(q, r, 31 + c) * TAU
			var box := _local_aabb(node)
			node.position = Vector3(cos(ang) * rad, -box.position.y * s, sin(ang) * rad)
	_sway.clear()
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(kit, meshes)
	var loose := bool(KIT_LOOSE_PARTS.get(kind, false))
	for i in meshes.size():
		var mi: MeshInstance3D = meshes[i]
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var box := _mesh_aabb_in(mi, kit)
		var h := box.size.y
		var span := maxf(box.size.x, box.size.z)
		if h < 0.07 and span > 0.30:
			mi.visible = false
			continue
		if maxf(h, span) < 0.025:
			mi.visible = false
			continue
		if loose:
			var jx := (_u(q, r, 60 + i) - 0.5) * 0.11
			var jz := (_u(q, r, 160 + i) - 0.5) * 0.11
			mi.position += Vector3(jx, 0.0, jz)
		if bool(KIT_WIND.get(kind, false)):
			var tall := clampf(h / maxf(span, 0.001), 0.25, 1.0)
			_sway.append({
				"mi": mi,
				"base": mi.rotation,
				"phase": _u(q, r, 300 + i) * TAU,
				"amp": 0.09 * tall,
			})
	var fitted_box := _local_aabb(kit)
	if fitted_box.size.length() < 0.001:
		kit.queue_free()
		return false
	var radius := maxf(fitted_box.size.x, fitted_box.size.z) * 0.5
	if radius < 0.001:
		radius = 0.5
	var target_r := float(PROP_R_KIND.get(kind, PROP_R))
	var fitted := target_r / radius
	kit.scale = Vector3(fitted, fitted, fitted)
	kit.position = Vector3(
		-fitted_box.get_center().x * fitted,
		-fitted_box.position.y * fitted - 0.2,
		-fitted_box.get_center().z * fitted
	)
	kit.rotation.y = _u(q, r, 7) * TAU
	_fill_hex_details(kind, q, r)
	if not _sway.is_empty():
		set_process(true)
	return true

func _instance_prop(packed: PackedScene) -> Node3D:
	var inst := packed.instantiate()
	if inst is Node3D:
		return inst
	var wrap := Node3D.new()
	wrap.add_child(inst)
	return wrap

# Detalle de suelo original de Lindero (sin assets de terceros).
# Pasto solo en pradera y sotobosque; rastrojo en grano; piedras mixtas en todos.
func _fill_hex_details(kind: int, q: int, r: int) -> void:
	_ensure_kit()
	match kind:
		KIND_MEADOW:
			_detail_grass(q, r, 18, true, 21.0, 48.0, 530)
			_detail_flowers(q, r)
			_detail_pebbles(q, r, 14, 24.0, 48.0, 560)
			_detail_bushes(q, r, 2, 43.0, 580)
		KIND_GRAIN:
			_detail_stubble(q, r)
			_detail_pebbles(q, r, 8, 28.0, 48.0, 640)
		KIND_WOOD:
			_detail_grass(q, r, 9, false, 23.0, 40.0, 700)
			_detail_pebbles(q, r, 7, 24.0, 47.0, 720)
		KIND_STONE:
			_detail_pebbles(q, r, 16, 22.0, 48.0, 800)
		KIND_CLAY:
			_detail_pebbles(q, r, 9, 26.0, 48.0, 880)

func _detail_grass(q: int, r: int, count: int, lush: bool, min_rad: float, max_rad: float, salt: int) -> void:
	var tufts: Array[Transform3D] = []
	for i in count:
		var p := _ring(q, r, i, count, (min_rad + max_rad) * 0.5, max_rad - min_rad, 0.18, salt, min_rad, max_rad)
		if p.length() < TOKEN_WELL_R + 4.0:
			continue
		var s := (13.0 + _u(q, r, salt + 20 + i) * 5.0) if lush else (8.0 + _u(q, r, salt + 20 + i) * 3.0)
		var lean := (_u(q, r, salt + 40 + i) - 0.5) * 0.06
		var yaw := _u(q, r, salt + 60 + i) * TAU
		var y0 := _ground(p.length())
		tufts.append(_xf(p, Vector3(s, s * (0.92 + _u(q, r, salt + 80 + i) * 0.2), s), yaw, lean, y0))
	_scatter("GrassCards", _tuft_card, _card_mat, tufts, false)

func _detail_flowers(q: int, r: int) -> void:
	var stems: Array[Transform3D] = []
	var golds: Array[Transform3D] = []
	var creams: Array[Transform3D] = []
	var roses: Array[Transform3D] = []
	var base_ang := _spin(q, r)
	for i in 9:
		var ang := base_ang + 0.8 + float(i) * 0.52 + _u(q, r, 170 + i) * 0.2
		var rad := clampf(27.0 + _u(q, r, 180 + i) * 18.0, 24.0, 46.0)
		var p := Vector2(cos(ang), sin(ang)) * rad
		var h := 2.6 + _u(q, r, 185 + i) * 1.1
		var yaw := _u(q, r, 190 + i) * TAU
		var y0 := _ground(p.length())
		stems.append(_xf(p, Vector3(0.14, h, 0.14), yaw, 0.08, y0 + h * 0.5))
		var fl := _xf(p, Vector3(0.7, 0.5, 0.7), yaw, 0.0, y0 + h + 0.28)
		if i % 3 == 0:
			golds.append(fl)
		elif i % 3 == 1:
			creams.append(fl)
		else:
			roses.append(fl)
	_scatter("FlowerStems", _stem, _grass, stems, false)
	_scatter("GoldFlowers", _ball, _petal_gold, golds, false)
	_scatter("CreamFlowers", _ball, _petal_cream, creams, false)
	_scatter("RoseFlowers", _ball, _petal_rose, roses, false)

func _detail_bushes(q: int, r: int, count: int, rad: float, salt: int) -> void:
	var bushes: Array[Transform3D] = []
	var base_ang := _spin(q, r)
	for i in count:
		var ang := base_ang + 1.3 + float(i) * 2.15
		var p := Vector2(cos(ang), sin(ang)) * rad
		var s := 2.4 + _u(q, r, salt + i) * 0.9
		bushes.append(_xf(p, Vector3(s, s * 0.55, s), _u(q, r, salt + 20 + i) * TAU, 0.0, _ground(p.length()) + s * 0.22))
	_scatter("PastureBushes", _ball, _bush_mat, bushes, false)

func _detail_stubble(q: int, r: int) -> void:
	var stubs: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var stems: Array[Transform3D] = []
	var base_ang := _spin(q, r)
	for i in 11:
		var p := _ring(q, r, i, 11, 40.0, 12.0, 0.4, 650, 30.0, 48.0)
		var s := 4.6 + _u(q, r, 660 + i) * 2.2
		var lean := (_u(q, r, 670 + i) - 0.5) * 0.14
		var y0 := _ground(p.length())
		stubs.append(_xf(p, Vector3(s, s, s), _u(q, r, 680 + i) * TAU, lean, y0))
	for i in 5:
		var ang := base_ang + 1.7 + float(i) * 0.18
		var p := Vector2(cos(ang), sin(ang)) * (34.0 + float(i % 2) * 6.0)
		_stalk(stems, heads, q, r, p, 5.2 + _u(q, r, 690 + i) * 1.8, 0.4, 700 + i)
	_scatter("Stubble", _tuft_dry, _blade_dry, stubs, false)
	_scatter("EdgeStalks", _stem, _straw, stems, false)
	_scatter("EdgeHeads", _cone, _head, heads, false)

func _detail_pebbles(q: int, r: int, count: int, min_rad: float, max_rad: float, salt: int) -> void:
	var round_n: Array[Transform3D] = []
	var round_d: Array[Transform3D] = []
	var round_p: Array[Transform3D] = []
	var moss: Array[Transform3D] = []
	var slabs: Array[Transform3D] = []
	var shards: Array[Transform3D] = []
	for i in count:
		var p := _ring(q, r, i, count, (min_rad + max_rad) * 0.5, max_rad - min_rad, 0.22, salt, min_rad, max_rad)
		if p.length() < TOKEN_WELL_R + 5.0:
			continue
		var y0 := _ground(p.length())
		var yaw := _u(q, r, salt + 40 + i) * TAU
		var lean := (_u(q, r, salt + 80 + i) - 0.5) * 0.4
		var s := 1.0 + _u(q, r, salt + 20 + i) * 1.6
		var shape := int(_u(q, r, salt + 10 + i) * 6.0)
		match shape:
			0:
				round_n.append(_xf(p, Vector3(s * 1.2, s * 0.62, s), yaw, 0.0, y0 + s * 0.28))
			1:
				round_d.append(_xf(p, Vector3(s * 1.05, s * 0.55, s * 0.88), yaw, 0.0, y0 + s * 0.24))
			2:
				round_p.append(_xf(p, Vector3(s * 0.92, s * 0.48, s * 1.15), yaw, 0.0, y0 + s * 0.22))
			3:
				moss.append(_xf(p, Vector3(s * 1.18, s * 0.5, s * 0.86), yaw, 0.0, y0 + s * 0.22))
			4:
				var slab := Vector3(s * 1.85, s * 0.36, s * 1.15)
				slabs.append(_xf(p, slab, yaw, lean * 0.35, y0 + slab.y * 0.48))
			_:
				var shard := Vector3(s * 0.52, s * 1.2, s * 0.72)
				shards.append(_xf(p, shard, yaw, lean, y0 + shard.y * 0.46))
	_scatter("PebbleRound", _cobble, _rock, round_n, false)
	_scatter("PebbleDark", _cobble, _rock_dark, round_d, false)
	_scatter("PebblePale", _cobble, _rock_pale, round_p, false)
	_scatter("PebbleMoss", _cobble, _rock_moss, moss, false)
	_scatter("PebbleSlab", _box, _rock, slabs, false)
	_scatter("PebbleShard", _box, _rock_dark, shards, false)

func _mesh_aabb_in(mi: MeshInstance3D, space: Node3D) -> AABB:
	var a := mi.get_aabb()
	var xf := _mesh_to_root(mi, space)
	var box := AABB(xf * a.position, Vector3.ZERO)
	for e in 8:
		box = box.expand(xf * a.get_endpoint(e))
	return box

static func clear_pilot_cache() -> void:
	_pilot_mesh.clear()
	_pilot_box.clear()
	_pilot_clip.clear()
	last_reports.clear()

func mount_calibrated_glb(kind: int, q: int = 0) -> bool:
	if not PILOT_GLB.has(kind):
		return false
	var spec: Dictionary = PILOT_GLB[kind]
	var path: String = spec["path"]
	if not _pilot_mesh.has(kind) and not ResourceLoader.exists(path):
		last_reports[kind] = {"path": path, "missing": true, "kind": kind}
		return false
	var node := Node3D.new()
	node.name = "Pilot"
	add_child(node)
	if not _pilot_mesh.has(kind):
		var packed := load(path) as PackedScene
		if packed == null:
			last_reports[kind] = {"path": path, "load_failed": true, "kind": kind}
			node.queue_free()
			return false
		var loaded := packed.instantiate() as Node3D
		if loaded == null:
			node.queue_free()
			return false
		loaded.rotation.y = float(spec.get("rot_y", 0.0))
		node.add_child(loaded)
		var raw_box := _local_aabb(node)
		var cut := _cut_pilot_to_hex(node, kind)
		node.remove_child(loaded)
		loaded.free()
		if cut == null:
			last_reports[kind] = {"path": path, "cut_failed": true, "kind": kind, "raw_aabb": raw_box}
			node.queue_free()
			return false
		cut = _strip_low_plate(cut)
		_pilot_mesh[kind] = cut
		var probe := MeshInstance3D.new()
		probe.mesh = cut
		node.add_child(probe)
		_pilot_box[kind] = _local_aabb(node)
		node.remove_child(probe)
		probe.free()
		var clip_center := raw_box.get_center()
		var measured := _mesh_hex_radius(cut, clip_center)
		_pilot_clip[kind] = {
			"center": clip_center,
			"radius": maxf(measured, _inscribed_hex_radius(raw_box)),
		}
		last_reports[kind] = {
			"path": path,
			"kind": kind,
			"raw_aabb": raw_box,
			"cut_aabb": _pilot_box[kind],
			"clip_radius": _pilot_clip[kind]["radius"],
			"surfaces": cut.get_surface_count(),
			"caps": false,
			"stripped_plate": true,
		}
		if debug_log:
			var rb: AABB = raw_box
			var cb: AABB = _pilot_box[kind]
			print("[dress] kind=%d path=%s raw=%s cut=%s clip_r=%.4f surfs=%d" % [
				kind, path, rb, cb, float(_pilot_clip[kind]["radius"]), cut.get_surface_count()
			])
	var inst := MeshInstance3D.new()
	inst.name = "HexCut"
	inst.mesh = _pilot_mesh[kind] as ArrayMesh
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(inst)
	var sink := float(spec.get("sink_y", SCENERY_SINK))
	var clip: Dictionary = _pilot_clip.get(kind, {})
	_fit_scenery(
		node,
		_pilot_box[kind] as AABB,
		sink,
		clip.get("center", (_pilot_box[kind] as AABB).get_center()),
		float(clip.get("radius", 0.0)),
		PROP_R
	)
	if last_reports.has(kind) and last_reports[kind] is Dictionary:
		var rep: Dictionary = last_reports[kind]
		rep["fitted_scale"] = node.scale.x
		rep["fitted_pos"] = node.position
		rep["sink"] = sink
		last_reports[kind] = rep
	return true

func _fit_scenery(node: Node3D, box: AABB, sink: float, clip_center: Vector3 = Vector3.INF, clip_radius: float = -1.0, target_r: float = -1.0) -> void:
	var radius := clip_radius if clip_radius > 0.001 else maxf(box.size.x, box.size.z) * 0.5
	if radius < 0.001:
		return
	var fit_to := target_r if target_r > 0.001 else SCENERY_R
	var fitted := fit_to / radius
	var center := clip_center
	if not center.is_finite():
		center = box.get_center()
	node.scale = Vector3(fitted, fitted, fitted)
	node.position = Vector3(-center.x * fitted, -box.position.y * fitted - sink, -center.z * fitted)

func _mesh_hex_radius(mesh: ArrayMesh, center: Vector3) -> float:
	var worst := 0.0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for v in verts:
			worst = maxf(worst, _point_hex_r(Vector2(v.x - center.x, v.z - center.z)))
	return worst

func _point_hex_r(p: Vector2) -> float:
	var worst := 0.0
	for i in 6:
		var a := HexGeom.corner_at(Vector2.ZERO, i, 1.0)
		var b := HexGeom.corner_at(Vector2.ZERO, (i + 1) % 6, 1.0)
		var edge := b - a
		var inward := Vector2(-edge.y, edge.x)
		if inward.length_squared() < 0.000001:
			continue
		inward = inward.normalized()
		var denom := inward.dot(a)
		if absf(denom) < 0.000001:
			continue
		worst = maxf(worst, inward.dot(p) / denom)
	return worst

func _inscribed_hex_radius(box: AABB) -> float:
	var half_x := box.size.x * 0.5
	var half_z := box.size.z * 0.5
	var r_height := half_z
	var r_width := half_x * 2.0 / sqrt(3.0)
	return minf(r_height, r_width)

func cut_to_hex(node: Node3D, center: Vector3, radius: float) -> ArrayMesh:
	if node == null or radius < 0.001:
		return null
	var planes: Array = _hex_planes(center.x, center.z, radius, true)
	var sources: Array[MeshInstance3D] = []
	_collect_meshes(node, sources)
	var cut := ArrayMesh.new()
	var cap_v := PackedVector3Array()
	var cap_n := PackedVector3Array()
	var cap_i := PackedInt32Array()
	for mi in sources:
		_clip_instance(mi, _mesh_to_root(mi, node), planes, cut, cap_v, cap_n, cap_i)
	_apply_caps(cut, cap_v, cap_n, cap_i)
	if cut.get_surface_count() == 0:
		return null
	return cut

func _apply_caps(cut: ArrayMesh, cap_v: PackedVector3Array, cap_n: PackedVector3Array, cap_i: PackedInt32Array) -> void:
	if cap_i.is_empty() or cap_v.is_empty():
		return
	var uvs := PackedVector2Array()
	uvs.resize(cap_v.size())
	for i in cap_v.size():
		uvs[i] = Vector2(cap_v[i].x / (HexGeom.SIZE * 2.0) + 0.5, cap_v[i].z / (HexGeom.SIZE * 2.0) + 0.5)
	var out: Array = []
	out.resize(Mesh.ARRAY_MAX)
	out[Mesh.ARRAY_VERTEX] = cap_v
	out[Mesh.ARRAY_NORMAL] = cap_n
	out[Mesh.ARRAY_TEX_UV] = uvs
	out[Mesh.ARRAY_INDEX] = cap_i
	cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)

func _cut_pilot_to_hex(pilot: Node3D, kind: int = 0) -> ArrayMesh:
	var box := _local_aabb(pilot)
	var center := box.get_center()
	var radius := _inscribed_hex_radius(box)
	if radius < 0.001:
		return null
	var plate_y := box.position.y + box.size.y * PLATE_CUT
	var planes: Array = [{
		"point": Vector3(center.x, plate_y, center.z),
		"normal": Vector3.UP,
		"out": Vector3.DOWN,
		"edges": [],
		"cap": false,
	}]
	planes.append_array(_hex_planes(center.x, center.z, radius, false))
	var sources: Array[MeshInstance3D] = []
	_collect_meshes(pilot, sources)
	var cut := ArrayMesh.new()
	var cap_v := PackedVector3Array()
	var cap_n := PackedVector3Array()
	var cap_i := PackedInt32Array()
	for mi in sources:
		_clip_instance(mi, _mesh_to_root(mi, pilot), planes, cut, cap_v, cap_n, cap_i)
	if cut.get_surface_count() > 0:
		for plane in planes:
			plane["edges"] = []
		var merged := MeshInstance3D.new()
		merged.mesh = cut
		var pass2 := ArrayMesh.new()
		var cap2_v := PackedVector3Array()
		var cap2_n := PackedVector3Array()
		var cap2_i := PackedInt32Array()
		_clip_instance(merged, Transform3D.IDENTITY, planes, pass2, cap2_v, cap2_n, cap2_i)
		merged.free()
		if pass2.get_surface_count() > 0:
			cut = pass2
	if cut.get_surface_count() == 0:
		return null
	return cut

func _strip_low_plate(mesh: ArrayMesh) -> ArrayMesh:
	if mesh == null or mesh.get_surface_count() == 0:
		return mesh
	var lo := INF
	var hi := -INF
	for s in mesh.get_surface_count():
		var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
		for v in verts:
			lo = minf(lo, v.y)
			hi = maxf(hi, v.y)
	var span := hi - lo
	if span < 0.0001:
		return mesh
	var cutoff := lo + span * 0.16
	var out := ArrayMesh.new()
	var kept := 0
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var src_i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var dst_v := PackedVector3Array()
		var dst_n := PackedVector3Array()
		var dst_uv := PackedVector2Array()
		var dst_i := PackedInt32Array()
		var tri_count := src_i.size() / 3 if not src_i.is_empty() else src_v.size() / 3
		for t in tri_count:
			var i0 := src_i[t * 3] if not src_i.is_empty() else t * 3
			var i1 := src_i[t * 3 + 1] if not src_i.is_empty() else t * 3 + 1
			var i2 := src_i[t * 3 + 2] if not src_i.is_empty() else t * 3 + 2
			if i0 >= src_v.size() or i1 >= src_v.size() or i2 >= src_v.size():
				continue
			var a: Vector3 = src_v[i0]
			var b: Vector3 = src_v[i1]
			var c: Vector3 = src_v[i2]
			var ymax := maxf(a.y, maxf(b.y, c.y))
			var nrm := (b - a).cross(c - a)
			var nlen := nrm.length()
			var up := absf(nrm.y / nlen) if nlen > 0.00001 else 1.0
			if ymax <= cutoff and up >= 0.72:
				continue
			var base := dst_v.size()
			for idx in [i0, i1, i2]:
				dst_v.append(src_v[idx])
				dst_n.append(src_n[idx] if idx < src_n.size() else Vector3.UP)
				dst_uv.append(src_uv[idx] if idx < src_uv.size() else Vector2.ZERO)
			dst_i.append(base)
			dst_i.append(base + 1)
			dst_i.append(base + 2)
			kept += 1
		if dst_i.is_empty():
			continue
		var out_a: Array = []
		out_a.resize(Mesh.ARRAY_MAX)
		out_a[Mesh.ARRAY_VERTEX] = dst_v
		out_a[Mesh.ARRAY_NORMAL] = dst_n
		out_a[Mesh.ARRAY_TEX_UV] = dst_uv
		out_a[Mesh.ARRAY_INDEX] = dst_i
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out_a)
		var mat := mesh.surface_get_material(s)
		if mat != null:
			out.surface_set_material(out.get_surface_count() - 1, mat)
	if kept < 16 or out.get_surface_count() == 0:
		return mesh
	return out

func _collect_meshes(root: Node, into: Array[MeshInstance3D]) -> void:
	if root is MeshInstance3D and (root as MeshInstance3D).mesh != null:
		into.append(root)
	for child in root.get_children():
		_collect_meshes(child, into)

func _mesh_to_root(mi: MeshInstance3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var walk: Node = mi
	while walk != root and walk is Node3D:
		xf = (walk as Node3D).transform * xf
		walk = walk.get_parent()
	return xf

func _local_aabb(root: Node3D) -> AABB:
	return _calc_aabb_xf(root, root)

func _calc_aabb_xf(root: Node3D, space: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var sources: Array[MeshInstance3D] = []
	_collect_meshes(root, sources)
	for mi in sources:
		var xf := _mesh_to_root(mi, space)
		var a := mi.get_aabb()
		for i in 8:
			var p := xf * a.get_endpoint(i)
			if first:
				box = AABB(p, Vector3.ZERO)
				first = false
			else:
				box = box.expand(p)
	return box

func _hex_planes(cx: float, cz: float, radius: float, cap_sides: bool = true) -> Array:
	var planes: Array = []
	var verts: Array[Vector3] = []
	for i in 6:
		var c := HexGeom.corner_at(Vector2.ZERO, i, radius)
		verts.append(Vector3(cx + c.x, 0.0, cz + c.y))
	for i in 6:
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[(i + 1) % 6]
		var edge := b - a
		var inward := Vector3(-edge.z, 0.0, edge.x).normalized()
		planes.append({"point": a, "normal": inward, "out": -inward, "edges": [], "cap": cap_sides})
	return planes

func _hole_planes(cx: float, cz: float, radius: float) -> Array:
	var planes: Array = []
	var verts: Array[Vector3] = []
	for i in 6:
		var c := HexGeom.corner_at(Vector2.ZERO, i, radius)
		verts.append(Vector3(cx + c.x, 0.0, cz + c.y))
	for i in 6:
		var a: Vector3 = verts[i]
		var b: Vector3 = verts[(i + 1) % 6]
		var edge := b - a
		var outward := Vector3(edge.z, 0.0, -edge.x).normalized()
		planes.append({"point": a, "normal": outward, "out": -outward, "edges": [], "cap": true})
	return planes

func _clip_instance(mi: MeshInstance3D, xf: Transform3D, planes: Array, cut: ArrayMesh, cap_v: PackedVector3Array, cap_n: PackedVector3Array, cap_i: PackedInt32Array) -> void:
	var mesh := mi.mesh
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(s)
		var src_v: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		if src_v.is_empty():
			continue
		var src_n: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var src_uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var src_i: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var dst_v := PackedVector3Array()
		var dst_n := PackedVector3Array()
		var dst_uv := PackedVector2Array()
		var dst_i := PackedInt32Array()
		var tri_count := src_i.size() / 3 if not src_i.is_empty() else src_v.size() / 3
		for t in tri_count:
			var poly: Array = []
			for k in 3:
				var idx := src_i[t * 3 + k] if not src_i.is_empty() else t * 3 + k
				var nrm := Vector3.UP
				if idx < src_n.size():
					nrm = (xf.basis * src_n[idx]).normalized()
				var uv := Vector2.ZERO
				if idx < src_uv.size():
					uv = src_uv[idx]
				poly.append([xf * src_v[idx], nrm, uv])
			for plane in planes:
				if poly.size() < 3:
					break
				poly = _clip_poly(poly, plane)
			if poly.size() < 3:
				continue
			var base := dst_v.size()
			for rec in poly:
				dst_v.append(rec[0])
				dst_n.append(rec[1])
				dst_uv.append(rec[2])
			for k in poly.size() - 2:
				dst_i.append(base)
				dst_i.append(base + k + 1)
				dst_i.append(base + k + 2)
		if dst_i.is_empty():
			continue
		var out: Array = []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = dst_v
		out[Mesh.ARRAY_NORMAL] = dst_n
		out[Mesh.ARRAY_TEX_UV] = dst_uv
		out[Mesh.ARRAY_INDEX] = dst_i
		cut.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
		var mat := mesh.surface_get_material(s)
		if mat == null:
			mat = mi.get_active_material(s)
		if mat != null:
			cut.surface_set_material(cut.get_surface_count() - 1, mat.duplicate())
	_caps_from_planes(planes, cap_v, cap_n, cap_i)

func _clip_poly(poly: Array, plane: Dictionary) -> Array:
	var out: Array = []
	var point: Vector3 = plane["point"]
	var normal: Vector3 = plane["normal"]
	var hits: Array[Vector3] = []
	var n := poly.size()
	for i in n:
		var cur: Array = poly[i]
		var prev: Array = poly[(i + n - 1) % n]
		var dc: float = normal.dot(cur[0] - point)
		var dp: float = normal.dot(prev[0] - point)
		var cin := dc >= -0.00001
		var pin := dp >= -0.00001
		if cin != pin:
			var denom := dp - dc
			var t := 0.0 if absf(denom) < 0.0000001 else clampf(dp / denom, 0.0, 1.0)
			var hit: Array = _lerp_rec(prev, cur, t)
			out.append(hit)
			hits.append(hit[0])
		if cin:
			out.append(cur)
	if hits.size() >= 2:
		plane["edges"].append([hits[0], hits[hits.size() - 1]])
	return out

func _lerp_rec(a: Array, b: Array, t: float) -> Array:
	var nrm: Vector3 = (a[1] as Vector3).lerp(b[1], t)
	if nrm.length_squared() < 0.000001:
		nrm = Vector3.UP
	else:
		nrm = nrm.normalized()
	return [(a[0] as Vector3).lerp(b[0], t), nrm, (a[2] as Vector2).lerp(b[2], t)]

func _caps_from_planes(planes: Array, cap_v: PackedVector3Array, cap_n: PackedVector3Array, cap_i: PackedInt32Array) -> void:
	for plane in planes:
		if not bool(plane.get("cap", true)):
			plane["edges"] = []
			continue
		var edges: Array = plane["edges"]
		plane["edges"] = []
		if edges.is_empty():
			continue
		var outward: Vector3 = plane["out"]
		var eps := 0.004
		var used: Array = []
		used.resize(edges.size())
		for i in edges.size():
			used[i] = false
		for start in edges.size():
			if used[start]:
				continue
			used[start] = true
			var loop: Array[Vector3] = [edges[start][0]]
			var tip: Vector3 = edges[start][1]
			var guard := 0
			while tip.distance_to(loop[0]) > eps and guard < edges.size():
				guard += 1
				var found := false
				for j in edges.size():
					if used[j]:
						continue
					if tip.distance_to(edges[j][0]) <= eps:
						used[j] = true
						loop.append(tip)
						tip = edges[j][1]
						found = true
						break
					elif tip.distance_to(edges[j][1]) <= eps:
						used[j] = true
						loop.append(tip)
						tip = edges[j][0]
						found = true
						break
				if not found:
					break
			if loop.size() < 3:
				continue
			var acc := Vector3.ZERO
			for p in loop:
				acc += p
			var mid := acc / float(loop.size())
			var base := cap_v.size()
			cap_v.append(mid)
			cap_n.append(outward)
			for p in loop:
				cap_v.append(p)
				cap_n.append(outward)
			for k in loop.size():
				cap_i.append(base)
				cap_i.append(base + 1 + k)
				cap_i.append(base + 1 + ((k + 1) % loop.size()))

func _calc_aabb(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			var mi := n as MeshInstance3D
			var a := mi.get_aabb()
			for i in 8:
				var p := a.get_endpoint(i)
				if first:
					box = AABB(p, Vector3.ZERO)
					first = false
				else:
					box = box.expand(p)
	return box

static func _ensure_kit() -> void:
	if _ready_kit:
		return
	
	_trunk = CylinderMesh.new()
	_trunk.top_radius = 0.72
	_trunk.bottom_radius = 1.0
	_trunk.height = 1.0
	_trunk.radial_segments = 8
	
	_stem = CylinderMesh.new()
	_stem.top_radius = 0.65
	_stem.bottom_radius = 1.0
	_stem.height = 1.0
	_stem.radial_segments = 6
	
	_ball = SphereMesh.new()
	_ball.radius = 1.0
	_ball.height = 2.0
	_ball.radial_segments = 12
	_ball.rings = 8
	
	_cobble = SphereMesh.new()
	_cobble.radius = 1.0
	_cobble.height = 2.0
	_cobble.radial_segments = 10
	_cobble.rings = 6
	
	_box = BoxMesh.new()
	_box.size = Vector3.ONE
	
	_cone = CylinderMesh.new()
	_cone.top_radius = 0.12
	_cone.bottom_radius = 1.0
	_cone.height = 1.0
	_cone.radial_segments = 7
	
	_soil = _annulus()
	_water = _pool()
	_tuft = _build_grass_tuft(36, 0.58, 0.62, 1.12, Color("355e2c"), Color("8bb85a"))
	_tuft_dry = _build_grass_tuft(16, 0.42, 0.42, 0.78, Color("7a5a22"), Color("d7b45c"))
	_tuft_card = _build_grass_card()
	
	_bark = _paint(Color("5c3826"), 0.88)
	_leaf = _paint(Color("2e7a36"), 0.82)
	_leaf_deep = _paint(Color("1e5628"), 0.86)
	_leaf_light = _paint(Color("3d8544"), 0.80)
	_bush_mat = _paint(Color("285c2c"), 0.84)
	_rock = _paint(Color("78716c"), 0.92)
	_rock_dark = _paint(Color("57534e"), 0.94)
	_rock_pale = _paint(Color("a8a29e"), 0.93)
	_rock_moss = _paint(Color("6b7a5c"), 0.90)
	_grass_deep = _paint(Color("2f5e2c"), 0.90)
	_vein = _paint(Color("fbbf24"), 0.35, 0.75)
	_straw = _paint(Color("eab308"), 0.85)
	_head = _paint(Color("fef08a"), 0.78)
	_bale = _paint(Color("d97706"), 0.88)
	_band = _paint(Color("78350f"), 0.80)
	_clay = _paint(Color("b85a36"), 0.90)
	_brick = _paint(Color("942b1a"), 0.80)
	_grass = _paint(Color("488238"), 0.88)
	_blade_mat = _paint(Color("4a7a38"), 0.86)
	_blade_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blade_mat.vertex_color_use_as_albedo = true
	_blade_dry = _paint(Color("c9a04a"), 0.88)
	_blade_dry.cull_mode = BaseMaterial3D.CULL_DISABLED
	_blade_dry.vertex_color_use_as_albedo = true
	_card_mat = StandardMaterial3D.new()
	_card_mat.albedo_color = Color.WHITE
	var grass_tex: Texture2D = null
	if ResourceLoader.exists("res://art/pasto_mata.png"):
		grass_tex = load("res://art/pasto_mata.png") as Texture2D
	if grass_tex != null:
		_card_mat.albedo_texture = grass_tex
	_card_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_card_mat.alpha_scissor_threshold = 0.34
	_card_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_card_mat.roughness = 0.92
	_card_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_petal_gold = _paint(Color("fbc02d"), 0.70)
	_petal_cream = _paint(Color("fffbeb"), 0.65)
	_petal_rose = _paint(Color("e11d48"), 0.70)
	_wool = _paint(Color("f6f4ee"), 0.96)
	_sheep_dark = _paint(Color("2e2722"), 0.85)
	_soil_wood = _paint(Color("2d3b24"), 0.96)
	_soil_grain = _paint(Color("ad8346"), 0.95)
	_soil_stone = _paint(Color("524e49"), 0.96)
	_soil_clay = _paint(Color("8c3823"), 0.94)
	_soil_meadow = _paint(Color("3f6e2d"), 0.95)
	_sand = _paint(Color("d6be90"), 0.94)
	
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.18, 0.62, 0.64, 0.28)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.roughness = 0.08
	_water_mat.metallic = 0.06
	_water_mat.clearcoat_enabled = true
	_water_mat.clearcoat = 0.7
	_water_mat.clearcoat_roughness = 0.1
	_water_mat.rim_enabled = true
	_water_mat.rim = 0.22
	_water_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	
	_ready_kit = true

static func _paint(color: Color, rough: float, metal: float = 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metal
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	return mat

static func _build_grass_tuft(blade_count: int, spread: float, h_min: float, h_max: float, c_base: Color, c_tip: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in blade_count:
		var yaw := TAU * float(i) / float(blade_count) + float((i * 13) % 7) * 0.09
		var radial := spread * (0.12 + float(i % 5) * 0.11)
		var h := lerpf(h_min, h_max, float((i * 3) % 11) / 10.0)
		var lean := 0.10 + float(i % 6) * 0.05
		var w := 0.042 + float(i % 4) * 0.014
		var side := Vector3(-sin(yaw), 0.0, cos(yaw))
		var outward := Vector3(cos(yaw), 0.0, sin(yaw))
		var b0 := outward * radial - side * w
		var b1 := outward * radial + side * w
		var tip := outward * (radial + sin(lean) * h) + Vector3(0.0, h, 0.0)
		var t0 := tip - side * (w * 0.16)
		var t1 := tip + side * (w * 0.16)
		var nrm := (b1 - b0).cross(t0 - b0)
		if nrm.length_squared() < 0.000001:
			nrm = Vector3.UP
		else:
			nrm = nrm.normalized()
		_tuft_tri(st, b0, b1, t1, nrm, c_base, c_base, c_tip)
		_tuft_tri(st, b0, t1, t0, nrm, c_base, c_tip, c_tip)
	return st.commit()

static func _tuft_tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_normal(nrm)
	st.set_color(ca)
	st.add_vertex(a)
	st.set_normal(nrm)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_normal(nrm)
	st.set_color(cc)
	st.add_vertex(c)

static func _build_grass_card() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := 0.56
	_card_quad(st, Vector3(-hw, 0.0, 0.0), Vector3(hw, 0.0, 0.0), Vector3(hw, 1.0, 0.0), Vector3(-hw, 1.0, 0.0), Vector3(0.0, 0.0, 1.0))
	_card_quad(st, Vector3(0.0, 0.0, -hw), Vector3(0.0, 0.0, hw), Vector3(0.0, 1.0, hw), Vector3(0.0, 1.0, -hw), Vector3(1.0, 0.0, 0.0))
	return st.commit()

static func _card_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3) -> void:
	st.set_normal(nrm)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(a)
	st.set_normal(nrm)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(b)
	st.set_normal(nrm)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(c)
	st.set_normal(nrm)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(a)
	st.set_normal(nrm)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(c)
	st.set_normal(nrm)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(d)

func _add_soil(mat: Material) -> void:
	var soil := MeshInstance3D.new()
	soil.name = "Soil"
	soil.mesh = _soil
	soil.material_override = mat
	soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(soil)

# -----------------------------------------------------------------------------
# BOSQUE:
# - Agrupá árboles de diferentes tamaños en conjuntos naturales (2 arboledas orgánicas).
# - Alterná espacios abiertos con zonas de vegetación (claro forestal despejado).
# - Incorporá arbustos, pasto y piedras pequeñas como detalles secundarios.
# - Evitá árboles perfectamente alineados, copias idénticas y ramas fuera del hexágono.
# -----------------------------------------------------------------------------
func _forest(q: int, r: int) -> void:
	var heft := _heft(q, r)
	var base_ang := _spin(q, r)
	
	var trunks: Array[Transform3D] = []
	var crowns: Array[Transform3D] = []
	var crowns_deep: Array[Transform3D] = []
	var crowns_light: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	var cobbles: Array[Transform3D] = []
	var roots: Array[Transform3D] = []
	
	# Arboleda 1 (Principal): 4 árboles de porte variado agrupados armónicamente
	var c1_ang := base_ang
	var trees_c1 := [
		# [radio_centro, ang_offset, altura, radio_corona, tipo: 0=pino_alto, 1=roble, 2=pino_medio, 3=joven]
		[36.0, 0.0, 26.0, 7.5, 0],
		[29.0, 0.22, 18.0, 6.5, 1],
		[43.0, -0.20, 20.0, 5.5, 2],
		[27.0, 0.36, 12.0, 3.8, 3],
	]
	
	for t in trees_c1:
		var rad: float = float(t[0])
		var ang: float = c1_ang + float(t[1])
		var h: float = float(t[2]) * heft
		var cr: float = float(t[3]) * heft
		var kind: int = int(t[4])
		var p := Vector2(cos(ang), sin(ang)) * rad
		var y0 := _ground(p.length())
		var yaw := ang + _u(q, r, 20 + kind) * 0.8
		var lean := (_u(q, r, 25 + kind) - 0.5) * 0.12
		
		# Tronco con apoyo convincente en el suelo
		var tr_r := cr * 0.24
		trunks.append(_xf(p, Vector3(tr_r, h, tr_r), yaw, lean, y0 + h * 0.5))
		
		# Corona según tipo botánico artesanal
		match kind:
			0: # Pino conífero alto de 3 niveles escalonados
				crowns_deep.append(_xf(p, Vector3(cr, cr * 0.85, cr), yaw, 0.0, y0 + h * 0.55))
				crowns.append(_xf(p, Vector3(cr * 0.72, cr * 0.75, cr * 0.72), yaw + 0.4, 0.0, y0 + h * 0.75))
				crowns.append(_xf(p, Vector3(cr * 0.45, cr * 0.65, cr * 0.45), yaw + 0.8, 0.0, y0 + h * 0.95))
			1: # Roble de fronda ancha estratificada
				crowns_light.append(_xf(p, Vector3(cr, cr * 0.75, cr), yaw, 0.0, y0 + h * 0.85))
				var off := Vector2(cos(yaw), sin(yaw)) * (cr * 0.3)
				crowns.append(_xf(p + off, Vector3(cr * 0.65, cr * 0.55, cr * 0.65), yaw + 0.5, 0.0, y0 + h * 0.72))
			2: # Pino mediano de 2 niveles
				crowns_deep.append(_xf(p, Vector3(cr, cr * 0.8, cr), yaw, 0.0, y0 + h * 0.62))
				crowns.append(_xf(p, Vector3(cr * 0.65, cr * 0.7, cr * 0.65), yaw + 0.5, 0.0, y0 + h * 0.88))
			3: # Arbolito joven de sotobosque
				crowns.append(_xf(p, Vector3(cr, cr * 0.9, cr), yaw, 0.0, y0 + h * 0.82))
	
	# Raíces expuestas saliendo de la arboleda principal
	var p_main := Vector2(cos(c1_ang), sin(c1_ang)) * 34.0
	roots.append(_prone(p_main, c1_ang + 0.6, 1.1, 7.5 * heft, _ground(p_main.length()) + 0.5))
	roots.append(_prone(p_main, c1_ang - 0.7, 0.9, 6.0 * heft, _ground(p_main.length()) + 0.45))
	
	# Arboleda 2 (Secundaria): conjunto menor separado por un claro amplio
	var c2_ang := base_ang + 2.45
	var trees_c2 := [
		[35.0, 0.0, 19.0, 5.8, 2],
		[42.0, 0.24, 13.5, 4.8, 1],
	]
	for t in trees_c2:
		var rad: float = float(t[0])
		var ang: float = c2_ang + float(t[1])
		var h: float = float(t[2]) * heft
		var cr: float = float(t[3]) * heft
		var kind: int = int(t[4])
		var p := Vector2(cos(ang), sin(ang)) * rad
		var y0 := _ground(p.length())
		var yaw := ang + _u(q, r, 30 + kind)
		var tr_r := cr * 0.23
		trunks.append(_xf(p, Vector3(tr_r, h, tr_r), yaw, 0.04, y0 + h * 0.5))
		if kind == 2:
			crowns_deep.append(_xf(p, Vector3(cr, cr * 0.8, cr), yaw, 0.0, y0 + h * 0.65))
			crowns.append(_xf(p, Vector3(cr * 0.62, cr * 0.68, cr * 0.62), yaw + 0.4, 0.0, y0 + h * 0.88))
		else:
			crowns_light.append(_xf(p, Vector3(cr, cr * 0.75, cr), yaw, 0.0, y0 + h * 0.82))
	
	# Arbustos de sotobosque y piedras musgosas en la base y márgenes
	for i in 4:
		var ang := c1_ang + (float(i) - 1.5) * 0.35
		var rad := 27.0 + _u(q, r, 40 + i) * 16.0
		var p := Vector2(cos(ang), sin(ang)) * rad
		var s := (2.8 + _u(q, r, 50 + i) * 1.5) * heft
		bushes.append(_xf(p, Vector3(s, s * 0.55, s), _u(q, r, 60 + i) * TAU, 0.0, _ground(p.length()) + s * 0.22))
	
	for i in 5:
		var ang := base_ang + float(i) * 1.25 + _u(q, r, 70 + i) * 0.4
		var rad := clampf(24.0 + _u(q, r, 80 + i) * 22.0, 22.0, 48.0)
		var p := Vector2(cos(ang), sin(ang)) * rad
		var s := 1.4 + _u(q, r, 90 + i) * 1.3
		cobbles.append(_xf(p, Vector3(s * 1.2, s * 0.7, s), _u(q, r, 100 + i) * TAU, 0.0, _ground(p.length()) + s * 0.28))
	
	_scatter("Trunks", _trunk, _bark, trunks, true)
	_scatter("Crowns", _ball, _leaf, crowns, true)
	_scatter("CrownsDeep", _ball, _leaf_deep, crowns_deep, true)
	_scatter("CrownsLight", _ball, _leaf_light, crowns_light, true)
	_scatter("Roots", _trunk, _bark, roots, false)
	_scatter("Bushes", _ball, _bush_mat, bushes, false)
	_scatter("Cobbles", _cobble, _rock, cobbles, false)

# -----------------------------------------------------------------------------
# PRADERA Y OVEJAS:
# - Distribuí las ovejas en pequeños grupos irregulares (rebaño y pareja).
# - Orientá sus cuerpos de forma coherente con el terreno.
# - Dejá espacio visible entre ellas.
# - Evitá que se superpongan, floten o queden ocultas por otros objetos.
# -----------------------------------------------------------------------------
func _meadow(q: int, r: int) -> void:
	var base_ang := _spin(q, r)
	
	# Grupo 1 (Rebaño familiar de 3 ovejas) en un sector abierto
	var g1_ang := base_ang
	var p1 := Vector2(cos(g1_ang), sin(g1_ang)) * 34.0
	var o1 := _build_sheep(q, r, p1, g1_ang + 1.2, 1.0, true) # comiendo pasto
	add_child(o1)
	
	var p2 := Vector2(cos(g1_ang + 0.38), sin(g1_ang + 0.38)) * 42.0 # distancia ~12.5 unidades
	var o2 := _build_sheep(q, r, p2, g1_ang - 0.4, 1.08, false) # atenta mirando el valle
	add_child(o2)
	
	var p3 := Vector2(cos(g1_ang - 0.32), sin(g1_ang - 0.32)) * 38.0 # distancia ~11.0 unidades
	var o3 := _build_sheep(q, r, p3, g1_ang + 0.8, 0.82, true) # corderito
	add_child(o3)
	
	# Grupo 2 (Pareja pastando en el otro flanco)
	var g2_ang := base_ang + 2.6
	var p4 := Vector2(cos(g2_ang), sin(g2_ang)) * 36.0
	var o4 := _build_sheep(q, r, p4, g2_ang + 1.4, 1.02, true)
	add_child(o4)
	
	var p5 := Vector2(cos(g2_ang + 0.34), sin(g2_ang + 0.34)) * 42.0 # distancia ~11.5 unidades
	var o5 := _build_sheep(q, r, p5, g2_ang + 2.7, 0.94, false)
	add_child(o5)
	
	# Entorno de pastura: briznas de hierba, flores silvestres y cantos rodados de campo
	var blades: Array[Transform3D] = []
	var stems: Array[Transform3D] = []
	var golds: Array[Transform3D] = []
	var creams: Array[Transform3D] = []
	var roses: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var bushes: Array[Transform3D] = []
	
	for i in 14:
		var ang := base_ang + float(i) * (TAU / 14.0) + _u(q, r, 120 + i) * 0.3
		var rad := clampf(24.0 + _u(q, r, 130 + i) * 22.0, 22.0, 48.0)
		var p := Vector2(cos(ang), sin(ang)) * rad
		var h := 2.6 + _u(q, r, 140 + i) * 1.8
		var lean := (_u(q, r, 150 + i) - 0.3) * 0.25
		blades.append(_xf(p, Vector3(0.38, h, 0.95), _u(q, r, 160 + i) * TAU, lean, _ground(p.length()) + h * 0.42))
	
	for i in 7:
		var ang := base_ang + 1.2 + float(i) * 0.5 + _u(q, r, 170 + i) * 0.2
		var rad := clampf(28.0 + _u(q, r, 180 + i) * 18.0, 24.0, 46.0)
		var p := Vector2(cos(ang), sin(ang)) * rad
		var h := 3.0
		var yaw := _u(q, r, 190 + i) * TAU
		stems.append(_xf(p, Vector3(0.16, h, 0.16), yaw, 0.08, _ground(p.length()) + h * 0.5))
		var fl := _xf(p, Vector3(0.75, 0.55, 0.75), yaw, 0.0, _ground(p.length()) + h + 0.32)
		if i % 3 == 0:
			golds.append(fl)
		elif i % 3 == 1:
			creams.append(fl)
		else:
			roses.append(fl)
	
	for i in 3:
		var ang := base_ang + 1.6 + float(i) * 1.8
		var p := Vector2(cos(ang), sin(ang)) * 43.0
		var s := 1.4 + _u(q, r, 200 + i) * 0.8
		stones.append(_xf(p, Vector3(s * 1.2, s * 0.7, s), _u(q, r, 210 + i) * TAU, 0.0, _ground(p.length()) + s * 0.25))
	
	for i in 2:
		var ang := base_ang + 1.4 + float(i) * 2.2
		var p := Vector2(cos(ang), sin(ang)) * 44.0
		var s := 2.6 + _u(q, r, 220 + i) * 0.8
		bushes.append(_xf(p, Vector3(s, s * 0.58, s), _u(q, r, 230 + i) * TAU, 0.0, _ground(p.length()) + s * 0.22))
	
	# Valla rústica de pastizal delimitando el borde del prado
	var fence_ang := base_ang - 1.85
	var fence_yaw := fence_ang + 0.5
	var fence_tan := Vector2(-sin(fence_yaw), cos(fence_yaw))
	var fence_p := Vector2(cos(fence_ang), sin(fence_ang)) * 43.0
	for fi in 3:
		var post_p: Vector2 = fence_p + fence_tan * (float(fi - 1) * 6.0)
		var yf := _ground(post_p.length())
		stems.append(_xf(post_p, Vector3(0.55, 4.4, 0.55), fence_yaw, 0.0, yf + 2.2))
	for ri in 2:
		var ry := 1.6 + float(ri) * 1.5
		var yf_mid := _ground(fence_p.length())
		stems.append(_xf(fence_p, Vector3(0.35, 0.4, 13.5), fence_yaw, 0.0, yf_mid + ry))
	
	_scatter("Grass", _box, _grass, blades, false)
	_scatter("FlowerStems", _stem, _grass, stems, false)
	_scatter("GoldFlowers", _ball, _petal_gold, golds, false)
	_scatter("CreamFlowers", _ball, _petal_cream, creams, false)
	_scatter("RoseFlowers", _ball, _petal_rose, roses, false)
	_scatter("PastureStones", _cobble, _rock, stones, false)
	_scatter("PastureBushes", _ball, _bush_mat, bushes, false)

func _build_sheep(_q: int, _r: int, p: Vector2, yaw: float, scale_mult: float, grazing: bool) -> Node3D:
	var sheep := Node3D.new()
	sheep.name = "Sheep"
	var y0 := _ground(p.length())
	sheep.position = Vector3(p.x, y0, p.y)
	sheep.rotation.y = yaw
	
	var root := Node3D.new()
	root.name = "SheepMesh"
	root.scale = Vector3.ONE * scale_mult
	sheep.add_child(root)
	
	# Cuerpo de lana (elipsoide acogedor)
	var body := MeshInstance3D.new()
	body.mesh = _ball
	body.material_override = _wool
	body.scale = Vector3(1.7, 1.35, 2.2)
	body.position = Vector3(0.0, 2.3, 0.0)
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(body)
	
	# Cabeza de madera oscura
	var head := MeshInstance3D.new()
	head.mesh = _ball
	head.material_override = _sheep_dark
	head.scale = Vector3(0.85, 0.85, 1.1)
	if grazing:
		head.position = Vector3(0.0, 1.3, 2.0)
		head.rotation.x = deg_to_rad(28.0)
	else:
		head.position = Vector3(0.0, 2.6, 2.0)
		head.rotation.x = deg_to_rad(-8.0)
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(head)
	
	# Orejitas
	for side: float in [-0.75, 0.75]:
		var ear := MeshInstance3D.new()
		ear.mesh = _ball
		ear.material_override = _sheep_dark
		ear.scale = Vector3(0.35, 0.22, 0.5)
		ear.position = head.position + Vector3(side, 0.35, -0.2)
		ear.rotation.z = deg_to_rad(side * -25.0)
		ear.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(ear)
	
	# 4 patas de clavija bien apoyadas en el suelo (Y=0 relativo a y0)
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.22
	leg_mesh.bottom_radius = 0.26
	leg_mesh.height = 1.4
	leg_mesh.radial_segments = 6
	
	var leg_positions := [
		Vector3(-0.85, 0.7, 1.1),
		Vector3(0.85, 0.7, 1.1),
		Vector3(-0.85, 0.7, -1.1),
		Vector3(0.85, 0.7, -1.1),
	]
	for lpos in leg_positions:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		leg.material_override = _sheep_dark
		leg.position = lpos
		leg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		root.add_child(leg)
	
	# Colita de lana
	var tail := MeshInstance3D.new()
	tail.mesh = _ball
	tail.material_override = _wool
	tail.scale = Vector3(0.4, 0.4, 0.45)
	tail.position = Vector3(0.0, 2.3, -2.15)
	tail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	root.add_child(tail)
	
	return sheep

# -----------------------------------------------------------------------------
# MONTAÑA Y PIEDRAS:
# - Creá agrupaciones rocosas con tamaños variados (2 macizos escalonados).
# - Mantené una silueta reconocible, sin llenar toda la superficie de piedras.
# - Evitá que las rocas atraviesen la base o tapen el espacio central.
# -----------------------------------------------------------------------------
func _mountain(q: int, r: int) -> void:
	var heft := _heft(q, r)
	var base_ang := _spin(q, r)
	
	var slabs: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var veins: Array[Transform3D] = []
	var scrub: Array[Transform3D] = []
	
	# Macizo 1 (Cumbre principal): 4 bloques escalonados en estratos geológicos
	var m1_ang := base_ang
	var p1 := Vector2(cos(m1_ang), sin(m1_ang)) * 36.0
	var y1 := _ground(p1.length())
	var yaw1 := m1_ang + 0.3
	
	var s1_base := Vector3(15.0, 3.6, 10.5) * heft
	slabs.append(_xf(p1, s1_base, yaw1, 0.0, y1 + s1_base.y * 0.5))
	
	var s1_mid := Vector3(11.5, 3.2, 8.0) * heft
	var p1_mid := p1 + Vector2(cos(yaw1), sin(yaw1)) * 1.2
	var y1_mid := y1 + s1_base.y + s1_mid.y * 0.5 - 0.2
	slabs.append(_xf(p1_mid, s1_mid, yaw1 + 0.15, 0.0, y1_mid))
	
	var s1_peak := Vector3(7.5, 3.0, 5.5) * heft
	var p1_peak := p1_mid + Vector2(cos(yaw1 + 0.4), sin(yaw1 + 0.4)) * 1.8
	var y1_peak := y1_mid + s1_mid.y * 0.5 + s1_peak.y * 0.5 - 0.2
	slabs.append(_xf(p1_peak, s1_peak, yaw1 + 0.32, 0.0, y1_peak))
	
	var s1_crag := Vector3(4.5, 2.4, 3.6) * heft
	var y1_crag := y1_peak + s1_peak.y * 0.5 + s1_crag.y * 0.5 - 0.15
	slabs.append(_xf(p1_peak, s1_crag, yaw1 + 0.55, 0.0, y1_crag))
	
	# Veta de mineral dorada incrustada en una hendidura de la roca media
	veins.append(_xf(p1_mid, Vector3(1.6, 0.85, 6.2) * heft, yaw1 + 0.6, 0.18, y1_mid + 0.4))
	
	# Macizo 2 (Cresta secundaria): 2 bloques menores en el flanco opuesto
	var m2_ang := base_ang + 2.4
	var p2 := Vector2(cos(m2_ang), sin(m2_ang)) * 38.0
	var y2 := _ground(p2.length())
	var yaw2 := m2_ang + 0.45
	
	var s2_base := Vector3(11.5, 3.2, 7.5) * heft
	slabs.append(_xf(p2, s2_base, yaw2, 0.0, y2 + s2_base.y * 0.5))
	
	var s2_top := Vector3(7.0, 2.6, 4.8) * heft
	var y2_top := y2 + s2_base.y + s2_top.y * 0.5 - 0.2
	slabs.append(_xf(p2 + Vector2(cos(yaw2), sin(yaw2)) * 1.0, s2_top, yaw2 + 0.2, 0.0, y2_top))
	
	# Pedregal / Talud de cantos rodados caídos al pie de los riscos
	for i in 7:
		var ang := base_ang + float(i) * 0.85 + _u(q, r, 240 + i) * 0.3
		var rad := clampf(27.0 + _u(q, r, 250 + i) * 19.0, 23.0, 47.0)
		var p := Vector2(cos(ang), sin(ang)) * rad
		var s := (1.4 + _u(q, r, 260 + i) * 1.4) * heft
		stones.append(_xf(p, Vector3(s * 1.25, s * 0.72, s), _u(q, r, 270 + i) * TAU, 0.0, _ground(p.length()) + s * 0.28))
	
	# Arbustos alpinos que crecen en las grietas
	for i in 2:
		var p := (p1 if i == 0 else p2) + Vector2(cos(base_ang + float(i) * 2.0), sin(base_ang + float(i) * 2.0)) * 6.5
		var s := 2.2 * heft
		scrub.append(_xf(p, Vector3(s, s * 0.5, s), _u(q, r, 280 + i) * TAU, 0.0, _ground(p.length()) + s * 0.2))
	
	_scatter("Slabs", _box, _rock_dark, slabs, true)
	_scatter("Cobbles", _cobble, _rock, stones, false)
	_scatter("Veins", _box, _vein, veins, false)
	_scatter("AlpineScrub", _ball, _bush_mat, scrub, false)

# -----------------------------------------------------------------------------
# TRIGO:
# - Organizá las espigas en parcelas o grupos visualmente coherentes.
# - Alterná alturas y densidades (hileras onduladas con viento).
# - Ubicá los fardos de paja en zonas secundarias, sin bloquear el centro ni los bordes.
# -----------------------------------------------------------------------------
func _field(q: int, r: int) -> void:
	var base_ang := _spin(q, r)
	var stems: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	var bales: Array[Transform3D] = []
	var bands: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	
	# Parcela 1: Arco de cultivo denso con 3 hileras ordenadas
	var plot_ang := base_ang
	# Hilera interior (R ~ 29.0)
	for i in 6:
		var ang := plot_ang - 0.95 + float(i) * (1.9 / 5.0)
		var p := Vector2(cos(ang), sin(ang)) * 29.0
		var h := 7.0 + _u(q, r, 300 + i) * 1.5
		_stalk(stems, heads, q, r, p, h, 0.48, 310 + i)
	
	# Hilera central de espigas altas y maduras (R ~ 36.0)
	for i in 8:
		var ang := plot_ang - 1.05 + float(i) * (2.1 / 7.0)
		var p := Vector2(cos(ang), sin(ang)) * 36.0
		var h := 8.8 + _u(q, r, 320 + i) * 2.0
		_stalk(stems, heads, q, r, p, h, 0.54, 330 + i)
	
	# Hilera exterior (R ~ 43.0)
	for i in 6:
		var ang := plot_ang - 0.95 + float(i) * (1.9 / 5.0)
		var p := Vector2(cos(ang), sin(ang)) * 43.0
		var h := 7.5 + _u(q, r, 340 + i) * 1.6
		_stalk(stems, heads, q, r, p, h, 0.50, 350 + i)
	
	# Parcela 2: Pequeña parcela cosechada / rastrojo más bajo
	for i in 6:
		var ang := plot_ang + 1.8 + float(i) * 0.16
		var p := Vector2(cos(ang), sin(ang)) * (33.0 + float(i % 2) * 6.0)
		var h := 4.2 + _u(q, r, 360 + i) * 1.6
		_stalk(stems, heads, q, r, p, h, 0.42, 370 + i)
	
	# Fardos de paja en zona secundaria (área limpia de carga, fuera del centro y bordes)
	var bale_ang := base_ang - 2.2
	var p_bale := Vector2(cos(bale_ang), sin(bale_ang)) * 39.0
	var bale_yaw := bale_ang + 0.4
	var tangent := Vector2(-sin(bale_yaw), cos(bale_yaw))
	
	var sz_bale := Vector3(7.4, 3.6, 4.4)
	# Fardo 1 en el suelo
	var b1_pos := p_bale - tangent * 3.8
	var y1 := _ground(b1_pos.length())
	bales.append(_xf(b1_pos, sz_bale, bale_yaw + 0.08, 0.0, y1 + sz_bale.y * 0.5))
	bands.append(_xf(b1_pos, Vector3(sz_bale.x + 0.25, 0.55, sz_bale.z + 0.25), bale_yaw + 0.08, 0.0, y1 + sz_bale.y * 0.55))
	
	# Fardo 2 en el suelo paralelo
	var b2_pos := p_bale + tangent * 3.8
	var y2 := _ground(b2_pos.length())
	bales.append(_xf(b2_pos, sz_bale, bale_yaw - 0.06, 0.0, y2 + sz_bale.y * 0.5))
	bands.append(_xf(b2_pos, Vector3(sz_bale.x + 0.25, 0.55, sz_bale.z + 0.25), bale_yaw - 0.06, 0.0, y2 + sz_bale.y * 0.55))
	
	# Fardo 3 apilado naturalmente sobre la unión de los dos inferiores
	var b3_pos := p_bale + Vector2(cos(bale_ang), sin(bale_ang)) * 0.4
	var y3 := maxf(y1, y2) + sz_bale.y
	var sz_top := Vector3(7.0, 3.4, 4.2)
	bales.append(_xf(b3_pos, sz_top, bale_yaw + 0.02, 0.0, y3 + sz_top.y * 0.5))
	bands.append(_xf(b3_pos, Vector3(sz_top.x + 0.25, 0.55, sz_top.z + 0.25), bale_yaw + 0.02, 0.0, y3 + sz_top.y * 0.55))
	
	# Detalle secundario: piedras al borde del cultivo
	for i in 2:
		var ang := plot_ang + 1.2 + float(i) * 0.7
		var p := Vector2(cos(ang), sin(ang)) * 44.0
		var s := 1.5 + _u(q, r, 380 + i) * 0.8
		stones.append(_xf(p, Vector3(s * 1.2, s * 0.7, s), _u(q, r, 390 + i) * TAU, 0.0, _ground(p.length()) + s * 0.25))
	
	_scatter("WheatStalks", _stem, _straw, stems, false)
	_scatter("WheatHeads", _cone, _head, heads, false)
	_scatter("HayBales", _box, _bale, bales, true)
	_scatter("BaleBands", _box, _band, bands, false)
	_scatter("FieldStones", _cobble, _rock, stones, false)

# -----------------------------------------------------------------------------
# ARCILLA:
# - Usá tierra rojiza como base visual.
# - Agrupá ladrillos y bloques de arcilla como si fueran parte de una cantera.
# - Evitá bloques flotantes, alineaciones artificiales o acumulaciones excesivas.
# -----------------------------------------------------------------------------
func _clay_pit(q: int, r: int) -> void:
	var base_ang := _spin(q, r)
	var blocks: Array[Transform3D] = []
	var bricks: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var skids: Array[Transform3D] = []
	
	# Frente de cantera: 2 bancos de extracción de arcilla tallados en la ladera
	var pit_ang := base_ang
	var p_bench1 := Vector2(cos(pit_ang), sin(pit_ang)) * 38.0
	var y_bench1 := _ground(p_bench1.length())
	var yaw_bench := pit_ang + 0.25
	
	var sz_bench1 := Vector3(14.0, 3.4, 8.0)
	blocks.append(_xf(p_bench1, sz_bench1, yaw_bench, 0.0, y_bench1 + sz_bench1.y * 0.5))
	
	var p_bench2 := p_bench1 + Vector2(cos(yaw_bench + 0.3), sin(yaw_bench + 0.3)) * 6.5
	var y_bench2 := _ground(p_bench2.length())
	var sz_bench2 := Vector3(10.0, 2.6, 6.0)
	blocks.append(_xf(p_bench2, sz_bench2, yaw_bench + 0.15, 0.0, y_bench2 + sz_bench2.y * 0.5))
	
	# Bloques crudos de arcilla extraídos, apoyados naturalmente en la solera
	var cut_sizes := [Vector3(5.4, 2.8, 3.8), Vector3(4.8, 2.6, 3.4), Vector3(4.2, 2.4, 3.0)]
	for i in 3:
		var ang := pit_ang - 0.25 + float(i) * 0.22
		var rad := 31.0 + float(i % 2) * 3.0
		var p := Vector2(cos(ang), sin(ang)) * rad
		var sz: Vector3 = cut_sizes[i]
		blocks.append(_xf(p, sz, base_ang + float(i) * 0.85, 0.0, _ground(p.length()) + sz.y * 0.5))
	
	# Pila artesanal de ladrillos horneados en el patio de curado
	var stack_ang := base_ang + 2.5
	var p_stack := Vector2(cos(stack_ang), sin(stack_ang)) * 37.0
	var stack_yaw := stack_ang + 0.4
	var y_stack := _ground(p_stack.length())
	var right := Vector2(-sin(stack_yaw), cos(stack_yaw))
	var forward := Vector2(cos(stack_yaw), sin(stack_yaw))
	
	# Maderos guía en el suelo
	for side: float in [-1.6, 1.6]:
		var sp: Vector2 = p_stack + right * side
		skids.append(_xf(sp, Vector3(5.2, 0.35, 0.75), stack_yaw, 0.0, y_stack + 0.18))
	
	# 4 hiladas de ladrillos trabados (aparejo alternado realista)
	var sz_brick := Vector3(4.8, 1.15, 2.15)
	var y_cur := y_stack + 0.35
	
	# Hilada 1 (longitudinal)
	bricks.append(_xf(p_stack - right * 1.15, sz_brick, stack_yaw, 0.0, y_cur + sz_brick.y * 0.5))
	bricks.append(_xf(p_stack + right * 1.15, sz_brick, stack_yaw, 0.0, y_cur + sz_brick.y * 0.5))
	y_cur += sz_brick.y
	
	# Hilada 2 (transversal cruzada)
	bricks.append(_xf(p_stack - forward * 1.15, sz_brick, stack_yaw + PI * 0.5, 0.0, y_cur + sz_brick.y * 0.5))
	bricks.append(_xf(p_stack + forward * 1.15, sz_brick, stack_yaw + PI * 0.5, 0.0, y_cur + sz_brick.y * 0.5))
	y_cur += sz_brick.y
	
	# Hilada 3 (longitudinal)
	bricks.append(_xf(p_stack - right * 1.15, sz_brick, stack_yaw + 0.04, 0.0, y_cur + sz_brick.y * 0.5))
	bricks.append(_xf(p_stack + right * 1.15, sz_brick, stack_yaw + 0.04, 0.0, y_cur + sz_brick.y * 0.5))
	y_cur += sz_brick.y
	
	# Hilada 4 (remate centrado)
	bricks.append(_xf(p_stack, sz_brick, stack_yaw + PI * 0.5 - 0.02, 0.0, y_cur + sz_brick.y * 0.5))
	
	# Tinglado artesanal de secado de ladrillos (cobertizo de vigas y techumbre)
	var shed_ang := base_ang - 1.8
	var p_shed := Vector2(cos(shed_ang), sin(shed_ang)) * 38.0
	var shed_yaw := shed_ang + 0.35
	var y_shed := _ground(p_shed.length())
	var s_right := Vector2(-sin(shed_yaw), cos(shed_yaw))
	var s_forward := Vector2(cos(shed_yaw), sin(shed_yaw))
	
	# 4 postes de soporte
	for sx: float in [-3.2, 3.2]:
		for sz: float in [-2.2, 2.2]:
			var post_p: Vector2 = p_shed + s_forward * sx + s_right * sz
			skids.append(_xf(post_p, Vector3(0.55, 6.4, 0.55), shed_yaw, 0.0, y_shed + 3.2))
	# Vigas longitudinales superiores
	for sz: float in [-2.2, 2.2]:
		var beam_p: Vector2 = p_shed + s_right * sz
		skids.append(_xf(beam_p, Vector3(7.4, 0.45, 0.55), shed_yaw, 0.0, y_shed + 6.4))
	# Cubierta de tablones rústicos de secado
	blocks.append(_xf(p_shed, Vector3(8.4, 0.45, 6.0), shed_yaw, 0.08, y_shed + 6.8))

	# Grava y pedregullo de arcilla en el pie de corte
	for i in 4:
		var ang := pit_ang + 0.4 + float(i) * 0.3
		var p := Vector2(cos(ang), sin(ang)) * (42.0 + float(i % 2) * 2.0)
		var s := 1.2 + _u(q, r, 410 + i) * 0.9
		stones.append(_xf(p, Vector3(s * 1.2, s * 0.7, s), _u(q, r, 420 + i) * TAU, 0.0, _ground(p.length()) + s * 0.25))
	
	_scatter("ClayBlocks", _box, _clay, blocks, true)
	_scatter("Bricks", _box, _brick, bricks, true)
	_scatter("TimberSkids", _box, _bark, skids, false)
	_scatter("ClayRubble", _cobble, _rock, stones, false)

# -----------------------------------------------------------------------------
# LAGUNA:
# - Lográ una superficie de agua limpia y claramente distinguible.
# - Integrá la orilla con la base (cantos rodados de ribera en el zócalo).
# - Evitá objetos terrestres flotando sobre el agua sin justificación.
# -----------------------------------------------------------------------------
func _lagoon(q: int, r: int) -> void:
	# 1. Fondo arenoso amplio y limpio
	var bed := MeshInstance3D.new()
	bed.name = "LagoonBed"
	bed.mesh = _hex_disc(SCENERY_R - 0.4, 0.02)
	bed.material_override = _sand
	bed.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(bed)

	# 2. Espejo de agua cristalina turquesa a ras de la ficha
	var water := MeshInstance3D.new()
	water.name = "WaterSurface"
	water.mesh = _hex_disc(SCENERY_R, 0.16)
	water.material_override = _water_mat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)

	# 3. Orilla de cantos rodados perfectamente asentados dentro del margen seguro
	var shore: Array[Transform3D] = []
	var shore_dark: Array[Transform3D] = []
	for i in 22:
		var p := _ring(q, r, i, 22, 62.5, 3.5, 0.15, 430, 56.0, 66.5)
		var s := 1.6 + _u(q, r, 440 + i) * 1.8
		var sy := s * (0.35 + _u(q, r, 450 + i) * 0.2)
		var xf := _xf(p, Vector3(s * 1.2, sy, s), _u(q, r, 460 + i) * TAU, 0.0, 0.12 + sy * 0.25)
		if i % 3 == 0:
			shore_dark.append(xf)
		else:
			shore.append(xf)
	_scatter("ShoreRocks", _cobble, _rock, shore, true)
	_scatter("ShoreDarkRocks", _cobble, _rock_dark, shore_dark, true)

	# 4. Muelle artesanal de madera
	var dock_angle := _u(q, r, 12) * TAU
	var dock_dir := Vector2(cos(dock_angle), sin(dock_angle))
	var dock_side := Vector2(-dock_dir.y, dock_dir.x)
	var dock_start := dock_dir * 64.0
	var dock_end := dock_dir * 38.0
	var dock_len := 26.0

	var dock_root := Node3D.new()
	dock_root.name = "Dock"
	dock_root.position = Vector3((dock_start.x + dock_end.x) * 0.5, 0.32, (dock_start.y + dock_end.y) * 0.5)
	dock_root.rotation.y = -dock_angle
	add_child(dock_root)

	for k in 6:
		var px := -dock_len * 0.5 + float(k) * (dock_len / 5.0)
		var plank := MeshInstance3D.new()
		var p_mesh := BoxMesh.new()
		p_mesh.size = Vector3(3.4, 0.25, 7.8)
		plank.mesh = p_mesh
		plank.position = Vector3(px, 0.0, 0.0)
		plank.material_override = _bark
		plank.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		dock_root.add_child(plank)

	for pi in 3:
		var ppx := -dock_len * 0.42 + float(pi) * (dock_len * 0.42)
		for side: float in [-3.2, 3.2]:
			var pole := MeshInstance3D.new()
			var pole_mesh := CylinderMesh.new()
			pole_mesh.top_radius = 0.55
			pole_mesh.bottom_radius = 0.65
			pole_mesh.height = 0.55
			pole.mesh = pole_mesh
			pole.position = Vector3(ppx, -0.15, side)
			pole.material_override = _bark
			pole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			dock_root.add_child(pole)

	# 5. Bote de pesca amarrado al muelle sobre la superficie del agua
	var boat := Node3D.new()
	boat.name = "Boat"
	boat.position = Vector3(dock_end.x + dock_side.x * 6.8, 0.20, dock_end.y + dock_side.y * 6.8)
	boat.rotation.y = -dock_angle + 0.35
	add_child(boat)

	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(9.5, 0.85, 4.6)
	hull.mesh = hull_mesh
	hull.position = Vector3(0, 0.28, 0)
	hull.material_override = _bark
	hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	boat.add_child(hull)

	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(1.8, 0.25, 3.8)
	seat.mesh = seat_mesh
	seat.position = Vector3(0, 0.6, 0)
	seat.material_override = _straw
	boat.add_child(seat)

	# 6. Nenúfares y flores de loto flotando exactamente sobre la lámina de agua
	var lilies: Array[Transform3D] = []
	var petals: Array[Transform3D] = []
	for li in 7:
		var lp := _ring(q, r, li, 7, 24.0, 7.0, 0.6, 480, 20.0, 36.0)
		var ls := 2.6 + _u(q, r, 490 + li) * 1.4
		lilies.append(_xf(lp, Vector3(ls, 0.06, ls), _u(q, r, 500 + li) * TAU, 0.0, 0.18))
		if li % 2 == 0:
			petals.append(_xf(lp, Vector3(0.9, 0.6, 0.9), _u(q, r, 510 + li) * TAU, 0.0, 0.22))
	_scatter("LilyPads", _ball, _grass, lilies, false)
	_scatter("LotusBlossoms", _ball, _petal_cream, petals, false)

# -----------------------------------------------------------------------------
# Utilitarios geométricos y matemáticos
# -----------------------------------------------------------------------------
func _stalk(stems: Array[Transform3D], heads: Array[Transform3D], q: int, r: int, p: Vector2, height: float, thick: float, salt: int) -> void:
	var yaw := _u(q, r, salt) * TAU
	var lean := (_u(q, r, salt + 1) - 0.35) * 0.20
	var y0 := _ground(p.length())
	stems.append(_xf(p, Vector3(thick, height, thick), yaw, lean, y0 + height * 0.5))
	var reach := sin(lean) * height * 0.5
	var tip := p + Vector2(cos(yaw), sin(yaw)) * reach
	heads.append(_xf(tip, Vector3(1.15, 2.25, 1.15), yaw, lean * 0.5, y0 + height + 0.55))

func _ring(q: int, r: int, slot: int, count: int, radius: float, jitter: float, phase: float, salt: int, min_r: float = 23.0, max_r: float = 46.0) -> Vector2:
	var ang := _spin(q, r) + phase + TAU * float(slot) / float(maxi(count, 1))
	ang += (_u(q, r, salt + slot) - 0.5) * 0.4
	var rad := clampf(radius + (_u(q, r, salt + 17 + slot) - 0.5) * jitter, min_r, max_r)
	return Vector2(cos(ang), sin(ang)) * rad

func _xf(pos: Vector2, scale: Vector3, yaw: float, lean: float, y: float) -> Transform3D:
	var basis := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean)
	basis = basis.scaled(scale)
	return Transform3D(basis, Vector3(pos.x, y, pos.y))

func _prone(pos: Vector2, yaw: float, radius: float, length: float, y: float) -> Transform3D:
	var flat := Vector3(cos(yaw), 0.0, sin(yaw))
	var dir := (flat + Vector3(0.0, 0.16, 0.0)).normalized()
	var x := Vector3.UP.cross(dir).normalized()
	var z := x.cross(dir).normalized()
	var basis := Basis(x, dir, z).scaled(Vector3(radius, length, radius))
	var origin := Vector3(pos.x, y, pos.y) + flat * (length * 0.38)
	return Transform3D(basis, origin)

func _scatter(node_name: String, mesh: Mesh, mat: Material, xforms: Array[Transform3D], shadow: bool) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var inst := MultiMeshInstance3D.new()
	inst.name = node_name
	inst.multimesh = mm
	inst.material_override = mat
	inst.set_meta("xforms", xforms)
	inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(inst)

static func _spin(q: int, r: int) -> float:
	return _u(q, r, 2) * TAU

static func _heft(q: int, r: int) -> float:
	return 0.92 + _u(q, r, 3) * 0.16

static func _u(q: int, r: int, salt: int) -> float:
	var n := absi((q + 11) * 73 + (r + 11) * 179 + salt * 47)
	n = (n * 1103515245 + 12345) & 0x7fffffff
	return float(n % 1000) / 999.0

static func _ground(dist: float) -> float:
	if dist < 18.0:
		return 0.03
	if dist < 34.0:
		return lerpf(0.03, 0.55, (dist - 18.0) / 16.0)
	if dist < 56.0:
		return lerpf(0.55, 0.22, (dist - 34.0) / 22.0)
	return lerpf(0.22, 0.02, clampf((dist - 56.0) / 26.0, 0.0, 1.0))

static func _annulus() -> ArrayMesh:
	return _rings([[18.0, 0.03], [34.0, 0.55], [56.0, 0.22], [82.0, 0.02]], false)

static func _pool() -> ArrayMesh:
	return _rings([[0.0, 1.15], [36.0, 0.85], [50.0, 0.16]], true)

static func _rings(profile: Array, filled: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings: Array = []
	for step in profile:
		var row: Array[Vector3] = []
		var radius := float(step[0])
		var y := float(step[1])
		if radius <= 0.01:
			row.append(Vector3(0.0, y, 0.0))
		else:
			var k := radius / HexGeom.SIZE
			for i in 6:
				var c := HexGeom.corner(Vector2.ZERO, i) * k
				row.append(Vector3(c.x, y, c.y))
		rings.append(row)
	var start := 0
	if filled and (rings[0] as Array).size() == 1:
		var center: Vector3 = rings[0][0]
		var lip: Array = rings[1]
		for i in lip.size():
			var j := (i + 1) % lip.size()
			_tri(st, center, lip[i], lip[j])
		start = 1
	for band in range(start, rings.size() - 1):
		var inner: Array = rings[band]
		var outer: Array = rings[band + 1]
		if inner.size() != outer.size():
			continue
		for i in inner.size():
			var j := (i + 1) % inner.size()
			_tri(st, inner[i], inner[j], outer[j])
			_tri(st, inner[i], outer[j], outer[i])
	return st.commit()

static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var n := (b - a).cross(c - a)
	if n.y < 0.0:
		var swap := b
		b = c
		c = swap
		n = -n
	n = n.normalized() if n.length() > 0.001 else Vector3.UP
	for p in [a, b, c]:
		st.set_normal(n)
		st.add_vertex(p)

static func _hex_disc(radius: float, height: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var k := radius / HexGeom.SIZE
	var corners: Array[Vector3] = []
	for i in 6:
		var c := HexGeom.corner(Vector2.ZERO, i) * k
		corners.append(Vector3(c.x, height, c.y))
	var center := Vector3(0.0, height, 0.0)
	for i in 6:
		var j := (i + 1) % 6
		_tri(st, center, corners[i], corners[j])
	return st.commit()
