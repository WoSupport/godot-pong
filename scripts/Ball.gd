extends CharacterBody2D

const SPEED_INITIAL = 300.0
const SPEED_INCREMENT = 20.0
const MAX_SPEED = 700.0

var direction = Vector2.ZERO
var speed = SPEED_INITIAL

@onready var main = get_parent()

func _ready():
	reset()

func reset():
	position = Vector2(400, 300)
	speed = SPEED_INITIAL
	var angle = randf_range(-PI / 4, PI / 4)
	if randi() % 2 == 0:
		angle += PI
	direction = Vector2(cos(angle), sin(angle))

func _physics_process(delta):
	if not main.game_active:
		return

	var motion = direction * speed * delta
	var collision = move_and_collide(motion)

	if collision:
		var normal = collision.get_normal()
		# Bounce off paddles and walls
		direction = direction.bounce(normal)
		speed = min(speed + SPEED_INCREMENT, MAX_SPEED)

	# Bounce off top and bottom walls
	var viewport_size = get_viewport_rect().size
	if position.y < 10:
		position.y = 10
		direction.y = abs(direction.y)
	elif position.y > viewport_size.y - 10:
		position.y = viewport_size.y - 10
		direction.y = -abs(direction.y)

	# Score when ball exits left or right
	if position.x < -20:
		main.score("left")
	elif position.x > viewport_size.x + 20:
		main.score("right")
