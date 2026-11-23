extends Control
class_name GameMenuDropdown

## Menú superior de partida — identidad “Lindero Isla”.
## Solo emite acciones cableadas. Ítems sin backend quedan como “Pronto”.

signal motion_pressed
signal restart_pressed
signal resume_pressed
signal menu_pressed
signal guide_pressed
signal hand_pressed
signal build_pressed
signal trade_pressed
signal end_turn_pressed
signal open_changed(is_open: bool)

const UiTheme := preload("res://scripts/ui_theme.gd")
const AnimUtil := preload("res://scripts/anim_util.gd")
const UiIcons := preload("res://scripts/ui_icons.gd")

const PANEL_W := 300.0
const TOKEN_H := 52.0
const WOOD_TEX := "res://art/terreno_madera.jpg"
const PAPER_TEX := "res://art/icono_papel.jpg"
const COIN_TEX := "res://art/icono_moneda.jpg"
const CLOTH_TEX := "res://art/icono_tela.jpg"
const ROAD_TEX := "res://art/camino.jpg"
const ISLA_TEX := "res://art/menu_isla.jpg"
const GRAIN_TEX := "res://art/icono_grano.jpg"
const SHEEP_TEX := "res://art/icono_ovejas.jpg"

var motion_btn: Button
var restart_btn: Button
var resume_btn: Button
var to_menu_btn: Button
var guide_btn: Button

var _open := false
var _dim: ColorRect
var _panel: Panel
var _banner_lab: Label
var _chevron: _BrassMark
var _tokens: Array[Control] = []
var _tw: Tween
var _pulse_tw: Tween
var _seq := 0
var _calm := false
var _wood: Texture2D
var _icons: Dictionary = {}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80
	visible = true
	_load_art()
	_build()
	_apply_closed_instant()


func is_open() -> bool:
	return _open


func set_calm(on: bool) -> void:
	_calm = on
	if motion_btn != null:
		motion_btn.text = "Calma activa" if on else "Menos movimiento"
		var ink: Color = UiTheme.GOLD if on else UiTheme.INK_SOFT
		motion_btn.add_theme_color_override("font_color", ink)
		motion_btn.add_theme_color_override("font_hover_color", UiTheme.GOLD)
	_refresh_motion_token()


