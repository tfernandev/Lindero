extends Control

const GameScript := preload("res://scripts/match.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const AnimUtil := preload("res://scripts/anim_util.gd")
const ResourceHandScript := preload("res://scripts/resource_hand.gd")
const GameMenuDropdownScript := preload("res://scripts/game_menu_dropdown.gd")
const PlayfulButtonScript := preload("res://scripts/playful_button.gd")
const UiIcons := preload("res://scripts/ui_icons.gd")

signal roll_pressed
signal end_pressed
signal tool_pressed(kind: String)
signal trade_pressed
signal advance_pressed(track: int)
signal give_pressed(index: int)
signal take_pressed(index: int)
signal menu_pressed
signal restart_pressed
signal motion_pressed
signal guide_pressed
signal layout_changed
signal hand_opened

var instruction_label: Label
var dice_label: Label
var dice_parts: Label
var dice_edge: StyleBoxFlat
var score_you: Label
var score_rival: Label
var turn_label: Label
var roll_btn: Button
var end_btn: Button
var road_btn: Button
var set_btn: Button
var up_btn: Button
var trade_btn: Button
var restart_btn: Button
var menu_btn: Button
var motion_btn: Button
var cost_label: Label
var log_label: Label
var rival_chart: Label
var you_counts: Array[Label] = []
var rival_counts: Array[Label] = []
var you_icons: Array[CanvasItem] = []
var rival_icons: Array[CanvasItem] = []
var you_badges: Array[Panel] = []
var rival_badges: Array[Panel] = []
var track_btns: Array[Button] = []
var give_btns: Array[Button] = []
var take_btns: Array[Button] = []
var hand_marks: Array[Panel] = []
var hand_names: Array[Label] = []
var hand_blocks: Array[Control] = []
var dock_btns: Dictionary = {}
var sheet: Panel
var dimmer: ColorRect
var pause_panel: Control
var game_menu: GameMenuDropdown
var sheet_title: Label
var sheet_body: Control
var hand_page: Control
var build_page: Control
var trade_page: Control
var note_label: Label
var primary_roll: Button
var toast_label: Label
var res_labs: Array[Label] = []
var rival_n: Label
var rival_summary: Label
var you_hand: ResourceHand
var rival_hand: ResourceHand
var _open := ""
var _card_tex: Array[Texture2D] = []
var _drag_from := Vector2.ZERO
var _slot_n := 8
var _toast_tw: Tween
var _sheet_tw: Tween
var _pulse_tweens: Dictionary = {}

func setup(card_tex: Array[Texture2D]) -> void:
	_card_tex = card_tex
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTheme.install(self)
	_build()

func top_reserve() -> float:
	return 96.0

func bottom_reserve() -> float:
	if _open == "mano":
		return 420.0
	if _open == "build":
		return 340.0
	if _open == "trade":
		return 360.0
	# Sin footer: solo espacio para FAB flotante (Tirar / Listo).
	return 56.0

func sheet_open() -> bool:
	return _open != ""

func pause_open() -> bool:
	return game_menu != null and game_menu.is_open()

func open_id() -> String:
	return _open

func blocks_board() -> bool:
	return pause_open() or _open == "mano" or _open == "trade" or _open == "guide"

func close_sheets() -> void:
	_show_sheet("")

func close_pause() -> void:
	_show_pause(false)

func show_toast(text: String) -> void:
	if toast_label == null or text == "":
		return
	AnimUtil.kill(_toast_tw)
	_toast_tw = null
	toast_label.text = text
	toast_label.visible = true
	toast_label.modulate.a = 1.0
	if UiTheme.reduce_motion:
		return
	_toast_tw = create_tween()
	_toast_tw.tween_interval(1.4)
	_toast_tw.tween_property(toast_label, "modulate:a", 0.0, 0.28)
	_toast_tw.tween_callback(func() -> void:
		toast_label.visible = false
		_toast_tw = null
	)

## Global center for harvest FX destination (hand chip or sheet card).
func resource_anchor(player: int, res_index: int) -> Vector2:
	if player == 0 and _open == "mano" and you_hand != null and res_index >= 0 and res_index < you_hand.cards.size():
		var card: Control = you_hand.cards[res_index]
		if card != null and card.is_inside_tree():
			return card.get_global_rect().get_center()
	if player == 0 and res_index >= 0 and res_index < res_labs.size() and res_labs[res_index] != null:
		return res_labs[res_index].get_global_rect().get_center()
	if player == 1:
		if rival_n != null and rival_n.is_inside_tree():
			return rival_n.get_global_rect().get_center()
		if score_rival != null:
			return score_rival.get_global_rect().get_center()
	return get_global_rect().get_center() + Vector2(0, -120)

func pulse_resource(player: int, res_index: int) -> void:
	if UiTheme.reduce_motion:
		return
	var target: Control = null
	if player == 0 and _open == "mano" and you_hand != null and res_index < you_hand.cards.size():
		target = you_hand.cards[res_index]
	elif player == 0 and res_index < res_labs.size():
		target = res_labs[res_index]
	elif player == 1 and rival_n != null:
		target = rival_n
	if target == null:
		return
	var key := target.get_instance_id()
	if _pulse_tweens.has(key):
		AnimUtil.kill(_pulse_tweens[key] as Tween)
		_pulse_tweens.erase(key)
	target.pivot_offset = target.size * 0.5
	target.scale = Vector2.ONE
	var tw := create_tween()
	_pulse_tweens[key] = tw
	tw.tween_property(target, "scale", Vector2(1.16, 1.16), 0.07)
	tw.tween_property(target, "scale", Vector2.ONE, 0.12)
	tw.tween_callback(func() -> void:
		_pulse_tweens.erase(key)
	)

func _build() -> void:
	_build_top()
	_build_action_rail()
	_build_roll_fab()
	_build_end_fab()
	_build_sheets()
	_build_pause()

func _build_top() -> void:
	var bar := Panel.new()
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 0.0
	bar.anchor_bottom = 0.0
	bar.offset_left = 12.0
	bar.offset_right = -12.0
	bar.offset_top = 10.0
	bar.offset_bottom = 90.0
	bar.clip_contents = true
	bar.add_theme_stylebox_override("panel", _bar_box())
	add_child(bar)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_right = -8
	col.offset_top = 4
	col.offset_bottom = -4
	col.add_theme_constant_override("separation", 2)
	bar.add_child(col)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	col.add_child(row)
	menu_btn = _menu_toggle_btn()
	menu_btn.pressed.connect(func() -> void:
		if pause_open():
			_show_pause(false)
		else:
			_show_pause(true)
	)
	row.add_child(menu_btn)
	turn_label = _lab("Vos · tu turno", 15, false)
	turn_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_label.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[0])
	row.add_child(turn_label)
	for i in GameScript.RES_COUNT:
		# Icon chip + count: open Mano sheet for the full card hand.
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 3)
		chip.mouse_filter = Control.MOUSE_FILTER_STOP
		chip.tooltip_text = GameScript.RES_NAME[i]
		chip.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and ev.pressed:
				_show_sheet("mano")
				hand_opened.emit()
		)
		var icon := _res_icon(i)
		if icon != null:
			chip.add_child(icon)
		var lab := _lab("0" if icon != null else "%s 0" % GameScript.RES_LETTER[i], 17, false)
		lab.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		chip.add_child(lab)
		row.add_child(chip)
		res_labs.append(lab)
	score_you = _lab("0/5", 16, false)
	score_you.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[0])
	score_rival = _lab("0", 16, false)
	score_rival.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[1])
	row.add_child(_chip("Vos", score_you, GameScript.PLAYER_COLOR[0]))
	var rival_box := _chip("Vecino", score_rival, GameScript.PLAYER_COLOR[1])
	rival_n = _lab("", 11, false)
	rival_n.add_theme_color_override("font_color", UiTheme.INK_DIM)
	rival_n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rival_box.add_child(rival_n)
	row.add_child(rival_box)
	dice_edge = StyleBoxFlat.new()
	dice_edge.bg_color = Color("241c18")
	dice_edge.border_color = UiTheme.BORDER
	dice_edge.set_border_width_all(1)
	dice_edge.set_corner_radius_all(8)
	var dice_well := Panel.new()
	dice_well.custom_minimum_size = Vector2(52, 40)
	dice_well.add_theme_stylebox_override("panel", dice_edge)
	var dcol := VBoxContainer.new()
	dcol.set_anchors_preset(Control.PRESET_FULL_RECT)
	dcol.alignment = BoxContainer.ALIGNMENT_CENTER
	dcol.add_theme_constant_override("separation", -4)
	dice_label = _lab("—", 16, false)
	dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_parts = _lab("", 10, false)
	dice_parts.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dice_parts.add_theme_color_override("font_color", UiTheme.INK_DIM)
	dcol.add_child(dice_label)
	dcol.add_child(dice_parts)
	dice_well.add_child(dcol)
	row.add_child(dice_well)
	instruction_label = _lab("", 14, false)
	instruction_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instruction_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	col.add_child(instruction_label)
	toast_label = _lab("", 15, false)
	toast_label.visible = false
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.anchor_left = 0.15
	toast_label.anchor_right = 0.85
	toast_label.anchor_top = 0.0
	toast_label.offset_top = 96.0
	toast_label.offset_bottom = 122.0
	toast_label.add_theme_color_override("font_color", UiTheme.GOLD)
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_label)

