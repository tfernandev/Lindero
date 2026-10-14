extends RefCounted

# Mesa de Lindero: madera oscura, papel crema, oro viejo.
# Un solo acento fuerte por vez. Los números no viven en las imágenes.

const INK := Color("f3ead7")
const INK_DIM := Color("9a8b78")
const INK_ON_GOLD := Color("2a1c10")
const GOLD := Color("e2b15a")
const GOLD_DEEP := Color("a8752e")
const GOLD_HOVER := Color("f0c36a")
const WOOD := Color("3a2e24")
const WOOD_HOVER := Color("4a3c30")
const WOOD_PRESS := Color("241c16")
const PANEL := Color("1c1612")
const BORDER := Color("6b5340")
const PAPER := Color("f4efe4")
const BRASS := Color("c4a574")
const SPACE := 8

static var theme: Theme
static var display_font: Font
static var reduce_motion := false
static var _roles: Dictionary = {}
static var _motion_loaded := false

static func install(node: Control) -> void:
	_load_motion()
	if theme == null:
		_build()
	node.theme = theme

static func _load_motion() -> void:
	if _motion_loaded:
		return
	_motion_loaded = true
	var cfg := ConfigFile.new()
	if cfg.load("user://lindero.cfg") == OK:
		reduce_motion = bool(cfg.get_value("view", "reduce_motion", false))

static func fit_window(window: Window) -> bool:
	var screen := DisplayServer.window_get_size()
	if screen.x < 64 or screen.y < 64:
		return false
	var base := Vector2i(1280, 720)
	var want := screen if screen.x < base.x or screen.y < base.y else base
	if window.content_scale_size == want and window.content_scale_mode == Window.CONTENT_SCALE_MODE_CANVAS_ITEMS and window.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_EXPAND:
		return false
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	window.content_scale_size = want
	return true

static func set_reduce_motion(on: bool) -> void:
	reduce_motion = on
	var cfg := ConfigFile.new()
	cfg.load("user://lindero.cfg")
	cfg.set_value("view", "reduce_motion", on)
	cfg.save("user://lindero.cfg")

static func panel_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PANEL
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	box.shadow_color = Color(0, 0, 0, 0.45)
	box.shadow_size = 14
	box.shadow_offset = Vector2(0, 5)
	return box

static func paper_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = PAPER
	box.border_color = BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(4)
	box.shadow_color = Color(0, 0, 0, 0.28)
	box.shadow_size = 3
	box.shadow_offset = Vector2(0, 1)
	return box

static func well(border: Color, fill: Color) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = border
	box.set_border_width_all(2)
	box.set_corner_radius_all(8)
	box.content_margin_left = 6
	box.content_margin_right = 6
	box.content_margin_top = 2
	box.content_margin_bottom = 2
	return box

static func paint(btn: Button, role: String) -> void:
	if theme == null:
		_build()
	var pack: Dictionary = _roles[role]
	var boxes: Dictionary = pack["box"]
	for state in boxes.keys():
		btn.add_theme_stylebox_override(String(state), boxes[state])
	var ink: Color = pack["ink"]
	btn.add_theme_color_override("font_color", ink)
	btn.add_theme_color_override("font_hover_color", ink)
	btn.add_theme_color_override("font_pressed_color", ink)
	btn.add_theme_color_override("font_focus_color", ink)
	btn.add_theme_color_override("font_disabled_color", pack["dim"])

static func _build() -> void:
	var body := _font("res://fonts/Nunito-Regular.ttf")
	var bold := _font("res://fonts/Nunito-Bold.ttf")
	display_font = _font("res://fonts/Fraunces-SemiBold.ttf")
	theme = Theme.new()
	if body != null:
		theme.default_font = body
	theme.default_font_size = 16
	if bold != null:
		theme.set_font("font", "Button", bold)
	var quiet := _pack(WOOD, WOOD_HOVER, WOOD_PRESS, BORDER, GOLD, INK, INK_DIM, 3)
	var primary := _pack(GOLD, GOLD_HOVER, GOLD_DEEP, GOLD_DEEP, Color("f6f1e4"), INK_ON_GOLD, Color("6d5a40"), 4)
	var chip := _pack(WOOD, WOOD_HOVER, WOOD_PRESS, BORDER, GOLD, INK, INK_DIM, 0)
	var chip_on := _pack(GOLD, GOLD_HOVER, GOLD_DEEP, GOLD_DEEP, Color("f6f1e4"), INK_ON_GOLD, Color("6d5a40"), 0)
	var short := _pack(Color("2a221c"), Color("342c26"), WOOD_PRESS, Color("4a4036"), GOLD, INK_DIM, INK_DIM, 0)
	_roles = {
		"quiet": quiet,
		"primary": primary,
		"armed": primary,
		"chip": chip,
		"chip_on": chip_on,
		"short": short,
	}
	var base: Dictionary = quiet["box"]
	for state in base.keys():
		theme.set_stylebox(String(state), "Button", base[state])
	theme.set_color("font_color", "Button", INK)
	theme.set_color("font_hover_color", "Button", INK)
	theme.set_color("font_pressed_color", "Button", INK)
	theme.set_color("font_focus_color", "Button", INK)
	theme.set_color("font_disabled_color", "Button", INK_DIM)
	theme.set_color("font_color", "Label", INK)

static func _pack(normal: Color, hover: Color, pressed: Color, border: Color, focus_border: Color, ink: Color, dim: Color, shadow: int) -> Dictionary:
	return {
		"ink": ink,
		"dim": dim,
		"box": {
			"normal": _box(normal, border, 1, shadow),
			"hover": _box(hover, focus_border, 1, shadow + 1),
			"pressed": _box(pressed, focus_border, 1, 0),
			"focus": _box(normal, focus_border, 2, shadow),
			"disabled": _box(Color("241c18"), Color("3a322c"), 1, 0),
		},
	}

static func _box(bg: Color, border: Color, width: int, shadow: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(8)
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 4
	box.content_margin_bottom = 4
	box.shadow_color = Color(0, 0, 0, 0.38)
	box.shadow_size = shadow
	box.shadow_offset = Vector2(0, 1)
	return box

static func _font(path: String) -> Font:
	if ResourceLoader.exists(path):
		return load(path)
	return null
