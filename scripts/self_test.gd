extends SceneTree

const GameScript := preload("res://scripts/match.gd")
const HexGeom := preload("res://scripts/hex_lib.gd")

func _init() -> void:
	var fails := 0
	fails += _test_topology()
	fails += _test_rules()
	fails += _test_expansion()
	fails += _test_dice_faces()
	fails += _test_full_game()
	if fails > 0:
		push_error("Lindero self-test failed: %d" % fails)
		quit(1)
	else:
		print("LINDERO SELFTEST OK")
		quit(0)

func _fail(msg: String) -> int:
	push_error(msg)
	print("FAIL: ", msg)
	return 1

func _test_topology() -> int:
	var g = GameScript.new()
	g.new_game()
	if g.hexes.size() != 19:
		return _fail("expected 19 hexes, got %d" % g.hexes.size())
	var lagoon := 0
	for h in g.hexes:
		if int(h.resource) < 0:
			lagoon += 1
		if (h.vertices as Array).size() != 6:
			return _fail("hex without 6 corners")
	if lagoon != 1:
		return _fail("expected 1 lagoon, got %d" % lagoon)
	if g.v_pos.size() >= 19 * 6 or g.v_pos.size() < 40:
		return _fail("vertex weld looks wrong: %d" % g.v_pos.size())
	for i in g.v_pos.size():
		var ncount := (g.v_neighbors[i] as Array).size()
		if ncount != 2 and ncount != 3:
			return _fail("vertex %d has degree %d" % [i, ncount])
		var around := (g.v_hexes[i] as Array).size()
		if around < 1 or around > 3:
			return _fail("vertex %d touches %d hexes" % [i, around])
	for ek in g.edges.keys():
		var ends: Array = g.edges[ek]
		var d: float = g.v_pos[int(ends[0])].distance_to(g.v_pos[int(ends[1])])
		if d < HexGeom.SIZE * 0.85 or d > HexGeom.SIZE * 1.15:
			return _fail("edge %s length %s" % [ek, d])
	return 0

func _finish_setup(g) -> String:
	var guard := 0
	while g.phase == GameScript.Phase.SETUP_SETTLEMENT or g.phase == GameScript.Phase.SETUP_ROAD:
		guard += 1
		if guard > 12:
			return "setup did not finish"
		var p: int = g.current_player
		if g.phase == GameScript.Phase.SETUP_SETTLEMENT:
			var err: String = g.place_settlement(p, g.choose_setup_vertex(p))
			if err != "":
				return err
		else:
			var err: String = g.place_road(p, g.choose_setup_road(p))
			if err != "":
				return err
	if g.phase != GameScript.Phase.ROLL or g.current_player != 0:
		return "setup ended in phase %s player %s" % [g.phase, g.current_player]
	if g.scores[0] != 2 or g.scores[1] != 2:
		return "setup scores %s" % str(g.scores)
	return ""