func _build_roll_fab() -> void:
	primary_roll = PlayfulButtonScript.new()
	primary_roll.text = " Tirar dados"
	primary_roll.custom_minimum_size = Vector2(200, 52)
	primary_roll.add_theme_font_size_override("font_size", 17)
	if UiTheme.display_font != null:
		primary_roll.add_theme_font_override("font", UiTheme.display_font)
	primary_roll.anchor_left = 0.5
	primary_roll.anchor_right = 0.5
	primary_roll.anchor_top = 1.0
	primary_roll.anchor_bottom = 1.0
	primary_roll.offset_left = -100
	primary_roll.offset_right = 100
	primary_roll.offset_top = -96
	primary_roll.offset_bottom = -44
	UiIcons.apply(primary_roll, "dice", 24)
	primary_roll.pressed.connect(func() -> void: roll_pressed.emit())
	UiTheme.paint(primary_roll, "primary")
	add_child(primary_roll)
	roll_btn = primary_roll

## Rail lateral flotante (no footer): Mano / Construir / Cambiar.
func _build_action_rail() -> void:
	var rail := Panel.new()
	rail.mouse_filter = Control.MOUSE_FILTER_STOP
	rail.anchor_left = 1.0
	rail.anchor_right = 1.0
	rail.anchor_top = 0.5
	rail.anchor_bottom = 0.5
	rail.offset_left = -72
	rail.offset_right = -12
	rail.offset_top = -110
	rail.offset_bottom = 110
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.12, 0.14, 0.11, 0.88)
	box.border_color = UiTheme.SAGE_DEEP
	box.set_border_width_all(1)
	box.set_corner_radius_all(18)
	box.shadow_color = Color(0, 0, 0, 0.35)
	box.shadow_size = 8
	rail.add_theme_stylebox_override("panel", box)
	add_child(rail)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 8
	col.offset_right = -8
	col.offset_top = 10
	col.offset_bottom = -10
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	rail.add_child(col)
	for item in [["mano", "hand", "Mano"], ["build", "build", "Construir"], ["trade", "trade", "Cambiar"]]:
		var btn: Button = PlayfulButtonScript.new()
		btn.text = ""
		btn.tooltip_text = String(item[2])
		btn.custom_minimum_size = Vector2(48, 48)
		btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		UiIcons.apply(btn, String(item[1]), 26)
		var id := String(item[0])
		btn.pressed.connect(_toggle_sheet.bind(id))
		UiTheme.paint(btn, "quiet")
		col.add_child(btn)
		dock_btns[id] = btn

