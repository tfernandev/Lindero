extends Node2D

const GameScript := preload("res://scripts/match.gd")
const HexGeom := preload("res://scripts/hex_lib.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const TableBoard := preload("res://scripts/table_board.gd")

var game = null
var font: Font
var board_scale := 1.0
var board_origin := Vector2(80, 60)
var tool := "settlement"
var banner := ""
var ai_running := false
var turn_token := 0

var instruction_label: Label
var dice_label: Label
var score_label: RichTextLabel
var log_label: Label
var terrain_tex: Array[Texture2D] = []
var lagoon_tex: Texture2D
var sea_tex: Texture2D
var puesto_tex: Texture2D
var granja_tex: Texture2D
var camino_tex: Texture2D
var card_tex: Array[Texture2D] = []
var you_counts: Array[Label] = []
var rival_counts: Array[Label] = []
var you_icons: Array[CanvasItem] = []
var rival_icons: Array[CanvasItem] = []
var you_badges: Array[Panel] = []
var rival_badges: Array[Panel] = []
var hand_blocks: Array[Control] = []
var hand_names: Array[Label] = []
var hand_marks: Array[Panel] = []
var dice_well: Panel
var dice_edge: StyleBoxFlat
var seen_counts: Array[int] = []
var dice_parts: Label
var roll_btn: Button
var road_btn: Button
var set_btn: Button
var up_btn: Button
var end_btn: Button
var restart_btn: Button
var menu_btn: Button
var cost_label: Label
var rival_chart: Label
var track_btns: Array[Button] = []
var give_btns: Array[Button] = []
var take_btns: Array[Button] = []
var trade_btn: Button
var give_sel := 0
var take_sel := 2
var give_ware := false
var take_ware := false
var motion_btn: Button
var exit_row: HBoxContainer
var hud_panel: Panel
var chart_panel: Panel
var chart_box: VBoxContainer
var hud_box: VBoxContainer
var give_row: HBoxContainer
var take_row: HBoxContainer
var deal_row: HBoxContainer
var hand_rows: Array[HBoxContainer] = []
var table_host: SubViewportContainer
var table_view: SubViewport
var table: TableBoard
var hover_q := -999
var hover_r := -999
var hover_vertex := -1
var hover_edge := ""
var placed_edge := ""
var placed_vertex := -1
var placed_level := 1
var place_t := 1.0
var produce_n := 0
var produce_t := 1.0
var _motion_ready := false
var _seen_roll := 0
var _seen_player := 0
var _seen_roads: Dictionary = {}
var _seen_buildings: Dictionary = {}
var _seen_prog: Array[int] = [0, 0, 0]
var _dice_tween: Tween

func _ready() -> void:
	font = ThemeDB.fallback_font
	game = GameScript.new()
	game.new_game()
	_load_art()
	_build_table()
	_build_hud()
	get_viewport().size_changed.connect(_on_resized)
	UiTheme.fit_window(get_window())
	_layout_chrome()
	_refresh()
	set_process(false)

func _process(delta: float) -> void:
	var busy := false
	if place_t < 1.0:
		place_t = minf(1.0, place_t + delta / 0.22)
		busy = true
	if produce_t < 1.0:
		produce_t = minf(1.0, produce_t + delta / 0.36)
		busy = true
	if busy:
		queue_redraw()
	else:
		set_process(false)

func _on_resized() -> void:
	if UiTheme.fit_window(get_window()):
		return
	_layout_chrome()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_hover(event.position)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_SPACE:
				_on_roll()
			KEY_1:
				_set_tool("road")
			KEY_2:
				_set_tool("settlement")
			KEY_3:
				_set_tool("upgrade")
			KEY_4:
				_on_advance(0)
			KEY_5:
				_on_advance(1)
			KEY_6:
				_on_advance(2)
			KEY_ENTER, KEY_KP_ENTER:
				_on_end_turn()
			KEY_ESCAPE:
				if banner != "":
					banner = ""
					_refresh()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_board_click(event.position)

func _draw() -> void:
	var view := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, view), Color("171310"))
	var frame := Rect2(12, 12, maxf(80.0, view.x - _hud_width(view) - 36.0), maxf(80.0, view.y - _chart_height(view) - 24.0))
	draw_rect(frame, Color("3d2c22"))
	draw_rect(frame.grow(-7), Color("c4a574"))
	var plate := frame.grow(-10)
	if table != null:
		return
	if sea_tex != null:
		_draw_cover(sea_tex, plate)
	else:
		draw_rect(plate, Color("1b4038"))
	if game == null:
		return
	for h in game.hexes:
		draw_colored_polygon(_hex_pts(h, 1.2, Vector2(0, 7)), Color(0.04, 0.07, 0.06, 0.38))
	for h in game.hexes:
		draw_colored_polygon(_hex_pts(h, 1.13, Vector2.ZERO), Color("b08968"))
	for h in game.hexes:
		draw_colored_polygon(_hex_pts(h, 1.06, Vector2.ZERO), Color("f0e2c8"))
	for h in game.hexes:
		_draw_hex(h)
	for ek in game.edges.keys():
		_draw_edge(String(ek))
	for v in game.v_pos.size():
		_draw_vertex(v)

func _draw_hex(h: Dictionary) -> void:
	var center := HexGeom.hex_to_pixel(int(h.q), int(h.r))
	var spin := float(posmod(int(h.q) * 2 + int(h.r) * 3, 6)) * TAU / 6.0
	var cs := cos(spin)
	var sn := sin(spin)
	var pts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for i in 6:
		var corner := HexGeom.corner(center, i)
		pts.append(_to_screen(corner))
		var rel := corner - center
		rel = Vector2(rel.x * cs - rel.y * sn, rel.x * sn + rel.y * cs)
		uvs.append(Vector2(rel.x / (HexGeom.SIZE * 2.0) + 0.5, rel.y / (HexGeom.SIZE * 2.0) + 0.5))
		cols.append(Color.WHITE)
	var res := int(h.resource)
	var number := int(h.number)
	var tex: Texture2D = null
	if res < 0:
		tex = lagoon_tex
	elif res < terrain_tex.size():
		tex = terrain_tex[res]
	if tex != null:
		draw_polygon(pts, cols, uvs, tex)
	else:
		var flat: Color = GameScript.LAGOON if res < 0 else GameScript.RES_COLOR[res]
		draw_colored_polygon(pts, flat)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color("2a1c10"), maxf(1.6, 2.0 * board_scale), true)
	var hot: bool = number > 0 and number == game.last_roll and game.last_roll != 7 and game.phase != GameScript.Phase.SETUP_SETTLEMENT and game.phase != GameScript.Phase.SETUP_ROAD
	var screen_center := _to_screen(center)
	if hot:
		draw_colored_polygon(pts, Color(1, 1, 1, 0.2))
		var mark := PackedVector2Array()
		for point in pts:
			mark.append(screen_center + (point - screen_center) * 0.9)
		mark.append(mark[0])
		draw_polyline(mark, Color("e2b15a"), maxf(1.8, 2.2 * board_scale), true)
	if int(h.q) == hover_q and int(h.r) == hover_r:
		var inner := PackedVector2Array()
		for point in pts:
			inner.append(screen_center + (point - screen_center) * 0.88)
		inner.append(inner[0])
		draw_polyline(inner, Color("e2b15a"), maxf(1.7, 2.1 * board_scale), true)
	if produce_t < 1.0 and number == produce_n and number != 7:
		var fade := 1.0 - _ease_out(produce_t)
		draw_arc(screen_center, maxf(22.0, 28.0 * board_scale), 0, TAU, 28, Color(0.89, 0.69, 0.35, 0.5 * fade), maxf(1.5, 2.2 * board_scale), true)
	if res >= 0:
		var ware := int(GameScript.WARE_OF_RES[res])
		if ware >= 0 and board_scale >= 0.82:
			var ware_at := screen_center + Vector2(0, 34.0 * board_scale)
			var ware_size := int(clampf(13.0 * board_scale, 12.0, 14.0))
			var chip := font.get_string_size(GameScript.WARE_LETTER[ware], HORIZONTAL_ALIGNMENT_LEFT, -1, ware_size)
			var chip_w := maxf(chip.x + 8.0, 20.0 * board_scale)
			var chip_h := maxf(chip.y + 2.0, 14.0 * board_scale)
			var chip_rect := Rect2(ware_at.x - chip_w * 0.5, ware_at.y - chip_h * 0.5, chip_w, chip_h)
			draw_rect(chip_rect.grow(1.0), Color("c4a574"))
			draw_rect(chip_rect, Color("241c16"))
			_draw_centered(GameScript.WARE_LETTER[ware], ware_at, ware_size, GameScript.WARE_COLOR[ware])
		var token := screen_center + Vector2(0, 6.0 * board_scale)
		var num_size := int(clampf(18.0 * board_scale, 12.0, 22.0))
		var seal := clampf(maxf(19.0 * board_scale, float(num_size) * 0.9), 12.0, 26.0)
		draw_circle(token, seal + maxf(1.25, 1.5 * board_scale), Color("2a1c10"))
		draw_circle(token, seal, Color("f6f1e4"))
		var num_col := Color("b42318") if number == 6 or number == 8 else Color("241c16")
		_draw_centered(str(number), token + Vector2(0, -6.0 * board_scale), num_size, num_col)
		_draw_pips(token + Vector2(0, 10.0 * board_scale), HexGeom.pips(number), num_col)
	else:
		_draw_centered("Laguna", screen_center, int(clamp(16.0 * board_scale, 13, 22)), Color("f6f1e4"))

