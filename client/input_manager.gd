extends Node
class_name InputManager

var joystick_handle :Sprite2D
var depth_slider :VSlider
var balast_up: TextureRect
var balast_down: TextureRect
var translation_hbox: HFlowContainer
var translation_label: Label

#
var _is_connected := false
var translation := Vector2.ZERO
# we skip sending successive null translations after the first one's been sent
var _last_tx_was_zero := false
var tx_force :float = ProjectSettings.get_setting('application/run/max_fps')
var tx_damping := .85
var tx_deadzone := 0.01
# [0, 1]
var _balast_level :float = .5
var _balast_level_has_changed := false
var _balast_delta :float = 1.
# input is aggregated at a local  high rate,
# and flushed to the shrimp at a lower rate
var command_flush_timer := Timer.new()

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
	translation_hbox = get_tree().root.find_child('translation-hbox', true, false)
	translation_label = get_tree().root.find_child('translation-label', true, false)
	assert(joystick_handle!=null)
	add_child(command_flush_timer)
	command_flush_timer.timeout.connect(_flush_commands)
	command_flush_timer.start(1./Settings.instance.command_flush_rate)

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

func _process(delta :float)->void :
	var tx_delta := Vector2.ZERO
	if Input.is_action_pressed("forward") :
		tx_delta.y += Input.get_action_strength("forward")*delta*tx_force
	if Input.is_action_pressed("backward") :
		tx_delta.y += -Input.get_action_strength("backward")*delta*tx_force
	if Input.is_action_pressed("left") :
		tx_delta.x += -Input.get_action_strength("left")*delta*tx_force
	if Input.is_action_pressed("right") :
		tx_delta.x += Input.get_action_strength("right")*delta*tx_force
	balast_up.visible = Input.is_action_pressed("up")
	if balast_up.visible:
		_balast_level += _balast_delta*delta
		_balast_level_has_changed = true
	balast_down.visible = Input.is_action_pressed("down")
	if balast_down.visible:
		_balast_level -= _balast_delta*delta
		_balast_level_has_changed = true
	if balast_up.visible and balast_down.visible and not is_equal_approx(_balast_level, .5):
		_balast_level = .5
		_log('reset balast level')

	translation = translation*tx_damping+tx_delta*(1.-tx_damping)
	# when no input is seen, and we're damping tx under the deadzone
	if tx_delta.is_zero_approx() and translation.length_squared() < tx_deadzone*Vector2.ONE.length():
		translation = Vector2.ZERO
	_update_input_visualization()

func _flush_commands() -> void :
	if _is_connected :
		if not translation.is_zero_approx() or not _last_tx_was_zero:
			SignalBus.signals.new_command.emit(Command.NAME.TRANSLATE, {d=translation})
		_last_tx_was_zero = translation.is_zero_approx()
		if _balast_level_has_changed:
			SignalBus.signals.new_command.emit(Command.NAME.SET_BALAST_LEVEL, {b=_balast_level})
	# reset state
	_balast_level_has_changed = false

func _update_input_visualization() -> void :
	# JOYSTICK
	var handle_parent := joystick_handle.get_parent() as TextureRect
	var parent_rect := handle_parent.get_rect()
	var center := parent_rect.get_center()-handle_parent.position

	translation_hbox.visible = not translation.is_zero_approx()
	translation_label.text = '[%d, %d]'%[translation.x*100, translation.y*100]

	# BALAST SLIDER
	_balast_level = clampf(_balast_level, 0., 1.)
	var parent_size := Vector2.ONE * (minf(parent_rect.size.x, parent_rect.size.y)-joystick_handle.get_rect().size.x)
	joystick_handle.position = center+(translation*Vector2(1., -1.))*parent_size/2.
	depth_slider.value = _balast_level
