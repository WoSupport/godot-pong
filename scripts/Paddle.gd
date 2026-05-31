extends CharacterBody2D

const SPEED = 400.0

@export var up_action: String = "ui_up"
@export var down_action: String = "ui_down"

func _physics_process(_delta):
	var dir = 0
	if Input.is_action_pressed(up_action):
		dir -= 1
	if Input.is_action_pressed(down_action):
		dir += 1

	velocity = Vector2(0, dir * SPEED)
	move_and_slide()

	# Clamp to screen
	var viewport_size = get_viewport_rect().size
	position.y = clamp(position.y, 50, viewport_size.y - 50)
