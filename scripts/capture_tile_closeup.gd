extends SceneTree
# Primer plano de una loseta sin overlay de debug (ventana GPU, no --headless).
# Uso: godot --path . -s res://scripts/capture_tile_closeup.gd -- q r archivo.png [zoom]

const TableBoardScript := preload("res://scripts/table_board.gd")
const GameScript := preload("res://scripts/match.gd")

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var a := OS.get_cmdline_user_args()
	var q := int(a[0]) if a.size() > 0 else 0
	var r := int(a[1]) if a.size() > 1 else 1
	var out := String(a[2]) if a.size() > 2 else "closeup.png"
	var zoom := float(a[3]) if a.size() > 3 else 0.42
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	root.msaa_3d = Viewport.MSAA_4X
	var board = TableBoardScript.new()
	root.add_child(board)
	var g = GameScript.new()
	g.new_game()
	var terrains: Array[Texture2D] = []
	for n in ["terreno_madera", "terreno_arcilla", "terreno_grano", "terreno_piedra", "terreno_ovejas"]:
		terrains.append(load("res://art/%s.jpg" % n))
	var font: Font = load("res://fonts/Nunito-Bold.ttf") if ResourceLoader.exists("res://fonts/Nunito-Bold.ttf") else ThemeDB.fallback_font
	board.bind(g, terrains, load("res://art/terreno_laguna.jpg"), load("res://art/mar_isla.jpg"), font)
	board.look_at_hex(q, r, zoom)
	for i in 10:
		await process_frame
		RenderingServer.force_draw()
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("res://debug_captures/%s" % out)
	print("[closeup] %s" % out)
	quit(0)