func _test_rules() -> int:
	var g = GameScript.new()
	g.new_game()
	var spot := -1
	var spot_res := -1
	for i in g.v_pos.size():
		for hi in g.v_hexes[i]:
			var h: Dictionary = g.hexes[int(hi)]
			if int(h.number) == 6 and int(h.resource) >= 0:
				spot = i
				spot_res = int(h.resource)
				break
		if spot >= 0:
			break
	if spot < 0:
		return _fail("no vertex on a 6")
	var err: String = g.place_settlement(0, spot)
	if err != "":
		return _fail(err)
	for n in g.v_neighbors[spot]:
		if not g.vertex_blocked(int(n)):
			return _fail("adjacent vertex stayed open")
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.produce(6)
	if int(g.hands[0][spot_res]) < 1:
		return _fail("roll 6 did not pay the settlement")
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.produce(7)
	var total := 0
	for p in 2:
		for i in GameScript.RES_COUNT:
			total += int(g.hands[p][i])
	if total != 0:
		return _fail("drought produced resources")
	err = _finish_setup(g)
	if err != "":
		return _fail(err)
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.forced_roll = 7
	err = g.roll(0)
	if err != "" or g.phase != GameScript.Phase.BUILD:
		return _fail("forced drought roll failed: %s" % err)
	for p in 2:
		for i in GameScript.RES_COUNT:
			if int(g.hands[p][i]) != 0:
				return _fail("hands changed on a 7")
	var before: int = g.buildings.size()
	err = g.place_settlement(0, g.v_pos.size() - 1)
	if err == "":
		return _fail("built a settlement with an empty hand")
	if g.buildings.size() != before:
		return _fail("failed build still created a settlement")
	g.hands[0] = [0, 0, 2, 2, 0]
	var mine := -1
	for vkey in g.buildings.keys():
		if int(g.buildings[vkey].player) == 0 and int(g.buildings[vkey].level) == 1:
			mine = int(vkey)
			break
	if mine < 0:
		return _fail("no own settlement to upgrade")
	var score_before: int = g.scores[0]
	err = g.upgrade(0, mine)
	if err != "":
		return _fail(err)
	if g.scores[0] != score_before + 1:
		return _fail("upgrade did not add a point")
	return 0

func _score_of(g, player: int) -> int:
	var s := 0
	for vkey in g.buildings.keys():
		if int(g.buildings[vkey].player) == player:
			s += int(g.buildings[vkey].level)
	if int(g.progress[player][GameScript.Track.CONSEJO]) >= 3:
		s += 1
	return s

func _only_number(g, hex_index: int, number: int) -> void:
	for i in g.hexes.size():
		g.hexes[i].number = 0
	g.hexes[hex_index].number = number

func _first_hex(g, res: int) -> int:
	for i in g.hexes.size():
		if int(g.hexes[i].resource) == res:
			return i
	return -1