func _draw_edge(ek: String) -> void:
	var ends: Array = game.edges[ek]
	var a := _to_screen(game.v_pos[int(ends[0])])
	var b := _to_screen(game.v_pos[int(ends[1])])
	if game.roads.has(ek):
		var tip := b
		if ek == placed_edge and place_t < 1.0:
			tip = a.lerp(b, _ease_out(place_t))
		_draw_path(a, tip, int(game.roads[ek]))
		if ek == placed_edge and place_t < 1.0:
			draw_circle(tip, maxf(2.0, 2.4 * board_scale), Color(0.96, 0.91, 0.82, 1.0 - place_t))
	elif _hint_road(ek):
		var width := maxf(3.0, 3.6 * board_scale) if ek == hover_edge else maxf(1.6, 2.2 * board_scale)
		draw_line(a, b, Color("f6f1e4"), width, true)

func _draw_vertex(v: int) -> void:
	var p := _to_screen(game.v_pos[v])
	if game.buildings.has(v):
		var b: Dictionary = game.buildings[v]
		var col: Color = GameScript.PLAYER_COLOR[int(b.player)]
		var tall: bool = int(b.level) >= 2
		var height := clampf((58.0 if tall else 40.0) * board_scale, 22.0, 72.0)
		var pop := 1.0
		if v == placed_vertex and place_t < 1.0:
			pop = lerpf(0.86, 1.0, _ease_out(place_t))
		_draw_token(p, granja_tex if tall else puesto_tex, col, height * pop)
		if v == placed_vertex and place_t < 1.0:
			_draw_motes(p, place_t, Color("e2b15a") if placed_level >= 2 else Color("f6f1e4"))
		if game.phase == GameScript.Phase.SETUP_ROAD and v == game.anchor:
			draw_arc(p, height * 0.62, 0, TAU, 24, Color("f6f1e4"), 2.0, true)
	elif _hint_vertex(v):
		var radius := maxf(4.5, 6.2 * board_scale)
		if v == hover_vertex:
			radius *= 1.35
			draw_arc(p, radius + 5.0, 0, TAU, 18, Color("e2b15a"), 2.0, true)
		_draw_peg(p, radius)
	elif _hint_upgrade(v):
		draw_arc(p, 16.0 * board_scale, 0, TAU, 24, Color("f0c36a"), 2.5, true)

func _draw_house(p: Vector2, col: Color, s: float) -> void:
	var pts := PackedVector2Array([
		p + Vector2(-s, s * 0.55),
		p + Vector2(s, s * 0.55),
		p + Vector2(s, -s * 0.15),
		p + Vector2(0, -s),
		p + Vector2(-s, -s * 0.15),
	])
	draw_colored_polygon(pts, col)
	var outline := pts.duplicate()
	outline.append(pts[0])
	draw_polyline(outline, Color(0.08, 0.06, 0.04), maxf(1.0, s * 0.12), true)

func _draw_pips(center: Vector2, count: int, color: Color) -> void:
	if count <= 0:
		return
	var gap := maxf(3.0, 4.2 * board_scale)
	var start := center.x - float(count - 1) * gap * 0.5
	var radius := maxf(1.1, 1.5 * board_scale)
	for i in count:
		draw_circle(Vector2(start + float(i) * gap, center.y), radius, color)

func _draw_centered(text: String, center: Vector2, size: int, color: Color) -> void:
	var ts := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var baseline := Vector2(center.x - ts.x * 0.5, center.y + ts.y * 0.32)
	draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)

func _hint_vertex(v: int) -> bool:
	if ai_running or game.current_player != 0:
		return false
	if game.phase == GameScript.Phase.SETUP_SETTLEMENT:
		return game.legal_settlement_vertices(0).has(v)
	if game.phase == GameScript.Phase.BUILD and tool == "settlement":
		return game.legal_settlement_vertices(0).has(v)
	return false

func _hint_upgrade(v: int) -> bool:
	return not ai_running and game.current_player == 0 and game.phase == GameScript.Phase.BUILD and tool == "upgrade" and game.legal_upgrades(0).has(v)

func _hint_road(ek: String) -> bool:
	if ai_running or game.current_player != 0:
		return false
	if game.phase != GameScript.Phase.SETUP_ROAD and not (game.phase == GameScript.Phase.BUILD and tool == "road"):
		return false
	return game.legal_roads(0).has(ek)

func _on_board_click(screen: Vector2) -> void:
	if game.phase == GameScript.Phase.OVER:
		return
	if ai_running or game.current_player != 0:
		_flash("Turno del vecino.")
		return
	if game.phase == GameScript.Phase.ROLL:
		_flash("Primero tirá los dados.")
		return
	var local := _pointer_board(screen)
	if game.phase == GameScript.Phase.SETUP_SETTLEMENT or (game.phase == GameScript.Phase.BUILD and tool == "settlement"):
		var v := _pick_vertex(local)
		if v < 0:
			_flash(_miss_settlement())
			return
		_after(game.place_settlement(0, v))
	elif game.phase == GameScript.Phase.SETUP_ROAD or (game.phase == GameScript.Phase.BUILD and tool == "road"):
		var ek := _pick_edge(local)
		if ek == "":
			_flash(_miss_road())
			return
		_after(game.place_road(0, ek))
	elif game.phase == GameScript.Phase.BUILD and tool == "upgrade":
		var v := _pick_vertex(local)
		if v < 0:
			_flash(_miss_upgrade())
			return
		_after(game.upgrade(0, v))

func _pick_vertex(local: Vector2) -> int:
	var best := -1
	var best_d := 34.0 if table != null else 36.0 / board_scale
	for v in game.v_pos.size():
		var d := local.distance_to(game.v_pos[v])
		if d < best_d:
			best_d = d
			best = v
	return best

func _pick_edge(local: Vector2) -> String:
	var best := ""
	var best_d := 20.0 if table != null else 24.0 / board_scale
	for ek in game.edges.keys():
		var ends: Array = game.edges[ek]
		var d := _dist_segment(local, game.v_pos[int(ends[0])], game.v_pos[int(ends[1])])
		if d < best_d:
			best_d = d
			best = String(ek)
	return best

