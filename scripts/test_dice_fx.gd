extends SceneTree

## Smoke: DiceRollFx presenta caras de match; combos clave; cancel/skip.

const DiceRollFxScript := preload("res://scripts/dice_roll_fx.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

var _fails := 0

func _fail(msg: String) -> void:
	_fails += 1
	push_error(msg)
	print("FAIL: ", msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	UiTheme.set_reduce_motion(true)
	var root := Node.new()
	get_root().add_child(root)
	var fx = DiceRollFxScript.new()
	root.add_child(fx)
	await process_frame

	var combos := [[1, 1], [3, 4], [5, 6], [2, 6], [4, 3], [6, 6]]
	for pair in combos:
		var a: int = int(pair[0])
		var b: int = int(pair[1])
		fx.play(a, b, a + b)
		var got: int = await fx.finished
		if got != a + b:
			_fail("total %d for %d+%d" % [got, a, b])
		if int(fx._final_a) != a or int(fx._final_b) != b:
			_fail("faces stored %d+%d expected %d+%d" % [fx._final_a, fx._final_b, a, b])

	# Skip path with motion on — finished must still carry real total
	UiTheme.set_reduce_motion(false)
	fx.play(2, 5, 7)
	await process_frame
	fx.skip_now()
	var skip_got: int = await fx.finished
	if skip_got != 7:
		_fail("skip total %d" % skip_got)
	if int(fx._final_a) != 2 or int(fx._final_b) != 5:
		_fail("skip faces %d+%d" % [fx._final_a, fx._final_b])

	# Cancel no emit
	var cancel_n := 0
	var on_cancel := func(_t: int) -> void:
		cancel_n += 1
	fx.finished.connect(on_cancel)
	fx.play(1, 2, 3)
	fx.cancel()
	await create_timer(0.05).timeout
	fx.finished.disconnect(on_cancel)
	if cancel_n != 0 or fx.is_busy():
		_fail("cancel leaked")

	if _fails > 0:
		push_error("dice fx test failed: %d" % _fails)
		quit(1)
	else:
		print("LINDERO DICE FX OK")
		quit(0)
