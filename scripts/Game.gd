extends Node

# ── Constants ─────────────────────────────────────────────────────────────────
const WINNING_SCORE         := 5
const BALL_SPEED_START      := 250.0   # px/s at kick-off
const BALL_SPEED_ON_HIT     := 25.0    # added per paddle hit
const BALL_SPEED_PER_SEC    := 20.0    # gradual ramp-up during a rally
const MAX_BOUNCE_ANGLE      := 75.0    # degrees — hitting the paddle edge sends the ball steep
const PADDLE_SPEED          := 400.0
const AI_SPEED              := 310.0   # AI is slower → beatable; struggles at high ball speed
const W                     := 800.0
const H                     := 600.0

# ── State ─────────────────────────────────────────────────────────────────────
var left_score  := 0
var right_score := 0
var game_active := false
var ai_mode     := false
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
	# Background
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

	# Physics bodies
	left_paddle  = _make_paddle(Vector2(30, H / 2))
	right_paddle = _make_paddle(Vector2(W - 30, H / 2))
	ball         = _make_ball()
	ball.visible = false
	add_child(left_paddle)
	add_child(right_paddle)
	add_child(ball)

	# UI
	var ui := CanvasLayer.new()
	ui.layer = 10
	add_child(ui)

	lbl_left    = _make_label("0", Vector2(200, 20), 48)
	lbl_right   = _make_label("0", Vector2(530, 20), 48)
	lbl_message = _make_label("", Vector2(0, 220), 30)
	lbl_message.size                 = Vector2(W, 160)
	lbl_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl_message.autowrap_mode        = TextServer.AUTOWRAP_WORD

	ui.add_child(lbl_left)
	ui.add_child(lbl_right)
	ui.add_child(lbl_message)

	_show_title()

# ── Builders ──────────────────────────────────────────────────────────────────
func _make_paddle(pos: Vector2) -> StaticBody2D:
	var p   := StaticBody2D.new()
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
	var b   := CharacterBody2D.new()
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
			ai_mode = true
			_start_game()
		KEY_2:
			ai_mode = false
			_start_game()

# ── Game loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not game_active:
		return

	# Left paddle — always human (W / S)
	var dir1 := 0
	if Input.is_key_pressed(KEY_W): dir1 -= 1
	if Input.is_key_pressed(KEY_S): dir1 += 1
	left_paddle.position.y = clamp(
		left_paddle.position.y + dir1 * PADDLE_SPEED * delta, 50.0, H - 50.0)

	# Right paddle — human or AI
	if ai_mode:
		_tick_ai(delta)
	else:
		var dir2 := 0
		if Input.is_key_pressed(KEY_UP):   dir2 -= 1
		if Input.is_key_pressed(KEY_DOWN): dir2 += 1
		right_paddle.position.y = clamp(
			right_paddle.position.y + dir2 * PADDLE_SPEED * delta, 50.0, H - 50.0)

	_tick_ball(delta)

func _tick_ai(delta: float) -> void:
	# Track ball when it's heading our way; drift to centre otherwise
	var target_y := H / 2.0
	if ball_dir.x > 0.0:
		target_y = ball.position.y
	var diff := target_y - right_paddle.position.y
	var move := clampf(diff, -AI_SPEED * delta, AI_SPEED * delta)
	right_paddle.position.y = clamp(right_paddle.position.y + move, 50.0, H - 50.0)

func _tick_ball(delta: float) -> void:
	# Uncapped ramp-up — ball gets faster until nobody can return it
	ball_speed += BALL_SPEED_PER_SEC * delta

	var col := ball.move_and_collide(ball_dir * ball_speed * delta)
	if col:
		# Where on the paddle did the ball hit? -1 = top edge, 0 = centre, +1 = bottom edge
		var hit_pos := clampf(
			(ball.position.y - col.get_collider().position.y) / 40.0, -1.0, 1.0)
		# Map hit position to outgoing angle (steeper toward edges)
		var angle  := hit_pos * deg_to_rad(MAX_BOUNCE_ANGLE)
		# Always bounce away from the paddle that was hit
		var out_x  := 1.0 if col.get_collider() == left_paddle else -1.0
		ball_dir    = Vector2(cos(angle) * out_x, sin(angle))   # already unit-length
		ball_speed += BALL_SPEED_ON_HIT

	# Top / bottom walls
	if ball.position.y < 10.0:
		ball.position.y = 10.0
		ball_dir.y      = absf(ball_dir.y)
	elif ball.position.y > H - 10.0:
		ball.position.y = H - 10.0
		ball_dir.y      = -absf(ball_dir.y)

	# Scoring
	if   ball.position.x < -20.0:    _score("left")
	elif ball.position.x > W + 20.0: _score("right")

# ── Game state ────────────────────────────────────────────────────────────────
func _show_title() -> void:
	lbl_message.text = "PONG\n\nPress  1  to play vs Computer\nPress  2  to play vs a Friend"

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
	lbl_message.text = winner + " wins!\n\nPress  1  to play vs Computer\nPress  2  to play vs a Friend"
