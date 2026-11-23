extends Control
class_name HarvestFx

## Cartas voladoras: solo feedback visual. No toca hands/wares ni turnos.

const UiTheme := preload("res://scripts/ui_theme.gd")
const MAX_ACTIVE := 28
const CARD_SIZE := Vector2(52, 78)

var _flyers: Array = []
var _tweens: Array = []
var _seq := 0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	z_index = 80


func clear_all() -> void:
	_seq += 1
	for tw in _tweens:
		if tw is Tween and is_instance_valid(tw) and (tw as Tween).is_valid():
			(tw as Tween).kill()
	_tweens.clear()
	for n in _flyers:
		if is_instance_valid(n):
			(n as Node).queue_free()
	_flyers.clear()


func active_count() -> int:
	var n := 0
	for c in _flyers:
		if is_instance_valid(c):
			n += 1
	return n


func play_card(
	tex: Texture2D,
	accent: Color,
	from: Vector2,
	to: Vector2,
	delay: float = 0.0,
	on_arrive: Callable = Callable()
) -> void:
	if UiTheme.reduce_motion:
		if on_arrive.is_valid():
			on_arrive.call()
		return
	while _flyers.size() >= MAX_ACTIVE:
		var old: Variant = _flyers.pop_front()
		if is_instance_valid(old):
			(old as Node).queue_free()
	var inv := get_global_transform_with_canvas().affine_inverse()
	var from_l: Vector2 = inv * from
	var to_l: Vector2 = inv * to
	var token := _seq
	var card := _make_card(tex, accent)
	card.scale = Vector2(0.35, 0.35)
	card.modulate.a = 0.0
	card.rotation = randf_range(-0.22, 0.22)
	add_child(card)
	_flyers.append(card)

	var jitter := Vector2(randf_range(-14.0, 14.0), randf_range(-10.0, 10.0))
	var start: Vector2 = from_l + jitter * 0.35
	var end: Vector2 = to_l + jitter * 0.15
	var mid: Vector2 = (start + end) * 0.5 + Vector2(0.0, -48.0 - randf() * 28.0)
	card.position = start - CARD_SIZE * 0.5

	var flight := 0.42 + randf() * 0.08
	var spin_to := randf_range(-0.4, 0.4)
	var tw := create_tween()
	_tweens.append(tw)
	if delay > 0.001:
		tw.tween_interval(delay)
	tw.tween_callback(func() -> void: _reveal(card, token))
	tw.tween_property(card, "scale", Vector2(0.92, 0.92), 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(card, "modulate:a", 1.0, 0.1)
	tw.tween_method(func(t: float) -> void: _fly_step(card, start, mid, end, token, t), 0.0, 1.0, flight).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tw.parallel().tween_property(card, "rotation", spin_to, flight)
	tw.parallel().tween_property(card, "scale", Vector2(0.78, 0.78), flight).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_property(card, "scale", Vector2(1.08, 1.08), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func() -> void: _arrive(on_arrive, token))
	tw.tween_property(card, "scale", Vector2(0.55, 0.55), 0.12)
	tw.parallel().tween_property(card, "modulate:a", 0.0, 0.12)
	tw.tween_callback(func() -> void: _finish(card, token, tw))


func _reveal(card: Control, token: int) -> void:
	if token != _seq or not is_instance_valid(card):
		return
	card.modulate.a = 1.0


func _fly_step(card: Control, start: Vector2, mid: Vector2, end: Vector2, token: int, t: float) -> void:
	if token != _seq or not is_instance_valid(card):
		return
	# Solo posición: la escala la maneja el tween (evita pelea de propiedades).
	var p := _bezier(start, mid, end, t)
	card.position = p - CARD_SIZE * 0.5


func _arrive(on_arrive: Callable, token: int) -> void:
	if token != _seq:
		return
	if on_arrive.is_valid():
		on_arrive.call()


func _finish(card: Control, token: int, tw: Tween) -> void:
	_tweens.erase(tw)
	if token != _seq:
		return
	if is_instance_valid(card):
		_flyers.erase(card)
		card.queue_free()


func _bezier(a: Vector2, b: Vector2, c: Vector2, t: float) -> Vector2:
	var u := 1.0 - t
	return u * u * a + 2.0 * u * t * b + t * t * c


func _make_card(tex: Texture2D, accent: Color) -> Control:
	var root := Panel.new()
	root.custom_minimum_size = CARD_SIZE
	root.size = CARD_SIZE
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.pivot_offset = CARD_SIZE * 0.5
	var frame := StyleBoxFlat.new()
	frame.bg_color = Color("2a221c")
	frame.border_color = accent
	frame.set_border_width_all(2)
	frame.set_corner_radius_all(8)
	frame.shadow_color = Color(0, 0, 0, 0.35)
	frame.shadow_size = 3
	root.add_theme_stylebox_override("panel", frame)

	var paper := Panel.new()
	paper.set_anchors_preset(Control.PRESET_FULL_RECT)
	paper.offset_left = 3
	paper.offset_right = -3
	paper.offset_top = 3
	paper.offset_bottom = -3
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pb := StyleBoxFlat.new()
	pb.bg_color = Color("f3ead7")
	pb.set_corner_radius_all(5)
	paper.add_theme_stylebox_override("panel", pb)
	root.add_child(paper)

	var art := TextureRect.new()
	art.texture = tex
	art.set_anchors_preset(Control.PRESET_FULL_RECT)
	art.offset_left = 4
	art.offset_right = -4
	art.offset_top = 4
	art.offset_bottom = -4
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	paper.add_child(art)

	var sheen := ColorRect.new()
	sheen.color = Color(1.0, 0.9, 0.55, 0.18)
	sheen.set_anchors_preset(Control.PRESET_FULL_RECT)
	sheen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(sheen)
	return root
