extends Node

const WINNING_SCORE = 5

@onready var ball = $Ball
@onready var left_paddle = $LeftPaddle
@onready var right_paddle = $RightPaddle
@onready var left_score_label = $UI/LeftScore
@onready var right_score_label = $UI/RightScore
@onready var message_label = $UI/Message

var left_score = 0
var right_score = 0
var game_active = false

func _ready():
	message_label.text = "Press SPACE to Start"
	ball.visible = false

func _process(_delta):
	if Input.is_action_just_pressed("ui_accept") and not game_active:
		start_game()

func start_game():
	left_score = 0
	right_score = 0
	update_score_display()
	message_label.text = ""
	game_active = true
	ball.visible = true
	ball.reset()

func score(side):
	if not game_active:
		return
	if side == "left":
		right_score += 1
	else:
		left_score += 1
	update_score_display()
	if left_score >= WINNING_SCORE or right_score >= WINNING_SCORE:
		end_game()
	else:
		ball.reset()

func update_score_display():
	left_score_label.text = str(left_score)
	right_score_label.text = str(right_score)

func end_game():
	game_active = false
	ball.visible = false
	var winner = "Left" if left_score >= WINNING_SCORE else "Right"
	message_label.text = winner + " Player Wins!\nPress SPACE to Restart"
