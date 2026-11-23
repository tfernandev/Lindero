extends SceneTree
# Reglas de partida: acciones inválidas, comercio, victoria. Sin UI.

const Game := preload("res://scripts/match.gd")

var fails := 0

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	print("=== TEST REGLAS PARTIDA ===")
	_invalid_actions()
	_setup_and_grant()
	_trade_requires_market()
	_forced_victory()
	_play_seeds()
	print("=== RESULTADO fails=%d ===" % fails)
	quit(1 if fails > 0 else 0)

func _invalid_actions() -> void:
	var g = Game.new()
	g.new_game()
	_ok("no tira en fundación", g.roll(0) != "")
	_ok("no termina en fundación", g.end_turn(0) != "")
	_ok("rival no funda en tu turno", g.place_settlement(1, 0) != "")
	var legal: Array = g.legal_settlement_vertices(0)
	_ok("hay puestos legales al empezar", not legal.is_empty())
	if legal.is_empty():
		return
	var v := int(legal[0])
	_ok("fundar válido", g.place_settlement(0, v) == "")
	_ok("no se funda dos veces el mismo", g.place_settlement(0, v) != "")
	_ok("no se tira durante el camino", g.roll(0) != "")
	var roads: Array = g.legal_roads(0)
	_ok("hay camino legal tras el puesto", not roads.is_empty())
	if not roads.is_empty():
		_ok("camino de fundación", g.place_road(0, String(roads[0])) == "")

func _setup_and_grant() -> void:
	var g = _finished_setup()
	_ok("después de fundar se tira", int(g.phase) == Game.Phase.ROLL)
	_ok("reserva de madera", int(g.hands[0][Game.Goods.WOOD]) >= 2)
	_ok("reserva de arcilla", int(g.hands[0][Game.Goods.CLAY]) >= 2)
	_ok("dos puestos por bando", _count_level(g, 0, 1) == 2 and _count_level(g, 1, 1) == 2)

func _trade_requires_market() -> void:
	var g = _finished_setup()
	g.phase = Game.Phase.BUILD
	g.current_player = 0
	g.hands[0] = [6, 6, 6, 6, 6]
	_ok("sin Mercado no hay tasa", int(g.trade_rate(0)) == 0)
	_ok("cambio rechazado sin Mercado", g.trade(0, 0, 1, false) != "")
	g.wares[0][Game.Ware.CLOTH] = 3
	g.progress[0][Game.Track.MERCADO] = 1
	_ok("Mercado 1 permite 4:1", int(g.trade_rate(0)) == 4)
	_ok("cambio 4:1", g.trade(0, 0, 1, false) == "")

func _forced_victory() -> void:
	var g = _finished_setup()
	g.phase = Game.Phase.BUILD
	g.current_player = 0
	g.hands[0] = [20, 20, 20, 20, 20]
	g.wares[0] = [6, 6, 6]
	for vkey in g.buildings.keys():
		var b: Dictionary = g.buildings[vkey]
		if int(b.player) == 0 and int(b.level) == 1:
			var err: String = String(g.upgrade(0, int(vkey)))
			_ok("mejorar puesto %s" % vkey, err == "")
	g.progress[0][Game.Track.CONSEJO] = 3
	g._refresh_scores()
	_ok("2 granjas + sede = 5", int(g.scores[0]) >= Game.WIN)
	_ok("la partida termina al ganar", int(g.phase) == Game.Phase.OVER)
	_ok("ganador humano", int(g.winner) == 0)
	_ok("no se construye después", g.place_settlement(0, 0) != "")
	_ok("no se tira después", g.roll(0) != "")

func _play_seeds() -> void:
	for seed in [1, 7, 13, 29, 41]:
		seed(seed)
		var g = Game.new()
		g.new_game()
		var turns := 0
		var stuck := 0
		while int(g.phase) != Game.Phase.OVER and turns < 80:
			turns += 1
			var p := int(g.current_player)
			if int(g.phase) == Game.Phase.SETUP_SETTLEMENT:
				var v := g.choose_setup_vertex(p)
				if v < 0 or g.place_settlement(p, v) != "":
					stuck += 1
					break
			elif int(g.phase) == Game.Phase.SETUP_ROAD:
				var ek := g.choose_setup_road(p)
				if ek == "" or g.place_road(p, ek) != "":
					stuck += 1
					break
			elif int(g.phase) == Game.Phase.ROLL:
				if g.roll(p) != "":
					stuck += 1
					break
			elif int(g.phase) == Game.Phase.BUILD:
				var act: Dictionary = g.choose_action(p)
				if act.is_empty():
					if g.end_turn(p) != "":
						stuck += 1
						break
				elif g.apply_action(p, act) != "":
					if g.end_turn(p) != "":
						stuck += 1
						break
			else:
				break
		print("[reglas] seed=%d turns=%d fase=%s puntos=%s-%s ganador=%s" % [
			seed, turns, g.phase, g.scores[0], g.scores[1], g.winner
		])
		_ok("seed %d no se traba" % seed, stuck == 0)
		_ok("seed %d respeta 19 hex" % seed, g.hexes.size() == 19)

func _finished_setup():
	var g = Game.new()
	g.new_game()
	var guard := 0
	while int(g.phase) != Game.Phase.ROLL and guard < 12:
		guard += 1
		var p := int(g.current_player)
		if int(g.phase) == Game.Phase.SETUP_SETTLEMENT:
			var v := g.choose_setup_vertex(p)
			var err: String = String(g.place_settlement(p, v))
			if err != "":
				print("FAIL setup puesto p=%d %s" % [p, err])
				fails += 1
				break
		else:
			var ek := g.choose_setup_road(p)
			var err: String = String(g.place_road(p, ek))
			if err != "":
				print("FAIL setup camino p=%d %s" % [p, err])
				fails += 1
				break
	return g

func _count_level(g, player: int, level: int) -> int:
	var n := 0
	for v in g.buildings.keys():
		var b: Dictionary = g.buildings[v]
		if int(b.player) == player and int(b.level) == level:
			n += 1
	return n

func _ok(name: String, cond: bool) -> void:
	if cond:
		print("[reglas] ok %s" % name)
	else:
		print("[reglas] FALLO %s" % name)
		fails += 1
