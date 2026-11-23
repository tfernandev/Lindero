extends RefCounted
class_name LinderoMatch

const HexGeom := preload("res://scripts/hex_lib.gd")

# Partida corta, original. Hexágonos, dados y construcción.
# Cinco primas (madera, arcilla, trigo, piedra, lana). Las granjas pagan
# mercancías y con eso se sube la tabla: Taller, Mercado y Consejo.
# Meta: 5 puntos. Puesto = 1, granja = 2, sede del Consejo = 1.
# Costos de construcción siguen en las cuatro primas clásicas (sin lana).

enum Phase { SETUP_SETTLEMENT, SETUP_ROAD, ROLL, BUILD, OVER }
enum Goods { WOOD, CLAY, GRAIN, STONE, SHEEP }
enum Ware { PAPER, CLOTH, COIN }
enum Track { TALLER, MERCADO, CONSEJO }

const WIN := 5
const PLAYER_NAME := ["Vos", "Vecino"]
const RES_NAME := ["Madera", "Arcilla", "Trigo", "Piedra", "Lana"]
const RES_LETTER := ["M", "A", "T", "P", "L"]
const RES_COLOR := [
	Color("2f7a3e"),
	Color("b85a32"),
	Color("d4a437"),
	Color("7e8288"),
	Color("c9b896"),
]
const WARE_NAME := ["Papel", "Tela", "Moneda"]
const WARE_LETTER := ["Pa", "Te", "Mo"]
const WARE_COLOR := [Color("f4efe2"), Color("d7c4b0"), Color("e2b340")]
const TRACK_NAME := ["Taller", "Mercado", "Consejo"]
const TRACK_COLOR := [Color("7dbe63"), Color("7eb6e0"), Color("e07a72")]
const PERK_SHORT := [
	["Grúa", "Andamio", "Acequia"],
	["Trueque", "Feria", "Lonja"],
	["Licencia", "Fuero", "Sede"],
]
const PROG_COST := [1, 2, 3]
# Madera → papel, trigo → tela, piedra → moneda, lana → tela. Arcilla sin mercancía.
const WARE_OF_RES := [0, -1, 1, 2, 1]
const RES_COUNT := 5
const HAND_EMPTY := [0, 0, 0, 0, 0]
const PLAYER_COLOR := [Color("e39b3b"), Color("3d6fdb")]
const LAGOON := Color("2c6f86")
const COST := {
	"road": [1, 1, 0, 0],
	"settlement": [1, 1, 1, 1],
	"upgrade": [0, 0, 2, 2],
}
const SETUP_PLAYER := [0, 1, 1, 0]
const SETUP_GRANT := [false, false, true, true]
const TILE_DEF := {
	"-2,0": [0, 6],
	"-2,1": [4, 3],
	"-2,2": [3, 8],
	"-1,-1": [1, 4],
	"-1,0": [2, 5],
	"-1,1": [0, 9],
	"-1,2": [1, 10],
	"0,-2": [3, 9],
	"0,-1": [0, 10],
	"0,0": [-1, 0],
	"0,1": [3, 5],
	"0,2": [2, 4],
	"1,-2": [1, 8],
	"1,-1": [4, 11],
	"1,0": [0, 3],
	"1,1": [1, 6],
	"2,-2": [3, 11],
	"2,-1": [2, 12],
	"2,0": [0, 2],
}

var phase: Phase = Phase.SETUP_SETTLEMENT
var current_player := 0
var winner := -1
var last_roll := 0
var die_a := 0
var die_b := 0
var forced_roll := 0
var anchor := -1
var setup_index := 0
var scores: Array = [0, 0]
var hands: Array = [HAND_EMPTY.duplicate(), HAND_EMPTY.duplicate()]
var wares: Array = [[0, 0, 0], [0, 0, 0]]
var progress: Array = [[0, 0, 0], [0, 0, 0]]
var log: Array[String] = []
var hexes: Array = []
var v_pos: Array[Vector2] = []
var v_neighbors: Array = []
var v_hexes: Array = []
var edges: Dictionary = {}
var buildings: Dictionary = {}
var roads: Dictionary = {}