func open_menu() -> void:
	if _open:
		return
	_open = true
	_seq += 1
	var token := _seq
	_kill_tween()
	_dim.visible = true
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.visible = true
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_panel()
	if _chevron != null:
		_chevron.open = true
		_chevron.queue_redraw()
	open_changed.emit(true)
	if UiTheme.reduce_motion:
		_dim.modulate.a = 1.0
		_panel.modulate.a = 1.0
		_panel.scale = Vector2.ONE
		_panel.position.y = _rest_y()
		for t in _tokens:
			t.modulate.a = 1.0
			t.position.x = 0.0
		return
	_dim.modulate.a = 0.0
	_panel.modulate.a = 0.0
	_panel.scale = Vector2(0.96, 0.92)
	_panel.pivot_offset = Vector2(PANEL_W * 0.15, 0.0)
	_panel.position.y = _rest_y() - 14.0
	for t in _tokens:
		t.modulate.a = 0.0
		t.position.x = -10.0
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_dim, "modulate:a", 1.0, 0.18)
	_tw.tween_property(_panel, "modulate:a", 1.0, 0.2)
	_tw.tween_property(_panel, "scale", Vector2.ONE, 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.tween_property(_panel, "position:y", _rest_y(), 0.24).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_tw.set_parallel(false)
	for i in _tokens.size():
		if token != _seq:
			break
		var node: Control = _tokens[i]
		_tw.tween_property(node, "modulate:a", 1.0, 0.1)
		_tw.parallel().tween_property(node, "position:x", 0.0, 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if i < _tokens.size() - 1:
			_tw.tween_interval(0.025)


func close_menu() -> void:
	if not _open:
		_apply_closed_instant()
		return
	_open = false
	_seq += 1
	var token := _seq
	_kill_tween()
	if _chevron != null:
		_chevron.open = false
		_chevron.queue_redraw()
	open_changed.emit(false)
	if UiTheme.reduce_motion:
		_apply_closed_instant()
		return
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(_dim, "modulate:a", 0.0, 0.12)
	_tw.tween_property(_panel, "modulate:a", 0.0, 0.14)
	_tw.tween_property(_panel, "scale", Vector2(0.97, 0.94), 0.14)
	_tw.tween_property(_panel, "position:y", _rest_y() - 10.0, 0.14)
	_tw.set_parallel(false)
	_tw.tween_callback(func() -> void:
		if token != _seq:
			return
		_apply_closed_instant()
	)


func toggle_menu() -> void:
	if _open:
		close_menu()
	else:
		open_menu()


func _apply_closed_instant() -> void:
	_open = false
	_kill_tween()
	_dim.visible = false
	_dim.modulate.a = 0.0
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.modulate.a = 0.0
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.scale = Vector2.ONE
	if _chevron != null:
		_chevron.open = false
		_chevron.queue_redraw()


func _rest_y() -> float:
	return 92.0


func _layout_panel() -> void:
	var margin := 12.0
	_panel.position = Vector2(margin, _rest_y())
	var h := 58.0
	for t in _tokens:
		h += t.custom_minimum_size.y + 6.0
	h += 18.0
	_panel.size = Vector2(PANEL_W, h)
	var vp := get_viewport_rect().size
	if _panel.position.x + _panel.size.x > vp.x - 8.0:
		_panel.position.x = maxf(8.0, vp.x - _panel.size.x - 8.0)
	if _panel.position.y + _panel.size.y > vp.y - 8.0:
		_panel.position.y = maxf(8.0, vp.y - _panel.size.y - 8.0)


func _kill_tween() -> void:
	if _tw != null and is_instance_valid(_tw):
		_tw.kill()
	_tw = null


func _load_art() -> void:
	if ResourceLoader.exists(WOOD_TEX):
		_wood = load(WOOD_TEX)
	_icons = {
		"resume": UiIcons.tex("play"),
		"guide": UiIcons.tex("book"),
		"calm": UiIcons.tex("calm"),
		"restart": UiIcons.tex("refresh"),
		"menu": UiIcons.tex("home"),
		"hand_action": UiIcons.tex("hand"),
		"build_action": UiIcons.tex("build"),
		"trade_action": UiIcons.tex("trade"),
		"end_action": UiIcons.tex("check"),
		"soon_profile": _crop_icon(SHEEP_TEX),
		"soon_collection": _crop_icon(GRAIN_TEX),
		"soon_stats": _crop_icon(COIN_TEX),
		"soon_continue": _crop_icon(ISLA_TEX, Rect2(0.2, 0.35, 0.45, 0.4)),
		"banner": _crop_icon(PAPER_TEX),
	}


func _crop_icon(path: String, region_frac: Rect2 = Rect2(0.17, 0.17, 0.66, 0.66)) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var src: Texture2D = load(path)
	if src == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = src
	var sz := src.get_size()
	atlas.region = Rect2(sz.x * region_frac.position.x, sz.y * region_frac.position.y, sz.x * region_frac.size.x, sz.y * region_frac.size.y)
	return atlas


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Veladura salvia-oscuro (simula blur suave sin shader)
	_dim.color = Color(0.08, 0.1, 0.08, 0.5)
	_dim.modulate.a = 0.0
	_dim.visible = false
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			close_menu()
	)
	add_child(_dim)

	_panel = Panel.new()
	_panel.visible = false
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.clip_contents = true
	_panel.add_theme_stylebox_override("panel", UiTheme.panel_box())
	add_child(_panel)

	if _wood != null:
		var grain := TextureRect.new()
		grain.texture = _wood
		grain.set_anchors_preset(Control.PRESET_FULL_RECT)
		grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grain.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		grain.modulate = Color(0.4, 0.38, 0.3, 0.45)
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(grain)
		var wash := ColorRect.new()
		wash.set_anchors_preset(Control.PRESET_FULL_RECT)
		wash.color = Color(0.12, 0.14, 0.11, 0.55)
		wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_panel.add_child(wash)

	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_right = -12
	col.offset_top = 12
	col.offset_bottom = -12
	col.add_theme_constant_override("separation", 6)
	_panel.add_child(col)

	col.add_child(_make_banner("Partida"))

	col.add_child(_make_section("En la mesa"))
	var hand_btn := _make_token("Mano", UiTheme.SAGE, "hand_action", true)
	var build_btn := _make_token("Construir", UiTheme.BRASS, "build_action", true)
	var trade_btn := _make_token("Cambiar", UiTheme.GOLD, "trade_action", true)
	var end_turn_btn := _make_token("Listo", UiTheme.SAGE_MIST, "end_action", true)
	for b in [hand_btn, build_btn, trade_btn, end_turn_btn]:
		col.add_child(b.get_meta("wrap") as Control)

	col.add_child(_make_section("Partida"))
	resume_btn = _make_token("Seguir jugando", UiTheme.SAGE, "resume", true)
	guide_btn = _make_token("Cómo jugar", UiTheme.BRASS, "guide", true)
	motion_btn = _make_token("Menos movimiento", UiTheme.GOLD, "calm", true)
	restart_btn = _make_token("Nueva partida", UiTheme.GOLD, "restart", true)
	to_menu_btn = _make_token("Inicio", UiTheme.SAGE_MIST, "menu", true)
	for b2 in [resume_btn, guide_btn, motion_btn, restart_btn, to_menu_btn]:
		col.add_child(b2.get_meta("wrap") as Control)

	col.add_child(_make_section("Más adelante"))
	for soon in [
		_make_token("Continuar partida", UiTheme.BORDER, "soon_continue", false),
		_make_token("Perfil", UiTheme.BORDER, "soon_profile", false),
		_make_token("Colección", UiTheme.BORDER, "soon_collection", false),
		_make_token("Estadísticas", UiTheme.BORDER, "soon_stats", false),
	]:
		col.add_child(soon.get_meta("wrap") as Control)

	hand_btn.pressed.connect(func() -> void:
		_pulse(hand_btn); close_menu(); hand_pressed.emit()
	)
	build_btn.pressed.connect(func() -> void:
		_pulse(build_btn); close_menu(); build_pressed.emit()
	)
	trade_btn.pressed.connect(func() -> void:
		_pulse(trade_btn); close_menu(); trade_pressed.emit()
	)
	end_turn_btn.pressed.connect(func() -> void:
		_pulse(end_turn_btn); close_menu(); end_turn_pressed.emit()
	)
	resume_btn.pressed.connect(func() -> void:
		_pulse(resume_btn)
		close_menu()
		resume_pressed.emit()
	)
	guide_btn.pressed.connect(func() -> void:
		_pulse(guide_btn)
		close_menu()
		guide_pressed.emit()
	)
	motion_btn.pressed.connect(func() -> void:
		_pulse(motion_btn)
		motion_pressed.emit()
	)
	restart_btn.pressed.connect(func() -> void:
		_pulse(restart_btn)
		close_menu()
		restart_pressed.emit()
	)
	to_menu_btn.pressed.connect(func() -> void:
		_pulse(to_menu_btn)
		menu_pressed.emit()
	)

	resized.connect(func() -> void:
		if _open:
			_layout_panel()
	)


func _make_banner(title: String) -> Control:
	var banner := Panel.new()
	banner.custom_minimum_size = Vector2(0, 46)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.clip_contents = true
	banner.add_theme_stylebox_override("panel", UiTheme.sage_banner())
	if _icons.get("banner") != null:
		var parchment := TextureRect.new()
		parchment.texture = _icons["banner"]
		parchment.set_anchors_preset(Control.PRESET_FULL_RECT)
		parchment.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		parchment.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		parchment.modulate = Color(1, 0.95, 0.85, 0.4)
		parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
		banner.add_child(parchment)
	var brow := HBoxContainer.new()
	brow.set_anchors_preset(Control.PRESET_FULL_RECT)
	brow.offset_left = 12
	brow.offset_right = -10
	brow.add_theme_constant_override("separation", 10)
	banner.add_child(brow)
	var crest := _HexCrest.new()
	crest.custom_minimum_size = Vector2(24, 24)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(crest)
	_banner_lab = Label.new()
	_banner_lab.text = title
	_banner_lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_banner_lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_banner_lab.add_theme_font_size_override("font_size", 20)
	_banner_lab.add_theme_color_override("font_color", UiTheme.INK_PAPER)
	if UiTheme.display_font != null:
		_banner_lab.add_theme_font_override("font", UiTheme.display_font)
	brow.add_child(_banner_lab)
	_chevron = _BrassMark.new()
	_chevron.custom_minimum_size = Vector2(16, 16)
	_chevron.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brow.add_child(_chevron)
	return banner


func _make_section(title: String) -> Control:
	var lab := Label.new()
	lab.text = title
	lab.add_theme_font_size_override("font_size", 12)
	lab.add_theme_color_override("font_color", UiTheme.SAGE_MIST)
	lab.modulate.a = 0.85
	return lab


func _make_token(title: String, accent: Color, id: String, enabled: bool) -> Button:
	var wrap := Panel.new()
	wrap.custom_minimum_size = Vector2(0, TOKEN_H if enabled else 44.0)
	wrap.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	wrap.clip_contents = true
	wrap.add_theme_stylebox_override("panel", _token_box(false, enabled))
	wrap.set_meta("token_id", id)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -8
	row.offset_top = 6
	row.offset_bottom = -6
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrap.add_child(row)

	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(38, 38) if enabled else Vector2(32, 32)
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var chip_box := StyleBoxFlat.new()
	chip_box.bg_color = Color("2a241c")
	chip_box.border_color = accent if enabled else UiTheme.BORDER
	chip_box.set_border_width_all(2)
	chip_box.set_corner_radius_all(19)
	chip.add_theme_stylebox_override("panel", chip_box)
	row.add_child(chip)
	var icon_tex: Texture2D = _icons.get(id) as Texture2D
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.set_anchors_preset(Control.PRESET_FULL_RECT)
		icon.offset_left = 5
		icon.offset_right = -5
		icon.offset_top = 5
		icon.offset_bottom = -5
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		icon.modulate.a = 1.0 if enabled else 0.4
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(icon)

	var btn := Button.new()
	btn.text = title if enabled else "%s  ·  Pronto" % title
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.flat = true
	btn.disabled = not enabled
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.add_theme_font_size_override("font_size", 15 if enabled else 13)
	btn.add_theme_color_override("font_color", UiTheme.INK_SOFT if enabled else Color("7a6e60"))
	btn.add_theme_color_override("font_hover_color", UiTheme.GOLD)
	btn.add_theme_color_override("font_disabled_color", Color("6a5e52"))
	btn.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	btn.set_meta("wrap", wrap)
	row.add_child(btn)

	if enabled:
		var tip := _BrassMark.new()
		tip.sideways = true
		tip.open = true
		tip.custom_minimum_size = Vector2(12, 12)
		tip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(tip)
		wrap.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				btn.emit_signal("pressed")
		)
		btn.mouse_entered.connect(func() -> void:
			wrap.add_theme_stylebox_override("panel", _token_box(true, true))
		)
		btn.mouse_exited.connect(func() -> void:
			if id == "calm" and _calm:
				wrap.add_theme_stylebox_override("panel", _token_box_active())
			else:
				wrap.add_theme_stylebox_override("panel", _token_box(false, true))
		)

	_tokens.append(wrap)
	return btn


