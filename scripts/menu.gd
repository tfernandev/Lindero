extends Control

const UiTheme := preload("res://scripts/ui_theme.gd")
const GameScript := preload("res://scripts/match.gd")
const MATCH_SCENE := "res://scenes/main.tscn"
const BG_PATH := "res://art/menu_isla.jpg"
const PLATE := Color("f4efe4")
const PLATE_INK := Color("2a1c10")
const PLATE_DIM := Color("3a2e24")

var bg: TextureRect
var light_mat: ShaderMaterial
var column: Panel
var home: Control
var guide: Control
var title: Label
var crest_row: Control
var play_btn: Button
var guide_btn: Button
var quit_btn: Button
var back_btn: Button
var drift := 0.0

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	UiTheme.install(self)
	_build_world()
	_build_column()
	get_viewport().size_changed.connect(_layout)
	UiTheme.fit_window(get_window())
	_show_home()
	column.modulate.a = 0.0
	var intro := create_tween()
	intro.tween_property(column, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	play_btn.grab_focus()

func _process(delta: float) -> void:
	drift += delta
	if bg != null:
		var sway := Vector2(sin(drift * 0.17) * 16.0, cos(drift * 0.13) * 10.0)
		bg.offset_left = -64.0 + sway.x
		bg.offset_top = -64.0 + sway.y
		bg.offset_right = 64.0 + sway.x
		bg.offset_bottom = 64.0 + sway.y
	if light_mat != null:
		light_mat.set_shader_parameter("shift", 0.68 + sin(drift * 0.32) * 0.035)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and guide.visible:
		_show_home()
		get_viewport().set_input_as_handled()

func _build_world() -> void:
	var clip := Control.new()
	clip.set_anchors_preset(Control.PRESET_FULL_RECT)
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)

	bg = TextureRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	if ResourceLoader.exists(BG_PATH):
		bg.texture = load(BG_PATH)
	clip.add_child(bg)

	var vignette := ColorRect.new()
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.material = _shader_mat(
		"shader_type canvas_item;\nvoid fragment() {\n\tvec2 p = UV - vec2(0.72, 0.42);\n\tfloat d = length(p * vec2(1.05, 0.86));\n\tfloat v = smoothstep(0.28, 0.92, d);\n\tCOLOR = vec4(0.04, 0.03, 0.02, v * 0.5);\n}\n"
	)
	add_child(vignette)

	var light := ColorRect.new()
	light.set_anchors_preset(Control.PRESET_FULL_RECT)
	light.mouse_filter = Control.MOUSE_FILTER_IGNORE
	light_mat = _shader_mat(
		"shader_type canvas_item;\nuniform float shift = 0.68;\nvoid fragment() {\n\tfloat band = smoothstep(0.14, 0.0, abs(UV.x - shift));\n\tfloat down = smoothstep(1.0, 0.12, UV.y);\n\tCOLOR = vec4(1.0, 0.9, 0.68, band * down * 0.13);\n}\n"
	)
	light.material = light_mat
	add_child(light)

func _build_column() -> void:
	column = Panel.new()
	column.mouse_filter = Control.MOUSE_FILTER_STOP
	column.add_theme_stylebox_override("panel", _plate())
	add_child(column)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_bottom", 24)
	column.add_child(margin)

	home = _home_block()
	guide = _guide_block()
	margin.add_child(home)
	margin.add_child(guide)
	_crop_marks(column)

func _home_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 8)

	crest_row = CenterContainer.new()
	crest_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest_row.add_child(SurveyMark.new())
	box.add_child(crest_row)

	title = Label.new()
	title.text = "Lindero"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", PLATE_INK)
	if UiTheme.display_font != null:
		title.add_theme_font_override("font", UiTheme.display_font)
	box.add_child(title)

	box.add_child(_rule(96))

	var line := Label.new()
	line.text = "Cuatro cosechas en una isla."
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.add_theme_font_size_override("font_size", 16)
	line.add_theme_color_override("font_color", PLATE_DIM)
	box.add_child(line)

	box.add_child(_harvests())

	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(gap)

	play_btn = _verb("Jugar", 48)
	guide_btn = _verb("Cómo se juega", 44)
	quit_btn = _verb("Salir", 44)
	play_btn.pressed.connect(_on_play)
	guide_btn.pressed.connect(_show_guide)
	quit_btn.pressed.connect(_on_quit)
	UiTheme.paint(play_btn, "primary")
	UiTheme.paint(guide_btn, "quiet")
	UiTheme.paint(quit_btn, "quiet")
	box.add_child(play_btn)
	box.add_child(guide_btn)
	box.add_child(quit_btn)
	return box