func new_game() -> void:
	phase = Phase.SETUP_SETTLEMENT
	current_player = 0
	winner = -1
	last_roll = 0
	die_a = 0
	die_b = 0
	forced_roll = 0
	anchor = -1
	setup_index = 0
	scores = [0, 0]
	hands = [HAND_EMPTY.duplicate(), HAND_EMPTY.duplicate()]
	wares = [[0, 0, 0], [0, 0, 0]]
	progress = [[0, 0, 0], [0, 0, 0]]
	log.clear()
	hexes.clear()
	v_pos.clear()
	v_neighbors.clear()
	v_hexes.clear()
	edges.clear()
	buildings.clear()
	roads.clear()
	_build_board()

func instruction() -> String:
	match phase:
		Phase.SETUP_SETTLEMENT:
			if current_player == 0:
				return "Puesto %d de 2. Tocá un punto blanco, sin tocar otro." % (_settlement_count(0) + 1)
			return "El vecino elige dónde fundar."
		Phase.SETUP_ROAD:
			if current_player == 0:
				return "Tocá una raya blanca que salga de ese puesto."
			return "El vecino traza un camino."
		Phase.ROLL:
			if current_player == 0:
				return "Tirar dados. El 6 y el 8 producen más."
			return "Turno del vecino."
		Phase.BUILD:
			if current_player == 0:
				return "Construí donde está marcado, subí la tabla o cambiá."
			return "El vecino construye."
		Phase.OVER:
			if winner == 0:
				return "Ganaste. Llegaste a %d puntos." % scores[0]
			return "Ganó el vecino, con %d puntos." % scores[winner]
	return ""

func say(text: String) -> void:
	log.append(text)
	while log.size() > 5:
		log.pop_front()

func vertex_blocked(vkey: int) -> bool:
	if vkey < 0 or vkey >= v_pos.size() or buildings.has(vkey):
		return true
	for n in v_neighbors[vkey]:
		if buildings.has(int(n)):
			return true
	return false

func cost_of(player: int, kind: String) -> Array:
	var cost: Array = (COST[kind] as Array).duplicate()
	var taller := int(progress[player][Track.TALLER])
	var consejo := int(progress[player][Track.CONSEJO])
	if kind == "settlement" and taller >= 1:
		cost[Goods.WOOD] = 0
	if kind == "road" and taller >= 2:
		cost[Goods.WOOD] = 0
	if kind == "upgrade" and consejo >= 1:
		cost[Goods.GRAIN] = maxi(0, int(cost[Goods.GRAIN]) - 1)
	if kind == "upgrade" and consejo >= 2:
		cost[Goods.STONE] = maxi(0, int(cost[Goods.STONE]) - 1)
	return cost

func fmt_cost(cost: Array) -> String:
	var bits: PackedStringArray = []
	for i in cost.size():
		var n := int(cost[i])
		if n <= 0:
			continue
		if n == 1:
			bits.append(RES_NAME[i])
		else:
			bits.append("%d %s" % [n, RES_NAME[i]])
	if bits.is_empty():
		return "nada"
	return " + ".join(bits)

func can_afford(player: int, kind: String) -> bool:
	var cost := cost_of(player, kind)
	for i in cost.size():
		if int(hands[player][i]) < int(cost[i]):
			return false
	return true

func trade_rate(player: int) -> int:
	var lvl := int(progress[player][Track.MERCADO])
	if lvl <= 0:
		return 0
	return 5 - lvl

func can_advance(player: int, track: int) -> bool:
	if phase != Phase.BUILD or current_player != player:
		return false
	if track < 0 or track > 2:
		return false
	var lvl := int(progress[player][track])
	if lvl >= 3:
		return false
	return int(wares[player][track]) >= int(PROG_COST[lvl])

func legal_settlement_vertices(player: int) -> Array:
	var out: Array = []
	if current_player != player:
		return out
	if phase != Phase.SETUP_SETTLEMENT and phase != Phase.BUILD:
		return out
	if phase == Phase.BUILD and not can_afford(player, "settlement"):
		return out
	for v in v_pos.size():
		if vertex_blocked(v):
			continue
		if phase == Phase.BUILD and not _connected_to_player(v, player):
			continue
		out.append(v)
	return out

func legal_roads(player: int) -> Array:
	var out: Array = []
	if current_player != player:
		return out
	if phase == Phase.SETUP_ROAD:
		for ek in edges.keys():
			if roads.has(ek):
				continue
			var ends: Array = edges[ek]
			if int(ends[0]) == anchor or int(ends[1]) == anchor:
				out.append(String(ek))
		return out
	if phase != Phase.BUILD or not can_afford(player, "road"):
		return out
	for ek in edges.keys():
		if roads.has(ek):
			continue
		if _edge_touches_network(String(ek), player):
			out.append(String(ek))
	return out