func _test_expansion() -> int:
	var g = GameScript.new()
	g.new_game()
	var wood_hex := _first_hex(g, GameScript.Goods.WOOD)
	var clay_hex := _first_hex(g, GameScript.Goods.CLAY)
	var grain_hex := _first_hex(g, GameScript.Goods.GRAIN)
	var stone_hex := _first_hex(g, GameScript.Goods.STONE)
	if wood_hex < 0 or clay_hex < 0 or grain_hex < 0 or stone_hex < 0:
		return _fail("missing a terrain")
	g.buildings.clear()
	g.buildings[int(g.hexes[wood_hex].vertices[0])] = {"player": 0, "level": 2}
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.wares = [[0, 0, 0], [0, 0, 0]]
	g.progress = [[3, 0, 0], [0, 0, 0]]
	_only_number(g, wood_hex, 6)
	g.produce(6)
	if int(g.hands[0][GameScript.Goods.WOOD]) != 1 or int(g.wares[0][GameScript.Ware.PAPER]) != 1:
		return _fail("wood farm should pay 1 wood + 1 paper, got %s / %s" % [g.hands[0], g.wares[0]])
	g.buildings.clear()
	g.hands = [[1, 2, 0, 3, 0], [0, 0, 0, 0, 0]]
	g.produce(6)
	if int(g.hands[0][GameScript.Goods.GRAIN]) != 1:
		return _fail("acequia should grant the scarcest prima")
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.wares = [[0, 0, 0], [0, 0, 0]]
	g.produce(7)
	if int(g.hands[0][0]) != 0:
		return _fail("drought paid through acequia")
	g.buildings[int(g.hexes[clay_hex].vertices[0])] = {"player": 0, "level": 2}
	_only_number(g, clay_hex, 9)
	g.produce(9)
	var clay_sum := 0
	for i in GameScript.RES_COUNT:
		clay_sum += int(g.hands[0][i])
	if int(g.hands[0][GameScript.Goods.CLAY]) != 2 or clay_sum != 2:
		return _fail("clay farm should pay exactly 2 clay, got %s" % g.hands[0])
	for i in 3:
		if int(g.wares[0][i]) != 0:
			return _fail("clay farm paid a commodity")
	g.buildings.clear()
	g.buildings[int(g.hexes[grain_hex].vertices[0])] = {"player": 0, "level": 2}
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	g.progress = [[0, 0, 0], [0, 0, 0]]
	_only_number(g, grain_hex, 5)
	g.produce(5)
	if int(g.wares[0][GameScript.Ware.CLOTH]) != 1 or int(g.hands[0][GameScript.Goods.GRAIN]) != 1:
		return _fail("grain farm should pay cloth")
	g.buildings.clear()
	g.buildings[int(g.hexes[stone_hex].vertices[0])] = {"player": 0, "level": 2}
	g.wares = [[0, 0, 0], [0, 0, 0]]
	g.hands = [[0, 0, 0, 0, 0], [0, 0, 0, 0, 0]]
	_only_number(g, stone_hex, 8)
	g.produce(8)
	if int(g.wares[0][GameScript.Ware.COIN]) != 1 or int(g.hands[0][GameScript.Goods.STONE]) != 1:
		return _fail("stone farm should pay coin")
	g.phase = GameScript.Phase.BUILD
	g.current_player = 0
	g.winner = -1
	g.buildings.clear()
	g.progress = [[0, 0, 0], [0, 0, 0]]
	g.wares = [[0, 0, 0], [0, 0, 0]]
	var err: String = g.advance(0, GameScript.Track.TALLER)
	if err == "":
		return _fail("advanced taller for free")
	g.wares[0][GameScript.Ware.PAPER] = 1
	err = g.advance(0, GameScript.Track.TALLER)
	if err != "" or int(g.progress[0][0]) != 1 or int(g.wares[0][0]) != 0:
		return _fail("taller advance failed: %s" % err)
	var cost: Array = g.cost_of(0, "settlement")
	if int(cost[GameScript.Goods.WOOD]) != 0 or int(cost[GameScript.Goods.CLAY]) != 1:
		return _fail("crane did not drop wood: %s" % cost)
	g.wares[0][0] = 2
	err = g.advance(0, GameScript.Track.TALLER)
	if err != "" or int(g.progress[0][0]) != 2:
		return _fail("scaffold advance failed: %s" % err)
	var road: Array = g.cost_of(0, "road")
	if int(road[GameScript.Goods.WOOD]) != 0 or int(road[GameScript.Goods.CLAY]) != 1:
		return _fail("scaffold road cost %s" % road)
	g.progress[0][GameScript.Track.MERCADO] = 1
	g.hands[0] = [4, 0, 0, 0, 0]
	err = g.trade(0, GameScript.Goods.WOOD, GameScript.Goods.GRAIN, false)
	if err != "" or int(g.hands[0][0]) != 0 or int(g.hands[0][2]) != 1:
		return _fail("4:1 trade failed: %s %s" % [err, g.hands[0]])
	err = g.trade(0, 0, 1, true)
	if err == "":
		return _fail("ware trade opened before lonja")
	g.progress[0][GameScript.Track.MERCADO] = 3
	g.wares[0] = [2, 0, 0]
	err = g.trade(0, 0, 1, true)
	if err != "" or int(g.wares[0][0]) != 0 or int(g.wares[0][1]) != 1:
		return _fail("lonja trade failed: %s %s" % [err, g.wares[0]])
	g.buildings.clear()
	g.progress[0][GameScript.Track.CONSEJO] = 3
	g.phase = GameScript.Phase.BUILD
	g._refresh_scores()
	if int(g.scores[0]) != 1:
		return _fail("sede should be worth 1, got %s" % str(g.scores))
	g.progress[0][GameScript.Track.CONSEJO] = 1
	var up: Array = g.cost_of(0, "upgrade")
	if int(up[GameScript.Goods.GRAIN]) != 1 or int(up[GameScript.Goods.STONE]) != 2:
		return _fail("licencia cost %s" % up)
	g.progress[0][GameScript.Track.CONSEJO] = 2
	up = g.cost_of(0, "upgrade")
	if int(up[GameScript.Goods.GRAIN]) != 1 or int(up[GameScript.Goods.STONE]) != 1:
		return _fail("fuero cost %s" % up)
	var ai = GameScript.new()
	ai.new_game()
	ai.phase = GameScript.Phase.BUILD
	ai.current_player = 0
	ai.wares[0][GameScript.Ware.PAPER] = 1
	var action: Dictionary = ai.choose_action(0)
	if String(action.get("kind", "")) != "advance":
		return _fail("ai should buy taller, got %s" % action)
	return 0

