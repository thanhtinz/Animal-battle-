class_name RTSCamera
extends Camera2D
## RTS camera: drag-pan (middle mouse / right-drag / two-finger touch),
## wheel + pinch zoom, WASD/arrow keys, clamped to map bounds.

## 15e: emitted whenever the USER moves the camera by hand
## (keys, drag pan, wheel zoom, pinch). Programmatic moves
## (focus_on) never emit it — the spectator controller listens
## to break follow/auto mode back to free on manual input.
signal manual_input

var world_size := Vector2(2048, 2048)
var min_zoom := 0.4
var max_zoom := 2.5
var key_pan_speed := 620.0

var _panning := false
var _touches: Dictionary = {} # touch index -> screen position
var _pinch_dist := 0.0
var _pinch_mid := Vector2.ZERO


func _ready() -> void:
	make_current()


func _process(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1.0
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1.0
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1.0
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1.0
	if dir != Vector2.ZERO:
		position += dir.normalized() * key_pan_speed * delta / zoom.x
		_clamp()
		manual_input.emit()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.12, mb.position)
			manual_input.emit()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.12, mb.position)
			manual_input.emit()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_panning = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not mb.pressed:
			_panning = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_panning = true
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			position -= mm.relative / zoom.x
			_clamp()
			manual_input.emit()
	elif event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed:
			_touches[st.index] = st.position
		else:
			_touches.erase(st.index)
		_reset_pinch()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		_touches[sd.index] = sd.position
		if _touches.size() == 2:
			var pts: Array = _touches.values()
			var mid: Vector2 = (pts[0] + pts[1]) * 0.5
			var dist: float = pts[0].distance_to(pts[1])
			if _pinch_dist > 0.0:
				position -= (mid - _pinch_mid) / zoom.x
				var f := clampf(dist / _pinch_dist, 0.9, 1.1)
				zoom = Vector2.ONE * clampf(zoom.x * f, min_zoom, max_zoom)
				_clamp()
				manual_input.emit()
			_pinch_dist = dist
			_pinch_mid = mid


## Centre the camera on a world position (clamped to map bounds).
func focus_on(wpos: Vector2) -> void:
	position = wpos
	_clamp()


func _reset_pinch() -> void:
	_pinch_dist = 0.0
	_pinch_mid = Vector2.ZERO


func _zoom_at(factor: float, _screen_pos: Vector2) -> void:
	var before := get_global_mouse_position()
	zoom = Vector2.ONE * clampf(zoom.x * factor, min_zoom, max_zoom)
	# Keep the world point under the cursor stable.
	position += before - get_global_mouse_position()
	_clamp()


func _clamp() -> void:
	var view := get_viewport_rect().size
	var half := view / (2.0 * zoom)
	var cx := world_size.x * 0.5
	var cy := world_size.y * 0.5
	if half.x * 2.0 >= world_size.x:
		position.x = cx
	else:
		position.x = clampf(position.x, half.x, world_size.x - half.x)
	if half.y * 2.0 >= world_size.y:
		position.y = cy
	else:
		position.y = clampf(position.y, half.y, world_size.y - half.y)