func legal_upgrades(player: int) -> Array:
	var out: Array = []
	if phase != Phase.BUILD or current_player != player or not can_afford(player, "upgrade"):
		return out
	for vkey in buildings.keys():
		var b: Dictionary = buildings[vkey]
		if int(b.player) == player and int(b.level) == 1:
			out.append(int(vkey))
	return out

func place_settlement(player: int, vkey: int) -> String:
	if phase == Phase.OVER:
		return "La partida ya terminó."
	if current_player != player:
		return "No es tu turno."
	if vkey < 0 or vkey >= v_pos.size():
		return "Tocá un punto blanco."
	if not legal_settlement_vertices(player).has(vkey):
		if phase == Phase.BUILD and not can_afford(player, "settlement"):
			return "Para un puesto hacen falta %s." % fmt_cost(cost_of(player, "settlement"))
		if vertex_blocked(vkey):
			return "Muy cerca de otro puesto."
		if phase == Phase.BUILD and not _connected_to_player(vkey, player):
			return "El puesto tiene que tocar un camino tuyo."
		return "Ahí no se puede fundar."
	if phase == Phase.BUILD:
		_pay(player, "settlement")
	buildings[vkey] = {"player": player, "level": 1}
	_refresh_scores()
	if phase == Phase.OVER:
		return ""
	if phase == Phase.SETUP_SETTLEMENT:
		anchor = vkey
		phase = Phase.SETUP_ROAD
		say("%s fundó un puesto." % PLAYER_NAME[player])
	else:
		say("%s fundó un puesto (%d-%d)." % [PLAYER_NAME[player], scores[0], scores[1]])
	return ""

func place_road(player: int, ekey: String) -> String:
	if phase == Phase.OVER:
		return "La partida ya terminó."
	if current_player != player:
		return "No es tu turno."
	if ekey == "" or not edges.has(ekey):
		return "Tocá una raya libre."
	if not legal_roads(player).has(ekey):
		if phase == Phase.BUILD and not can_afford(player, "road"):
			return "Un camino cuesta %s." % fmt_cost(cost_of(player, "road"))
		if phase == Phase.SETUP_ROAD:
			return "El camino tiene que salir del puesto que acabás de fundar."
		return "Ese camino no conecta con lo tuyo."
	if phase == Phase.BUILD:
		_pay(player, "road")
	roads[ekey] = player
	if phase == Phase.SETUP_ROAD:
		say("%s trazó un camino." % PLAYER_NAME[player])
		_advance_setup(player)
	elif phase == Phase.BUILD:
		say("%s trazó un camino." % PLAYER_NAME[player])
	return ""

func upgrade(player: int, vkey: int) -> String:
	if phase == Phase.OVER:
		return "La partida ya terminó."
	if not legal_upgrades(player).has(vkey):
		if phase == Phase.BUILD and current_player == player and not can_afford(player, "upgrade"):
			return "La granja cuesta %s." % fmt_cost(cost_of(player, "upgrade"))
		return "Ese puesto no se puede mejorar."
	_pay(player, "upgrade")
	buildings[vkey].level = 2
	_refresh_scores()
	if phase != Phase.OVER:
		say("%s levantó una granja (%d-%d)." % [PLAYER_NAME[player], scores[0], scores[1]])
	return ""

func roll(player: int) -> String:
	if phase != Phase.ROLL or current_player != player:
		return "Ahora no se tira."
	if forced_roll >= 2 and forced_roll <= 12:
		last_roll = forced_roll
		die_a = clampi(last_roll - 1, 1, 6)
		die_b = last_roll - die_a
		if die_b > 6:
			die_b = 6
			die_a = last_roll - 6
	else:
		die_a = randi_range(1, 6)
		die_b = randi_range(1, 6)
		last_roll = die_a + die_b
	forced_roll = 0
	if last_roll == 7:
		say("%s sacó 7. Sequía: nadie produce." % PLAYER_NAME[player])
	else:
		produce(last_roll)
		say("%s sacó %d." % [PLAYER_NAME[player], last_roll])
	phase = Phase.BUILD
	return ""

