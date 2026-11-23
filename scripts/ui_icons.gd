extends RefCounted
class_name UiIcons

## Iconos Lucide locales (MIT) en art/icons/.

const DIR := "res://art/icons/"

static var _cache: Dictionary = {}

static func tex(name: String) -> Texture2D:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + "icon_%s.svg" % name
	if not ResourceLoader.exists(path):
		return null
	var t: Texture2D = load(path)
	_cache[name] = t
	return t

static func apply(btn: Button, name: String, max_w: int = 22) -> void:
	var t := tex(name)
	if t == null or btn == null:
		return
	btn.icon = t
	btn.expand_icon = true
	btn.add_theme_constant_override("icon_max_width", max_w)
