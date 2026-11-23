extends SceneTree

## Auditoría PROMPT7: reglas + presentación (cartas, harvest, dados, menú) en flujo real.
## Headless-friendly para lógica; carga main.tscn para wiring HUD/FX.

const GameScript := preload("res://scripts/match.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")
const HarvestFxScript := preload("res://scripts/harvest_fx.gd")
const DiceRollFxScript := preload("res://scripts/dice_roll_fx.gd")
const MenuScript := preload("res://scripts/game_menu_dropdown.gd")
const HandScript := preload("res://scripts/resource_hand.gd")

var fails := 0
var notes: PackedStringArray = PackedStringArray()

func _fail(msg: String) -> void:
	fails += 1
	push_error("[AUDIT] " + msg)
	print("FAIL: ", msg)

func _ok(msg: String) -> void:
	print("OK: ", msg)

func _note(msg: String) -> void:
	notes.append(msg)
	print("NOTE: ", msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== AUDIT POLISH PROMPT7 ===")
	UiTheme.set_reduce_motion(true)
	_audit_five_resources()
	_audit_sheep_produce()
	_audit_consume_trade()
	_audit_hand_sync()
	await _audit_harvest_cleanup()
	await _audit_dice_integrity()
	await _audit_menu()
	_audit_regression_setup_build()
	await _audit_main_wiring()
	print("=== NOTES ===")
	for n in notes:
		print("- ", n)
	print("=== AUDIT DONE fails=%d ===" % fails)
	quit(1 if fails > 0 else 0)

func _finish_setup(g) -> String:
	var guard := 0
	while g.phase == GameScript.Phase.SETUP_SETTLEMENT or g.phase == GameScript.Phase.SETUP_ROAD:
		guard += 1
		if guard > 12:
			return "setup stuck"
		var p: int = g.current_player
		if g.phase == GameScript.Phase.SETUP_SETTLEMENT:
			var err: String = g.place_settlement(p, g.choose_setup_vertex(p))
			if err != "":
				return err
		else:
			var err2: String = g.place_road(p, g.choose_setup_road(p))
			if err2 != "":
				return err2
	return ""

func _audit_five_resources() -> void:
	if GameScript.RES_COUNT != 5 or GameScript.RES_NAME.size() != 5:
		_fail("RES_COUNT/RES_NAME not 5")
		return
	var expected := ["Madera", "Arcilla", "Trigo", "Piedra", "Lana"]
	for i in 5:
		if GameScript.RES_NAME[i] != expected[i]:
			_fail("RES_NAME[%d]=%s" % [i, GameScript.RES_NAME[i]])
			return
	var paths := [
		"res://art/icono_madera.jpg",
		"res://art/icono_arcilla.jpg",
		"res://art/icono_grano.jpg",
		"res://art/icono_piedra.jpg",
		"res://art/icono_ovejas.jpg",
	]
	for p in paths:
		if not ResourceLoader.exists(p):
			_fail("missing asset %s" % p)
			return
	# Meadow tiles must map to SHEEP (4)
	var g = GameScript.new()
	g.new_game()
	var sheep := 0
	for h in g.hexes:
		if int(h.resource) == GameScript.Goods.SHEEP:
			sheep += 1
	if sheep < 1:
		_fail("no meadow/sheep hexes on board")
		return
	_ok("five resources + sheep hexes (%d)" % sheep)

func _audit_sheep_produce() -> void:
	var g = GameScript.new()
	g.new_game()
	var sheep_hex := -1
	for i in g.hexes.size():
		if int(g.hexes[i].resource) == GameScript.Goods.SHEEP:
			sheep_hex = i
			break
	if sheep_hex < 0:
		_fail("no sheep hex")
		return
	g.buildings.clear()
	g.buildings[int(g.hexes[sheep_hex].vertices[0])] = {"player": 0, "level": 1}
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.wares = [[0, 0, 0], [0, 0, 0]]
	var num := int(g.hexes[sheep_hex].number)
	g.produce(num)
	if int(g.hands[0][GameScript.Goods.SHEEP]) < 1:
		_fail("settlement on sheep did not pay Lana")
		return
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.wares = [[0, 0, 0], [0, 0, 0]]
	g.buildings[int(g.hexes[sheep_hex].vertices[0])] = {"player": 0, "level": 2}
	g.produce(num)
	if int(g.hands[0][GameScript.Goods.SHEEP]) != 1 or int(g.wares[0][GameScript.Ware.CLOTH]) != 1:
		_fail("sheep farm should pay 1 Lana + 1 Tela, got hands=%s wares=%s" % [g.hands[0], g.wares[0]])
		return
	_ok("sheep produce settlement+farm")

func _audit_consume_trade() -> void:
	var g = GameScript.new()
	g.new_game()
	var err := _finish_setup(g)
	if err != "":
		_fail("setup: " + err)
		return
	g.forced_roll = 7
	err = g.roll(0)
	if err != "" or g.phase != GameScript.Phase.BUILD:
		_fail("need BUILD for consume: " + err)
		return
	g.hands[0] = [2, 2, 2, 2, 1]
	g.wares[0] = [0, 0, 0]
	# Spend on road
	var before_w := int(g.hands[0][GameScript.Goods.WOOD])
	var before_c := int(g.hands[0][GameScript.Goods.CLAY])
	var roads: Array = g.legal_roads(0)
	if roads.is_empty():
		_fail("no legal roads for consume test")
		return
	err = g.place_road(0, String(roads[0]))
	if err != "":
		_fail("place_road: " + err)
		return
	if int(g.hands[0][GameScript.Goods.WOOD]) != before_w - 1 or int(g.hands[0][GameScript.Goods.CLAY]) != before_c - 1:
		_fail("road did not consume wood+clay")
		return
	# Trade: Mercado 1 → rate 4:1
	g.progress[0][GameScript.Track.MERCADO] = 1
	g.hands[0][GameScript.Goods.WOOD] = 4
	g.hands[0][GameScript.Goods.GRAIN] = 0
	err = g.trade(0, GameScript.Goods.WOOD, GameScript.Goods.GRAIN, false)
	if err != "":
		_fail("trade 4:1: " + err)
		return
	if int(g.hands[0][GameScript.Goods.WOOD]) != 0 or int(g.hands[0][GameScript.Goods.GRAIN]) != 1:
		_fail("trade hands wood=%d grain=%d" % [g.hands[0][GameScript.Goods.WOOD], g.hands[0][GameScript.Goods.GRAIN]])
		return
	_ok("consume via road + trade 4:1")

func _audit_hand_sync() -> void:
	var root := Control.new()
	root.size = Vector2(800, 600)
	get_root().add_child(root)
	var tex: Array[Texture2D] = []
	for name in ["icono_madera", "icono_arcilla", "icono_grano", "icono_piedra", "icono_ovejas", "icono_papel", "icono_tela", "icono_moneda"]:
		tex.append(load("res://art/%s.jpg" % name))
	var hand = HandScript.new()
	root.add_child(hand)
	hand.setup(0, tex, true)
	var g = GameScript.new()
	g.new_game()
	g.hands[0] = [3, 1, 0, 2, 4]
	g.wares[0] = [1, 0, 2]
	hand.sync_game(g)
	if hand.cards.size() != 5:
		_fail("hand cards != 5")
		return
	for i in 5:
		var card = hand.cards[i]
		var shown := int(card.count_node().text) if card.count_node() != null else -1
		# ResourceCard may show count in label
		if card.has_method("set_count"):
			pass
		var n := int(g.hands[0][i])
		# Read via sync state: re-sync and check label text
		if hand.count_labels[i].text != str(n):
			_fail("hand label[%d]=%s expected %d" % [i, hand.count_labels[i].text, n])
			return
	if hand.ware_counts[0].text != "1" or hand.ware_counts[2].text != "2":
		_fail("ware sync mismatch")
		return
	# Inventory mutation reflected
	g.hands[0][GameScript.Goods.SHEEP] = 0
	hand.sync_game(g)
	if hand.count_labels[GameScript.Goods.SHEEP].text != "0":
		_fail("hand did not drop Lana to 0")
		return
	root.queue_free()
	_ok("ResourceHand sync 5 primas + wares")

func _audit_harvest_cleanup() -> void:
	var root := Control.new()
	root.size = Vector2(1280, 720)
	get_root().add_child(root)
	var fx = HarvestFxScript.new()
	root.add_child(fx)
	await process_frame
	UiTheme.set_reduce_motion(false)
	var arrivals := 0
	for i in 5:
		fx.play_card(null, Color.WHITE, Vector2(100, 100), Vector2(400, 200), 0.0, func() -> void: arrivals += 1)
	if fx.active_count() < 1:
		_fail("harvest flyers not created")
		return
	fx.clear_all()
	await process_frame
	if fx.active_count() != 0:
		_fail("clear_all left %d flyers" % fx.active_count())
		return
	# Cap + consecutive
	for i in 40:
		fx.play_card(null, Color.WHITE, Vector2(10, 10), Vector2(200, 200), 0.0)
	if fx.active_count() > 28:
		_fail("MAX_ACTIVE exceeded: %d" % fx.active_count())
		return
	fx.clear_all()
	await process_frame
	UiTheme.set_reduce_motion(true)
	if not UiTheme.reduce_motion:
		_fail("UiTheme.reduce_motion did not stick")
		return
	var box := {"n": 0}
	fx.play_card(null, Color.WHITE, Vector2.ZERO, Vector2.ONE, 0.0, func() -> void: box["n"] = int(box["n"]) + 1)
	if int(box["n"]) != 1:
		_fail("reduce_motion harvest should callback (got %d, calm=%s, active=%d)" % [box["n"], UiTheme.reduce_motion, fx.active_count()])
		return
	if fx.active_count() != 0:
		_fail("reduce_motion left flyers=%d" % fx.active_count())
		return
	root.queue_free()
	_ok("HarvestFx cleanup + cap + reduce_motion")
	_note("Harvest FX flies primas only; farm ware (papel/tela/moneda) has no flyer — visual gap, not inventory bug.")

func _audit_dice_integrity() -> void:
	var g = GameScript.new()
	g.new_game()
	var err := _finish_setup(g)
	if err != "":
		_fail(err)
		return
	for total in range(2, 13):
		if g.phase != GameScript.Phase.ROLL:
			err = g.end_turn(g.current_player)
			if err != "":
				_fail(err)
				return
		g.forced_roll = total
		err = g.roll(g.current_player)
		if err != "" or g.last_roll != total or g.die_a + g.die_b != total:
			_fail("forced %d -> %d+%d=%d" % [total, g.die_a, g.die_b, g.last_roll])
			return
		err = g.end_turn(g.current_player)
		if err != "":
			_fail(err)
			return
	# FX presents match faces
	var root := Control.new()
	get_root().add_child(root)
	var dice = DiceRollFxScript.new()
	root.add_child(dice)
	await process_frame
	UiTheme.set_reduce_motion(true)
	dice.play(4, 3, 7)
	var got: int = await dice.finished
	if got != 7:
		_fail("dice FX total got %d (faces %d+%d calm=%s)" % [got, dice._final_a, dice._final_b, UiTheme.reduce_motion])
		return
	if int(dice._final_a) != 4 or int(dice._final_b) != 3:
		_fail("dice FX faces %d+%d" % [dice._final_a, dice._final_b])
		return
	var cancel_emits := 0
	dice.finished.connect(func(_t: int) -> void: cancel_emits += 1)
	dice.play(6, 6, 12)
	dice.cancel()
	await create_timer(0.05).timeout
	if dice.is_busy():
		_fail("dice busy after cancel")
		return
	if cancel_emits != 0:
		_fail("cancel emitted finished")
		return
	root.queue_free()
	_ok("dice logic 2..12 + FX faces + cancel")

func _audit_menu() -> void:
	var root := Control.new()
	root.size = Vector2(1280, 720)
	get_root().add_child(root)
	var menu = MenuScript.new()
	root.add_child(menu)
	await process_frame
	UiTheme.set_reduce_motion(true)
	if menu.is_open():
		_fail("menu starts open")
		return
	menu.open_menu()
	if not menu.is_open():
		_fail("menu open")
		return
	menu.set_calm(true)
	var motion_kept := menu.is_open()
	menu.motion_btn.emit_signal("pressed")
	if not motion_kept or not menu.is_open():
		_fail("calm should keep menu open")
		return
	menu.resume_btn.emit_signal("pressed")
	await process_frame
	if menu.is_open():
		_fail("resume should close")
		return
	# Small resolution clamp
	root.size = Vector2(360, 640)
	DisplayServer.window_set_size(Vector2i(360, 640))
	menu.open_menu()
	await process_frame
	var panel: Control = menu.get_node_or_null(".") # layout via _panel
	# Access private-ish via method
	menu.close_menu()
	# Touch-like: open/close toggle
	menu.toggle_menu()
	menu.toggle_menu()
	await process_frame
	if menu.is_open():
		_fail("toggle closed failed")
		return
	root.queue_free()
	_ok("menu open/close/calm/toggle + narrow layout path")

func _audit_regression_setup_build() -> void:
	var g = GameScript.new()
	g.new_game()
	var err := _finish_setup(g)
	if err != "":
		_fail("regression setup: " + err)
		return
	if g.scores[0] != 2 or g.scores[1] != 2:
		_fail("setup scores")
		return
	g.forced_roll = 7
	err = g.roll(0)
	if err != "" or g.phase != GameScript.Phase.BUILD:
		_fail("roll to build")
		return
	g.hands[0] = [1, 1, 1, 1, 0]
	var verts: Array = g.legal_settlement_vertices(0)
	if verts.is_empty():
		_note("no legal settlement after drought — may be topology")
	else:
		err = g.place_settlement(0, int(verts[0]))
		if err != "":
			_fail("settlement: " + err)
			return
		if int(g.scores[0]) != 3:
			_fail("settlement score")
			return
	# Upgrade path
	g.hands[0] = [0, 0, 2, 2, 0]
	var mine := -1
	for vkey in g.buildings.keys():
		if int(g.buildings[vkey].player) == 0 and int(g.buildings[vkey].level) == 1:
			mine = int(vkey)
			break
	if mine >= 0:
		var sc := int(g.scores[0])
		err = g.upgrade(0, mine)
		if err != "":
			_fail("upgrade: " + err)
			return
		if int(g.scores[0]) != sc + 1 or int(g.buildings[mine].level) != 2:
			_fail("upgrade level/score")
			return
		_ok("regression settlement+upgrade")
	else:
		_note("no settlement to upgrade in this seed")
	_ok("regression setup+roll drought")

func _audit_main_wiring() -> void:
	print("--- main.tscn wiring ---")
	change_scene_to_file("res://scenes/main.tscn")
	await create_timer(0.8).timeout
	var main = current_scene
	if main == null or main.hud == null or main.game == null:
		_fail("main/hud/game missing")
		return
	if main.dice_fx == null:
		_fail("dice_fx not built")
		return
	if main.harvest_fx == null:
		_fail("harvest_fx not built")
		return
	if main.hud.game_menu == null:
		_fail("game_menu missing")
		return
	if main.hud.you_hand == null or main.hud.you_hand.cards.size() != 5:
		_fail("you_hand cards != 5")
		return
	# Finish setup quickly via AI-ish
	var guard := 0
	while (main.game.phase == GameScript.Phase.SETUP_SETTLEMENT or main.game.phase == GameScript.Phase.SETUP_ROAD) and guard < 12:
		guard += 1
		var p: int = main.game.current_player
		if main.game.phase == GameScript.Phase.SETUP_SETTLEMENT:
			main._after(main.game.place_settlement(p, main.game.choose_setup_vertex(p)))
		else:
			main._after(main.game.place_road(p, main.game.choose_setup_road(p)))
		await process_frame
	if main.game.phase != GameScript.Phase.ROLL:
		_fail("main not in ROLL after setup")
		return
	# Menu does not block forever
	main.hud._show_pause(true)
	await process_frame
	if not main.hud.pause_open() or not main.hud.blocks_board():
		_fail("pause should block board")
		return
	main.hud.close_pause()
	await process_frame
	if main.hud.pause_open():
		_fail("pause still open")
		return
	# Forced roll through presentation path
	UiTheme.set_reduce_motion(true)
	if int(main.game.phase) != GameScript.Phase.ROLL or int(main.game.current_player) != 0:
		_fail("expected human ROLL, phase=%s player=%s" % [main.game.phase, main.game.current_player])
		return
	main.game.forced_roll = 6
	main._after(main.game.roll(0))
	await process_frame
	await create_timer(0.45).timeout
	if int(main.game.last_roll) != 6:
		_fail("main roll last_roll != 6 got %d phase=%s" % [main.game.last_roll, main.game.phase])
		return
	if int(main.game.die_a) + int(main.game.die_b) != 6:
		_fail("main die faces mismatch %d+%d" % [main.game.die_a, main.game.die_b])
		return
	if main._dice_busy:
		_fail("dice still busy after reduce_motion settle")
		return
	# Double-roll blocked while busy
	main._dice_busy = true
	var roll_snap := int(main.game.last_roll)
	main._on_roll()
	if int(main.game.last_roll) != roll_snap:
		_fail("roll while busy mutated last_roll")
		return
	main._dice_busy = false
	# Hand sheet sync
	main.hud.dock_btns["mano"].pressed.emit()
	await process_frame
	main.hud.you_hand.sync_game(main.game)
	for i in 5:
		if main.hud.you_hand.count_labels[i].text != str(int(main.game.hands[0][i])):
			_fail("mano sheet desync res %d label=%s hand=%d" % [i, main.hud.you_hand.count_labels[i].text, main.game.hands[0][i]])
			return
	main.hud.close_sheets()
	# Menu does not invent actions: only existing signals
	var menu_signals := ["motion_pressed", "restart_pressed", "resume_pressed", "menu_pressed"]
	for s in menu_signals:
		if not main.hud.game_menu.has_signal(s):
			_fail("menu missing signal " + s)
			return
	_ok("main wiring: menu/dice/hand after real roll")