func produce(number: int) -> void:
	if number < 2 or number > 12 or number == 7:
		return
	var gained := [false, false]
	for h in hexes:
		if int(h.number) != number or int(h.resource) < 0:
			continue
		var res := int(h.resource)
		if res < 0 or res >= RES_COUNT:
			continue
		for v in h.vertices:
			var vi := int(v)
			if not buildings.has(vi):
				continue
			var b: Dictionary = buildings[vi]
			var owner := int(b.player)
			if int(b.level) <= 1:
				hands[owner][res] = int(hands[owner][res]) + 1
			else:
				var ware := int(WARE_OF_RES[res])
				if ware < 0:
					hands[owner][res] = int(hands[owner][res]) + 2
				else:
					hands[owner][res] = int(hands[owner][res]) + 1
					wares[owner][ware] = int(wares[owner][ware]) + 1
			gained[owner] = true
	for p in 2:
		if int(progress[p][Track.TALLER]) < 3 or gained[p]:
			continue
		var res := _least_res(p)
		hands[p][res] = int(hands[p][res]) + 1
		say("Acequia: %s recibe 1 %s." % [PLAYER_NAME[p], RES_NAME[res]])

func advance(player: int, track: int) -> String:
	if phase != Phase.BUILD or current_player != player:
		return "Ahora no se sube la tabla."
	if track < 0 or track > 2:
		return "Esa columna no existe."
	var lvl := int(progress[player][track])
	if lvl >= 3:
		return "%s ya está al máximo." % TRACK_NAME[track]
	var cost := int(PROG_COST[lvl])
	if int(wares[player][track]) < cost:
		return "Hacen falta %d %s." % [cost, WARE_NAME[track]]
	wares[player][track] = int(wares[player][track]) - cost
	progress[player][track] = lvl + 1
	_refresh_scores()
	if phase != Phase.OVER:
		say("%s sube %s a %d (%s)." % [PLAYER_NAME[player], TRACK_NAME[track], lvl + 1, PERK_SHORT[track][lvl]])
	return ""

func trade(player: int, give: int, take: int, ware: bool) -> String:
	if phase != Phase.BUILD or current_player != player:
		return "Ahora no se cambia."
	var mercado := int(progress[player][Track.MERCADO])
	if mercado <= 0:
		return "El Mercado nivel 1 abre el cambio: 4 primas iguales por 1."
	if ware and mercado < 3:
		return "Las mercancías se cambian con la Lonja, en Mercado 3."
	var pile: Array = wares if ware else hands
	var n := 3 if ware else RES_COUNT
	if give < 0 or take < 0 or give >= n or take >= n:
		return "Elegí qué das y qué querés."
	if give == take:
		return "Elegí otra cosa para recibir."
	var rate := 2 if ware else trade_rate(player)
	if int(pile[player][give]) < rate:
		var missing: String = WARE_NAME[give] if ware else RES_NAME[give]
		return "Te faltan %d %s para cambiar." % [rate, missing]
	pile[player][give] = int(pile[player][give]) - rate
	pile[player][take] = int(pile[player][take]) + 1
	var give_name: String = WARE_NAME[give] if ware else RES_NAME[give]
	var take_name: String = WARE_NAME[take] if ware else RES_NAME[take]
	say("%s cambia %d %s por 1 %s." % [PLAYER_NAME[player], rate, give_name, take_name])
	return ""

func end_turn(player: int) -> String:
	if phase != Phase.BUILD or current_player != player:
		return "Todavía no podés terminar."
	current_player = 1 - player
	phase = Phase.ROLL
	say("Turno de %s." % PLAYER_NAME[current_player])
	return ""

func apply_action(player: int, action: Dictionary) -> String:
	match String(action.get("kind", "")):
		"road":
			return place_road(player, String(action.get("edge", "")))
		"settlement":
			return place_settlement(player, int(action.get("vertex", -1)))
		"upgrade":
			return upgrade(player, int(action.get("vertex", -1)))
		"advance":
			return advance(player, int(action.get("track", -1)))
		"trade":
			return trade(player, int(action.get("give", -1)), int(action.get("take", -1)), bool(action.get("ware", false)))
		_:
			return "Acción desconocida."

func choose_setup_vertex(player: int) -> int:
	var best := -1
	var best_score := -1.0
	for vkey in legal_settlement_vertices(player):
		var v := int(vkey)
		var score := vertex_value(v, player) * 10.0 + float(_min_building_distance(v)) * 0.35
		if score > best_score:
			best_score = score
			best = v
	return best

