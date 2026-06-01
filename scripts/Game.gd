extends Node

# ── Constants ─────────────────────────────────────────────────────────────────
const WINNING_SCORE      := 5
const BALL_SPEED_START   := 250.0
const BALL_SPEED_ON_HIT  := 30.0
const MAX_BOUNCE_ANGLE   := 75.0
const PADDLE_SPEED       := 400.0
const W                  := 800.0
const H                  := 600.0
const WALL_TOP           := 10.0
const WALL_BOT           := H - 10.0
const FIELD_H            := WALL_BOT - WALL_TOP
const TRAIL_LEN          := 10     # number of ghost positions behind the ball

# ── Game state ────────────────────────────────────────────────────────────────
var left_score     := 0
var right_score    := 0
var game_active    := false
var ai_left        := false
var ai_right       := false
var ball_dir       := Vector2.ZERO
var ball_speed     := BALL_SPEED_START
var time_since_hit := 1.0

# ── Visual state ──────────────────────────────────────────────────────────────
var left_flash_t    := 0.0    # how long since last left-paddle hit  (counts down)
var right_flash_t   := 0.0    # how long since last right-paddle hit (counts down)
var wall_flash_t    := 0.0    # wall-bounce flash                    (counts down)
var lbl_left_pulse  := 0.0    # score-label pulse timer              (counts down)
var lbl_right_pulse := 0.0
var trail_pos       : Array = []   # ring of recent ball positions

# ── Node refs ─────────────────────────────────────────────────────────────────
var ball               : CharacterBody2D
var left_paddle        : StaticBody2D
var right_paddle       : StaticBody2D
var ball_vis           : Polygon2D
var left_vis           : Polygon2D
var right_vis          : Polygon2D
var wall_top_flash     : ColorRect
var wall_bot_flash     : ColorRect
var trail_nodes        : Array[Polygon2D] = []
var marker_left        : Polygon2D
var marker_right       : Polygon2D
var lbl_left           : Label
var lbl_right          : Label
var lbl_message        : Label

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_scene()

func _build_scene() -> void:
	# ── Background ───────────────────────────────────────────────────────────
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
	cline.color    = Color(0.2, 0.2, 0.2)
	bg_layer.add_child(cline)

	# Thin wall strips that flash on bounce
	wall_top_flash = ColorRect.new()
	wall_top_flash.position = Vector2(0, 0)
	wall_top_flash.size     = Vector2(W, WALL_TOP)
	wall_top_flash.color    = Color(0.05, 0.05, 0.05)
	bg_layer.add_child(wall_top_flash)

	wall_bot_flash = ColorRect.new()
	wall_bot_flash.position = Vector2(0, WALL_BOT)
	wall_bot_flash.size     = Vector2(W, H - WALL_BOT)
	wall_bot_flash.color    = Color(0.05, 0.05, 0.05)
	bg_layer.add_child(wall_bot_flash)

	# ── Physics bodies ────────────────────────────────────────────────────────
	left_paddle  = _make_paddle(Vector2(30, H / 2))
	right_paddle = _make_paddle(Vector2(W - 30, H / 2))
	ball         = _make_ball()
	ball.visible = false
	add_child(left_paddle)
	add_child(right_paddle)
	add_child(ball)

	# Store references to the visual Polygon2D children (index 1 — after CollisionShape2D)
	left_vis  = left_paddle.get_child(1)  as Polygon2D
	right_vis = right_paddle.get_child(1) as Polygon2D
	ball_vis  = ball.get_child(1)         as Polygon2D

	# ── Ball trail ────────────────────────────────────────────────────────────
	for i in range(TRAIL_LEN):
		var t := Polygon2D.new()
		t.polygon = PackedVector2Array([
			Vector2(0, -5), Vector2(5, 0), Vector2(0, 5), Vector2(-5, 0)
		])
		t.color   = Color.WHITE
		t.visible = false
		add_child(t)
		trail_nodes.append(t)

	# ── UI ────────────────────────────────────────────────────────────────────
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

	# Prediction markers
	marker_left  = _make_marker(Color(1.0, 0.85, 0.0, 0.85))
	marker_right = _make_marker(Color(0.0, 1.0,  1.0, 0.85))
	add_child(marker_left)
	add_child(marker_right)

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

