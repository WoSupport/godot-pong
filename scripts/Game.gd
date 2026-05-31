extends Node

# ── Constants ─────────────────────────────────────────────────────────────────
const WINNING_SCORE      := 5
const BALL_SPEED_START   := 250.0
const BALL_SPEED_ON_HIT  := 25.0
const BALL_SPEED_PER_SEC := 20.0
const MAX_BOUNCE_ANGLE   := 75.0    # degrees — edge hit sends ball steepest
const PADDLE_SPEED       := 400.0   # AI uses the same speed as the player
const W                  := 800.0
const H                  := 600.0

# Wall bounds used by ball and prediction
const WALL_TOP    := 10.0
const WALL_BOT    := H - 10.0
const FIELD_H     := WALL_BOT - WALL_TOP   # 580.0

# ── State ─────────────────────────────────────────────────────────────────────
var left_score  := 0
var right_score := 0
var game_active := false
var ai_left     := false
var ai_right    := false
var ball_dir    := Vector2.ZERO
var ball_speed  := BALL_SPEED_START

# ── Node refs ─────────────────────────────────────────────────────────────────
var ball         : CharacterBody2D
var left_paddle  : StaticBody2D
var right_paddle : StaticBody2D
var lbl_left     : Label
var lbl_right    : Label
var lbl_message  : Label

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_scene()

func _build_scene() -> void:
	var bg_layer := CanvasLayer.new()
	bg_layer.layer = -10
	add_child(bg_layer)

	var bg := ColorRect.new()
	bg.position = Vector2.ZERO
	bg.size     = Vector2(W, H)
	bg.color    = Color(0.05, 0.05, 0.05)
	bg_layer.add_child(bg)

	var cline := ColorRect.new()
	cline.position = Vector2(396, 0)
	cline.size     = Vector2(8, H)
	cline.color    = Color(0.3, 0.3, 0.3)
	bg_layer.add_child(cline)

	left_paddle  = _make_paddle(Vector2(30, H / 2))
	right_paddle = _make_paddle(Vector2(W - 30, H / 2))
	ball         = _make_ball()
	ball.visible = false
	add_child(left_paddle)
	add_child(right_paddle)
	add_child(ball)

	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	lbl_left    = _make_label("0", Vector2(200, 20), 48)
	lbl_right   = _make_label("0", Vector2(530, 20), 48)
	lbl_message = _make_label("", Vector2(0, 200), 30)
	lbl_message.size                 = Vector2(W, 200)
	lbl_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_message.autowrap_mode        = TextServer.AUTOWRAP_WORD

	ui.add_child(lbl_left)
	ui.add_child(lbl_right)
	ui.add_child(lbl_message)

	_show_title()

# ── Builders ──────────────────────────────────────────────────────────────────
func _make_paddle(pos: Vector2) -> StaticBody2D:
	var p     := StaticBody2D.new()
	p.position = pos
	var col   := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 80)
	col.shape  = shape
	p.add_child(col)
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-8, -40), Vector2(8, -40),
		Vector2(8,   40), Vector2(-8,  40)
	])
	vis.color = Color.WHITE
	p.add_child(vis)
	return p

func _make_ball() -> CharacterBody2D:
	var b     := CharacterBody2D.new()
	b.position = Vector2(W / 2, H / 2)
	var col   := CollisionShape2D.new()
	var shape := RectangleShape2D.new()
	shape.size = Vector2(16, 16)
	col.shape  = shape
	b.add_child(col)
	var vis := Polygon2D.new()
	vis.polygon = PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8),
		Vector2(8,   8), Vector2(-8,  8)
	])
	vis.color = Color.WHITE
	b.add_child(vis)
	return b

func _make_label(txt: String, pos: Vector2, font_size: int) -> Label:
	var lbl := Label.new()
	lbl.text     = txt
	lbl.position = pos
	lbl.add_theme_font_size_override("font_size", font_size)
	return lbl

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if game_active:
		return
	match event.physical_keycode:
		KEY_1:
			ai_left = false;  ai_right = true;  _start_game()
		KEY_2:
			ai_left = true;   ai_right = false;  _start_game()
		KEY_3:
			ai_left = false;  ai_right = false;  _start_game()

# ── Game loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not game_active:
		return

	# Left paddle
	if ai_left:
		_tick_ai(left_paddle, right_paddle, false, delta)
	else:
		var d := (int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W)))
		left_paddle.position.y = clamp(
			left_paddle.position.y + d * PADDLE_SPEED * delta, 50.0, H - 50.0)

	# Right paddle
	if ai_right:
		_tick_ai(right_paddle, left_paddle, true, delta)
	else:
		var d := (int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP)))
		right_paddle.position.y = clamp(
			right_paddle.position.y + d * PADDLE_SPEED * delta, 50.0, H - 50.0)

	_tick_ball(delta)