func _dist_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var denom := ab.length_squared()
	if denom <= 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / denom, 0.0, 1.0)
	return p.distance_to(a + ab * t)

func _on_roll() -> void:
	if ai_running:
		return
	_after(game.roll(0))

func _on_end_turn() -> void:
	if ai_running:
		return
	_after(game.end_turn(0))

func _set_tool(next: String) -> void:
	tool = next
	_prefer_tool()
	_refresh()

func _after(err: String) -> void:
	banner = err
	if game.phase == GameScript.Phase.BUILD and game.current_player == 0:
		_prefer_tool()
	_refresh()
	if err != "":
		return
	if game.current_player == 1 and game.phase != GameScript.Phase.OVER:
		_run_rival()

func _prefer_tool() -> void:
	if game.phase != GameScript.Phase.BUILD or game.current_player != 0:
		return
	if tool == "settlement" and game.can_afford(0, "settlement") and game.legal_settlement_vertices(0).is_empty() and not game.legal_roads(0).is_empty():
		tool = "road"
	elif tool == "upgrade" and game.can_afford(0, "upgrade") and game.legal_upgrades(0).is_empty():
		tool = "settlement" if game.can_afford(0, "settlement") and not game.legal_settlement_vertices(0).is_empty() else "road"

func _run_rival() -> void:
	if ai_running:
		return
	ai_running = true
	var token := turn_token
	var builds := 0
	_refresh()
	while token == turn_token and game.current_player == 1 and game.phase != GameScript.Phase.OVER:
		var err := ""
		if game.phase == GameScript.Phase.SETUP_SETTLEMENT:
			builds = 0
			err = game.place_settlement(1, game.choose_setup_vertex(1))
		elif game.phase == GameScript.Phase.SETUP_ROAD:
			err = game.place_road(1, game.choose_setup_road(1))
		elif game.phase == GameScript.Phase.ROLL:
			builds = 0
			err = game.roll(1)
		elif game.phase == GameScript.Phase.BUILD:
			if builds >= 4:
				err = game.end_turn(1)
			else:
				var action: Dictionary = game.choose_action(1)
				if action.is_empty():
					err = game.end_turn(1)
				else:
					err = game.apply_action(1, action)
					builds += 1
		else:
			break
		if token != turn_token:
			return
		if err != "":
			banner = "El vecino se trabó: " + err
			ai_running = false
			_refresh()
			return
		_refresh()
		await get_tree().create_timer(0.45).timeout
	if token == turn_token:
		ai_running = false
		_refresh()

func _on_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/menu.tscn")

func _on_restart() -> void:
	turn_token += 1
	ai_running = false
	banner = ""
	tool = "settlement"
	game.new_game()
	_layout_board()
	_refresh()

func _prompt() -> String:
	if game.phase == GameScript.Phase.BUILD and game.current_player == 0 and not ai_running:
		if tool == "road":
			return "Tocá una raya blanca que toque lo tuyo."
		if tool == "upgrade":
			return "Tocá un puesto tuyo para hacer la granja."
		return "Tocá un punto blanco sobre un camino tuyo."
	return game.instruction()

func _miss_settlement() -> String:
	if game.phase == GameScript.Phase.BUILD and not game.can_afford(0, "settlement"):
		return "Para un puesto hacen falta %s." % game.fmt_cost(game.cost_of(0, "settlement"))
	if not game.legal_settlement_vertices(0).is_empty():
		return "Tocá un punto blanco."
	var open := false
	for v in game.v_pos.size():
		if not game.vertex_blocked(int(v)):
			open = true
			break
	if game.phase == GameScript.Phase.BUILD and open:
		return "El puesto tiene que tocar un camino tuyo."
	return "Muy cerca de otro puesto."

func _miss_road() -> String:
	if game.phase == GameScript.Phase.BUILD and not game.can_afford(0, "road"):
		return "Un camino cuesta %s." % game.fmt_cost(game.cost_of(0, "road"))
	if not game.legal_roads(0).is_empty():
		return "Tocá una raya blanca."
	if game.phase == GameScript.Phase.SETUP_ROAD:
		return "El camino tiene que salir del puesto que acabás de fundar."
	return "Ese camino no conecta con lo tuyo."

func _miss_upgrade() -> String:
	if not game.can_afford(0, "upgrade"):
		return "La granja cuesta %s." % game.fmt_cost(game.cost_of(0, "upgrade"))
	if game.legal_upgrades(0).is_empty():
		return "Ese puesto no se puede mejorar."
	return "Tocá uno de tus puestos."

func _explain_controls(human_roll: bool, human_build: bool) -> void:
	var quiet := ""
	if game.phase == GameScript.Phase.OVER:
		quiet = ""
	elif game.current_player != 0 or ai_running:
		quiet = "Turno del vecino."
	elif game.phase == GameScript.Phase.ROLL:
		quiet = "Primero tirá los dados."
	elif game.phase == GameScript.Phase.SETUP_SETTLEMENT or game.phase == GameScript.Phase.SETUP_ROAD:
		quiet = "Primero terminá de fundar."
	if human_roll:
		roll_btn.tooltip_text = ""
	elif game.current_player != 0 or ai_running:
		roll_btn.tooltip_text = "Turno del vecino."
	elif game.phase == GameScript.Phase.SETUP_SETTLEMENT or game.phase == GameScript.Phase.SETUP_ROAD:
		roll_btn.tooltip_text = "Primero terminá de fundar."
	else:
		roll_btn.tooltip_text = "Se tira al empezar tu turno."
	var build_tip := "" if human_build else quiet
	for btn in [road_btn, set_btn, up_btn, end_btn]:
		btn.tooltip_text = build_tip
	for btn in track_btns:
		btn.tooltip_text = build_tip
	for btn in give_btns:
		btn.tooltip_text = build_tip
	for btn in take_btns:
		btn.tooltip_text = build_tip
	trade_btn.tooltip_text = build_tip

func _flash(text: String) -> void:
	banner = text
	_refresh()

func _on_motion() -> void:
	UiTheme.set_reduce_motion(not UiTheme.reduce_motion)
	if UiTheme.reduce_motion:
		place_t = 1.0
		produce_t = 1.0
		set_process(false)
		if instruction_label != null:
			instruction_label.modulate.a = 1.0
		if dice_label != null:
			dice_label.scale = Vector2.ONE
	_paint_motion_btn()
	queue_redraw()

func _paint_motion_btn() -> void:
	if motion_btn == null:
		return
	var calm: bool = UiTheme.reduce_motion
	var compact: bool = motion_btn.get_parent() == exit_row
	motion_btn.text = ("● " if calm else "") + ("Calma" if compact else "Menos movimiento")
	UiTheme.paint(motion_btn, "quiet")
	var ink: Color = UiTheme.INK_DIM if calm else UiTheme.INK
	motion_btn.add_theme_color_override("font_color", ink)
	motion_btn.add_theme_color_override("font_hover_color", ink)
	motion_btn.add_theme_color_override("font_pressed_color", ink)
	motion_btn.add_theme_color_override("font_focus_color", ink)

func _hover(screen: Vector2) -> void:
	if game == null:
		return
	var area := _board_area()
	var q := -999
	var r := -999
	var vertex := -1
	var edge := ""
	if area.has_point(screen):
		var local := _pointer_board(screen)
		var best := HexGeom.SIZE * 0.92
		for h in game.hexes:
			var dist := local.distance_to(HexGeom.hex_to_pixel(int(h.q), int(h.r)))
			if dist < best:
				best = dist
				q = int(h.q)
				r = int(h.r)
		vertex = _pick_vertex(local)
		edge = _pick_edge(local)
	if q == hover_q and r == hover_r and vertex == hover_vertex and edge == hover_edge:
		return
	hover_q = q
	hover_r = r
	hover_vertex = vertex
	hover_edge = edge
	if table != null:
		table.mark(game.last_roll, hover_q, hover_r)
	queue_redraw()