func _build_end_fab() -> void:
	end_btn = PlayfulButtonScript.new()
	end_btn.text = " Listo"
	end_btn.custom_minimum_size = Vector2(160, 48)
	end_btn.add_theme_font_size_override("font_size", 16)
	end_btn.anchor_left = 0.5
	end_btn.anchor_right = 0.5
	end_btn.anchor_top = 1.0
	end_btn.anchor_bottom = 1.0
	end_btn.offset_left = -80
	end_btn.offset_right = 80
	end_btn.offset_top = -96
	end_btn.offset_bottom = -48
	UiIcons.apply(end_btn, "check", 22)
	end_btn.pressed.connect(func() -> void: end_pressed.emit())
	UiTheme.paint(end_btn, "soft")
	add_child(end_btn)
	dock_btns["end"] = end_btn

func _build_sheets() -> void:
	dimmer = ColorRect.new()
	dimmer.color = Color(0, 0, 0, 0.45)
	dimmer.set_anchors_preset(Control.PRESET_FULL_RECT)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	dimmer.visible = false
	dimmer.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and ev.pressed:
			if _open == "guide":
				_hide_guide_sheet()
			else:
				_show_sheet("")
	)
	add_child(dimmer)
	sheet = Panel.new()
	sheet.visible = false
	sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	sheet.anchor_left = 0.0
	sheet.anchor_right = 1.0
	sheet.anchor_top = 1.0
	sheet.anchor_bottom = 1.0
	sheet.offset_left = 10.0
	sheet.offset_right = -10.0
	sheet.offset_top = -420.0
	sheet.offset_bottom = -16.0
	sheet.add_theme_stylebox_override("panel", UiTheme.panel_box())
	add_child(sheet)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 12
	col.offset_right = -12
	col.offset_top = 8
	col.offset_bottom = -8
	col.add_theme_constant_override("separation", 8)
	sheet.add_child(col)
	var head := HBoxContainer.new()
	head.gui_input.connect(_on_sheet_drag)
	sheet_title = _lab("", 18, false)
	sheet_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sheet_title)
	var close := Button.new()
	close.text = "Cerrar"
	close.custom_minimum_size = Vector2(88, 44)
	close.pressed.connect(func() -> void: _show_sheet(""))
	UiTheme.paint(close, "quiet")
	head.add_child(close)
	col.add_child(head)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	sheet_body = VBoxContainer.new()
	sheet_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet_body.add_theme_constant_override("separation", 8)
	scroll.add_child(sheet_body)
	hand_page = _make_hand_page()
	build_page = _make_build_page()
	trade_page = _make_trade_page()
	sheet_body.add_child(hand_page)
	sheet_body.add_child(build_page)
	sheet_body.add_child(trade_page)
	note_label = _lab("", 13)
	note_label.add_theme_color_override("font_color", UiTheme.INK_DIM)
	col.add_child(note_label)

func _make_hand_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 10)
	wrap.add_child(_lab("Mano de recursos", 15, false))
	you_hand = ResourceHandScript.new()
	you_hand.setup(0, _card_tex, true)
	you_hand.resource_selected.connect(_select_card)
	wrap.add_child(you_hand)
	_bind_hand_arrays(you_hand, you_counts, you_icons, you_badges)
	hand_blocks.append(you_hand)
	hand_names.append(you_hand._title)
	hand_marks.append(Panel.new())

	rival_hand = ResourceHandScript.new()
	rival_hand.setup(1, _card_tex, false)
	wrap.add_child(rival_hand)
	_bind_hand_arrays(rival_hand, rival_counts, rival_icons, rival_badges)
	hand_blocks.append(rival_hand)
	hand_names.append(rival_hand._title)
	hand_marks.append(Panel.new())
	rival_summary = _lab("", 12)
	rival_summary.add_theme_color_override("font_color", UiTheme.INK_DIM)
	wrap.add_child(rival_summary)
	return wrap