func _guide_block() -> Control:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 12)
	box.visible = false

	var heading := Label.new()
	heading.text = "Cómo se juega"
	heading.add_theme_font_size_override("font_size", 22)
	heading.add_theme_color_override("font_color", PLATE_INK)
	var bold := UiTheme._font("res://fonts/Nunito-Bold.ttf")
	if bold != null:
		heading.add_theme_font_override("font", bold)
	box.add_child(heading)
	box.add_child(_rule(64))

	box.add_child(_rule_block("Dados", "El 6 y el 8 producen más. Si sale 7, hay sequía y nadie cobra."))
	box.add_child(_rule_block("Construir", "Camino: 1 madera y 1 arcilla. Puesto: una de cada prima, sin tocar otro. Granja: 2 grano y 2 piedra."))
	box.add_child(_rule_block("Progreso", "Papel, tela y moneda suben el Taller, el Mercado y el Consejo. Gana quien llega a 5."))

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	box.add_child(gap)

	back_btn = _verb("Volver", 44)
	back_btn.pressed.connect(_show_home)
	UiTheme.paint(back_btn, "quiet")
	box.add_child(back_btn)
	return box

func _harvests() -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in GameScript.RES_NAME.size():
		var col := VBoxContainer.new()
		col.mouse_filter = Control.MOUSE_FILTER_IGNORE
		col.add_theme_constant_override("separation", 2)
		col.alignment = BoxContainer.ALIGNMENT_CENTER
		var chip := HarvestMark.new()
		chip.fill = GameScript.RES_COLOR[i]
		col.add_child(chip)
		var name := Label.new()
		name.text = GameScript.RES_NAME[i]
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name.add_theme_font_size_override("font_size", 13)
		name.add_theme_color_override("font_color", PLATE_DIM)
		col.add_child(name)
		row.add_child(col)
	return row

func _rule_block(heading: String, body: String) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 3)
	var bold := UiTheme._font("res://fonts/Nunito-Bold.ttf")
	var h := Label.new()
	h.text = heading
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", PLATE_INK)
	if bold != null:
		h.add_theme_font_override("font", bold)
	box.add_child(h)
	var copy := Label.new()
	copy.text = body
	copy.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_theme_font_size_override("font_size", 15)
	copy.add_theme_color_override("font_color", PLATE_DIM)
	box.add_child(copy)
	return box

func _rule(width: float) -> Control:
	var host := CenterContainer.new()
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bar := ColorRect.new()
	bar.custom_minimum_size = Vector2(width, 2)
	bar.color = UiTheme.BRASS
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bar)
	return host

func _plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PLATE
	box.border_color = UiTheme.BRASS
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.shadow_color = Color(0, 0, 0, 0.4)
	box.shadow_size = 18
	box.shadow_offset = Vector2(0, 8)
	return box

func _crop_marks(host: Control) -> void:
	var marks := [
		[0.0, 0.0, 12.0, 28.0, 12.0, 14.0],
		[0.0, 0.0, 12.0, 14.0, 12.0, 28.0],
		[1.0, 0.0, -28.0, -12.0, 12.0, 14.0],
		[1.0, 0.0, -14.0, -12.0, 12.0, 28.0],
		[0.0, 1.0, 12.0, 28.0, -14.0, -12.0],
		[0.0, 1.0, 12.0, 14.0, -28.0, -12.0],
		[1.0, 1.0, -28.0, -12.0, -14.0, -12.0],
		[1.0, 1.0, -14.0, -12.0, -28.0, -12.0],
	]
	for mark in marks:
		var bar := ColorRect.new()
		bar.color = PLATE_INK
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.anchor_left = float(mark[0])
		bar.anchor_right = float(mark[0])
		bar.anchor_top = float(mark[1])
		bar.anchor_bottom = float(mark[1])
		bar.offset_left = float(mark[2])
		bar.offset_right = float(mark[3])
		bar.offset_top = float(mark[4])
		bar.offset_bottom = float(mark[5])
		host.add_child(bar)

func _verb(text: String, height: int) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, height)
	btn.focus_mode = Control.FOCUS_ALL
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return btn