func _watch_motion() -> void:
	if not _motion_ready:
		_snapshot_motion()
		_motion_ready = true
		return
	var rolled: bool = int(game.last_roll) != _seen_roll and int(game.last_roll) != 0
	var turned: bool = int(game.current_player) != _seen_player
	var new_edge := ""
	for ek in game.roads.keys():
		if not _seen_roads.has(ek):
			new_edge = String(ek)
	var new_vertex := -1
	var new_level := 1
	for v in game.buildings.keys():
		var lvl := int(game.buildings[v].level)
		if int(_seen_buildings.get(int(v), 0)) != lvl:
			new_vertex = int(v)
			new_level = lvl
	var progressed := false
	for i in mini(3, track_btns.size()):
		if int(game.progress[0][i]) != _seen_prog[i]:
			progressed = true
			_pop_control(track_btns[i])
	if rolled:
		_pop_dice()
		if int(game.last_roll) == 7:
			produce_n = 0
			produce_t = 1.0
		else:
			produce_n = int(game.last_roll)
			produce_t = 0.0 if not UiTheme.reduce_motion else 1.0
	if new_edge != "":
		placed_edge = new_edge
		placed_vertex = -1
		place_t = 0.0 if not UiTheme.reduce_motion else 1.0
	elif new_vertex >= 0:
		placed_vertex = new_vertex
		placed_level = new_level
		placed_edge = ""
		place_t = 0.0 if not UiTheme.reduce_motion else 1.0
	if turned:
		_pop_hand(int(game.current_player))
	if not UiTheme.reduce_motion and (rolled or new_edge != "" or new_vertex >= 0 or progressed or turned):
		set_process(true)
	_snapshot_motion()

func _snapshot_motion() -> void:
	_seen_roll = int(game.last_roll)
	_seen_player = int(game.current_player)
	_seen_roads = game.roads.duplicate()
	_seen_buildings.clear()
	for v in game.buildings.keys():
		_seen_buildings[int(v)] = int(game.buildings[v].level)
	for i in 3:
		_seen_prog[i] = int(game.progress[0][i])

func _pop_dice() -> void:
	if dice_label == null or UiTheme.reduce_motion:
		return
	if _dice_tween != null and _dice_tween.is_valid():
		_dice_tween.kill()
	dice_label.pivot_offset = dice_label.size * 0.5
	dice_label.scale = Vector2(1.08, 1.08)
	_dice_tween = create_tween()
	_dice_tween.tween_property(dice_label, "scale", Vector2.ONE, 0.16)

func _pop_hand(player: int) -> void:
	if UiTheme.reduce_motion or player < 0 or player >= hand_marks.size():
		return
	var mark := hand_marks[player]
	mark.pivot_offset = mark.size * 0.5
	mark.scale = Vector2(1.3, 1.3)
	var tw := create_tween()
	tw.tween_property(mark, "scale", Vector2.ONE, 0.18)
	if instruction_label != null:
		instruction_label.modulate.a = 0.45
		var fade := create_tween()
		fade.tween_property(instruction_label, "modulate:a", 1.0, 0.2)

func _pop_control(node: Control) -> void:
	if UiTheme.reduce_motion or node == null:
		return
	node.pivot_offset = node.size * 0.5
	node.scale = Vector2(1.03, 1.03)
	var tw := create_tween()
	tw.tween_property(node, "scale", Vector2.ONE, 0.16)

func _draw_motes(at: Vector2, t: float, ink: Color) -> void:
	var fade := 1.0 - t
	for i in 4:
		var ang := float(i) / 4.0 * TAU + 0.5
		var rad := lerpf(5.0, 16.0, _ease_out(t)) * board_scale
		var dot := at + Vector2(cos(ang), sin(ang) * 0.7) * rad
		draw_circle(dot, maxf(1.3, 1.6 * board_scale), Color(ink.r, ink.g, ink.b, 0.7 * fade))

func _ease_out(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)

func _refresh() -> void:
	if instruction_label == null:
		queue_redraw()
		return
	var failed: bool = banner != ""
	var human_roll: bool = game.phase == GameScript.Phase.ROLL and game.current_player == 0 and not ai_running
	var human_build: bool = game.phase == GameScript.Phase.BUILD and game.current_player == 0 and not ai_running
	instruction_label.text = banner if failed else _prompt()
	instruction_label.add_theme_color_override("font_color", UiTheme.GOLD if failed else UiTheme.INK)
	if game.last_roll == 0:
		dice_label.text = "dados"
		dice_label.add_theme_font_size_override("font_size", 13)
		dice_parts.visible = false
		dice_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
		if dice_edge != null:
			dice_edge.border_color = UiTheme.BORDER
	else:
		dice_label.text = str(game.last_roll)
		dice_label.add_theme_font_size_override("font_size", 22)
		dice_parts.visible = true
		dice_parts.text = "%d+%d" % [game.die_a, game.die_b]
		var drought: bool = game.last_roll == 7
		dice_label.add_theme_color_override("font_color", Color("b42318") if drought else UiTheme.GOLD)
		if dice_edge != null:
			dice_edge.border_color = Color("b42318") if drought else UiTheme.GOLD
	score_label.text = "[color=#%s]Vos %d[/color]    [color=#%s]Vecino %d[/color]    meta %d" % [
		GameScript.PLAYER_COLOR[0].to_html(false), game.scores[0],
		GameScript.PLAYER_COLOR[1].to_html(false), game.scores[1],
		GameScript.WIN,
	]
	_paint_counts(you_counts, you_icons, 0)
	_paint_counts(rival_counts, rival_icons, 1)
	_mark_hands()
	if human_build:
		var piece := "Camino" if tool == "road" else ("Puesto" if tool == "settlement" else "Granja")
		var afford: bool = game.can_afford(0, tool)
		cost_label.text = "%s · %s" % [piece, game.fmt_cost(game.cost_of(0, tool))]
		cost_label.add_theme_color_override("font_color", UiTheme.INK_DIM if afford else UiTheme.GOLD)
	else:
		cost_label.text = ""
	rival_chart.text = "Vecino   " + _chart_line(1)
	var rate := int(game.trade_rate(0))
	trade_btn.text = "Cambiar %d:1" % rate if rate > 0 else "Cambiar"
	var tail := PackedStringArray()
	var from := maxi(0, game.log.size() - 3)
	for i in range(from, game.log.size()):
		tail.append(game.log[i])
	log_label.text = "\n".join(tail)
	roll_btn.disabled = not human_roll
	road_btn.disabled = not human_build
	set_btn.disabled = not human_build
	up_btn.disabled = not human_build
	end_btn.disabled = not human_build
	road_btn.text = ("● " if tool == "road" and human_build else "") + "Camino"
	set_btn.text = ("● " if tool == "settlement" and human_build else "") + "Puesto"
	up_btn.text = ("● " if tool == "upgrade" and human_build else "") + "Granja"
	UiTheme.paint(roll_btn, "primary" if human_roll else "quiet")
	UiTheme.paint(road_btn, _build_role("road", tool == "road"))
	UiTheme.paint(set_btn, _build_role("settlement", tool == "settlement"))
	UiTheme.paint(up_btn, _build_role("upgrade", tool == "upgrade"))
	UiTheme.paint(end_btn, "quiet")
	_explain_controls(human_roll, human_build)
	UiTheme.paint(restart_btn, "quiet")
	UiTheme.paint(menu_btn, "quiet")
	for i in track_btns.size():
		var open: bool = game.can_advance(0, i)
		track_btns[i].text = _track_caption(i, open)
		track_btns[i].disabled = not human_build
		var track_ink: Color = GameScript.TRACK_COLOR[i] if open else UiTheme.INK_DIM
		track_btns[i].add_theme_color_override("font_color", track_ink)
		track_btns[i].add_theme_color_override("font_hover_color", track_ink)
		track_btns[i].add_theme_color_override("font_pressed_color", track_ink)
	for i in give_btns.size():
		var ware := i >= 4
		var idx := i - 4 if ware else i
		var on := human_build and give_ware == ware and give_sel == idx
		give_btns[i].text = "●" if on else ""
		give_btns[i].disabled = not human_build
		UiTheme.paint(give_btns[i], "chip_on" if on else "chip")
	for i in take_btns.size():
		var ware := i >= 4
		var idx := i - 4 if ware else i
		var on := human_build and take_ware == ware and take_sel == idx
		take_btns[i].text = "●" if on else ""
		take_btns[i].disabled = not human_build
		UiTheme.paint(take_btns[i], "chip_on" if on else "chip")
	var deal_ready: bool = _trade_ready()
	trade_btn.text = _trade_deal()
	trade_btn.disabled = not human_build
	UiTheme.paint(trade_btn, "primary" if deal_ready else "chip")
	_paint_motion_btn()
	_watch_motion()
	_sync_table()
	queue_redraw()