func _bind_hand_arrays(hand: ResourceHand, counts: Array[Label], icons: Array[CanvasItem], badges: Array[Panel]) -> void:
	counts.clear()
	icons.clear()
	badges.clear()
	for lab in hand.count_labels:
		counts.append(lab)
	for lab in hand.ware_counts:
		counts.append(lab)
	for ic in hand.art_icons:
		icons.append(ic)
	for ic in hand.ware_icons:
		icons.append(ic)
	for _i in hand.count_labels.size():
		badges.append(Panel.new())
	for b in hand.ware_badges:
		badges.append(b)

func _make_build_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	cost_label = _lab("", 14)
	wrap.add_child(cost_label)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 6)
	road_btn = _button("Camino")
	set_btn = _button("Puesto")
	up_btn = _button("Granja")
	road_btn.pressed.connect(func() -> void: tool_pressed.emit("road"))
	set_btn.pressed.connect(func() -> void: tool_pressed.emit("settlement"))
	up_btn.pressed.connect(func() -> void: tool_pressed.emit("upgrade"))
	for btn in [road_btn, set_btn, up_btn]:
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 48)
		tools.add_child(btn)
	wrap.add_child(tools)
	wrap.add_child(_lab("Tabla de progreso", 15, false))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 6)
	for i in 3:
		var btn := Button.new()
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 56)
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func() -> void: advance_pressed.emit(i))
		cols.add_child(btn)
		track_btns.append(btn)
	wrap.add_child(cols)
	rival_chart = _lab("", 13, false)
	rival_chart.add_theme_color_override("font_color", UiTheme.INK_DIM)
	wrap.add_child(rival_chart)
	return wrap

func _make_trade_page() -> Control:
	var wrap := VBoxContainer.new()
	wrap.add_theme_constant_override("separation", 8)
	wrap.add_child(_lab("Cambio con el mercado (no hay trueque entre jugadores).", 13))
	var give_row := HBoxContainer.new()
	give_row.add_theme_constant_override("separation", 4)
	give_row.add_child(_lab("Doy", 14, false))
	_slot_n = GameScript.RES_COUNT + GameScript.WARE_NAME.size()
	for i in _slot_n:
		var btn := _tiny(_card_tex[i] if i < _card_tex.size() else null)
		btn.pressed.connect(func() -> void: give_pressed.emit(i))
		give_row.add_child(btn)
		give_btns.append(btn)
	wrap.add_child(give_row)
	var take_row := HBoxContainer.new()
	take_row.add_theme_constant_override("separation", 4)
	take_row.add_child(_lab("Quiero", 14, false))
	for i in _slot_n:
		var btn := _tiny(_card_tex[i] if i < _card_tex.size() else null)
		btn.pressed.connect(func() -> void: take_pressed.emit(i))
		take_row.add_child(btn)
		take_btns.append(btn)
	wrap.add_child(take_row)
	trade_btn = _button("Cambiar")
	trade_btn.custom_minimum_size = Vector2(0, 48)
	trade_btn.pressed.connect(func() -> void: trade_pressed.emit())
	wrap.add_child(trade_btn)
	return wrap

func _build_pause() -> void:
	game_menu = GameMenuDropdownScript.new() as GameMenuDropdown
	add_child(game_menu)
	pause_panel = game_menu
	motion_btn = game_menu.motion_btn
	restart_btn = game_menu.restart_btn
	game_menu.motion_pressed.connect(func() -> void: motion_pressed.emit())
	game_menu.restart_pressed.connect(func() -> void: restart_pressed.emit())
	game_menu.resume_pressed.connect(func() -> void: resume_closed())
	game_menu.menu_pressed.connect(func() -> void: menu_pressed.emit())
	game_menu.guide_pressed.connect(func() -> void:
		guide_pressed.emit()
		_show_guide_sheet()
	)
	game_menu.hand_pressed.connect(func() -> void: _toggle_sheet("mano"))
	game_menu.build_pressed.connect(func() -> void: _toggle_sheet("build"))
	game_menu.trade_pressed.connect(func() -> void: _toggle_sheet("trade"))
	game_menu.end_turn_pressed.connect(func() -> void: end_pressed.emit())
	game_menu.open_changed.connect(func(is_open: bool) -> void:
		_paint_menu_toggle(is_open)
		if not is_open:
			dimmer.visible = _open == "mano" or _open == "trade" or _open == "guide"
	)
	_build_guide_sheet()

func resume_closed() -> void:
	_show_pause(false)

var _guide_sheet: Panel

