extends Control
class_name DiceRollFx

## Overlay de dados animados. Solo presenta die_a/die_b ya calculados por LinderoMatch.
## ~1.2–1.4 s de tumble + hold del resultado. Calma = instantáneo. Toque = omitir.

signal finished(total: int)

const UiTheme := preload("res://scripts/ui_theme.gd")
const AnimUtil := preload("res://scripts/anim_util.gd")
const WOOD_TEX := "res://art/terreno_madera.jpg"

var _dim: ColorRect
var _tray: Panel
var _stage: Control
var _die_a: _DieView
var _die_b: _DieView
var _total_lab: Label
var _hint: Label
var _parts_lab: Label
var _busy := false
var _seq := 0
var _final_a := 1
var _final_b := 1
var _final_total := 2
var _tw: Tween
var _pop_tw: Tween
var _skip_armed := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 90
	visible = false
	_build()


func is_busy() -> bool:
	return _busy


func cancel() -> void:
	_seq += 1
	_busy = false
	_skip_armed = false
	_kill_tweens()
	_reset_visual_state()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func play(die_a: int, die_b: int, total: int) -> void:
	_final_a = clampi(die_a, 1, 6)
	_final_b = clampi(die_b, 1, 6)
	_final_total = clampi(total, 2, 12)
	if _final_a + _final_b != _final_total:
		_final_total = _final_a + _final_b
	_seq += 1
	var token := _seq
	_busy = true
	_skip_armed = true
	_kill_tweens()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_layout_for_viewport()
	_total_lab.text = ""
	_parts_lab.text = ""
	_total_lab.scale = Vector2.ONE
	_hint.text = "Tirando…"
	_die_a.set_face(randi_range(1, 6))
	_die_b.set_face(randi_range(1, 6))
	_die_a.modulate = Color.WHITE
	_die_b.modulate = Color.WHITE
	_reset_poses()
	_dim.modulate.a = 0.0
	_tray.modulate.a = 0.0

	if UiTheme.reduce_motion:
		_settle_instant(token)
		return

	_tw = create_tween()
	_tw.set_parallel(false)
	# Entrada bandeja
	_tw.tween_property(_dim, "modulate:a", 1.0, 0.1)
	_tw.parallel().tween_property(_tray, "modulate:a", 1.0, 0.12)
	# Lanzamiento hacia arriba
	_tw.tween_property(_die_a, "position", _toss_pos(true), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_die_b, "position", _toss_pos(false), 0.14).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_die_a, "scale", Vector2(1.12, 1.12), 0.14)
	_tw.parallel().tween_property(_die_b, "scale", Vector2(1.12, 1.12), 0.14)
	_tw.parallel().tween_property(_die_a, "rotation", -0.9, 0.14)
	_tw.parallel().tween_property(_die_b, "rotation", 1.1, 0.14)
	# Tumble ~0.85 s (caras fake → reales al final)
	for i in 7:
		var face_a := _final_a if i >= 5 else randi_range(1, 6)
		var face_b := _final_b if i >= 5 else randi_range(1, 6)
		var t := 0.07 + float(i) * 0.018
		_tw.tween_callback(_flash_faces.bind(face_a, face_b, token))
		_tw.tween_property(_die_a, "rotation", randf_range(-2.6, 2.6), t)
		_tw.parallel().tween_property(_die_b, "rotation", randf_range(-2.8, 2.8), t)
		_tw.parallel().tween_property(_die_a, "position", _tumble_pos(true), t)
		_tw.parallel().tween_property(_die_b, "position", _tumble_pos(false), t)
		_tw.parallel().tween_property(_die_a, "scale", Vector2(randf_range(0.92, 1.1), randf_range(0.92, 1.1)), t)
		_tw.parallel().tween_property(_die_b, "scale", Vector2(randf_range(0.92, 1.1), randf_range(0.92, 1.1)), t)
		_tw.parallel().tween_callback(_die_a.set_shadow_strength.bind(lerpf(0.2, 0.55, float(i) / 6.0)))
		_tw.parallel().tween_callback(_die_b.set_shadow_strength.bind(lerpf(0.2, 0.55, float(i) / 6.0)))
	# Caída + rebote
	_tw.tween_callback(_flash_faces.bind(_final_a, _final_b, token))
	_tw.tween_property(_die_a, "position", _rest_pos(true), 0.2).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_die_b, "position", _rest_pos(false), 0.22).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
	_tw.parallel().tween_property(_die_a, "rotation", -0.06, 0.2)
	_tw.parallel().tween_property(_die_b, "rotation", 0.08, 0.22)
	_tw.parallel().tween_property(_die_a, "scale", Vector2.ONE, 0.2)
	_tw.parallel().tween_property(_die_b, "scale", Vector2.ONE, 0.22)
	_tw.parallel().tween_callback(_die_a.set_shadow_strength.bind(0.85))
	_tw.parallel().tween_callback(_die_b.set_shadow_strength.bind(0.85))
	# Impacto + resultado
	_tw.tween_callback(_show_total.bind(token))
	_tw.tween_interval(0.65)
	_tw.tween_property(_dim, "modulate:a", 0.0, 0.16)
	_tw.parallel().tween_property(_tray, "modulate:a", 0.0, 0.16)
	_tw.tween_callback(_end.bind(token))