func _paint_counts(counts: Array[Label], icons: Array[CanvasItem], player: int) -> void:
	if counts.size() < 7:
		return
	for i in 7:
		var value := int(game.hands[player][i]) if i < 4 else int(game.wares[player][i - 4])
		counts[i].text = str(value)
		if player == 0:
			counts[i].tooltip_text = "%s · %d" % [_good_name(i), value]
			_mark_badge(i, value)
		if i < icons.size():
			icons[i].modulate = Color(1, 1, 1, 1.0 if value > 0 else 0.4)
		var slot := player * 7 + i
		if slot < seen_counts.size() and seen_counts[slot] >= 0 and seen_counts[slot] != value:
			_pulse_count(counts[i])
		if slot < seen_counts.size():
			seen_counts[slot] = value

func _pulse_count(label: Label) -> void:
	if UiTheme.reduce_motion or label == null:
		return
	if label.has_meta("pulse"):
		var old: Variant = label.get_meta("pulse")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	label.pivot_offset = label.size * 0.5
	label.scale = Vector2.ONE
	var tw := create_tween()
	label.set_meta("pulse", tw)
	tw.tween_property(label, "scale", Vector2(1.14, 1.14), 0.07)
	tw.tween_property(label, "scale", Vector2.ONE, 0.12)

func _mark_hands() -> void:
	var live: bool = game.phase != GameScript.Phase.OVER
	for i in hand_blocks.size():
		var on: bool = live and i == int(game.current_player)
		hand_blocks[i].modulate = Color(1, 1, 1, 1.0 if on else 0.7)
		if i < hand_marks.size() and hand_marks[i].has_meta("edge"):
			var edge: StyleBoxFlat = hand_marks[i].get_meta("edge")
			var tone: Color = hand_marks[i].get_meta("tone")
			edge.border_color = UiTheme.GOLD if on else tone
		if i < hand_names.size():
			hand_names[i].text = GameScript.PLAYER_NAME[i] + (" · ahora" if on else "")
			var ink: Color = GameScript.PLAYER_COLOR[i] if on else UiTheme.INK_DIM
			hand_names[i].add_theme_color_override("font_color", ink)

func _load_art() -> void:
	for name in ["terreno_madera", "terreno_arcilla", "terreno_grano", "terreno_piedra"]:
		terrain_tex.append(load("res://art/%s.jpg" % name))
	lagoon_tex = load("res://art/terreno_laguna.jpg")
	if ResourceLoader.exists("res://art/mar_isla.jpg"):
		sea_tex = load("res://art/mar_isla.jpg")
	puesto_tex = _cut_plate("res://art/puesto.jpg")
	granja_tex = _cut_plate("res://art/granja.jpg")
	camino_tex = _cut_plate("res://art/camino.jpg")
	for name in ["icono_madera", "icono_arcilla", "icono_grano", "icono_piedra", "icono_papel", "icono_tela", "icono_moneda"]:
		card_tex.append(load("res://art/%s.jpg" % name))

func _hex_pts(h: Dictionary, grow: float, nudge: Vector2) -> PackedVector2Array:
	var center := HexGeom.hex_to_pixel(int(h.q), int(h.r))
	var screen_center := _to_screen(center)
	var pts := PackedVector2Array()
	for i in 6:
		var corner := _to_screen(HexGeom.corner(center, i))
		pts.append(screen_center + nudge + (corner - screen_center) * grow)
	return pts

func _draw_cover(tex: Texture2D, rect: Rect2) -> void:
	var sz := tex.get_size()
	if sz.x < 1.0 or sz.y < 1.0:
		draw_rect(rect, Color("1b4038"))
		return
	var fit := maxf(rect.size.x / sz.x, rect.size.y / sz.y)
	var drawn := sz * fit
	var origin := rect.position + (rect.size - drawn) * 0.5
	var u0 := (rect.position.x - origin.x) / drawn.x
	var v0 := (rect.position.y - origin.y) / drawn.y
	var u1 := u0 + rect.size.x / drawn.x
	var v1 := v0 + rect.size.y / drawn.y
	var pts := PackedVector2Array([
		rect.position,
		rect.position + Vector2(rect.size.x, 0),
		rect.position + rect.size,
		rect.position + Vector2(0, rect.size.y),
	])
	var uvs := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	var cols := PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE])
	draw_polygon(pts, cols, uvs, tex)