func _build_guide_sheet() -> void:
	_guide_sheet = Panel.new()
	_guide_sheet.visible = false
	_guide_sheet.mouse_filter = Control.MOUSE_FILTER_STOP
	_guide_sheet.anchor_left = 0.08
	_guide_sheet.anchor_right = 0.92
	_guide_sheet.anchor_top = 0.18
	_guide_sheet.anchor_bottom = 0.78
	_guide_sheet.add_theme_stylebox_override("panel", UiTheme.paper_box())
	_guide_sheet.z_index = 70
	add_child(_guide_sheet)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 18
	col.offset_right = -18
	col.offset_top = 16
	col.offset_bottom = -16
	col.add_theme_constant_override("separation", 10)
	_guide_sheet.add_child(col)
	var title := Label.new()
	title.text = "Cómo se juega"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UiTheme.INK_PAPER)
	if UiTheme.display_font != null:
		title.add_theme_font_override("font", UiTheme.display_font)
	col.add_child(title)
	for block in [
		["Dados", "El 6 y el 8 producen más. Si sale 7, hay sequía y nadie cobra."],
		["Construir", "Camino: madera y arcilla. Puesto: una de cada prima clásica. Granja: 2 trigo y 2 piedra."],
		["Progreso", "Papel, tela y moneda suben Taller, Mercado y Consejo. Gana quien llega a 5."],
	]:
		var h := Label.new()
		h.text = String(block[0])
		h.add_theme_font_size_override("font_size", 15)
		h.add_theme_color_override("font_color", UiTheme.SAGE_DEEP)
		if UiTheme.bold_font != null:
			h.add_theme_font_override("font", UiTheme.bold_font)
		col.add_child(h)
		var b := Label.new()
		b.text = String(block[1])
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.add_theme_font_size_override("font_size", 14)
		b.add_theme_color_override("font_color", Color("5a4a3a"))
		col.add_child(b)
	var close := Button.new()
	close.text = "Entendido"
	close.custom_minimum_size = Vector2(0, 44)
	UiTheme.paint(close, "primary")
	close.pressed.connect(func() -> void: _hide_guide_sheet())
	col.add_child(close)

func _show_guide_sheet() -> void:
	_open = "guide"
	if _guide_sheet != null:
		_guide_sheet.visible = true
	dimmer.visible = true
	if not UiTheme.reduce_motion and _guide_sheet != null:
		_guide_sheet.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_guide_sheet, "modulate:a", 1.0, 0.16)

func _hide_guide_sheet() -> void:
	if _guide_sheet != null:
		_guide_sheet.visible = false
	if _open == "guide":
		_open = ""
	dimmer.visible = false

func _hand_block(player: int, counts: Array[Label], icons: Array[CanvasItem], badges: Array[Panel], height: int) -> Control:
	var wrap := VBoxContainer.new()
	var head := HBoxContainer.new()
	var mark := _swatch(GameScript.PLAYER_COLOR[player])
	var title := _lab(GameScript.PLAYER_NAME[player], 14, false)
	title.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[player])
	head.add_child(mark)
	head.add_child(title)
	wrap.add_child(head)
	if height <= 0:
		rival_summary = _lab("cartas del vecino", 13)
		rival_summary.add_theme_color_override("font_color", UiTheme.INK_DIM)
		wrap.add_child(rival_summary)
		for i in 7:
			var dummy := Label.new()
			dummy.visible = false
			counts.append(dummy)
			icons.append(dummy)
			badges.append(Panel.new())
	else:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var names: PackedStringArray = PackedStringArray(GameScript.RES_NAME) + PackedStringArray(GameScript.WARE_NAME)
		for i in _card_tex.size():
			row.add_child(_card(_card_tex[i], names[i], counts, icons, badges, height, player == 0, i))
		wrap.add_child(row)
	hand_blocks.append(wrap)
	hand_names.append(title)
	hand_marks.append(mark)
	return wrap

func _card(tex: Texture2D, name: String, counts: Array[Label], icons: Array[CanvasItem], badges: Array[Panel], height: int, selectable: bool = false, index: int = 0) -> Panel:
	var card := Panel.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(0, height)
	card.add_theme_stylebox_override("panel", UiTheme.paper_box())
	if selectable:
		card.mouse_filter = Control.MOUSE_FILTER_STOP
		card.gui_input.connect(func(ev: InputEvent) -> void:
			if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
				_select_card(index)
		)
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.offset_left = 3
	col.offset_right = -3
	col.offset_top = 3
	col.offset_bottom = -3
	col.add_theme_constant_override("separation", 2)
	card.add_child(col)
	var icon := TextureRect.new()
	icon.texture = tex
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	icon.custom_minimum_size.y = height - 28
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon)
	icons.append(icon)
	var name_l := _lab(name, 12, false)
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_color_override("font_color", Color("2a1c10"))
	col.add_child(name_l)
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(22, 18)
	badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var badge_box := StyleBoxFlat.new()
	badge_box.bg_color = UiTheme.PANEL
	badge_box.set_corner_radius_all(3)
	badge.add_theme_stylebox_override("panel", badge_box)
	var count := Label.new()
	count.text = "0"
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count.set_anchors_preset(Control.PRESET_FULL_RECT)
	count.add_theme_font_size_override("font_size", 13)
	count.add_theme_color_override("font_color", UiTheme.INK)
	badge.add_child(count)
	col.add_child(badge)
	badges.append(badge)
	counts.append(count)
	return card

