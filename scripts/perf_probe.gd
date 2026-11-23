extends SceneTree
# Perfil de rendimiento: mide fps/draws/primitivas apagando partes del tablero.
# Uso: godot --path . -s res://scripts/perf_probe.gd   (sin --headless)

var main: Node
var board: Node

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	print("[perf] adapter=%s driver=%s" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_method()])
	change_scene_to_file("res://scenes/main.tscn")
	for i in 30:
		await process_frame
	main = current_scene
	board = main.get("table")
	if board == null:
		print("[perf] sin tablero")
		quit(1)
		return
	RenderingServer.viewport_set_measure_render_time((main.get("table_view") as Viewport).get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	await _measure("base")
	var sun: DirectionalLight3D = board.get("_sun")
	sun.shadow_enabled = false
	await _measure("sin sombras")
	sun.shadow_enabled = true
	var sea := _find_sea(board)
	if sea:
		sea.visible = false
		await _measure("sin mar")
		sea.visible = true
	var hidden: Array[Node3D] = []
	for c in board.get_children():
		if c is Node3D and c != board.get("camera") and not (c is DirectionalLight3D) and c != sea:
			if (c as Node3D).visible:
				(c as Node3D).visible = false
				hidden.append(c)
	await _measure("solo mar")
	for c in hidden:
		c.visible = true
	_dump_tile_tris()
	quit(0)

func _find_sea(n: Node) -> Node3D:
	for c in n.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh is PlaneMesh:
			return c
	return null

func _dump_tile_tris() -> void:
	var by_name := {}
	_walk(board, by_name)
	var keys := by_name.keys()
	keys.sort_custom(func(a, b): return by_name[a] > by_name[b])
	for k in keys.slice(0, 12):
		print("[perf] tris %-40s %d" % [k, by_name[k]])

func _walk(n: Node, acc: Dictionary) -> void:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).is_visible_in_tree():
		var m: Mesh = (n as MeshInstance3D).mesh
		var t := 0
		for s in m.get_surface_count():
			var arr := m.surface_get_arrays(s)
			var idx = arr[Mesh.ARRAY_INDEX]
			t += int(idx.size() if idx != null else (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()) / 3
		var key := String(m.resource_path if m.resource_path != "" else m.resource_name)
		if key == "" and n.get_parent() != null:
			key = "%s/%s(%s)" % [String(n.get_parent().name).rstrip("0123456789_-"), m.get_class(), m.get_surface_count()]
		if key == "":
			key = String(n.name).rstrip("0123456789_")
		acc[key] = int(acc.get(key, 0)) + t
	elif n is MultiMeshInstance3D:
		var mm := (n as MultiMeshInstance3D).multimesh
		if mm and mm.mesh:
			var arr := mm.mesh.surface_get_arrays(0)
			var idx = arr[Mesh.ARRAY_INDEX]
			var t: int = (idx.size() if idx != null else 0) / 3
			acc["MM " + String(n.name)] = int(acc.get("MM " + String(n.name), 0)) + t * mm.instance_count
	for c in n.get_children():
		_walk(c, acc)

func _measure(label: String) -> void:
	for i in 20:
		await process_frame
	var t0 := Time.get_ticks_usec()
	var frames := 0
	while Time.get_ticks_usec() - t0 < 2_000_000:
		await process_frame
		frames += 1
	var secs := (Time.get_ticks_usec() - t0) / 1_000_000.0
	var vp: Viewport = main.get("table_view")
	var rid := vp.get_viewport_rid()
	var draws := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_DRAW_CALLS_IN_FRAME)
	var prims := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_VISIBLE, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	var sh_prims := RenderingServer.viewport_get_render_info(rid, RenderingServer.VIEWPORT_RENDER_INFO_TYPE_SHADOW, RenderingServer.VIEWPORT_RENDER_INFO_PRIMITIVES_IN_FRAME)
	print("[perf] %-14s fps=%.1f draws=%d prims=%d shadow_prims=%d cpu_ms=%.2f gpu_ms=%.2f" % [
		label, frames / secs, draws, prims, sh_prims,
		RenderingServer.viewport_get_measured_render_time_cpu(rid),
		RenderingServer.viewport_get_measured_render_time_gpu(rid)])
