class_name Ball
extends RigidBody2D
## Balón de fútbol con velocidad limitada y radio variable (power-ups).

signal touched_by_head(head)
signal touched_post

const BASE_RADIUS := 28.0
const MAX_SPEED := 1300.0
const BASE_BOUNCE := 0.78

var radius := BASE_RADIUS
var _shape: CircleShape2D

func _ready() -> void:
	mass = 1.0
	gravity_scale = 1.0
	linear_damp = 0.15
	angular_damp = 0.6
	contact_monitor = true
	max_contacts_reported = 6
	collision_layer = 2
	collision_mask = 1 | 4  # mundo y jugadores
	var mat := PhysicsMaterial.new()
	mat.bounce = BASE_BOUNCE
	mat.friction = 0.4
	physics_material_override = mat
	_shape = CircleShape2D.new()
	_shape.radius = radius
	var cs := CollisionShape2D.new()
	cs.shape = _shape
	add_child(cs)
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node) -> void:
	if body is Head:
		touched_by_head.emit(body)
	elif body.is_in_group("goal_post"):
		touched_post.emit()

func set_radius(r: float) -> void:
	radius = r
	_shape.radius = r
	queue_redraw()

func set_bounciness(b: float) -> void:
	physics_material_override.bounce = b

func reset_at(pos: Vector2) -> void:
	freeze = true
	global_position = pos
	rotation = 0.0
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	freeze = false
	sleeping = false

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if state.linear_velocity.length() > MAX_SPEED:
		state.linear_velocity = state.linear_velocity.normalized() * MAX_SPEED

func _draw() -> void:
	BallStyles.draw_ball(self, GameState.ball_style, radius)

func _process(_delta: float) -> void:
	queue_redraw()