## La animación de dados solo presenta die_a/die_b; la lógica debe dar caras coherentes.
func _test_dice_faces() -> int:
	var g = GameScript.new()
	g.new_game()
	var err := _finish_setup(g)
	if err != "":
		return _fail(err)
	for total in range(2, 13):
		if g.phase != GameScript.Phase.ROLL:
			err = g.end_turn(g.current_player)
			if err != "":
				return _fail("end_turn before forced %d: %s" % [total, err])
		var p: int = g.current_player
		g.forced_roll = total
		err = g.roll(p)
		if err != "":
			return _fail("forced roll %d: %s" % [total, err])
		if g.last_roll != total:
			return _fail("last_roll %d != forced %d" % [g.last_roll, total])
		if g.die_a < 1 or g.die_a > 6 or g.die_b < 1 or g.die_b > 6:
			return _fail("faces out of range on %d: %d+%d" % [total, g.die_a, g.die_b])
		if g.die_a + g.die_b != g.last_roll:
			return _fail("faces %d+%d != total %d" % [g.die_a, g.die_b, g.last_roll])
		err = g.end_turn(p)
		if err != "":
			return _fail("end_turn after %d: %s" % [total, err])
	for _i in 24:
		if g.phase != GameScript.Phase.ROLL:
			err = g.end_turn(g.current_player)
			if err != "":
				return _fail(err)
		var p2: int = g.current_player
		err = g.roll(p2)
		if err != "":
			return _fail(err)
		if g.die_a + g.die_b != g.last_roll:
			return _fail("free roll faces %d+%d != %d" % [g.die_a, g.die_b, g.last_roll])
		err = g.end_turn(p2)
		if err != "":
			return _fail(err)
	return 0

func _test_full_game() -> int:
	seed(14014)
	var g = GameScript.new()
	g.new_game()
	var err := _finish_setup(g)
	if err != "":
		return _fail(err)
	for p in 2:
		g.hands[p] = [12, 12, 12, 12, 12]
	var guard := 0
	while g.phase != GameScript.Phase.OVER and guard < 80:
		guard += 1
		var p: int = g.current_player
		if g.phase == GameScript.Phase.ROLL:
			err = g.roll(p)
		elif g.phase == GameScript.Phase.BUILD:
			var action: Dictionary = g.choose_action(p)
			if action.is_empty():
				err = g.end_turn(p)
			else:
				err = g.apply_action(p, action)
		else:
			return _fail("unexpected phase %s" % g.phase)
		if err != "":
			return _fail("%s | %s" % [err, "\n".join(g.log)])
		for q in 2:
			for i in GameScript.RES_COUNT:
				if int(g.hands[q][i]) < 0:
					return _fail("negative resources")
			for i in 3:
				if int(g.wares[q][i]) < 0:
					return _fail("negative commodity")
		if g.scores[0] != _score_of(g, 0) or g.scores[1] != _score_of(g, 1):
			return _fail("score desync %s" % str(g.scores))
	if g.phase != GameScript.Phase.OVER or g.winner < 0 or g.scores[g.winner] < GameScript.WIN:
		return _fail("no winner scores %s log %s" % [str(g.scores), " / ".join(g.log)])
	return 0