func choose_setup_road(player: int) -> String:
	var best := ""
	var best_score := -1.0
	for ek in legal_roads(player):
		var ends: Array = edges[ek]
		var other := int(ends[1]) if int(ends[0]) == anchor else int(ends[0])
		var score := vertex_value(other, player)
		if score > best_score:
			best_score = score
			best = String(ek)
	return best

func choose_action(player: int) -> Dictionary:
	if phase != Phase.BUILD or current_player != player:
		return {}
	var best := {}
	var best_score := -1.0
	for vkey in legal_upgrades(player):
		var v := int(vkey)
		var score := 55.0 + vertex_value(v, player)
		if _vertex_has_ware(v):
			score += 6.0
		if scores[player] + 1 >= WIN:
			score += 200.0
		if score > best_score:
			best_score = score
			best = {"kind": "upgrade", "vertex": v}
	for vkey in legal_settlement_vertices(player):
		var v := int(vkey)
		var score := 80.0 + vertex_value(v, player)
		if scores[player] + 1 >= WIN:
			score += 200.0
		if score > best_score:
			best_score = score
			best = {"kind": "settlement", "vertex": v}
	var deal := _best_trade(player)
	if not deal.is_empty():
		var trade_score := float(deal["score"])
		var trade_action := {
			"kind": "trade",
			"give": int(deal["give"]),
			"take": int(deal["take"]),
			"ware": bool(deal["ware"]),
		}
		if trade_score > best_score:
			best_score = trade_score
			best = trade_action
	for track in 3:
		if not can_advance(player, track):
			continue
		var score := _advance_score(player, track)
		if score > best_score:
			best_score = score
			best = {"kind": "advance", "track": track}
	if can_afford(player, "road"):
		var target := _best_open_vertex(player)
		if target >= 0:
			var road := _road_toward(player, target)
			if road != "" and legal_roads(player).has(road):
				var score := 30.0 + vertex_value(target, player) * 0.35
				if score > best_score:
					best = {"kind": "road", "edge": road}
	return best

func vertex_value(vkey: int, player: int) -> float:
	var value := 0.0
	var seen := {}
	for hi in v_hexes[vkey]:
		var h: Dictionary = hexes[int(hi)]
		var res := int(h.resource)
		if res < 0 or res >= RES_COUNT:
			continue
		value += float(HexGeom.pips(int(h.number)))
		if int(WARE_OF_RES[res]) >= 0:
			value += 0.35
		if not seen.has(res) and _resource_access(player, res) == 0:
			seen[res] = true
			value += 2.5
		else:
			seen[res] = true
	return value

func _build_board() -> void:
	for q in range(-2, 3):
		for r in range(-2, 3):
			if maxi(absi(q), maxi(absi(r), absi(q + r))) > 2:
				continue
			var key := "%d,%d" % [q, r]
			if not TILE_DEF.has(key):
				push_error("Falta el hexágono %s" % key)
				continue
			var def: Array = TILE_DEF[key]
			var index := hexes.size()
			var center := HexGeom.hex_to_pixel(q, r)
			var verts: Array = []
			for i in 6:
				verts.append(_add_vertex(HexGeom.corner(center, i), index))
			for i in 6:
				_link(int(verts[i]), int(verts[(i + 1) % 6]))
			hexes.append({
				"q": q,
				"r": r,
				"resource": int(def[0]),
				"number": int(def[1]),
				"vertices": verts,
			})

func _add_vertex(pos: Vector2, hex_index: int) -> int:
	var id := -1
	for i in v_pos.size():
		if v_pos[i].distance_to(pos) <= 1.0:
			id = i
			break
	if id < 0:
		id = v_pos.size()
		v_pos.append(pos)
		v_neighbors.append([])
		v_hexes.append([])
	var here: Array = v_hexes[id]
	if not here.has(hex_index):
		here.append(hex_index)
	return id

func _link(a: int, b: int) -> void:
	var na: Array = v_neighbors[a]
	if not na.has(b):
		na.append(b)
	var nb: Array = v_neighbors[b]
	if not nb.has(a):
		nb.append(a)
	var ek := _edge_key(a, b)
	if not edges.has(ek):
		edges[ek] = [a, b]

func _edge_key(a: int, b: int) -> String:
	if a < b:
		return "%d|%d" % [a, b]
	return "%d|%d" % [b, a]