# ── AI ────────────────────────────────────────────────────────────────────────
# ball_toward_positive_x: true for the right paddle AI, false for the left paddle AI
func _tick_ai(paddle: StaticBody2D, opponent: StaticBody2D, ball_toward_positive_x: bool, delta: float) -> void:
	var approaching := ball_dir.x > 0.0 if ball_toward_positive_x else ball_dir.x < 0.0

	var target_y: float
	if approaching:
		# Predict where the ball will actually land at our paddle x
		var landing_y := _predict_ball_y(paddle.position.x)

		# Strategic offset: hit the ball with the part of the paddle that deflects
		# it AWAY from where the opponent currently is.
		# opponent above centre → send ball down → hit ball below centre (hit_pos = +1)
		#   → our paddle must be ABOVE landing_y → target = landing_y - offset
		# opponent below centre → send ball up   → hit ball above centre (hit_pos = -1)
		#   → our paddle must be BELOW landing_y → target = landing_y + offset
		var opp_bias  := (opponent.position.y - H / 2.0) / (H / 2.0)  # -1 … +1
		target_y = landing_y - opp_bias * 36.0   # 36 ≈ 90 % of half-paddle (40)
	else:
		# Ball moving away — drift back to centre so we're not caught out of position
		target_y = H / 2.0

	target_y = clampf(target_y, 50.0, H - 50.0)
	var move  := clampf(target_y - paddle.position.y, -PADDLE_SPEED * delta, PADDLE_SPEED * delta)
	paddle.position.y = clamp(paddle.position.y + move, 50.0, H - 50.0)

# Predict the ball's Y coordinate when it reaches target_x, accounting for
# wall bounces. Returns H/2 if the ball is moving away from target_x.
func _predict_ball_y(target_x: float) -> float:
	if absf(ball_dir.x) < 0.01:
		return ball.position.y
	# Ball must be heading toward target_x
	if signf(target_x - ball.position.x) != signf(ball_dir.x):
		return H / 2.0

	var dx    := absf(target_x - ball.position.x)
	var dy    := (ball_dir.y / ball_dir.x) * dx   # total signed Y displacement

	# Fold into [WALL_TOP, WALL_BOT] using repeated reflection
	var y := ball.position.y + dy - WALL_TOP      # 0-based
	if y < 0.0:
		y = -y                                     # reflect off top
	y = fmod(y, FIELD_H * 2.0)
	if y > FIELD_H:
		y = FIELD_H * 2.0 - y                     # reflect off bottom

	return clampf(y + WALL_TOP, WALL_TOP, WALL_BOT)

# ── Ball ──────────────────────────────────────────────────────────────────────
func _tick_ball(delta: float) -> void:
	ball_speed += BALL_SPEED_PER_SEC * delta

	var col := ball.move_and_collide(ball_dir * ball_speed * delta)
	if col:
		var hit_pos := clampf(
			(ball.position.y - col.get_collider().position.y) / 40.0, -1.0, 1.0)
		var angle  := hit_pos * deg_to_rad(MAX_BOUNCE_ANGLE)
		var out_x  := 1.0 if col.get_collider() == left_paddle else -1.0
		ball_dir    = Vector2(cos(angle) * out_x, sin(angle))
		ball_speed += BALL_SPEED_ON_HIT

	if ball.position.y < WALL_TOP:
		ball.position.y = WALL_TOP
		ball_dir.y      = absf(ball_dir.y)
	elif ball.position.y > WALL_BOT:
		ball.position.y = WALL_BOT
		ball_dir.y      = -absf(ball_dir.y)

	if   ball.position.x < -20.0:    _score("left")
	elif ball.position.x > W + 20.0: _score("right")

# ── Game state ────────────────────────────────────────────────────────────────
func _show_title() -> void:
	lbl_message.text = "PONG\n\nPress 1 — vs Computer  (you play LEFT,  W / S)\nPress 2 — vs Computer  (you play RIGHT,  ↑ / ↓)\nPress 3 — 2 Players"

func _start_game() -> void:
	left_score  = 0
	right_score = 0
	_update_scores()
	lbl_message.text = ""
	game_active      = true
	ball.visible     = true
	_reset_ball()

func _reset_ball() -> void:
	ball.position = Vector2(W / 2, H / 2)
	ball_speed    = BALL_SPEED_START
	var angle     := randf_range(-PI / 4.0, PI / 4.0)
	if randi() % 2 == 0:
		angle += PI
	ball_dir = Vector2(cos(angle), sin(angle))

func _score(side: String) -> void:
	if not game_active:
		return
	if side == "left": right_score += 1
	else:              left_score  += 1
	_update_scores()
	if left_score >= WINNING_SCORE or right_score >= WINNING_SCORE:
		_end_game()
	else:
		_reset_ball()

func _update_scores() -> void:
	lbl_left.text  = str(left_score)
	lbl_right.text = str(right_score)

func _end_game() -> void:
	game_active  = false
	ball.visible = false
	var winner := "Left" if left_score >= WINNING_SCORE else "Right"
	lbl_message.text = winner + " wins!\n\nPress 1 — vs Computer  (you LEFT)\nPress 2 — vs Computer  (you RIGHT)\nPress 3 — 2 Players"