func _draw_path(a: Vector2, b: Vector2, owner: int) -> void:
	var delta := b - a
	var length := delta.length()
	if length < 1.0:
		return
	var thick := clampf(16.0 * board_scale, 8.0, 20.0)
	draw_line(a, b, GameScript.PLAYER_COLOR[owner], thick + 3.0, true)
	if camino_tex == null:
		draw_line(a, b, Color("a67c52"), thick, true)
		return
	var sz := camino_tex.get_size()
	draw_set_transform((a + b) * 0.5, delta.angle(), Vector2(length / sz.x, thick / sz.y))
	draw_texture(camino_tex, -sz * 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_token(p: Vector2, tex: Texture2D, col: Color, height: float) -> void:
	var base := p + Vector2(0, height * 0.12)
	draw_circle(base + Vector2(1.0, 2.0), height * 0.16, Color(0, 0, 0, 0.32))
	if tex == null:
		_draw_house(p, col, height * 0.42)
		_draw_seal(p + Vector2(height * 0.2, height * 0.12), col)
		return
	var aspect := tex.get_width() / float(tex.get_height())
	var w := height * aspect
	draw_texture_rect(tex, Rect2(p.x - w * 0.5, p.y - height * 0.82, w, height), false)
	_draw_seal(p + Vector2(w * 0.2, height * 0.05), col)

func _draw_seal(p: Vector2, col: Color) -> void:
	var radius := maxf(4.5, 5.6 * board_scale)
	draw_circle(p + Vector2(0.6, 1.0), radius, Color(0, 0, 0, 0.35))
	draw_circle(p, radius, col)
	draw_arc(p, radius, 0, TAU, 16, Color("2a1c10"), 1.15, true)

func _draw_peg(p: Vector2, radius: float) -> void:
	draw_circle(p, radius + 1.3, Color("2a1c10"))
	draw_circle(p, radius, Color("f6f1e4"))

func _cut_plate(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var loaded: Texture2D = load(path)
	var img := loaded.get_image()
	if img == null:
		return null
	img.convert(Image.FORMAT_RGBA8)
	var key := _corner_key(img)
	var w := img.get_width()
	var h := img.get_height()
	var min_x := w
	var min_y := h
	var max_x := 0
	var max_y := 0
	for y in h:
		for x in w:
			var c := img.get_pixel(x, y)
			var dist := sqrt(pow(c.r - key.r, 2.0) + pow(c.g - key.g, 2.0) + pow(c.b - key.b, 2.0))
			c.a = clampf((dist - 0.28) / 0.12, 0.0, 1.0)
			img.set_pixel(x, y, c)
			if c.a > 0.82:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x <= min_x or max_y <= min_y:
		return ImageTexture.create_from_image(img)
	min_x = maxi(0, min_x - 1)
	min_y = maxi(0, min_y - 1)
	max_x = mini(w - 1, max_x + 1)
	max_y = mini(h - 1, max_y + 1)
	return ImageTexture.create_from_image(img.get_region(Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)))

func _corner_key(img: Image) -> Color:
	var samples: Array[Vector2i] = [
		Vector2i(1, 1),
		Vector2i(img.get_width() - 2, 1),
		Vector2i(1, img.get_height() - 2),
		Vector2i(img.get_width() - 2, img.get_height() - 2),
	]
	var acc := Color(0, 0, 0, 0)
	for p in samples:
		acc += img.get_pixel(p.x, p.y)
	return acc / float(samples.size())

func _chart_line(player: int) -> String:
	var bits: PackedStringArray = []
	for t in 3:
		var lvl := int(game.progress[player][t])
		var dots := ""
		for i in 3:
			dots += "●" if i < lvl else "○"
		bits.append("%s %s" % [GameScript.TRACK_NAME[t], dots])
	return "   ".join(bits)

func _track_caption(track: int, open: bool) -> String:
	var lvl := int(game.progress[0][track])
	var dots := ""
	for i in 3:
		dots += "●" if i < lvl else "○"
	var perk: String
	var price: String
	if lvl >= 3:
		perk = GameScript.PERK_SHORT[track][2]
		price = "al máximo"
	else:
		perk = GameScript.PERK_SHORT[track][lvl]
		price = "%d %s" % [int(GameScript.PROG_COST[lvl]), GameScript.WARE_NAME[track]]
	var title: String = ("● " if open else "") + GameScript.TRACK_NAME[track]
	return "%s  %s\n%s · %s" % [title, dots, perk, price]

func _build_role(kind: String, armed: bool) -> String:
	if game.phase != GameScript.Phase.BUILD or game.current_player != 0 or ai_running:
		return "quiet"
	if armed:
		return "armed"
	if not game.can_afford(0, kind):
		return "short"
	return "quiet"

func _trade_ready() -> bool:
	if game.phase != GameScript.Phase.BUILD or game.current_player != 0 or ai_running:
		return false
	if give_ware != take_ware or give_sel == take_sel:
		return false
	var mercado := int(game.progress[0][GameScript.Track.MERCADO])
	if mercado <= 0 or (give_ware and mercado < 3):
		return false
	var rate := 2 if give_ware else int(game.trade_rate(0))
	var pile: Array = game.wares if give_ware else game.hands
	return int(pile[0][give_sel]) >= rate

func _trade_deal() -> String:
	if give_ware != take_ware:
		return "Cambiar"
	var rate := 2 if give_ware else int(game.trade_rate(0))
	if rate <= 0:
		return "Cambiar"
	var give_name: String = _good_name(give_sel + 4) if give_ware else _good_name(give_sel)
	var take_name: String = _good_name(take_sel + 4) if take_ware else _good_name(take_sel)
	return "%d %s → 1 %s" % [rate, give_name, take_name]

func _good_name(index: int) -> String:
	if index >= 4:
		return GameScript.WARE_NAME[index - 4]
	return GameScript.RES_NAME[index]

func _mark_badge(index: int, value: int) -> void:
	if index >= you_badges.size():
		return
	var kind := "plain"
	var yours: bool = game.phase == GameScript.Phase.BUILD and game.current_player == 0 and not ai_running
	if yours and index < 4:
		var need := int(game.cost_of(0, tool)[index])
		if need > 0 and value < need:
			kind = "short"
	if kind == "plain" and yours:
		var ware := index >= 4
		var idx := index - 4 if ware else index
		if give_ware == ware and give_sel == idx:
			kind = "give"
		elif take_ware == ware and take_sel == idx and give_ware == take_ware:
			kind = "take"
	you_badges[index].add_theme_stylebox_override("panel", _count_box(kind))
	if index < you_counts.size():
		you_counts[index].add_theme_color_override("font_color", UiTheme.INK_ON_GOLD if kind == "give" else UiTheme.INK)

func _count_box(kind: String) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.set_corner_radius_all(4)
	box.bg_color = UiTheme.PANEL
	if kind == "short":
		box.bg_color = Color("3a2420")
		box.border_color = Color("b42318")
		box.set_border_width_all(1)
	elif kind == "give":
		box.bg_color = UiTheme.GOLD
	elif kind == "take":
		box.border_color = UiTheme.GOLD
		box.set_border_width_all(1)
	return box

func _trade_letter(ware: bool, idx: int) -> String:
	if ware:
		return GameScript.WARE_LETTER[idx]
	return GameScript.RES_LETTER[idx]

func _on_advance(track: int) -> void:
	if ai_running or game.current_player != 0:
		return
	_after(game.advance(0, track))

func _on_trade() -> void:
	if ai_running or game.current_player != 0:
		return
	if give_ware != take_ware:
		_flash("Cambiá primas con primas, o mercancías con mercancías.")
		return
	_after(game.trade(0, give_sel, take_sel, give_ware))

func _pick_give(index: int) -> void:
	give_ware = index >= 4
	give_sel = index - 4 if give_ware else index
	_refresh()

func _pick_take(index: int) -> void:
	take_ware = index >= 4
	take_sel = index - 4 if take_ware else index
	_refresh()

func _hud_width(view: Vector2) -> float:
	return clampf(view.x * 0.26, 280.0, 336.0)

func _trade_splits(view: Vector2) -> bool:
	var inner := view.x - _hud_width(view) - 56.0
	return inner < 78.0 + 7.0 * 48.0 + 160.0

func _chart_estimate(view: Vector2) -> float:
	var h := 90.0
	if view.y >= 660.0:
		h += 24.0
	h += 96.0
	if _trade_splits(view):
		h += 48.0
	return h

func _chart_height(view: Vector2) -> float:
	if chart_panel != null and chart_panel.offset_top < -40.0:
		return -chart_panel.offset_top
	return _chart_estimate(view)

func _layout_chrome() -> void:
	var view := get_viewport_rect().size
	if hud_panel == null or view.x < 8.0 or view.y < 8.0:
		_layout_board()
		return
	var hud := _hud_width(view)
	var chart := _chart_height(view)
	hud_panel.offset_left = -(hud + 12.0)
	chart_panel.offset_right = -(hud + 24.0)
	chart_panel.offset_top = -chart
	if rival_chart != null:
		rival_chart.visible = view.y >= 660.0
	_layout_trade(_trade_splits(view))
	var short := view.y < 660.0
	_fit_hands(short)
	_fit_hud(short)
	if hud_box != null:
		hud_box.add_theme_constant_override("separation", 3 if short else 6)
	call_deferred("_fit_chart")
	_layout_board()

func _fit_chart() -> void:
	if chart_box == null or chart_panel == null:
		return
	var view := get_viewport_rect().size
	var need := chart_box.get_combined_minimum_size().y + 16.0
	var chart := clampf(need, 140.0, view.y * 0.40)
	chart_panel.offset_top = -chart
	_layout_board()

func _layout_trade(split: bool) -> void:
	if trade_btn == null or take_row == null or deal_row == null:
		return
	var host: Node = deal_row if split else take_row
	if trade_btn.get_parent() != host:
		trade_btn.get_parent().remove_child(trade_btn)
		host.add_child(trade_btn)
	deal_row.visible = split
	trade_btn.custom_minimum_size = Vector2(0.0 if split else 156.0, 44.0)
	trade_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if split else Control.SIZE_SHRINK_END

func _fit_hands(short: bool) -> void:
	var yours := 40 if short else 46
	var rival := 32 if short else 34
	for i in hand_rows.size():
		var h := yours if i == 0 else rival
		for child in hand_rows[i].get_children():
			if child is Panel:
				(child as Panel).custom_minimum_size.y = h

func _fit_hud(short: bool) -> void:
	if instruction_label != null:
		instruction_label.custom_minimum_size.y = 40.0 if short else 48.0
	if score_label != null:
		score_label.custom_minimum_size.y = 24.0 if short else 36.0
	if roll_btn != null:
		roll_btn.custom_minimum_size.y = 44.0 if short else 48.0
	if log_label != null:
		log_label.custom_minimum_size.y = 18.0 if short else 36.0
		log_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_place_motion(short)

func _place_motion(short: bool) -> void:
	if motion_btn == null or exit_row == null or hud_box == null:
		return
	var host: Node = exit_row if short else hud_box
	if motion_btn.get_parent() != host:
		motion_btn.reparent(host)
		if not short and log_label != null:
			hud_box.move_child(motion_btn, log_label.get_index())
	motion_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL if short else Control.SIZE_FILL
	_paint_motion_btn()

func _layout_board() -> void:
	if game == null or game.v_pos.is_empty():
		return
	var area := _board_area()
	var min_p := Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in game.v_pos:
		min_p = min_p.min(p)
		max_p = max_p.max(p)
	var bounds := max_p - min_p
	if bounds.x < 1.0 or bounds.y < 1.0:
		return
	var pad := 28.0
	var avail := area.size - Vector2(pad * 2.0, pad * 2.0)
	board_scale = minf(avail.x / bounds.x, avail.y / bounds.y)
	board_origin = area.position + (area.size - bounds * board_scale) * 0.5 - min_p * board_scale
	_place_table()
	queue_redraw()

func _build_table() -> void:
	table_host = SubViewportContainer.new()
	table_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	table_host.stretch = true
	add_child(table_host)
	table_view = SubViewport.new()
	table_view.own_world_3d = true
	table_view.handle_input_locally = false
	table_view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	table_view.msaa_3d = Viewport.MSAA_2X
	table_view.positional_shadow_atlas_size = 2048
	table_view.size = Vector2i(800, 480)
	table_host.add_child(table_view)
	table = TableBoard.new()
	table_view.add_child(table)
	var body: Font = ThemeDB.fallback_font
	if ResourceLoader.exists("res://fonts/Nunito-Bold.ttf"):
		body = load("res://fonts/Nunito-Bold.ttf")
	table.bind(game, terrain_tex, lagoon_tex, sea_tex, body)

func _plate_rect() -> Rect2:
	var view := get_viewport_rect().size
	var frame := Rect2(12, 12, maxf(80.0, view.x - _hud_width(view) - 36.0), maxf(80.0, view.y - _chart_height(view) - 24.0))
	return frame.grow(-10)

func _place_table() -> void:
	if table_host == null or table == null:
		return
	var plate := _plate_rect()
	table_host.position = plate.position
	table_host.size = plate.size
	var sz := Vector2i(maxi(int(plate.size.x), 8), maxi(int(plate.size.y), 8))
	if table_view.size != sz:
		table_view.size = sz
	if plate.size.y > 1.0:
		table.fit_camera(plate.size.x / plate.size.y)

func _pointer_board(screen: Vector2) -> Vector2:
	if table == null or table_view == null:
		return _to_board(screen)
	var plate := _plate_rect()
	if not plate.has_point(screen):
		return Vector2(99999, 99999)
	var vp := (screen - plate.position) / plate.size * Vector2(table_view.size)
	return table.plane_hit(vp)

func _sync_table() -> void:
	if table == null or game == null:
		return
	var pegs: Array = []
	var ups: Array = []
	for v in game.v_pos.size():
		if _hint_vertex(int(v)):
			pegs.append(int(v))
		elif _hint_upgrade(int(v)):
			ups.append(int(v))
	var ghosts: Array = []
	for ek in game.edges.keys():
		if _hint_road(String(ek)):
			ghosts.append(String(ek))
	table.sync(game, pegs, ghosts, ups)

func _board_area() -> Rect2:
	var view := get_viewport_rect().size
	var hud := _hud_width(view)
	var chart := _chart_height(view)
	return Rect2(28, 28, maxf(100.0, view.x - hud - 52.0), maxf(100.0, view.y - chart - 52.0))

func _to_screen(p: Vector2) -> Vector2:
	return board_origin + p * board_scale

func _to_board(screen: Vector2) -> Vector2:
	return (screen - board_origin) / board_scale

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	UiTheme.install(root)

	hud_panel = Panel.new()
	var panel := hud_panel
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = -328.0
	panel.offset_right = -12.0
	panel.offset_top = 12.0
	panel.offset_bottom = -12.0
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	root.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = 12
	scroll.offset_top = 10
	scroll.offset_right = -8
	scroll.offset_bottom = -10
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)

	hud_box = VBoxContainer.new()
	var box := hud_box
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 6)
	scroll.add_child(box)

	var title := _label("Lindero", 22, false)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	if UiTheme.display_font != null:
		title.add_theme_font_override("font", UiTheme.display_font)
	box.add_child(title)
	var rule := ColorRect.new()
	rule.custom_minimum_size = Vector2(56, 2)
	rule.color = UiTheme.BRASS
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)
	instruction_label = _label("", 16)
	instruction_label.custom_minimum_size = Vector2(0, 48)
	box.add_child(instruction_label)
	var status := HBoxContainer.new()
	status.alignment = BoxContainer.ALIGNMENT_CENTER
	status.add_theme_constant_override("separation", 8)
	score_label = RichTextLabel.new()
	score_label.bbcode_enabled = true
	score_label.fit_content = true
	score_label.scroll_active = false
	score_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	score_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	score_label.custom_minimum_size = Vector2(0, 36)
	score_label.add_theme_font_size_override("normal_font_size", 16)
	score_label.add_theme_color_override("default_color", UiTheme.INK)
	status.add_child(score_label)
	var dice_col := VBoxContainer.new()
	dice_col.alignment = BoxContainer.ALIGNMENT_CENTER
	dice_col.add_theme_constant_override("separation", 0)
	dice_label = _label("—", 22, false)
	dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_parts = _label("", 12, false)
	dice_parts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_parts.add_theme_color_override("font_color", UiTheme.INK_DIM)
	dice_col.add_child(dice_label)
	dice_col.add_child(dice_parts)
	dice_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dice_edge = StyleBoxFlat.new()
	dice_edge.bg_color = Color("241c18")
	dice_edge.border_color = UiTheme.BORDER
	dice_edge.set_border_width_all(1)
	dice_edge.set_corner_radius_all(8)
	dice_edge.content_margin_left = 8
	dice_edge.content_margin_right = 8
	dice_edge.content_margin_top = 1
	dice_edge.content_margin_bottom = 1
	dice_well = Panel.new()
	dice_well.custom_minimum_size = Vector2(64, 44)
	dice_well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	dice_well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dice_well.add_theme_stylebox_override("panel", dice_edge)
	dice_col.set_anchors_preset(Control.PRESET_FULL_RECT)
	dice_well.add_child(dice_col)
	status.add_child(dice_well)
	box.add_child(status)
	seen_counts.clear()
	for _i in 14:
		seen_counts.append(-1)
	box.add_child(_hand_block(0, you_counts, you_icons, 46))
	box.add_child(_hand_block(1, rival_counts, rival_icons, 34))
	cost_label = _label("", 13)
	cost_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	box.add_child(cost_label)

	roll_btn = _button("Tirar dados")
	road_btn = _button("Camino")
	set_btn = _button("Puesto")
	up_btn = _button("Granja")
	end_btn = _button("Terminar turno")
	restart_btn = _button("Otra partida")
	menu_btn = _button("Menú")
	roll_btn.pressed.connect(_on_roll)
	road_btn.pressed.connect(_set_tool.bind("road"))
	set_btn.pressed.connect(_set_tool.bind("settlement"))
	up_btn.pressed.connect(_set_tool.bind("upgrade"))
	end_btn.pressed.connect(_on_end_turn)
	restart_btn.pressed.connect(_on_restart)
	menu_btn.pressed.connect(_on_menu)
	roll_btn.custom_minimum_size = Vector2(0, 48)
	end_btn.custom_minimum_size = Vector2(0, 44)
	restart_btn.custom_minimum_size = Vector2(0, 44)
	menu_btn.custom_minimum_size = Vector2(0, 44)
	restart_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	for btn in [road_btn, set_btn, up_btn]:
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tools.add_child(btn)
	box.add_child(roll_btn)
	box.add_child(tools)
	box.add_child(end_btn)
	exit_row = HBoxContainer.new()
	exit_row.add_theme_constant_override("separation", 6)
	exit_row.add_child(restart_btn)
	exit_row.add_child(menu_btn)
	box.add_child(exit_row)
	motion_btn = _button("Menos movimiento")
	motion_btn.custom_minimum_size = Vector2(0, 44)
	motion_btn.tooltip_text = "Atenúa dados, fichas, caminos y el cambio de turno."
	motion_btn.pressed.connect(_on_motion)
	box.add_child(motion_btn)
	_build_chart(root)

	log_label = _label("", 13)
	log_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	log_label.custom_minimum_size = Vector2(0, 36)
	box.add_child(log_label)

