# ============================================================
#  AEONS — RTS globe camera
#  Drag grabs the globe (surface tracks the cursor ~1:1 at any
#  zoom), wheel zoom, WASD/arrows pan, Q/E zoom, inertia. Emits
#  `tile_clicked` when a press-release happens without dragging.
# ============================================================
class_name OrbitCamera
extends Node3D

signal tile_clicked(screen_pos: Vector2, button: int)

const R := 100.0

var cam: Camera3D
var theta := 0.6
var phi := 1.1
var dist := R * 3.0
var min_dist := R * 1.18
var max_dist := R * 4.4

var _v_theta := 0.0
var _v_phi := 0.0
var _dragging := false
var _moved := 0.0


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 1.0
	cam.far = 20000.0
	add_child(cam)
	_update_cam()


func _rot_speed() -> float:
	# radians of globe arc per screen pixel so the surface point under the
	# cursor stays under it while dragging (grab-the-globe), at any zoom
	var vp_h: float = maxf(1.0, get_viewport().get_visible_rect().size.y)
	var view_h: float = 2.0 * (dist - R) * tan(deg_to_rad(cam.fov * 0.5))
	return clampf(view_h / (R * vp_h), 0.0006, 0.02)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var e := event as InputEventMouseButton
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = clampf(dist * 0.93, min_dist, max_dist)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = clampf(dist * 1.07, min_dist, max_dist)
		elif e.button_index == MOUSE_BUTTON_LEFT or e.button_index == MOUSE_BUTTON_RIGHT or e.button_index == MOUSE_BUTTON_MIDDLE:
			if e.pressed:
				_dragging = true
				_moved = 0.0
			else:
				if _dragging and _moved < 6.0:
					tile_clicked.emit(e.position, e.button_index)
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var e2 := event as InputEventMouseMotion
		_moved += absf(e2.relative.x) + absf(e2.relative.y)
		if _moved >= 6.0:
			# grab convention: the surface follows the cursor on both axes
			var s := _rot_speed()
			theta += e2.relative.x * s
			phi -= e2.relative.y * s
			_v_theta = e2.relative.x * s
			_v_phi = -e2.relative.y * s
			phi = clampf(phi, 0.05, PI - 0.05)


func _process(delta: float) -> void:
	var k := _rot_speed() * 420.0 * delta
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		theta += k
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		theta -= k
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		phi -= k
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		phi += k
	if Input.is_key_pressed(KEY_Q):
		dist = clampf(dist * (1.0 + 0.9 * delta), min_dist, max_dist)
	if Input.is_key_pressed(KEY_E):
		dist = clampf(dist * (1.0 - 0.9 * delta), min_dist, max_dist)
	if not _dragging:
		theta += _v_theta
		phi += _v_phi
		_v_theta *= 0.90
		_v_phi *= 0.90
	phi = clampf(phi, 0.05, PI - 0.05)
	_update_cam()


func _update_cam() -> void:
	var sp := sin(phi)
	cam.position = Vector3(dist * sp * cos(theta), dist * cos(phi), dist * sp * sin(theta))
	cam.look_at(Vector3.ZERO, Vector3.UP)


func focus_on(unit_dir: Vector3) -> void:
	theta = atan2(unit_dir.z, unit_dir.x)
	phi = acos(clampf(unit_dir.y, -1.0, 1.0))
	phi = clampf(phi, 0.05, PI - 0.05)
	_v_theta = 0.0
	_v_phi = 0.0


func ray_origin(screen_pos: Vector2) -> Vector3:
	return cam.project_ray_origin(screen_pos)


func ray_dir(screen_pos: Vector2) -> Vector3:
	return cam.project_ray_normal(screen_pos)
