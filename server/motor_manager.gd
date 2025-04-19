extends Node
class_name MotorManager

var sbc :ggpio.SBC
var chip :ggpio.Chip
var propulsion_motor :ggpio.devices.output.PhaseEnableMotor
const PROPULSION_MOTOR_REVERSED_FILE := 'propulsion/reversed.dat'
var rotation_motor :ggpio.devices.output.PhaseEnableMotor
const ROTATION_MOTOR_REVERSED_FILE := 'rotation/reversed.dat'
var balast_motor :ggpio.devices.output.PhaseEnableMotor
const BALAST_MOTOR_REVERSED_FILE := 'balast/reversed.dat'

class MockMotor extends ggpio.devices.output.PhaseEnableMotor:
	var _value :float = 0
	func _set_value(v :float) -> float:
		_value = v
		return _value
	func _get_value() -> float:
		return _value

	func _init(_o0 :Object, _o1 :Object) -> void: pass
	func forward(speed :float = 1.) -> void: _value = speed
	func backward(speed :float = 1.) -> void: _value = speed
	func stop() -> void: _value = 0
	func close() -> void: _value = 0

var _balast_energy :float = 0.
var _min_balast_energy :float = -INF
var _max_balast_energy :float = INF
const BALAST_ENERGY_FILE := 'balast/energy.dat'
const BALAST_MIN_ENERGY_FILE := 'balast/minimum.dat'
const BALAST_MAX_ENERGY_FILE := 'balast/maximum.dat'
const BALAST_ZERO_TOLERANCE :float = .2

func _ready() -> void:
	ggpio.Init(true)
	sbc = ggpio.SBC.new()
	SignalBus.RegisterCommandHandler(Command.NAME.INITIALIZE_MOTORS, _initalize_motors)
	SignalBus.RegisterCommandHandler(Command.NAME.TRANSLATE, _on_translate_requested)
	SignalBus.RegisterCommandHandler(Command.NAME.BALAST_SET_MIMIMUM, _on_balast_set_minimum)
	SignalBus.RegisterCommandHandler(Command.NAME.BALAST_SET_MAXIMUM, _on_balast_set_maximum)
	SignalBus.RegisterCommandHandler(Command.NAME.BALAST_RESET_CALIBRATION, _on_balast_reset_calibration)
	SignalBus.RegisterCommandHandler(Command.NAME.REVERSE_MOTORS, _on_reverse_motors)
	_initalize_motors()

	_min_balast_energy = Utils.Uncache(BALAST_MIN_ENERGY_FILE, -INF)
	if _min_balast_energy >= 0: _min_balast_energy = -INF
	_max_balast_energy = Utils.Uncache(BALAST_MAX_ENERGY_FILE, INF)
	if _max_balast_energy <= 0: _max_balast_energy = INF
	_balast_energy = Utils.Uncache(BALAST_ENERGY_FILE, 0)
	print('Uncached balast energy %.2f within range [%s, %s]'%[
		_balast_energy,
		_min_balast_energy,
		_max_balast_energy
	])
	# TODO upon connection, notifiy client that a balast calibration is required

func _initalize_motors(_args := {}) -> void:
	var settings := Settings.instance

	# no access to gpio on desktop
	if [Settings.DESKTOP_IP].has(settings.server_host):
		sbc = ggpio.SBC.Mock()

	chip = sbc.open_chip(settings.ggpio_chipid)
	var chip_info := chip.get_info()
	if chip_info.gpio_count < 0:
		ggpio.log(
			'Could not connect to local gpio %s'%settings.ggpio_chipid,
			ggpio.LogLevel.ERROR
		)
		return
	ggpio.log(
		'Connected to %s / %s'%[
			chip_info.name,
			chip_info.usage,
		],
		ggpio.LogLevel.ERROR
	)
	#
	propulsion_motor = ggpio.devices.output.PhaseEnableMotor.Make(
		chip,
		settings.propulsion_motor_phase_gpio,
		settings.propulsion_motor_enable_gpio,
	)
	rotation_motor = ggpio.devices.output.PhaseEnableMotor.Make(
		chip,
		settings.rotation_motor_phase_gpio,
		settings.rotation_motor_enable_gpio,
	)
	balast_motor = ggpio.devices.output.PhaseEnableMotor.Make(
		chip,
		settings.balast_motor_phase_gpio,
		settings.balast_motor_enable_gpio,
	)
	_reload_motors_directions()

