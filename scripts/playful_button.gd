extends Button
class_name PlayfulButton

## Botón de juego con feedback táctil (press / release / select).
## No altera la lógica: solo presentación.

const UiTheme := preload("res://scripts/ui_theme.gd")
const AnimUtil := preload("res://scripts/anim_util.gd")

@export var press_scale := 0.92
@export var bounce := true
var _tw: Tween
var _base_modulate := Color.WHITE
var _selected := false


func _ready() -> void:
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = size * 0.5
	resized.connect(func() -> void: pivot_offset = size * 0.5)
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	pressed.connect(_on_click_pulse)


func set_selected(on: bool) -> void:
	_selected = on
	modulate = Color(1.08, 1.05, 0.92, 1.0) if on else _base_modulate


func _on_down() -> void:
	_kill()
	pivot_offset = size * 0.5
	if UiTheme.reduce_motion:
		scale = Vector2(press_scale, press_scale)
		modulate = Color(0.9, 0.88, 0.82, 1.0)
		return
	_tw = create_tween()
	_tw.set_parallel(true)
	_tw.tween_property(self, "scale", Vector2(press_scale, press_scale), 0.07).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tw.tween_property(self, "modulate", Color(0.9, 0.88, 0.82, 1.0), 0.07)


func _on_up() -> void:
	_kill()
	pivot_offset = size * 0.5
	var target_mod := Color(1.08, 1.05, 0.92, 1.0) if _selected else _base_modulate
	if UiTheme.reduce_motion:
		scale = Vector2.ONE
		modulate = target_mod
		return
	_tw = create_tween()
	if bounce:
		_tw.tween_property(self, "scale", Vector2(1.04, 1.04), 0.08).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_tw.tween_property(self, "scale", Vector2.ONE, 0.1)
	else:
		_tw.tween_property(self, "scale", Vector2.ONE, 0.1)
	_tw.parallel().tween_property(self, "modulate", target_mod, 0.1)


func _on_click_pulse() -> void:
	# Refuerzo corto si el release fue muy rápido
	if UiTheme.reduce_motion:
		return
	pivot_offset = size * 0.5


func _kill() -> void:
	AnimUtil.kill(_tw)
	_tw = null