func _make_marker(color: Color) -> Polygon2D:
	var m := Polygon2D.new()
	m.polygon = PackedVector2Array([
		Vector2(0, -8), Vector2(8, 0), Vector2(0, 8), Vector2(-8, 0)
	])
	m.color   = color
	m.visible = false
	return m

# ── Input ─────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if game_active:
		return
	match event.physical_keycode:
		KEY_1:  ai_left = false; ai_right = true;  _start_game()
		KEY_2:  ai_left = true;  ai_right = false; _start_game()
		KEY_3:  ai_left = false; ai_right = false; _start_game()

# ── Game loop ─────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if not game_active:
		return

	if ai_left:
		_tick_ai(left_paddle, right_paddle, false, delta)
	else:
		var d := int(Input.is_key_pressed(KEY_S)) - int(Input.is_key_pressed(KEY_W))
		left_paddle.position.y = clamp(left_paddle.position.y + d * PADDLE_SPEED * delta, 50.0, H - 50.0)

	if ai_right:
		_tick_ai(right_paddle, left_paddle, true, delta)
	else:
		var d := int(Input.is_key_pressed(KEY_DOWN)) - int(Input.is_key_pressed(KEY_UP))
		right_paddle.position.y = clamp(right_paddle.position.y + d * PADDLE_SPEED * delta, 50.0, H - 50.0)

	_tick_ball(delta)
	_update_markers()
	_update_visuals(delta)

# ── AI ────────────────────────────────────────────────────────────────────────
func _tick_ai(paddle: StaticBody2D, opponent: StaticBody2D, ball_toward_positive_x: bool, delta: float) -> void:
	var approaching := ball_dir.x > 0.0 if ball_toward_positive_x else ball_dir.x < 0.0

	var target_y: float
	if approaching:
		var landing_y := _predict_ball_y(paddle.position.x)
		var out_x     := -1.0 if ball_toward_positive_x else 1.0

		# Target landing: mirror the player's position, amplified so the AI
		# always drives the ball toward a corner. Small random noise stops it
		# being perfectly predictable.
		var ideal_land := clampf(
			H / 2.0 - (opponent.position.y - H / 2.0) * 2.0 + randf_range(-18.0, 18.0),
			WALL_TOP + 40.0, WALL_BOT - 40.0)

		# Search 41 candidate hit positions; pick the one whose return lands
		# closest to ideal_land. hp ≤ 0.75 → offset ≤ 30px < face half-height.
		var best_hp   := 0.0
		var best_diff := 1e9
		for i in range(41):
			var hp      := lerpf(-0.75, 0.75, float(i) / 40.0)
			var angle   := hp * deg_to_rad(MAX_BOUNCE_ANGLE)
			var out_dir := Vector2(cos(angle) * out_x, sin(angle))
			var pl_land := _predict_landing_y(
				paddle.position.x, landing_y, out_dir, opponent.position.x)
			var diff    := absf(pl_land - ideal_land)
			if diff < best_diff:
				best_diff = diff
				best_hp   = hp

		target_y = landing_y - best_hp * 40.0
	else:
		target_y = H / 2.0

	target_y = clampf(target_y, 50.0, H - 50.0)
	var move  := clampf(target_y - paddle.position.y, -PADDLE_SPEED * delta, PADDLE_SPEED * delta)
	paddle.position.y = clamp(paddle.position.y + move, 50.0, H - 50.0)

# ── Prediction markers ────────────────────────────────────────────────────────
func _update_markers() -> void:
	if ball_dir.x > 0.0:
		marker_right.visible    = true
		marker_right.position.x = right_paddle.position.x
		marker_right.position.y = _predict_ball_y(right_paddle.position.x)
		marker_left.visible     = false
	elif ball_dir.x < 0.0:
		marker_left.visible    = true
		marker_left.position.x = left_paddle.position.x
		marker_left.position.y = _predict_ball_y(left_paddle.position.x)
		marker_right.visible   = false
	else:
		marker_left.visible  = false
		marker_right.visible = false

