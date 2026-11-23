extends SceneTree

## Stress + sync audit for dice / harvest / HUD hold / tween cleanup.

const GameScript := preload("res://scripts/match.gd")
const DiceRollFxScript := preload("res://scripts/dice_roll_fx.gd")
const HarvestFxScript := preload("res://scripts/harvest_fx.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

var _fails := 0

func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("FAIL: ", msg)

func _ok(msg: String) -> void:
	print("OK: ", msg)

func _init() -> void:
	call_deferred("_run")

func _finish_setup(g) -> String:
	var guard := 0
	while (g.phase == GameScript.Phase.SETUP_SETTLEMENT or g.phase == GameScript.Phase.SETUP_ROAD) and guard < 16:
		guard += 1
		var p: int = g.current_player
		if g.phase == GameScript.Phase.SETUP_SETTLEMENT:
			var err: String = String(g.place_settlement(p, g.choose_setup_vertex(p)))
			if err != "":
				return err
		else:
			var err2: String = String(g.place_road(p, g.choose_setup_road(p)))
			if err2 != "":
				return err2
	if g.phase != GameScript.Phase.ROLL:
		return "not in ROLL after setup"
	return ""

func _run() -> void:
	await _stress_dice()
	await _stress_main_pipeline()
	if _fails > 0:
		push_error("audit_anim failed: %d" % _fails)
		quit(1)
	else:
		print("=== AUDIT ANIM OK ===")
		quit(0)

func _stress_dice() -> void:
	print("--- dice stress ---")
	UiTheme.set_reduce_motion(false)
	var root := Control.new()
	get_root().add_child(root)
	var fx = DiceRollFxScript.new()
	root.add_child(fx)
	await process_frame
	var combos := [[1, 1], [3, 4], [5, 6], [2, 6], [6, 6], [1, 6]]
	for pair in combos:
		fx.play(int(pair[0]), int(pair[1]), int(pair[0]) + int(pair[1]))
		await process_frame
		fx.skip_now()
		var got: int = await fx.finished
		if got != int(pair[0]) + int(pair[1]):
			_fail("skip combo %s got %d" % [str(pair), got])
			root.queue_free()
			return
		if fx.is_busy():
			_fail("busy after skip")
			root.queue_free()
			return
	# Rapid replay without awaiting mid-tween (cancel path)
	for i in 8:
		fx.play(2, 3, 5)
		await process_frame
		fx.cancel()
		if fx.is_busy():
			_fail("busy after cancel loop %d" % i)
			root.queue_free()
			return
	# Full calm settle
	UiTheme.set_reduce_motion(true)
	for pair in combos:
		fx.play(int(pair[0]), int(pair[1]), int(pair[0]) + int(pair[1]))
		var got2: int = await fx.finished
		if got2 != int(pair[0]) + int(pair[1]):
			_fail("calm combo %s" % str(pair))
			root.queue_free()
			return
	# Harvest cleanup under spam
	var hfx = HarvestFxScript.new()
	root.add_child(hfx)
	await process_frame
	UiTheme.set_reduce_motion(false)
	var tex: Texture2D = null
	for i in 12:
		hfx.play_card(tex, Color.WHITE, Vector2(10, 10), Vector2(200, 80), 0.0)
	hfx.clear_all()
	await process_frame
	if hfx.active_count() != 0:
		_fail("harvest flyers after clear")
		root.queue_free()
		return
	root.queue_free()
	_ok("dice stress skip/cancel/calm + harvest clear")

func _stress_main_pipeline() -> void:
	print("--- main pipeline ---")
	UiTheme.set_reduce_motion(true)
	change_scene_to_file("res://scenes/main.tscn")
	await create_timer(0.9).timeout
	var main = current_scene
	if main == null or main.game == null or main.hud == null:
		_fail("main missing")
		return
	var guard := 0
	while (main.game.phase == GameScript.Phase.SETUP_SETTLEMENT or main.game.phase == GameScript.Phase.SETUP_ROAD) and guard < 16:
		guard += 1
		var p: int = main.game.current_player
		if main.game.phase == GameScript.Phase.SETUP_SETTLEMENT:
			main._after(main.game.place_settlement(p, main.game.choose_setup_vertex(p)))
		else:
			main._after(main.game.place_road(p, main.game.choose_setup_road(p)))
		await process_frame
	if main.game.phase != GameScript.Phase.ROLL or main.game.current_player != 0:
		_fail("expected human ROLL")
		return
	# Snapshot before roll
	var before: Array = []
	for i in 5:
		before.append(int(main.game.hands[0][i]))
	main.game.forced_roll = 8
	# Force motion on to exercise hold path briefly
	UiTheme.set_reduce_motion(false)
	main._after(main.game.roll(0))
	await process_frame
	if not main._dice_busy:
		_fail("expected dice_busy after roll with motion")
		return
	# HUD must hold pre-roll counts while busy
	for i in mini(5, main.hud.res_labs.size()):
		var shown := int(main.hud.res_labs[i].text)
		if shown != int(before[i]):
			_fail("HUD spoiled res %d shown=%d before=%d during dice" % [i, shown, before[i]])
			return
	if main.hud.dice_label.text != "…":
		_fail("dice chip should be … while busy, got '%s'" % main.hud.dice_label.text)
		return
	# Open/close menu during dice
	main.hud._show_pause(true)
	await process_frame
	main.hud.close_pause()
	await process_frame
	# Skip dice
	(main.dice_fx as DiceRollFx).skip_now()
	await (main.dice_fx as DiceRollFx).finished
	await process_frame
	if main._dice_busy:
		_fail("still busy after skip")
		return
	if int(main.game.last_roll) != 8:
		_fail("last_roll changed")
		return
	# Counts should now match logic
	for i in mini(5, main.hud.res_labs.size()):
		if int(main.hud.res_labs[i].text) != int(main.game.hands[0][i]):
			_fail("post-dice HUD desync res %d" % i)
			return
	# Double roll blocked
	main._dice_busy = true
	var snap := int(main.game.last_roll)
	main._on_roll()
	if int(main.game.last_roll) != snap:
		_fail("roll while busy mutated")
		return
	main._dice_busy = false
	# Toast spam should not crash
	for i in 5:
		main.hud.show_toast("toast %d" % i)
	await process_frame
	# Scene leave while harvest possible
	main._on_menu()
	await create_timer(0.4).timeout
	_ok("main hold-counts + skip + menu + scene leave")
