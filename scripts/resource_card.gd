extends Panel
class_name ResourceCard

## Carta premium de recurso: marco cromático + arte + nombre + cantidad.
## Solo presenta; el inventario vive en LinderoMatch.hands / wares.

const UiTheme := preload("res://scripts/ui_theme.gd")
const AnimUtil := preload("res://scripts/anim_util.gd")

signal card_pressed(index: int)

var resource_index := 0
var accent := Color("6b5340")
var title := ""
var art: Texture2D
var count_label: Label
var art_rect: TextureRect
var title_label: Label
var _frame: StyleBoxFlat
var _inner: Panel
var _hover := false
var _selectable := false
var _base_min := Vector2(72, 118)
var _hover_tw: Tween

func setup(index: int, res_name: String, texture: Texture2D, tone: Color, selectable := false) -> void:
	resource_index = index
	title = res_name
	art = texture
	accent = tone
	_selectable = selectable
	mouse_filter = Control.MOUSE_FILTER_STOP if selectable else Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = _base_min
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_build()
	set_count(0)
	if selectable:
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))
		gui_input.connect(_on_gui)

func set_count(n: int) -> void:
	if count_label != null:
		count_label.text = str(maxi(0, n))
	var live := n > 0
	modulate = Color(1, 1, 1, 1.0 if live else 0.55)
	if art_rect != null:
		art_rect.modulate = Color(1, 1, 1, 1.0 if live else 0.72)
	tooltip_text = "%s · %d" % [title, n]

func count_node() -> Label:
	return count_label

func art_node() -> CanvasItem:
	return art_rect

func _build() -> void:
	_frame = StyleBoxFlat.new()
	_frame.bg_color = Color("2a221c")
	_frame.border_color = accent
	_frame.set_border_width_all(2)
	_frame.set_corner_radius_all(10)
	_frame.shadow_color = Color(0, 0, 0, 0.42)
	_frame.shadow_size = 4
	_frame.shadow_offset = Vector2(0, 2)
	_frame.content_margin_left = 4
	_frame.content_margin_right = 4
	_frame.content_margin_top = 4
	_frame.content_margin_bottom = 4
	add_theme_stylebox_override("panel", _frame)

	var root := MarginContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("margin_left", 3)
	root.add_theme_constant_override("margin_right", 3)
	root.add_theme_constant_override("margin_top", 3)
	root.add_theme_constant_override("margin_bottom", 3)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	_inner = Panel.new()
	_inner.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color("f3ead7")
	paper.border_color = Color(accent.r, accent.g, accent.b, 0.55)
	paper.set_border_width_all(1)
	paper.set_corner_radius_all(7)
	_inner.add_theme_stylebox_override("panel", paper)
	col.add_child(_inner)

	var art_wrap := MarginContainer.new()
	art_wrap.set_anchors_preset(Control.PRESET_FULL_RECT)
	art_wrap.add_theme_constant_override("margin_left", 4)
	art_wrap.add_theme_constant_override("margin_right", 4)
	art_wrap.add_theme_constant_override("margin_top", 4)
	art_wrap.add_theme_constant_override("margin_bottom", 4)
	art_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inner.add_child(art_wrap)

	art_rect = TextureRect.new()
	art_rect.texture = art
	art_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	art_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	art_wrap.add_child(art_rect)

	var band := Panel.new()
	band.custom_minimum_size = Vector2(0, 22)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band_box := StyleBoxFlat.new()
	band_box.bg_color = Color(accent.darkened(0.35))
	band_box.set_corner_radius_all(5)
	band.add_theme_stylebox_override("panel", band_box)
	col.add_child(band)

	title_label = Label.new()
	title_label.text = title
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	title_label.add_theme_font_size_override("font_size", 11)
	title_label.add_theme_color_override("font_color", Color("f6f1e4"))
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.add_child(title_label)

	var seal := Panel.new()
	seal.custom_minimum_size = Vector2(28, 22)
	seal.anchor_left = 1.0
	seal.anchor_right = 1.0
	seal.anchor_top = 0.0
	seal.anchor_bottom = 0.0
	seal.offset_left = -32
	seal.offset_right = -4
	seal.offset_top = 6
	seal.offset_bottom = 28
	seal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var seal_box := StyleBoxFlat.new()
	seal_box.bg_color = Color("1c1612")
	seal_box.border_color = UiTheme.GOLD
	seal_box.set_border_width_all(1)
	seal_box.set_corner_radius_all(6)
	seal.add_theme_stylebox_override("panel", seal_box)
	add_child(seal)

	count_label = Label.new()
	count_label.text = "0"
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	count_label.add_theme_font_size_override("font_size", 13)
	count_label.add_theme_color_override("font_color", Color("f3ead7"))
	count_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(count_label)

func _on_hover(on: bool) -> void:
	_hover = on
	pivot_offset = size * 0.5
	if _frame != null:
		_frame.border_color = accent.lightened(0.18) if on else accent
	if UiTheme.reduce_motion:
		scale = Vector2(1.04, 1.04) if on else Vector2.ONE
		return
	AnimUtil.kill(_hover_tw)
	_hover_tw = create_tween()
	var lift := 1.04 if on else 1.0
	_hover_tw.tween_property(self, "scale", Vector2(lift, lift), 0.08)

func _on_gui(ev: InputEvent) -> void:
	if not _selectable:
		return
	if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		card_pressed.emit(resource_index)