func sync(game, ctx: Dictionary) -> void:
	if instruction_label == null or game == null:
		return
	var failed: bool = bool(ctx.get("failed", false))
	var human_roll: bool = bool(ctx.get("human_roll", false))
	var human_build: bool = bool(ctx.get("human_build", false))
	instruction_label.text = String(ctx.get("prompt", ""))
	instruction_label.add_theme_color_override("font_color", UiTheme.GOLD if failed else UiTheme.INK)
	var you_now: bool = int(game.current_player) == 0 and not bool(ctx.get("ai", false))
	turn_label.text = "Vos · tu turno" if you_now else "Vecino · espera"
	turn_label.add_theme_color_override("font_color", GameScript.PLAYER_COLOR[0 if you_now else 1])
	score_you.text = "%d/%d" % [game.scores[0], GameScript.WIN]
	score_rival.text = str(game.scores[1])
	var dice_busy: bool = bool(ctx.get("dice_busy", false))
	var hold: bool = dice_busy and bool(ctx.get("hold_counts", false))
	var hands_you: Array = ctx.get("hands_you", []) as Array if hold else []
	var hands_rival: Array = ctx.get("hands_rival", []) as Array if hold else []
	var wares_you: Array = ctx.get("wares_you", []) as Array if hold else []
	if rival_n != null:
		var n := 0
		for i in GameScript.RES_COUNT:
			n += int(hands_rival[i]) if hold and i < hands_rival.size() else int(game.hands[1][i])
		for i in 3:
			n += int(game.wares[1][i])
		rival_n.text = "%d cartas" % n
		if rival_summary != null:
			var h1: Array = hands_rival if hold and hands_rival.size() >= 5 else game.hands[1]
			rival_summary.text = "M%d A%d T%d P%d L%d · Pa%d Te%d Mo%d" % [
				int(h1[0]), int(h1[1]), int(h1[2]), int(h1[3]), int(h1[4]),
				int(game.wares[1][0]), int(game.wares[1][1]), int(game.wares[1][2]),
			]
	for i in mini(GameScript.RES_COUNT, res_labs.size()):
		var have := int(hands_you[i]) if hold and i < hands_you.size() else int(game.hands[0][i])
		res_labs[i].text = str(have) if i < _card_tex.size() else "%s %d" % [GameScript.RES_LETTER[i], have]
		var need := 0
		if bool(ctx.get("human_build", false)):
			var cost: Array = game.cost_of(0, String(ctx.get("tool", "settlement")))
			if i < cost.size():
				need = int(cost[i])
		if need > have:
			res_labs[i].add_theme_color_override("font_color", UiTheme.GOLD)
		else:
			res_labs[i].add_theme_color_override("font_color", GameScript.RES_COLOR[i])
	if dice_busy:
		dice_label.text = "…"
		dice_parts.visible = false
		dice_edge.border_color = UiTheme.GOLD
	elif game.last_roll == 0:
		dice_label.text = "—"
		dice_parts.visible = false
		dice_edge.border_color = UiTheme.BORDER
	else:
		dice_label.text = str(game.last_roll)
		dice_parts.visible = true
		dice_parts.text = "%d+%d" % [game.die_a, game.die_b]
		dice_edge.border_color = Color("b42318") if game.last_roll == 7 else UiTheme.GOLD
	primary_roll.visible = human_roll or dice_busy
	primary_roll.disabled = not human_roll or dice_busy
	primary_roll.text = " Tirando…" if dice_busy else " Tirar dados"
	UiTheme.paint(primary_roll, "primary" if human_roll and not dice_busy else "quiet")
	end_btn.visible = human_build and not dice_busy
	end_btn.disabled = not human_build
	end_btn.text = " Listo"
	UiTheme.paint(end_btn, "soft" if human_build else "quiet")
	var tool := String(ctx.get("tool", "settlement"))
	road_btn.disabled = not human_build
	set_btn.disabled = not human_build
	up_btn.disabled = not human_build
	road_btn.text = ("● " if tool == "road" and human_build else "") + "Camino"
	set_btn.text = ("● " if tool == "settlement" and human_build else "") + "Puesto"
	up_btn.text = ("● " if tool == "upgrade" and human_build else "") + "Granja"
	UiTheme.paint(road_btn, String(ctx.get("road_role", "quiet")))
	UiTheme.paint(set_btn, String(ctx.get("set_role", "quiet")))
	UiTheme.paint(up_btn, String(ctx.get("up_role", "quiet")))
	cost_label.text = String(ctx.get("cost_line", ""))
	cost_label.add_theme_color_override("font_color", UiTheme.INK if bool(ctx.get("afford", true)) else UiTheme.GOLD)
	rival_chart.text = "Vecino  " + String(ctx.get("rival_chart", ""))
	for i in track_btns.size():
		track_btns[i].text = String(ctx.get("track_%d" % i, GameScript.TRACK_NAME[i]))
		track_btns[i].disabled = not human_build
		UiTheme.paint(track_btns[i], "quiet")
	var res_n := GameScript.RES_COUNT
	for i in give_btns.size():
		var ware := i >= res_n
		var idx := i - res_n if ware else i
		var on := human_build and bool(ctx.get("give_ware", false)) == ware and int(ctx.get("give_sel", 0)) == idx
		give_btns[i].disabled = not human_build
		UiTheme.paint(give_btns[i], "chip_on" if on else "chip")
	for i in take_btns.size():
		var ware := i >= res_n
		var idx := i - res_n if ware else i
		var on := human_build and bool(ctx.get("take_ware", false)) == ware and int(ctx.get("take_sel", 0)) == idx
		take_btns[i].disabled = not human_build
		UiTheme.paint(take_btns[i], "chip_on" if on else "chip")
	trade_btn.text = String(ctx.get("trade_deal", "Cambiar"))
	trade_btn.disabled = not human_build
	UiTheme.paint(trade_btn, "primary" if bool(ctx.get("trade_ready", false)) else "chip")
	if you_hand != null:
		if hold and hands_you.size() >= GameScript.RES_COUNT:
			you_hand.sync_counts(hands_you, wares_you if wares_you.size() >= 3 else game.wares[0])
		else:
			you_hand.sync_game(game)
	if rival_hand != null:
		if hold and hands_rival.size() >= GameScript.RES_COUNT:
			rival_hand.sync_counts(hands_rival, game.wares[1])
		else:
			rival_hand.sync_game(game)
	_paint_counts(game, you_counts, you_icons, 0, ctx)
	_paint_counts(game, rival_counts, rival_icons, 1, ctx)
	var live: bool = game.phase != GameScript.Phase.OVER
	if you_hand != null:
		you_hand.mark_active(live and int(game.current_player) == 0)
	if rival_hand != null:
		rival_hand.mark_active(live and int(game.current_player) == 1)
	var tail: PackedStringArray = PackedStringArray()
	var from := maxi(0, game.log.size() - 2)
	for i in range(from, game.log.size()):
		tail.append(game.log[i])
	if note_label != null and _open != "mano":
		note_label.text = "\n".join(tail)
	if game_menu != null:
		game_menu.set_calm(bool(ctx.get("calm", false)))
	_paint_menu_toggle(pause_open())
	for id in ["mano", "build", "trade"]:
		var b: Button = dock_btns.get(id) as Button
		if b == null:
			continue
		var on: bool = _open == id
		UiTheme.paint(b, "chip_on" if on else "quiet")
		if b is PlayfulButton:
			(b as PlayfulButton).set_selected(on)

