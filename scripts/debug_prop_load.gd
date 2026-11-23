extends SceneTree

func _init() -> void:
	print("=== DEBUG PROP/TEX ===")
	for p in [
		"res://art/terreno_madera.jpg",
		"res://art/terreno_ovejas.jpg",
		"res://art/terreno_arcilla.jpg",
		"res://art/terreno_grano.jpg",
		"res://art/terreno_piedra.jpg",
		"res://models/props/bosque_grupo_partes.glb",
		"res://models/props/bosque_grupo.glb",
		"res://scripts/hex_dressing.gd",
	]:
		print("exists ", p, " ", ResourceLoader.exists(p), " file ", FileAccess.file_exists(p))
	for name in ["terreno_madera", "terreno_arcilla", "terreno_grano", "terreno_piedra", "terreno_ovejas"]:
		var t = load("res://art/%s.jpg" % name)
		print("tex ", name, " ", t)
	var packed = load("res://models/props/bosque_grupo_partes.glb")
	print("packed partes ", packed)
	if packed is PackedScene:
		var n = packed.instantiate()
		print("root ", n, " class ", n.get_class() if n else "null")
		if n:
			print("children ", n.get_child_count())
			n.free()
	var Dress = load("res://scripts/hex_dressing.gd")
	print("dress script ", Dress)
	quit()