func _pay(player: int, kind: String) -> void:
	var cost := cost_of(player, kind)
	for i in cost.size():
		hands[player][i] = int(hands[player][i]) - int(cost[i])

func _advance_setup(player: int) -> void:
	if SETUP_GRANT[setup_index]:
		_grant_vertex(player, anchor)
		say("Ese puesto entrega las primas de alrededor.")
	setup_index += 1
	anchor = -1
	if setup_index >= SETUP_PLAYER.size():
		for p in 2:
			hands[p][Goods.WOOD] = int(hands[p][Goods.WOOD]) + 2
			hands[p][Goods.CLAY] = int(hands[p][Goods.CLAY]) + 2
			hands[p][Goods.GRAIN] = int(hands[p][Goods.GRAIN]) + 1
			hands[p][Goods.STONE] = int(hands[p][Goods.STONE]) + 1
		phase = Phase.ROLL
		current_player = 0
		say("Reserva: 2 madera, 2 arcilla, 1 trigo y 1 piedra.")
		return
	current_player = SETUP_PLAYER[setup_index]
	phase = Phase.SETUP_SETTLEMENT

func _grant_vertex(player: int, vkey: int) -> void:
	if vkey < 0:
		return
	for hi in v_hexes[vkey]:
		var res := int(hexes[int(hi)].resource)
		if res < 0 or res >= RES_COUNT:
			continue
		hands[player][res] = int(hands[player][res]) + 1

func _refresh_scores() -> void:
	scores = [0, 0]
	for vkey in buildings.keys():
		var b: Dictionary = buildings[vkey]
		scores[int(b.player)] += int(b.level)
	for p in 2:
		if int(progress[p][Track.CONSEJO]) >= 3:
			scores[p] += 1
	if phase == Phase.SETUP_SETTLEMENT or phase == Phase.SETUP_ROAD or phase == Phase.OVER:
		return
	for p in 2:
		if scores[p] >= WIN:
			winner = p
			phase = Phase.OVER
			say("%s llega a %d y gana." % [PLAYER_NAME[p], scores[p]])
			return

func _least_res(player: int) -> int:
	var best := 0
	for i in RES_COUNT:
		if int(hands[player][i]) < int(hands[player][best]):
			best = i
	return best

func _vertex_has_ware(vkey: int) -> bool:
	for hi in v_hexes[vkey]:
		var res := int(hexes[int(hi)].resource)
		if res >= 0 and res < RES_COUNT and int(WARE_OF_RES[res]) >= 0:
			return true
	return false

func _advance_score(player: int, track: int) -> float:
	var lvl := int(progress[player][track])
	var score := 38.0 + float(lvl) * 4.0
	if track == Track.TALLER and lvl == 0:
		score += 10.0
	if track == Track.MERCADO and lvl < 2:
		score += 6.0
	if track == Track.CONSEJO and lvl == 2:
		score += 28.0
		if scores[player] + 1 >= WIN:
			score += 200.0
	return score

func _best_trade(player: int) -> Dictionary:
	if trade_rate(player) <= 0:
		return {}
	var best := {}
	var best_score := -1.0
	if not can_afford(player, "settlement") and _open_connected(player):
		var deal := _deal_for(player, cost_of(player, "settlement"))
		if not deal.is_empty():
			best = deal
			best_score = 76.0
	if not can_afford(player, "upgrade") and _has_level1(player):
		var deal := _deal_for(player, cost_of(player, "upgrade"))
		if not deal.is_empty() and 62.0 > best_score:
			best = deal
			best_score = 62.0
	if int(progress[player][Track.MERCADO]) >= 3:
		for track in 3:
			var lvl := int(progress[player][track])
			if lvl >= 3:
				continue
			var need := int(PROG_COST[lvl])
			if int(wares[player][track]) + 1 < need:
				continue
			if int(wares[player][track]) >= need:
				continue
			for other in 3:
				if other == track or int(wares[player][other]) < 2:
					continue
				if 44.0 > best_score:
					best = {"kind": "trade", "give": other, "take": track, "ware": true}
					best_score = 44.0
	if best.is_empty():
		return {}
	best["score"] = best_score
	return best