func skip_now() -> void:
	if not _busy or not _skip_armed:
		return
	_skip_armed = false
	var token := _seq
	_kill_tweens()
	_settle_instant(token)


func _kill_tweens() -> void:
	AnimUtil.kill(_tw)
	AnimUtil.kill(_pop_tw)
	_tw = null
	_pop_tw = null


func _reset_visual_state() -> void:
	if _die_a == null or _die_b == null:
		return
	_die_a.scale = Vector2.ONE
	_die_b.scale = Vector2.ONE
	_die_a.rotation = 0.0
	_die_b.rotation = 0.0
	if _total_lab != null:
		_total_lab.scale = Vector2.ONE
	if _dim != null:
		_dim.modulate.a = 0.0
	if _tray != null:
		_tray.modulate.a = 0.0


func _gui_input(event: InputEvent) -> void:
	if not _busy:
		return
	if event is InputEventMouseButton and event.pressed:
		skip_now()
		accept_event()
	elif event is InputEventScreenTouch and event.pressed:
		skip_now()
		accept_event()


func _flash_faces(a: int, b: int, token: int) -> void:
	if token != _seq:
		return
	_die_a.set_face(a)
	_die_b.set_face(b)


func _show_total(token: int) -> void:
	if token != _seq:
		return
	_skip_armed = false
	_die_a.set_face(_final_a)
	_die_b.set_face(_final_b)
	_parts_lab.text = "%d  +  %d" % [_final_a, _final_b]
	_total_lab.text = str(_final_total)
	if _final_total == 7:
		_total_lab.add_theme_color_override("font_color", Color("f0a090"))
		_hint.text = "Sequía"
	else:
		_total_lab.add_theme_color_override("font_color", UiTheme.GOLD)
		_hint.text = "Resultado"
	# Impacto en dados + total
	_die_a.pivot_offset = _die_a.size * 0.5
	_die_b.pivot_offset = _die_b.size * 0.5
	_total_lab.pivot_offset = _total_lab.size * 0.5
	_total_lab.scale = Vector2(1.35, 1.35)
	if UiTheme.reduce_motion:
		_total_lab.scale = Vector2.ONE
		return
	AnimUtil.kill(_pop_tw)
	_pop_tw = create_tween()
	_pop_tw.set_parallel(true)
	_pop_tw.tween_property(_die_a, "scale", Vector2(1.12, 1.12), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tw.tween_property(_die_b, "scale", Vector2(1.12, 1.12), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tw.tween_property(_total_lab, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_pop_tw.set_parallel(false)
	_pop_tw.tween_property(_die_a, "scale", Vector2.ONE, 0.1)
	_pop_tw.parallel().tween_property(_die_b, "scale", Vector2.ONE, 0.1)


func _settle_instant(token: int) -> void:
	_die_a.set_face(_final_a)
	_die_b.set_face(_final_b)
	_die_a.position = _rest_pos(true)
	_die_b.position = _rest_pos(false)
	_die_a.rotation = 0.0
	_die_b.rotation = 0.0
	_die_a.scale = Vector2.ONE
	_die_b.scale = Vector2.ONE
	_die_a.set_shadow_strength(0.85)
	_die_b.set_shadow_strength(0.85)
	_dim.modulate.a = 0.55
	_tray.modulate.a = 1.0
	_show_total(token)
	_tw = create_tween()
	_tw.tween_interval(0.28)
	_tw.tween_callback(_end.bind(token))


func _end(token: int) -> void:
	if token != _seq:
		return
	_busy = false
	_skip_armed = false
	AnimUtil.kill(_pop_tw)
	_pop_tw = null
	_tw = null
	_die_a.scale = Vector2.ONE
	_die_b.scale = Vector2.ONE
	_total_lab.scale = Vector2.ONE
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	finished.emit(_final_total)


func _reset_poses() -> void:
	_die_a.position = _rest_pos(true) + Vector2(-8, 12)
	_die_b.position = _rest_pos(false) + Vector2(8, 8)
	_die_a.rotation = -0.35
	_die_b.rotation = 0.4
	_die_a.scale = Vector2(0.72, 0.72)
	_die_b.scale = Vector2(0.72, 0.72)
	_die_a.set_shadow_strength(0.25)
	_die_b.set_shadow_strength(0.25)


func _rest_pos(left: bool) -> Vector2:
	var s := _die_a._die_size if _die_a != null else 80.0
	var gap := 24.0
	var tray_w := absf(_tray.offset_right - _tray.offset_left) if _tray != null else 320.0
	var y := 78.0
	if left:
		return Vector2(tray_w * 0.5 - s - gap * 0.5, y)
	return Vector2(tray_w * 0.5 + gap * 0.5, y)


func _toss_pos(left: bool) -> Vector2:
	var base := _rest_pos(left)
	return base + Vector2(randf_range(-10, 10), -62.0 + randf_range(-8, 4))


func _tumble_pos(left: bool) -> Vector2:
	var base := _rest_pos(left)
	return base + Vector2(randf_range(-18, 18), randf_range(-22, 18))


func _layout_for_viewport() -> void:
	var vp := get_viewport_rect().size
	var short := vp.y < 700.0 or vp.x < 500.0
	var w := 280.0 if short else 320.0
	var h := 230.0 if short else 250.0
	_tray.offset_left = -w * 0.5
	_tray.offset_right = w * 0.5
	_tray.offset_top = -h * 0.5
	_tray.offset_bottom = h * 0.5
	var die_s := 64.0 if short else _DieView.DEFAULT_SIZE
	for d in [_die_a, _die_b]:
		d.set_die_size(die_s)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.06, 0.05, 0.04, 0.5)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.modulate.a = 0.0
	_dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			skip_now()
		elif ev is InputEventScreenTouch and ev.pressed:
			skip_now()
	)
	add_child(_dim)

	_tray = Panel.new()
	_tray.anchor_left = 0.5
	_tray.anchor_right = 0.5
	_tray.anchor_top = 0.5
	_tray.anchor_bottom = 0.5
	_tray.offset_left = -160
	_tray.offset_right = 160
	_tray.offset_top = -125
	_tray.offset_bottom = 125
	_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.clip_contents = true
	var box := StyleBoxFlat.new()
	box.bg_color = Color("1a1612f2")
	box.border_color = UiTheme.GOLD
	box.set_border_width_all(2)
	box.set_corner_radius_all(18)
	box.shadow_color = Color(0, 0, 0, 0.55)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 6)
	_tray.add_theme_stylebox_override("panel", box)
	_tray.modulate.a = 0.0
	add_child(_tray)

	if ResourceLoader.exists(WOOD_TEX):
		var grain := TextureRect.new()
		grain.texture = load(WOOD_TEX)
		grain.set_anchors_preset(Control.PRESET_FULL_RECT)
		grain.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		grain.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		grain.modulate = Color(0.45, 0.38, 0.28, 0.35)
		grain.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_tray.add_child(grain)

	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.add_child(_stage)

	_die_a = _DieView.new()
	_die_b = _DieView.new()
	for d in [_die_a, _die_b]:
		d.size = Vector2(_DieView.DEFAULT_SIZE, _DieView.DEFAULT_SIZE)
		_stage.add_child(d)

	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.anchor_left = 0.0
	_hint.anchor_right = 1.0
	_hint.anchor_top = 0.0
	_hint.anchor_bottom = 0.0
	_hint.offset_top = 10
	_hint.offset_bottom = 28
	_hint.add_theme_font_size_override("font_size", 13)
	_hint.add_theme_color_override("font_color", UiTheme.INK_DIM)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.add_child(_hint)

	_parts_lab = Label.new()
	_parts_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_parts_lab.anchor_left = 0.0
	_parts_lab.anchor_right = 1.0
	_parts_lab.anchor_top = 1.0
	_parts_lab.anchor_bottom = 1.0
	_parts_lab.offset_top = -72
	_parts_lab.offset_bottom = -50
	_parts_lab.add_theme_font_size_override("font_size", 18)
	_parts_lab.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	_parts_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.add_child(_parts_lab)

	_total_lab = Label.new()
	_total_lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_total_lab.anchor_left = 0.0
	_total_lab.anchor_right = 1.0
	_total_lab.anchor_top = 1.0
	_total_lab.anchor_bottom = 1.0
	_total_lab.offset_top = -48
	_total_lab.offset_bottom = -8
	_total_lab.add_theme_font_size_override("font_size", 40)
	_total_lab.add_theme_color_override("font_color", UiTheme.GOLD)
	if UiTheme.display_font != null:
		_total_lab.add_theme_font_override("font", UiTheme.display_font)
	_total_lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tray.add_child(_total_lab)


