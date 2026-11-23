extends RefCounted

## Utilidad mínima para matar tweens sin dejar estados a medias.
## Usar vía preload("res://scripts/anim_util.gd").


static func kill(tw: Tween) -> void:
	if tw != null and is_instance_valid(tw) and tw.is_valid():
		tw.kill()


static func replace(old: Tween, owner: Node) -> Tween:
	kill(old)
	if owner == null or not is_instance_valid(owner):
		return null
	return owner.create_tween()