func _deal_for(player: int, cost: Array) -> Dictionary:
	var rate := trade_rate(player)
	if rate <= 0:
		return {}
	var best := {}
	var best_surplus := -1
	for take in cost.size():
		if int(hands[player][take]) >= int(cost[take]):
			continue
		for give in RES_COUNT:
			if give == take:
				continue
			var sim: Array = (hands[player] as Array).duplicate()
			if int(sim[give]) < rate:
				continue
			sim[give] = int(sim[give]) - rate
			sim[take] = int(sim[take]) + 1
			var ok := true
			for i in cost.size():
				if int(sim[i]) < int(cost[i]):
					ok = false
					break
			if not ok:
				continue
			var surplus := int(sim[give]) - int(cost[give])
			if surplus > best_surplus:
				best_surplus = surplus
				best = {"kind": "trade", "give": give, "take": take, "ware": false}
	return best

func _open_connected(player: int) -> bool:
	for v in v_pos.size():
		if vertex_blocked(v):
			continue
		if _connected_to_player(v, player):
			return true
	return false

func _has_level1(player: int) -> bool:
	for vkey in buildings.keys():
		var b: Dictionary = buildings[vkey]
		if int(b.player) == player and int(b.level) == 1:
			return true
	return false

func _settlement_count(player: int) -> int:
	var n := 0
	for vkey in buildings.keys():
		if int(buildings[vkey].player) == player:
			n += 1
	return n

func _connected_to_player(vkey: int, player: int) -> bool:
	for n in v_neighbors[vkey]:
		if int(roads.get(_edge_key(vkey, int(n)), -1)) == player:
			return true
	return false

func _edge_touches_network(ek: String, player: int) -> bool:
	for v in edges[ek]:
		var vi := int(v)
		if buildings.has(vi):
			if int(buildings[vi].player) == player:
				return true
			continue
		for n in v_neighbors[vi]:
			if int(roads.get(_edge_key(vi, int(n)), -1)) == player:
				return true
	return false

func _resource_access(player: int, res: int) -> int:
	var n := 0
	for vkey in buildings.keys():
		if int(buildings[vkey].player) != player:
			continue
		for hi in v_hexes[int(vkey)]:
			var hr := int(hexes[int(hi)].resource)
			if hr < 0 or hr >= RES_COUNT:
				continue
			if hr == res:
				n += 1
	return n

func _min_building_distance(vkey: int) -> int:
	if buildings.is_empty():
		return 8
	var q: Array[int] = [vkey]
	var dist := {vkey: 0}
	var head := 0
	while head < q.size():
		var cur := q[head]
		head += 1
		if buildings.has(cur) and int(dist[cur]) > 0:
			return int(dist[cur])
		for n in v_neighbors[cur]:
			var nb := int(n)
			if dist.has(nb):
				continue
			dist[nb] = int(dist[cur]) + 1
			q.append(nb)
	return 8

func _best_open_vertex(player: int) -> int:
	var best := -1
	var best_score := -1.0
	for v in v_pos.size():
		if vertex_blocked(v):
			continue
		var score := vertex_value(v, player)
		if score > best_score:
			best_score = score
			best = v
	return best

func _network_vertices(player: int) -> Array:
	var set := {}
	for ek in roads.keys():
		if int(roads[ek]) != player:
			continue
		for v in edges[ek]:
			set[int(v)] = true
	for vkey in buildings.keys():
		if int(buildings[vkey].player) == player:
			set[int(vkey)] = true
	return set.keys()

func _road_toward(player: int, target: int) -> String:
	var network := {}
	for v in _network_vertices(player):
		network[int(v)] = true
	if network.is_empty() or network.has(target):
		return ""
	var q: Array[int] = []
	var parent := {}
	for v in network.keys():
		var vi := int(v)
		q.append(vi)
		parent[vi] = -1
	var head := 0
	var found := false
	while head < q.size():
		var cur := q[head]
		head += 1
		if cur == target:
			found = true
			break
		for n in v_neighbors[cur]:
			var nb := int(n)
			if parent.has(nb):
				continue
			var owner := int(roads.get(_edge_key(cur, nb), -1))
			if owner != -1 and owner != player:
				continue
			parent[nb] = cur
			q.append(nb)
	if not found:
		return ""
	var cur := target
	var chosen := ""
	var guard := 0
	while parent.has(cur) and int(parent[cur]) != -1 and guard < 64:
		guard += 1
		var prev := int(parent[cur])
		var ek := _edge_key(prev, cur)
		if not roads.has(ek):
			chosen = ek
		cur = prev
	return chosen
