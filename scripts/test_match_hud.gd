extends SceneTree
# Prueba el HUD móvil de partida. Ventana GPU, no --headless.

const OUT_DIR := "res://debug_captures"
const GameScript := preload("res://scripts/match.gd")
const _Main := preload("res://scripts/main.gd")
const _Hud := preload("res://scripts/match_hud.gd")

var fails := 0
var main

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== TEST HUD PARTIDA ===")
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	change_scene_to_file("res://scenes/main.tscn")
	await _settle()
	main = current_scene
	if main == null or main.hud == null or main.game == null:
		print("[hud] FALLO no cargó Main/HUD")
		quit(1)
		return
	_check("mapa protagonista", main.table_host.size.x >= 900.0 and main.table_host.size.y >= 480.0)
	_check("sin columna HUD", main._hud_width(Vector2(1280, 720)) < 8.0)
	_check("dados ocultos en fundación", main.roll_btn.visible == false or main.roll_btn.disabled)
	_check("Listo desactivado en fundación", main.end_btn.disabled)
	_shot("hud_setup.png")

	_place_settlement()
	_place_road()
	print("[hud] tras fundar 1 fase=%s jugador=%s" % [main.game.phase, main.game.current_player])
	await _wait_human()
	print("[hud] vuelve el turno fase=%s jugador=%s" % [main.game.phase, main.game.current_player])
	_place_settlement()
	_place_road()
	await _settle()
	print("[hud] tras fundar 2 fase=%s" % main.game.phase)
	_check("fase tirar", int(main.game.phase) == GameScript.Phase.ROLL)
	_check("Tirar visible", main.roll_btn.visible and not main.roll_btn.disabled)
	_shot("hud_roll.png")

	var off: String = String(main.game.roll(1))
	_check("no tira el rival en tu turno", off != "")
	main.hud.roll_pressed.emit()
	await _settle()
	_check("después de tirar, construir", int(main.game.phase) == GameScript.Phase.BUILD)
	_check("hay resultado", int(main.game.last_roll) >= 2)
	_shot("hud_despues_dados.png")

	main.hud.dock_btns["mano"].pressed.emit()
	await _settle()
	_check("mano abierta", main.hud.open_id() == "mano")
	_check("cartas de recursos", main.you_counts.size() == GameScript.RES_COUNT + GameScript.WARE_NAME.size())
	_shot("hud_mano.png")
	main.hud._select_card(0)
	await _settle()

	main.hud.dock_btns["build"].pressed.emit()
	await _settle()
	_check("construir abierto", main.hud.open_id() == "build")
	_check("mapa sigue visible al construir", main.table_host.size.y >= 280.0)
	_shot("hud_construir.png")

	main.banner = ""
	main._on_board_click(Vector2(1180, 160))
	await _settle()
	_check("toque inválido explica", main.banner != "")

	var before := int(main.game.phase)
	main.hud.end_pressed.emit()
	await _wait_human()
	_check("Listo cambia de turno o espera rival", before == GameScript.Phase.BUILD)

	main.hud.dock_btns["trade"].pressed.emit()
	await _settle()
	_check("comercio abierto", main.hud.open_id() == "trade")
	_shot("hud_cambiar.png")
	var trade_err := String(main.game.trade(0, 0, 1, false))
	_check("comercio respeta reglas", trade_err != "" or int(main.game.progress[0][GameScript.Track.MERCADO]) > 0)

	print("=== FIN HUD fails=%d ===" % fails)
	quit(1 if fails > 0 else 0)

func _place_settlement() -> void:
	var verts: Array = main.game.legal_settlement_vertices(0)
	_check("hay puesto legal", not verts.is_empty())
	if verts.is_empty():
		return
	main._after(main.game.place_settlement(0, int(verts[0])))

func _place_road() -> void:
	var roads: Array = main.game.legal_roads(0)
	_check("hay camino legal", not roads.is_empty())
	if roads.is_empty():
		return
	main._after(main.game.place_road(0, String(roads[0])))

func _wait_human() -> void:
	var n := 0
	while n < 900:
		if not bool(main.ai_running) and int(main.game.current_player) == 0:
			return
		await process_frame
		n += 1
	print("[hud] FALLO timeout esperando turno")
	fails += 1

func _check(name: String, ok: bool) -> void:
	if ok:
		print("[hud] ok %s" % name)
	else:
		print("[hud] FALLO %s" % name)
		fails += 1

func _settle() -> void:
	for i in 6:
		await process_frame
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw

func _shot(file_name: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var tex := root.get_texture()
	var img: Image = null
	if tex != null:
		img = tex.get_image()
	if img == null:
		print("[hud] FALLO captura %s" % file_name)
		fails += 1
		return
	var path := "%s/%s" % [OUT_DIR, file_name]
	img.save_png(path)
	print("[hud] captura %s %dx%d" % [file_name, img.get_width(), img.get_height()])
