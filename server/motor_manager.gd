extends Node
class_name MotorManager

var sbc :ggpio.SBC
var chip :ggpio.Chip
var propulsion_motor :ggpio.devices.output.PhaseEnableMotor
var rotation_motor :ggpio.devices.output.PhaseEnableMotor
var balast_motor :ggpio.devices.output.PhaseEnableMotor
var use_mock_motors := false

func _ready() -> void:
	ggpio.Init(true)
	sbc = ggpio.SBC.new()
	SignalBus.RegisterCommandHandler(Command.NAME.INITIALIZE_MOTORS, _initalize_motors)
	SignalBus.RegisterCommandHandler(Command.NAME.TRANSLATE, _on_translate_requested)
	# no access to gpio on desktop
	use_mock_motors = Settings.instance.server_host != Settings.instance.RPI_IP
	if not use_mock_motors:
		_initalize_motors()

func _initalize_motors(_args := {}) -> void:
	var settings := Settings.instance
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

func _on_translate_requested(args := {}) -> void:
	var tx :Vector2 = args.get('d', Vector2.ZERO) as Vector2
	var b :float = args.get('b', 0) as float
	if use_mock_motors:
		print('RCV.MOTOR prop: %.2f rot: %.2f bal: %.2f'%[tx.y, tx.x, b])
	else:
		propulsion_motor.value = tx.y
		rotation_motor.value = tx.x
		balast_motor.value = b