func _paint_counts(game, counts: Array[Label], icons: Array[CanvasItem], player: int, ctx: Dictionary) -> void:
	var slots := GameScript.RES_COUNT + GameScript.WARE_NAME.size()
	if counts.size() < slots:
		return
	var hold: bool = bool(ctx.get("hold_counts", false))
	var hands: Array = (ctx.get("hands_you", []) as Array) if player == 0 else (ctx.get("hands_rival", []) as Array)
	var wares: Array = (ctx.get("wares_you", []) as Array) if player == 0 else []
	for i in slots:
		var value := 0
		if i < GameScript.RES_COUNT:
			if hold and i < hands.size():
				value = int(hands[i])
			else:
				value = int(game.hands[player][i])
		else:
			var wi := i - GameScript.RES_COUNT
			if hold and player == 0 and wi < wares.size():
				value = int(wares[wi])
			else:
				value = int(game.wares[player][wi])
		counts[i].text = str(value)
		if i < icons.size() and icons[i] != null:
			icons[i].modulate = Color(1, 1, 1, 1.0 if value > 0 else 0.45)

func _select_card(index: int) -> void:
	var names: PackedStringArray = PackedStringArray(GameScript.RES_NAME) + PackedStringArray(GameScript.WARE_NAME)
	var uses := [
		"Sirve para camino y puesto.",
		"Sirve para camino y puesto.",
		"Sirve para puesto y granja.",
		"Sirve para puesto y granja.",
		"Se cosecha en praderas. Se cambia o se guarda; no entra en costos de construcción.",
		"Sube el Taller. No hay cartas de desarrollo.",
		"Sube el Mercado (habilita el cambio). No hay cartas de desarrollo.",
		"Sube el Consejo. No hay cartas de desarrollo.",
	]
	if index >= 0 and index < names.size() and note_label != null:
		note_label.text = "%s · %s" % [names[index], uses[index]]

func _toggle_sheet(id: String) -> void:
	if _open == id:
		_show_sheet("")
	else:
		_show_sheet(id)

func _show_sheet(id: String) -> void:
	_hide_guide_sheet()
	_open = id
	var show: bool = id != ""
	dimmer.visible = id == "mano" or id == "trade"
	sheet.visible = show
	hand_page.visible = id == "mano"
	build_page.visible = id == "build"
	trade_page.visible = id == "trade"
	match id:
		"mano":
			sheet_title.text = "Mano"
			note_label.text = "Esta partida no usa cartas de desarrollo."
		"build":
			sheet_title.text = "Construir"
			note_label.text = "Elegí una pieza y tocá el mapa. Las rayas y puntos blancos marcan lo válido."
		"trade":
			sheet_title.text = "Cambiar"
			note_label.text = "El Mercado habilita el cambio. No hay trueque con el vecino."
		_:
			sheet_title.text = ""
	AnimUtil.kill(_sheet_tw)
	_sheet_tw = null
	if show and not UiTheme.reduce_motion:
		sheet.modulate.a = 0.0
		_sheet_tw = create_tween()
		_sheet_tw.tween_property(sheet, "modulate:a", 1.0, 0.14)
	elif show:
		sheet.modulate.a = 1.0
	layout_changed.emit()

