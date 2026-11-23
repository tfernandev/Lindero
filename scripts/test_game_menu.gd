extends SceneTree

## Smoke del menú desplegable: abrir/cerrar, calm, sin inventar acciones.

const MenuScript := preload("res://scripts/game_menu_dropdown.gd")
const UiTheme := preload("res://scripts/ui_theme.gd")

var fails := 0
var got_motion := 0
var got_restart := 0
var got_resume := 0
var got_menu := 0

func _fail(msg: String) -> void:
	fails += 1
	push_error(msg)
	print("FAIL: ", msg)

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	UiTheme.install(Control.new())
	UiTheme.set_reduce_motion(true)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(1280, 720)
	get_root().add_child(root)
	var menu = MenuScript.new()
	root.add_child(menu)
	await process_frame
	menu.motion_pressed.connect(func() -> void: got_motion += 1)
	menu.restart_pressed.connect(func() -> void: got_restart += 1)
	menu.resume_pressed.connect(func() -> void: got_resume += 1)
	menu.menu_pressed.connect(func() -> void: got_menu += 1)

	if menu.is_open():
		_fail("starts closed")
	menu.open_menu()
	await process_frame
	if not menu.is_open():
		_fail("open_menu")
	menu.set_calm(true)
	if not String(menu.motion_btn.text).contains("activa"):
		_fail("calm label")
	menu.motion_btn.emit_signal("pressed")
	if got_motion != 1:
		_fail("motion signal")
	if not menu.is_open():
		_fail("calm keeps menu open")
	if menu.guide_btn == null:
		_fail("guide_btn missing")
		return
	menu.resume_btn.emit_signal("pressed")
	await process_frame
	if got_resume != 1 or menu.is_open():
		_fail("resume closes")
	menu.open_menu()
	menu.restart_btn.emit_signal("pressed")
	await process_frame
	if got_restart != 1 or menu.is_open():
		_fail("restart closes")
	menu.open_menu()
	menu.to_menu_btn.emit_signal("pressed")
	if got_menu != 1:
		_fail("menu signal")
	menu.close_menu()
	await process_frame
	if menu.is_open():
		_fail("close_menu")
	# Toggle + cancel mid open with motion
	UiTheme.set_reduce_motion(false)
	menu.toggle_menu()
	menu.toggle_menu()
	await create_timer(0.25).timeout
	if menu.is_open():
		_fail("toggle closed")

	if fails > 0:
		push_error("game menu test failed: %d" % fails)
		quit(1)
	else:
		print("LINDERO GAME MENU OK")
		quit(0)