class _DieView extends Control:
	var face := 1
	const DEFAULT_SIZE := 80.0
	var _face_box: StyleBoxFlat
	var _shade_box: StyleBoxFlat
	var _shadow_str := 0.4
	var _die_size := DEFAULT_SIZE

	func _ready() -> void:
		_die_size = DEFAULT_SIZE
		custom_minimum_size = Vector2(_die_size, _die_size)
		size = Vector2(_die_size, _die_size)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		pivot_offset = Vector2(_die_size * 0.5, _die_size * 0.5)
		_face_box = StyleBoxFlat.new()
		_face_box.bg_color = Color("f4efe4")
		_face_box.border_color = Color("c4a574")
		_face_box.set_border_width_all(2)
		_face_box.set_corner_radius_all(14)
		_face_box.shadow_color = Color(0, 0, 0, 0.4)
		_face_box.shadow_size = 8
		_face_box.shadow_offset = Vector2(3, 5)
		_shade_box = StyleBoxFlat.new()
		_shade_box.bg_color = Color(0.12, 0.08, 0.05, 0.14)
		_shade_box.set_corner_radius_all(11)

	func set_die_size(s: float) -> void:
		_die_size = s
		custom_minimum_size = Vector2(s, s)
		size = Vector2(s, s)
		pivot_offset = Vector2(s * 0.5, s * 0.5)
		queue_redraw()

	func set_face(n: int) -> void:
		face = clampi(n, 1, 6)
		queue_redraw()

	func set_shadow_strength(v: float) -> void:
		_shadow_str = clampf(v, 0.1, 1.0)
		if _face_box != null:
			_face_box.shadow_size = int(4.0 + _shadow_str * 8.0)
			_face_box.shadow_offset = Vector2(2.0 + _shadow_str * 2.0, 3.0 + _shadow_str * 3.0)
			_face_box.shadow_color = Color(0, 0, 0, 0.25 + _shadow_str * 0.35)
		queue_redraw()

	func _draw() -> void:
		var s := _die_size
		var r := Rect2(Vector2.ZERO, Vector2(s, s))
		draw_style_box(_face_box, r)
		draw_colored_polygon(PackedVector2Array([
			Vector2(8, 6), Vector2(s - 10, 6), Vector2(8, s - 14)
		]), Color(1, 1, 1, 0.2))
		draw_style_box(_shade_box, Rect2(8, s * 0.55, s - 16, s * 0.32))
		_draw_pips(face)

	func _draw_pips(n: int) -> void:
		var ink := Color("2a1c10")
		var c := _die_size * 0.5
		var d := _die_size * 0.22
		var rad := _die_size * 0.058
		var pts: Array[Vector2] = []
		match n:
			1:
				pts = [Vector2(c, c)]
			2:
				pts = [Vector2(c - d, c - d), Vector2(c + d, c + d)]
			3:
				pts = [Vector2(c - d, c - d), Vector2(c, c), Vector2(c + d, c + d)]
			4:
				pts = [Vector2(c - d, c - d), Vector2(c + d, c - d), Vector2(c - d, c + d), Vector2(c + d, c + d)]
			5:
				pts = [Vector2(c - d, c - d), Vector2(c + d, c - d), Vector2(c, c), Vector2(c - d, c + d), Vector2(c + d, c + d)]
			6:
				pts = [
					Vector2(c - d, c - d), Vector2(c + d, c - d),
					Vector2(c - d, c), Vector2(c + d, c),
					Vector2(c - d, c + d), Vector2(c + d, c + d),
				]
		for p in pts:
			draw_circle(p, rad + 1.2, Color(0, 0, 0, 0.2))
			draw_circle(p, rad, ink)
