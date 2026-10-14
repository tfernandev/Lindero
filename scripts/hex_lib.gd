extends RefCounted
class_name HexLib

const SIZE := 72.0

static func hex_to_pixel(q: int, r: int) -> Vector2:
	var x := SIZE * sqrt(3.0) * (float(q) + float(r) * 0.5)
	var y := SIZE * 1.5 * float(r)
	return Vector2(x, y)

static func corner(center: Vector2, i: int) -> Vector2:
	var angle := deg_to_rad(60.0 * float(i) - 30.0)
	return center + Vector2(cos(angle), sin(angle)) * SIZE

static func pips(number: int) -> int:
	match number:
		2, 12:
			return 1
		3, 11:
			return 2
		4, 10:
			return 3
		5, 9:
			return 4
		6, 8:
			return 5
		_:
			return 0