func _build_chart(root: Control) -> void:
	chart_panel = Panel.new()
	var panel := chart_panel
	panel.anchor_left = 0.0
	panel.anchor_right = 1.0
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_right = -340.0
	panel.offset_top = -162.0
	panel.offset_bottom = -12.0
	panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	root.add_child(panel)

	chart_box = VBoxContainer.new()
	var box := chart_box
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 12
	box.offset_top = 8
	box.offset_right = -12
	box.offset_bottom = -8
	box.add_theme_constant_override("separation", 3)
	panel.add_child(box)

	var title := _label("Tabla de progreso", 16, false)
	box.add_child(title)

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	box.add_child(cols)
	for i in 3:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 44)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.add_theme_font_size_override("font_size", 15)
		btn.add_theme_color_override("font_color", GameScript.TRACK_COLOR[i])
		btn.add_theme_color_override("font_hover_color", GameScript.TRACK_COLOR[i])
		btn.add_theme_color_override("font_pressed_color", GameScript.TRACK_COLOR[i])
		btn.add_theme_color_override("font_focus_color", UiTheme.GOLD)
		btn.add_theme_color_override("font_disabled_color", UiTheme.INK_DIM)
		btn.add_theme_stylebox_override("normal", UiTheme.well(GameScript.TRACK_COLOR[i], Color("2c241c")))
		btn.add_theme_stylebox_override("hover", UiTheme.well(GameScript.TRACK_COLOR[i], Color("3d3228")))
		btn.add_theme_stylebox_override("pressed", UiTheme.well(GameScript.TRACK_COLOR[i], Color("1a1510")))
		btn.add_theme_stylebox_override("focus", UiTheme.well(UiTheme.GOLD, Color("2c241c")))
		btn.add_theme_stylebox_override("disabled", UiTheme.well(Color("4a4036"), Color("241c16")))
		btn.pressed.connect(_on_advance.bind(i))
		cols.add_child(btn)
		track_btns.append(btn)

	rival_chart = _label("", 14, false)
	box.add_child(rival_chart)

	give_row = HBoxContainer.new()
	give_row.alignment = BoxContainer.ALIGNMENT_CENTER
	give_row.add_theme_constant_override("separation", 4)
	box.add_child(give_row)
	give_row.add_child(_label("Doy", 14, false))
	for i in 7:
		var btn := _tiny("", card_tex[i] if i < card_tex.size() else null)
		btn.tooltip_text = _good_name(i)
		btn.pressed.connect(_pick_give.bind(i))
		give_row.add_child(btn)
		give_btns.append(btn)
	take_row = HBoxContainer.new()
	take_row.alignment = BoxContainer.ALIGNMENT_CENTER
	take_row.add_theme_constant_override("separation", 4)
	box.add_child(take_row)
	take_row.add_child(_label("Quiero", 14, false))
	for i in 7:
		var btn := _tiny("", card_tex[i] if i < card_tex.size() else null)
		btn.tooltip_text = _good_name(i)
		btn.pressed.connect(_pick_take.bind(i))
		take_row.add_child(btn)
		take_btns.append(btn)
	deal_row = HBoxContainer.new()
	deal_row.alignment = BoxContainer.ALIGNMENT_CENTER
	deal_row.visible = false
	box.add_child(deal_row)
	trade_btn = _tiny("Cambiar")
	trade_btn.custom_minimum_size = Vector2(156, 44)
	trade_btn.pressed.connect(_on_trade)
	take_row.add_child(trade_btn)