# ── Visual juice ──────────────────────────────────────────────────────────────
func _ball_speed_color() -> Color:
	# White (slow) → yellow → orange → red (fast)
	var t := clampf((ball_speed - BALL_SPEED_START) / 500.0, 0.0, 1.0)
	if t < 0.5:
		return Color(1.0, 1.0, lerpf(1.0, 0.0, t * 2.0))   # white → yellow
	else:
		return Color(1.0, lerpf(1.0, 0.0, (t - 0.5) * 2.0), 0.0)  # yellow → red

func _update_visuals(delta: float) -> void:
	# ── Timers ────────────────────────────────────────────────────────────────
	left_flash_t    = maxf(left_flash_t    - delta, 0.0)
	right_flash_t   = maxf(right_flash_t   - delta, 0.0)
	wall_flash_t    = maxf(wall_flash_t    - delta, 0.0)
	lbl_left_pulse  = maxf(lbl_left_pulse  - delta, 0.0)
	lbl_right_pulse = maxf(lbl_right_pulse - delta, 0.0)

	# ── Ball colour by speed ──────────────────────────────────────────────────
	var bc := _ball_speed_color()
	ball_vis.color = bc

	# ── Ball trail ────────────────────────────────────────────────────────────
	trail_pos.push_front(ball.position)
	if trail_pos.size() > TRAIL_LEN:
		trail_pos.pop_back()

	for i in range(TRAIL_LEN):
		var node := trail_nodes[i]
		if i < trail_pos.size():
			node.visible  = game_active
			node.position = trail_pos[i]
			var age_t     := float(i + 1) / TRAIL_LEN          # 0=newest, 1=oldest
			node.color     = Color(bc.r, bc.g, bc.b, (1.0 - age_t) * 0.45)
		else:
			node.visible = false

	# ── Paddle flash (cyan burst → white) ─────────────────────────────────────
	const FLASH_DUR := 0.18
	left_vis.color  = Color.WHITE.lerp(Color(0.2, 1.0, 1.0), left_flash_t  / FLASH_DUR)
	right_vis.color = Color.WHITE.lerp(Color(0.2, 1.0, 1.0), right_flash_t / FLASH_DUR)

	# ── Wall flash (dim grey → bright on bounce) ──────────────────────────────
	const WALL_DUR := 0.10
	var wc := Color(0.05, 0.05, 0.05).lerp(Color(0.7, 0.85, 1.0), wall_flash_t / WALL_DUR)
	wall_top_flash.color = wc
	wall_bot_flash.color = wc

	# ── Score label pulse (white → gold on score) ─────────────────────────────
	const PULSE_DUR := 0.40
	lbl_left.add_theme_color_override("font_color",
		Color.WHITE.lerp(Color(1.0, 0.85, 0.0), lbl_left_pulse  / PULSE_DUR))
	lbl_right.add_theme_color_override("font_color",
		Color.WHITE.lerp(Color(1.0, 0.85, 0.0), lbl_right_pulse / PULSE_DUR))

# ── Ball prediction ───────────────────────────────────────────────────────────
func _predict_ball_y(target_x: float) -> float:
	if absf(ball_dir.x) < 0.01:
		return ball.position.y
	if signf(target_x - ball.position.x) != signf(ball_dir.x):
		return H / 2.0
	return _predict_landing_y(ball.position.x, ball.position.y, ball_dir, target_x)

func _predict_landing_y(from_x: float, from_y: float, dir: Vector2, target_x: float) -> float:
	if absf(dir.x) < 0.01:
		return from_y
	var dy := (dir.y / dir.x) * (target_x - from_x)
	var y  := from_y + dy - WALL_TOP
	if y < 0.0:
		y = -y
	y = fmod(y, FIELD_H * 2.0)
	if y > FIELD_H:
		y = FIELD_H * 2.0 - y
	return clampf(y + WALL_TOP, WALL_TOP, WALL_BOT)

