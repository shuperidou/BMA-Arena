class_name Main
extends Node2D
## 入口：用代码组装整个原型场景 (场地 / 球 / 两个角色 / 比赛 / UI / 调试)。
##
## 采用"代码组装"而不是大量手写 .tscn，是为了让所有几何与参数都来自 GameConfig，
## 方便快速迭代。之后要拆成场景/预制体很容易。

var arena: Arena
var ball: Ball
var block_system: BlockSystem
var match_ref: Match
var hud: Hud
var debug_layer: DebugLayer
var players: Array[PlayerController] = []

func _ready() -> void:
	arena = Arena.new()
	arena.name = "Arena"
	add_child(arena)

	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position = GameConfig.arena_center
	add_child(cam)
	cam.make_current()

	ball = Ball.new()
	ball.name = "Ball"
	add_child(ball)

	for i in 2:
		var p := PlayerController.new()
		p.name = "Player%d" % (i + 1)
		var scheme: InputScheme
		if i == 0:
			scheme = InputScheme.new(GameConfig.p1_move, GameConfig.p1_serve, GameConfig.p1_aim_mode)
		else:
			scheme = InputScheme.new(GameConfig.p2_move, GameConfig.p2_serve, GameConfig.p2_aim_mode,
				GameConfig.p2_rot_ccw, GameConfig.p2_rot_cw)
		p.setup(i + 1, scheme)
		p.global_position = Vector2(-300.0, 140.0) if i == 0 else Vector2(300.0, 140.0)
		add_child(p)
		players.append(p)

	block_system = BlockSystem.new()
	block_system.name = "BlockSystem"
	add_child(block_system)

	hud = Hud.new()
	hud.name = "Hud"
	add_child(hud)

	debug_layer = DebugLayer.new()
	debug_layer.name = "DebugLayer"
	add_child(debug_layer)

	match_ref = Match.new()
	match_ref.name = "Match"
	add_child(match_ref)
	match_ref.setup(players, ball, block_system, arena)

	hud.match_ref = match_ref
	debug_layer.match_ref = match_ref

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_F1:
			debug_layer.enabled = not debug_layer.enabled
		KEY_F2:
			GameConfig.show_hints = not GameConfig.show_hints
		KEY_R:
			match_ref.restart()
		KEY_ESCAPE:
			get_tree().quit()