func _on_translate_requested(args := {}) -> void:
	var delta :Vector3 = args.get('d', Vector2.ZERO) as Vector3

	if not is_inf(delta.z):
		propulsion_motor.value = delta.z
	if not is_inf(delta.x):
		rotation_motor.value = delta.x
	if not is_inf(delta.y):
		# prevent activating the motor if it would move its energy past a limit
		var predicted_energy := _balast_energy + balast_motor.value + delta.y * .2
		if (
				(delta.y > 0 and predicted_energy <= _max_balast_energy) or
				(delta.y < 0 and predicted_energy >= _min_balast_energy) or
				is_zero_approx(delta.y)
			):
			balast_motor.value = delta.y
			Utils.Cache(BALAST_ENERGY_FILE, _balast_energy)

	_send_translation_update()

func _send_translation_update() -> void:
	var balast_energy_ratio :float = NAN
	if not is_inf(_min_balast_energy) and not is_inf(_max_balast_energy):
		balast_energy_ratio = inverse_lerp(
			_min_balast_energy,
			_max_balast_energy,
			_balast_energy
		)
	if not is_nan(balast_energy_ratio):
		SignalBus.signals.new_command.emit(
			-Command.NAME.TRANSLATE,
			{
				balast_energy_ratio = balast_energy_ratio,
			}
		)

func print_status() ->void:
	print('bal V %.2f E: %.2f < %.2f < %.2f'%[
		balast_motor.value,
		_min_balast_energy,
		_balast_energy,
		_max_balast_energy,
	])

func _process(delta: float) -> void:
	if absf(balast_motor.value) > BALAST_ZERO_TOLERANCE:
		# stop the balast if it moves past min/max limits
		_balast_energy += balast_motor.value * delta
		var update_client := Engine.get_process_frames() % int(Engine.get_frames_per_second() / 4) == 0
		if balast_motor.value < -BALAST_ZERO_TOLERANCE and _balast_energy < _min_balast_energy:
			print('[SRV] hit _min_balast_energy: %.2f'%[_min_balast_energy])
			balast_motor.stop()
			update_client = true
		if balast_motor.value > BALAST_ZERO_TOLERANCE and _balast_energy > _max_balast_energy:
			print('[SRV] hit _max_balast_energy: %.2f'%[_max_balast_energy])
			balast_motor.stop()
			update_client = true

		if update_client:
			Utils.Cache(BALAST_ENERGY_FILE, _balast_energy)
			_send_translation_update()
	elif not is_zero_approx(balast_motor.value):
		balast_motor.stop()
		Utils.Cache(BALAST_ENERGY_FILE, _balast_energy)

func _on_balast_set_minimum(_args := {}) -> void:
	print('[SRV] BALAST set minimum: %s'%_balast_energy)
	_min_balast_energy = _balast_energy
	Utils.Cache(BALAST_MIN_ENERGY_FILE, _balast_energy)

func _on_balast_set_maximum(_args := {}) -> void:
	print('[SRV] BALAST set maximum: %s'%_balast_energy)
	_max_balast_energy = _balast_energy
	Utils.Cache(BALAST_MAX_ENERGY_FILE, _balast_energy)

func _on_balast_reset_calibration(_args := {}) -> void:
	print('[SRV] BALAST reset calibration')
	Utils.ClearCache(BALAST_MIN_ENERGY_FILE)
	Utils.ClearCache(BALAST_MAX_ENERGY_FILE)
	Utils.ClearCache(BALAST_ENERGY_FILE)
	_min_balast_energy = -INF
	_max_balast_energy = INF
	_balast_energy = 0
	balast_motor.stop()

	SignalBus.signals.new_command.emit(
		-Command.NAME.TRANSLATE,
		{
			balast_energy_ratio = .5,
		}
	)

func _on_reverse_motors(payload := {}) -> void:
	if payload.get('propulsion', false):
		propulsion_motor.reversed = not propulsion_motor.reversed
		Utils.Cache(PROPULSION_MOTOR_REVERSED_FILE, propulsion_motor.reversed)
	if payload.get('rotation', false):
		rotation_motor.reversed = not rotation_motor.reversed
		Utils.Cache(ROTATION_MOTOR_REVERSED_FILE, rotation_motor.reversed)
	if payload.get('balast', false):
		balast_motor.reversed = not balast_motor.reversed
		Utils.Cache(BALAST_MOTOR_REVERSED_FILE, balast_motor.reversed)
	_reload_motors_directions()

func _reload_motors_directions() -> void:
	propulsion_motor.reversed = Utils.Uncache(PROPULSION_MOTOR_REVERSED_FILE, false)
	rotation_motor.reversed = Utils.Uncache(ROTATION_MOTOR_REVERSED_FILE, false)
	balast_motor.reversed = Utils.Uncache(BALAST_MOTOR_REVERSED_FILE, false)
	print('[SRV] directions prop: %s rot: %s bal: %s'%[
		propulsion_motor.reversed,
		rotation_motor.reversed,
		balast_motor.reversed,
	])