func _on_sheet_drag(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var btn := ev as InputEventMouseButton
		if btn.pressed:
			_drag_from = btn.position
		elif btn.position.y - _drag_from.y > 40.0:
			_show_sheet("")
	elif ev is InputEventScreenDrag and (ev as InputEventScreenDrag).relative.y > 12.0:
		_show_sheet("")

func _show_pause(on: bool) -> void:
	if game_menu == null:
		return
	if on:
		if _open != "":
			_show_sheet("")
		game_menu.open_menu()
	else:
		game_menu.close_menu()
	dimmer.visible = _open == "mano" or _open == "trade"
	_paint_menu_toggle(on)

func _chip(title: String, value: Label, tone: Color) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", -2)
	var t := _lab(title, 11, false)
	t.add_theme_color_override("font_color", tone)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	box.add_child(value)
	return box

func _bar_box() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(0.11, 0.09, 0.07, 0.92)
	box.border_color = UiTheme.BORDER
	box.set_border_width_all(1)
	box.set_corner_radius_all(12)
	return box

func _swatch(col: Color) -> Panel:
	var mark := Panel.new()
	mark.custom_minimum_size = Vector2(12, 12)
	mark.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var edge := StyleBoxFlat.new()
	edge.bg_color = col
	edge.set_corner_radius_all(2)
	mark.add_theme_stylebox_override("panel", edge)
	return mark

func _lab(text: String, size: int, wrap: bool = true) -> Label:
	var lab := Label.new()
	lab.text = text
	lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	lab.add_theme_font_size_override("font_size", size)
	lab.add_theme_color_override("font_color", UiTheme.INK)
	return lab

func _button(text: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.custom_minimum_size = Vector2(0, 44)
	btn.add_theme_font_size_override("font_size", 16)
	return btn

func _icon_btn(text: String) -> Button:
	var btn := _button(text)
	btn.custom_minimum_size = Vector2(48, 48)
	UiTheme.paint(btn, "quiet")
	return btn

func _menu_toggle_btn() -> Button:
	var btn: Button = PlayfulButtonScript.new()
	btn.text = " Menú"
	btn.custom_minimum_size = Vector2(100, 40)
	btn.add_theme_font_size_override("font_size", 15)
	if UiTheme.display_font != null:
		btn.add_theme_font_override("font", UiTheme.display_font)
	UiIcons.apply(btn, "menu", 20)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color("2e362c")
	normal.border_color = UiTheme.SAGE
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(12)
	normal.shadow_color = Color(0, 0, 0, 0.3)
	normal.shadow_size = 4
	normal.content_margin_left = 12
	normal.content_margin_right = 12
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color("3a4638")
	hover.border_color = UiTheme.GOLD
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color("222820")
	btn.add_theme_stylebox_override("normal", normal)
	btn.add_theme_stylebox_override("hover", hover)
	btn.add_theme_stylebox_override("pressed", pressed)
	btn.add_theme_stylebox_override("focus", hover)
	btn.add_theme_color_override("font_color", UiTheme.INK_SOFT)
	btn.add_theme_color_override("font_hover_color", UiTheme.GOLD)
	btn.add_theme_color_override("font_pressed_color", UiTheme.GOLD_HOVER)
	btn.tooltip_text = "Menú de partida"
	return btn

func _paint_menu_toggle(is_open: bool) -> void:
	if menu_btn == null:
		return
	menu_btn.text = " Cerrar" if is_open else " Menú"
	UiIcons.apply(menu_btn, "close" if is_open else "menu", 20)
	if menu_btn is PlayfulButton:
		(menu_btn as PlayfulButton).set_selected(is_open)
	var border := UiTheme.GOLD if is_open else UiTheme.SAGE
	for state in ["normal", "hover", "pressed", "focus"]:
		var box: StyleBox = menu_btn.get_theme_stylebox(state)
		if box is StyleBoxFlat:
			(box as StyleBoxFlat).border_color = border
			if is_open:
				(box as StyleBoxFlat).bg_color = Color("3a4638") if state == "hover" else Color("2e362c")

# Square crop of the card art: the subject sits in the middle ~60% of a cream
# canvas, so the full image shrinks it to a dot at 26 px.
func _res_icon(i: int) -> TextureRect:
	if i >= _card_tex.size() or _card_tex[i] == null:
		return null
	var src := _card_tex[i]
	var crop := AtlasTexture.new()
	crop.atlas = src
	var sz := src.get_size()
	crop.region = Rect2(sz * 0.17, sz * 0.66)
	var rect := TextureRect.new()
	rect.texture = crop
	rect.custom_minimum_size = Vector2(26, 26)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return rect

func _tiny(icon: Texture2D) -> Button:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(44, 44)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if icon != null:
		btn.icon = icon
		btn.expand_icon = true
		btn.add_theme_constant_override("icon_max_width", 28)
	return btn