func _refresh_motion_token() -> void:
	if _tokens.size() < 3:
		return
	var wrap: Control = _tokens[2] # calm is 3rd live token after resume, guide
	# Find by meta
	for t in _tokens:
		if String(t.get_meta("token_id", "")) == "calm":
			wrap = t
			break
	if _calm:
		wrap.add_theme_stylebox_override("panel", _token_box_active())
	else:
		wrap.add_theme_stylebox_override("panel", _token_box(false, true))


func _pulse(btn: Button) -> void:
	var wrap: Control = btn.get_meta("wrap") as Control if btn.has_meta("wrap") else null
	if wrap == null or UiTheme.reduce_motion:
		return
	wrap.pivot_offset = wrap.size * 0.5
	AnimUtil.kill(_pulse_tw)
	wrap.scale = Vector2.ONE
	_pulse_tw = create_tween()
	_pulse_tw.tween_property(wrap, "scale", Vector2(1.03, 1.03), 0.06)
	_pulse_tw.tween_property(wrap, "scale", Vector2.ONE, 0.1)


func _token_box(hover: bool, enabled: bool) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	if not enabled:
		box.bg_color = Color("2a2620aa")
		box.border_color = Color("4a4036")
		box.set_border_width_all(1)
	else:
		box.bg_color = Color("3f4638cc") if hover else Color("322e28cc")
		box.border_color = UiTheme.GOLD if hover else UiTheme.BORDER
		box.set_border_width_all(2 if hover else 1)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(0, 0, 0, 0.28)
	box.shadow_size = 4 if hover else 2
	box.shadow_offset = Vector2(0, 2)
	return box


func _token_box_active() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color("3a4638dd")
	box.border_color = UiTheme.SAGE
	box.set_border_width_all(2)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(0.4, 0.55, 0.35, 0.25)
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 2)
	return box


class _HexCrest extends Control:
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := mini(size.x, size.y) * 0.42
		var pts := PackedVector2Array()
		for i in 6:
			var a := -PI / 2.0 + float(i) * TAU / 6.0
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Color("f4efe4"))
		draw_polyline(pts + PackedVector2Array([pts[0]]), Color("4f6b52"), 1.6, true)
		draw_circle(c, r * 0.22, Color("7a9a78"))


class _BrassMark extends Control:
	var open := false
	var sideways := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var col := Color("c4a574")
		if sideways or not open:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-3, -5), c + Vector2(5, 0), c + Vector2(-3, 5)]), col)
		else:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-5, -3), c + Vector2(5, -3), c + Vector2(0, 5)]), col)
