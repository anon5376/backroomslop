class_name FakeDoor
extends StaticBody3D
## A door that never opens. interact() plays a dull thunk with a cooldown.

var _thunk: AudioStreamPlayer3D = null
var _next_ok_msec: int = 0


func setup(thunk: AudioStreamPlayer3D) -> void:
	_thunk = thunk


func interact() -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_ok_msec:
		return
	_next_ok_msec = now + 600
	if is_instance_valid(_thunk):
		_thunk.pitch_scale = randf_range(0.9, 1.12)
		_thunk.play()
