extends VBoxContainer
class_name ResourceHand

## Mano visual de las cinco primas (+ mercancías compactas).
## Lee cantidades desde LinderoMatch; no guarda inventario propio.

const GameScript := preload("res://scripts/match.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const CardScene := preload("res://scripts/resource_card.gd")

signal resource_selected(index: int)

var player := 0
var cards: Array = []
var count_labels: Array[Label] = []
var art_icons: Array[CanvasItem] = []
var ware_counts: Array[Label] = []
var ware_icons: Array[CanvasItem] = []
var ware_badges: Array[Panel] = []
var _row: HBoxContainer
var _ware_row: HBoxContainer
var _title: Label

func setup(p: int, card_tex: Array[Texture2D], selectable := false) -> void:
	player = p
	add_theme_constant_override("separation", 8)
	_title = Label.new()
	_title.text = GameScript.PLAYER_NAME[p]
	_title.add_theme_font_size_override("font_size", 14)
	_title.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[p])
	add_child(_title)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", -10)
	_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_row)

	var n_res := GameScript.RES_NAME.size()
	for i in n_res:
		var tex: Texture2D = card_tex[i] if i < card_tex.size() else null
		var card: ResourceCard = CardScene.new()
		card.setup(i, GameScript.RES_NAME[i], tex, GameScript.RES_COLOR[i], selectable and p == 0)
		if selectable and p == 0:
			card.card_pressed.connect(func(idx: int) -> void: resource_selected.emit(idx))
		# Ligera superposición en abanico
		card.z_index = i
		_row.add_child(card)
		cards.append(card)
		count_labels.append(card.count_node())
		art_icons.append(card.art_node())

	var ware_lab := Label.new()
	ware_lab.text = "Mercancías"
	ware_lab.add_theme_font_size_override("font_size", 13)
	ware_lab.add_theme_color_override("font_color", UiTheme.INK_DIM)
	add_child(ware_lab)

	_ware_row = HBoxContainer.new()
	_ware_row.add_theme_constant_override("separation", 6)
	add_child(_ware_row)
	for i in GameScript.WARE_NAME.size():
		var tex_i := n_res + i
		var tex: Texture2D = card_tex[tex_i] if tex_i < card_tex.size() else null
		_ware_row.add_child(_ware_chip(i, GameScript.WARE_NAME[i], tex, GameScript.WARE_COLOR[i], selectable and p == 0))

func sync_game(game) -> void:
	if game == null:
		return
	sync_counts(game.hands[player], game.wares[player])


func sync_counts(hands: Array, wares: Array) -> void:
	var n_res := GameScript.RES_NAME.size()
	for i in cards.size():
		var n := int(hands[i]) if i < hands.size() else 0
		(cards[i] as ResourceCard).set_count(n)
	_layout_fan(n_res)
	for i in ware_counts.size():
		var n := int(wares[i]) if i < wares.size() else 0
		ware_counts[i].text = str(n)
		if i < ware_icons.size():
			ware_icons[i].modulate = Color(1, 1, 1, 1.0 if n > 0 else 0.45)

func mark_active(on: bool) -> void:
	_title.text = GameScript.PLAYER_NAME[player] + (" · ahora" if on else "")
	modulate = Color(1, 1, 1, 1.0 if on else 0.72)

func _layout_fan(n: int) -> void:
	if _row == null or n <= 0:
		return
	# Más cartas → más solape; pocas → más aire.
	var sep := -6 if n <= 4 else -12
	_row.add_theme_constant_override("separation", sep)
	var view_w := get_viewport_rect().size.x if is_inside_tree() else 720.0
	var card_h := 118.0 if view_w >= 700.0 else 102.0
	var card_w := 78.0 if view_w >= 700.0 else 66.0
	for c in cards:
		var card := c as ResourceCard
		card.custom_minimum_size = Vector2(card_w, card_h)

func _ware_chip(index: int, ware_name: String, tex: Texture2D, tone: Color, selectable: bool) -> Panel:
	var chip := Panel.new()
	chip.custom_minimum_size = Vector2(0, 52)
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var box := StyleBoxFlat.new()
	box.bg_color = Color("f4efe4")
	box.border_color = tone.darkened(0.25)
	box.set_border_width_all(1)
	box.set_corner_radius_all(8)
	chip.add_theme_stylebox_override("panel", box)
	if selectable:
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				resource_selected.emit(GameScript.RES_NAME.size() + index)
		)
	else:
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 6
	row.offset_right = -6
	row.offset_top = 4
	row.offset_bottom = -4
	row.add_theme_constant_override("separation", 6)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(row)

	var icon := TextureRect.new()
	icon.texture = tex
	icon.custom_minimum_size = Vector2(36, 36)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	ware_icons.append(icon)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var nm := Label.new()
	nm.text = ware_name
	nm.add_theme_font_size_override("font_size", 12)
	nm.add_theme_color_override("font_color", Color("2a1c10"))
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(nm)

	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(24, 18)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var bb := StyleBoxFlat.new()
	bb.bg_color = Color("1c1612")
	bb.set_corner_radius_all(4)
	badge.add_theme_stylebox_override("panel", bb)
	var count := Label.new()
	count.text = "0"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.add_theme_font_size_override("font_size", 12)
	count.add_theme_color_override("font_color", Color("f3ead7"))
	badge.add_child(count)
	col.add_child(badge)
	ware_badges.append(badge)
	ware_counts.append(count)
	return chip
