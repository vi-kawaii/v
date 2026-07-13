extends Node2D
#
#@onready var anchor = $skeleton/base/anchor
#@onready var jiggle_target = $skeleton/base/target
#
#@export var grab_radius: float = 60.0
#@export var lerp_speed_tracking: float = 5.0
#
#var tracking_influence: float = 1.0
#var hand_control_influence: float = 0.0
#
#var is_dragging: bool = false
#var simulated_tracking_pos: Vector2 = Vector2.ZERO
#
#func _ready() -> void:
	#jiggle_target.position = Vector2.ZERO
	#anchor.position = Vector2.ZERO
#
#func _input(event: InputEvent) -> void:
	#if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		#if event.pressed:
			#var distance = get_global_mouse_position().distance_to(jiggle_target.global_position)
			#if distance <= grab_radius:
				#is_dragging = true
		#else:
			#is_dragging = false
			#var tween = create_tween().set_parallel(true)
			#tween.tween_property(self, "hand_control_influence", 0.0, 0.2)
			#tween.tween_property(jiggle_target, "position", Vector2.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
#
#func _process(delta: float) -> void:
	#var time = Time.get_ticks_msec() / 1000.0
	#var raw_tracking = Vector2(cos(time) * 40.0, sin(time * 1.5) * 20.0)
#
	#simulated_tracking_pos = simulated_tracking_pos.lerp(raw_tracking, lerp_speed_tracking * delta)
#
	#if is_dragging:
		#hand_control_influence = lerp(hand_control_influence, 1.0, delta * 10.0)
		#var mouse_local_pos = self.get_local_mouse_position()
		#jiggle_target.position = mouse_local_pos.clamp(Vector2(-120, -120), Vector2(120, 120))
#
	#var mixed_pos = Vector2.ZERO
#
	#mixed_pos = mixed_pos.lerp(simulated_tracking_pos, tracking_influence)
#
	#mixed_pos = mixed_pos.lerp(jiggle_target.position, hand_control_influence)
#
	#anchor.position = mixed_pos