func _layout() -> void:
	if UiTheme.fit_window(get_window()):
		return
	var view := get_viewport_rect().size
	if view.x < 8.0 or view.y < 8.0:
		return
	var margin_x := clampf(view.x * 0.045, 16.0, 72.0)
	var col_w := clampf(view.x * 0.34, 300.0, 420.0)
	col_w = minf(col_w, view.x - margin_x * 2.0)
	var short := view.y < 680.0
	if crest_row != null:
		crest_row.visible = home.visible and not short
	var col_h := minf(view.y - 24.0, 580.0 if home.visible else 480.0)
	column.anchor_left = 0.0
	column.anchor_right = 0.0
	column.anchor_top = 0.5
	column.anchor_bottom = 0.5
	column.offset_left = margin_x
	column.offset_right = margin_x + col_w
	column.offset_top = -col_h * 0.5
	column.offset_bottom = col_h * 0.5
	if title != null:
		var least := 32.0 if view.y < 640.0 else 40.0
		title.add_theme_font_size_override("font_size", int(clampf(view.y * 0.074, least, 58.0)))

func _show_home() -> void:
	guide.visible = false
	home.visible = true
	_layout()
	if play_btn != null:
		play_btn.grab_focus()

func _show_guide() -> void:
	home.visible = false
	guide.visible = true
	_layout()
	back_btn.grab_focus()

func _on_play() -> void:
	get_tree().change_scene_to_file(MATCH_SCENE)

func _on_quit() -> void:
	get_tree().quit()

func _shader_mat(code: String) -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


class SurveyMark extends Control:
	var _tex: Array[Texture2D] = []

	func _ready() -> void:
		custom_minimum_size = Vector2(176, 108)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		for path in ["res://art/terreno_madera.jpg", "res://art/terreno_arcilla.jpg", "res://art/terreno_grano.jpg", "res://art/terreno_piedra.jpg"]:
			_tex.append(load(path) if ResourceLoader.exists(path) else null)

	func _draw() -> void:
		var s := 22.0
		var cells: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, -1)]
		var fills: Array[Color] = [Color("2f7a3e"), Color("b85a32"), Color("d4a437"), Color("7e8288")]
		var shift := Vector2.ZERO
		for cell in cells:
			shift += _axial(cell, s)
		var origin := size * 0.5 - shift / float(cells.size())
		var centers: Array[Vector2] = []
		for i in cells.size():
			var center := origin + _axial(cells[i], s)
			centers.append(center)
			_fill_hex(center, s - 1.4, _tex[i] if i < _tex.size() else null, fills[i])
		for center in centers:
			var outline := _hex(center, s - 0.3)
			outline.append(outline[0])
			draw_polyline(outline, Color("2a1c10"), 1.6, true)
		var road_a := _corner(centers[0], s - 0.2, 1)
		var road_b := _corner(centers[0], s - 0.2, 2)
		draw_line(road_a, road_b, Color("c4a07a"), 5.0)
		draw_line(road_a, road_b, Color("e39b3b"), 1.8)
		var peg := _corner(centers[3], s + 1.5, 5)
		draw_circle(peg, 3.4, Color("f4efe4"))
		draw_arc(peg, 3.4, 0.0, TAU, 16, Color("2a1c10"), 1.2, true)

	func _fill_hex(center: Vector2, hex_size: float, tex: Texture2D, fallback: Color) -> void:
		var pts := _hex(center, hex_size)
		if tex == null:
			draw_colored_polygon(pts, fallback)
			return
		var colors := PackedColorArray()
		var uvs := PackedVector2Array()
		for point in pts:
			colors.append(Color.WHITE)
			uvs.append(Vector2(0.5, 0.5) + (point - center) / (hex_size * 2.15))
		draw_polygon(pts, colors, uvs, tex)

	func _axial(qr: Vector2i, hex_size: float) -> Vector2:
		return Vector2(
			hex_size * sqrt(3.0) * (float(qr.x) + float(qr.y) * 0.5),
			hex_size * 1.5 * float(qr.y)
		)

	func _hex(center: Vector2, hex_size: float) -> PackedVector2Array:
		var pts := PackedVector2Array()
		for i in 6:
			var ang := deg_to_rad(60.0 * float(i) - 30.0)
			pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
		return pts

	func _corner(center: Vector2, hex_size: float, index: int) -> Vector2:
		var ang := deg_to_rad(60.0 * float(index) - 30.0)
		return center + Vector2(cos(ang), sin(ang)) * hex_size


class HarvestMark extends Control:
	var fill := Color("2f7a3e")

	func _ready() -> void:
		custom_minimum_size = Vector2(44, 40)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5 + Vector2(0, -2)
		var hex_size := 15.0
		var pts := PackedVector2Array()
		for i in 6:
			var ang := deg_to_rad(60.0 * float(i) - 30.0)
			pts.append(center + Vector2(cos(ang), sin(ang)) * hex_size)
		draw_colored_polygon(pts, fill)
		pts.append(pts[0])
		draw_polyline(pts, Color("2a1c10"), 1.25, true)