func _tiny(text: String, icon: Texture2D = null) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_ALL
	btn.custom_minimum_size = Vector2(44, 44)
	btn.add_theme_font_size_override("font_size", 14)
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 26)
		btn.add_theme_constant_override("icon_max_height", 26)
	return btn

func _hand_block(player: int, counts: Array[Label], icons: Array[CanvasItem], height: int) -> VBoxContainer:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 2)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	var mark := _swatch(GameScript.PLAYER_COLOR[player])
	head.add_child(mark)
	var title := _label(GameScript.PLAYER_NAME[player], 14, false)
	title.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[player])
	head.add_child(title)
	wrap.add_child(head)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	hand_rows.append(row)
	var names: PackedStringArray = PackedStringArray(GameScript.RES_NAME) + PackedStringArray(GameScript.WARE_NAME)
	for i in card_tex.size():
		if i == 4:
			var gap := Control.new()
			gap.custom_minimum_size = Vector2(5, 0)
			row.add_child(gap)
		var badges: Array[Panel] = you_badges if player == 0 else rival_badges
		row.add_child(_card(card_tex[i], names[i], counts, icons, badges, height))
	wrap.add_child(row)
	hand_blocks.append(wrap)
	hand_names.append(title)
	hand_marks.append(mark)
	return wrap

func _card(tex: Texture2D, tip: String, counts: Array[Label], icons: Array[CanvasItem], badges: Array[Panel], height: int) -> Panel:
	var card := Panel.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, height)
	card.tooltip_text = tip
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_theme_stylebox_override("panel", UiTheme.paper_box())
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = -2
	icon.offset_bottom = -2
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	icons.append(icon)
	var badge := Panel.new()
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.offset_left = -20
	badge.offset_top = -16
	badge.offset_right = -2
	badge.offset_bottom = -2
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = UiTheme.PANEL
	badge_box.border_color = UiTheme.BORDER
	badge_box.set_border_width_all(1)
	badge_box.set_corner_radius_all(3)
	badge.add_theme_stylebox_override("panel", badge_box)
	card.add_child(badge)
	badges.append(badge)
	var count := Label.new()
	count.text = "0"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", UiTheme.INK)
	badge.add_child(count)
	counts.append(count)
	return card

func _swatch(col: Color) -> Panel:
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(14, 14)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var edge := StyleBoxFlat.new()
	edge.bg_color = col
	edge.border_color = col
	edge.set_border_width_all(2)
	edge.set_corner_radius_all(2)
	mark.add_theme_stylebox_override("panel", edge)
	mark.set_meta("edge", edge)
	mark.set_meta("tone", col)
	return mark

func _label(text: String, size: int, wrap: bool = true) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", Color("f3ead7"))
	return lab

func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 16)
	btn.focus_mode = Control.FOCUS_ALL
	return btn
