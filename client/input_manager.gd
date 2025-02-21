extends Node
class_name InputManager

var joystick_handle :Sprite2D
var depth_slider :VSlider
var balast_up: TextureRect
var balast_down: TextureRect

#
var _is_connected := false
var translation := Vector2.ZERO
# [0, 1]
var _balast_level :float = .5
var _balast_level_has_changed := false
var _balast_delta :float = .05
# input is aggregated at a local  high rate,
# and flushed to the shrimp at a lower rate
var command_flush_timer := Timer.new()
var damping := .4

func _damp(x :float, y :float)->float :
	return x*damping+y*(1.-damping)

signal log(s:String)
func _log(text :String) -> void:
	log.emit(text)


func _init() -> void :
	SignalBus.signals.connected.connect(_on_connected)
	SignalBus.signals.disconnected.connect(_on_disconnected)

func _ready() -> void :
	owner = get_parent().owner
	joystick_handle = get_tree().root.find_child('joystick-handle', true, false)
	depth_slider = get_tree().root.find_child('depth-slider', true, false)
	balast_up = get_tree().root.find_child('balast-up', true, false)
	balast_down = get_tree().root.find_child('balast-down', true, false)
	assert(joystick_handle!=null)
	add_child(command_flush_timer)
	command_flush_timer.timeout.connect(_flush_commands)
	command_flush_timer.start(Settings.instance.command_flush_rate)


func _on_connected() -> void :
	_is_connected = true

func _on_disconnected() -> void :
	_is_connected = false

func _unhandled_key_input(raw_event: InputEvent) -> void:
	var event :InputEventKey = raw_event
	print('[CLI] InputManager._unhandled_key_input: ', event)
	match event.keycode:
		KEY_TAB:
			get_tree().quit()

func _process(_delta :float)->void :
	translation = Vector2.ZERO
	if Input.is_action_pressed("forward") :
		translation.y = _damp(translation.y, Input.get_action_strength("forward"))
	if Input.is_action_pressed("backward") :
		translation.y = _damp(translation.y, -Input.get_action_strength("backward"))
	if Input.is_action_pressed("left") :
		translation.x = _damp(translation.x, -Input.get_action_strength("left"))
	if Input.is_action_pressed("right") :
		translation.x = _damp(translation.x, Input.get_action_strength("right"))
	balast_up.visible = Input.is_action_pressed("up")
	if balast_up.visible:
		_balast_level += _balast_delta
		_balast_level_has_changed = true
	balast_down.visible = Input.is_action_pressed("down")
	if balast_down.visible:
		_balast_level -= _balast_delta
		_balast_level_has_changed = true
	if balast_up.visible and balast_down.visible and not is_equal_approx(_balast_level, .5):
		_balast_level = .5
		_log('reset balast level')
	_update_input_visualization()

func _flush_commands() -> void :
	if _is_connected :
		if translation != Vector2.ZERO :
			SignalBus.signals.new_command.emit(Command.NAME.TRANSLATE, {d=translation})
		if _balast_level_has_changed:
			SignalBus.signals.new_command.emit(Command.NAME.SET_BALAST_LEVEL, {l=_balast_level})
	# reset state
	translation = Vector2.ZERO
	_balast_level_has_changed = false
		#print('[CLI] %s~%s'%[Inputs.COMMAND.keys()[command], value])

func _update_input_visualization() -> void :
	# JOYSTICK
	var handle_parent := joystick_handle.get_parent() as TextureRect
	var parent_rect := handle_parent.get_rect()
	var center := parent_rect.get_center()-handle_parent.position
	if translation == Vector2.ZERO :
		joystick_handle.position = center

	# BALAST SLIDER
	_balast_level = clampf(_balast_level, 0., 1.)
	var parent_size := parent_rect.size
	joystick_handle.position = center+(translation*Vector2(1., -1.))*parent_size/2.
	depth_slider.value = _balast_level