# ── Ball ──────────────────────────────────────────────────────────────────────
func _tick_ball(delta: float) -> void:
	time_since_hit += delta

	var col := ball.move_and_collide(ball_dir * ball_speed * delta)
	if col:
		var collider := col.get_collider()
		var normal   := col.get_normal()

		if absf(normal.x) > 0.5:
			# Face hit — directional deflection + speed boost + paddle flash
			var hit_pos := clampf((ball.position.y - collider.position.y) / 40.0, -1.0, 1.0)
			var angle   := hit_pos * deg_to_rad(MAX_BOUNCE_ANGLE)
			var out_x   := 1.0 if collider == left_paddle else -1.0
			ball_dir     = Vector2(cos(angle) * out_x, sin(angle))
			if time_since_hit > 0.15:
				ball_speed    += BALL_SPEED_ON_HIT
				time_since_hit = 0.0
			# Trigger flash on the paddle that was hit
			if collider == left_paddle:  left_flash_t  = 0.18
			else:                        right_flash_t = 0.18
		else:
			# Edge clip — reflect and push clear
			ball_dir       = ball_dir.bounce(normal)
			ball.position += normal * 4.0

		if absf(ball_dir.y) < 0.15:
			ball_dir.y = 0.15 * signf(ball_dir.y) if ball_dir.y != 0.0 else 0.15
			ball_dir   = ball_dir.normalized()

	# Wall bounce — flash the strips
	if ball.position.y < WALL_TOP:
		ball.position.y = WALL_TOP + 1.0
		ball_dir.y      = absf(ball_dir.y)
		wall_flash_t    = 0.10
	elif ball.position.y > WALL_BOT:
		ball.position.y = WALL_BOT - 1.0
		ball_dir.y      = -absf(ball_dir.y)
		wall_flash_t    = 0.10

	if   ball.position.x < -20.0:    _score("left")
	elif ball.position.x > W + 20.0: _score("right")

# ── Game state ────────────────────────────────────────────────────────────────
func _show_title() -> void:
	lbl_message.text = "PONG\n\nPress 1 — vs Computer  (you play LEFT,  W / S)\nPress 2 — vs Computer  (you play RIGHT,  ↑ / ↓)\nPress 3 — 2 Players"

func _start_game() -> void:
	left_score  = 0
	right_score = 0
	_update_scores()
	lbl_message.text     = ""
	marker_left.visible  = false
	marker_right.visible = false
	left_flash_t         = 0.0
	right_flash_t        = 0.0
	wall_flash_t         = 0.0
	lbl_left_pulse       = 0.0
	lbl_right_pulse      = 0.0
	trail_pos.clear()
	game_active  = true
	ball.visible = true
	_reset_ball()

func _reset_ball() -> void:
	ball.position  = Vector2(W / 2, H / 2)
	ball_speed     = BALL_SPEED_START
	time_since_hit = 1.0
	trail_pos.clear()
	var angle := randf_range(-PI / 4.0, PI / 4.0)
	if randi() % 2 == 0:
		angle += PI
	ball_dir = Vector2(cos(angle), sin(angle))

func _score(side: String) -> void:
	if not game_active:
		return
	if side == "left":
		right_score    += 1
		lbl_right_pulse = 0.40
	else:
		left_score     += 1
		lbl_left_pulse  = 0.40
	_update_scores()
	if left_score >= WINNING_SCORE or right_score >= WINNING_SCORE:
		_end_game()
	else:
		_reset_ball()

func _update_scores() -> void:
	lbl_left.text  = str(left_score)
	lbl_right.text = str(right_score)

func _end_game() -> void:
	game_active          = false
	ball.visible         = false
	marker_left.visible  = false
	marker_right.visible = false
	for t in trail_nodes: t.visible = false
	trail_pos.clear()
	var winner := "Left" if left_score >= WINNING_SCORE else "Right"
	lbl_message.text = winner + " wins!\n\nPress 1 — vs Computer  (you LEFT)\nPress 2 — vs Computer  (you RIGHT)\nPress 3 — 2 Players"
