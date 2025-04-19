extends Control
class_name ShrimpClient

@onready var connection_status_label :Label = %'connection-status'
@onready var delta_t_label :Label = %'delta-t'
@onready var byte_count_label :Label = %'byte-rate'
@onready var frame_count_label :Label = %'frame-rate'
@onready var resolution_label :Label = %'resolution'
@onready var logs :ItemList = %'logs'
@onready var log_scroll_container :ScrollContainer = %'log-scroll-container'

var _socket :StreamPeerTCP
#var last_socket_status := StreamPeerTCP.STATUS_NONE
var byte_count :int = 0
var frame_count :int = 0
var one_second_timer := Timer.new()

var input_man: InputManager
var stream_man: StreamManager

func _log(text :String) -> void :
	print('[CLI] '+text)
	logs.add_item(text)
	while logs.item_count > 10:
		logs.remove_item(0)
	(func()->void:
		log_scroll_container.scroll_vertical = int(log_scroll_container.get_v_scroll_bar().max_value)
	).call_deferred()


func _ready() -> void :
	stream_man = find_child('stream-man', true, false)
	assert(stream_man!=null)
	input_man = find_child('input-man', true, false)
	assert(input_man!=null)
	input_man.log.connect(_log)
	## self init
	name = 'client_root'
	DisplayServer.set_icon(preload('res://asset/icon.client.png').get_image())
	DisplayServer.window_set_title('Shrimp Client')
	DisplayServer.window_set_size(Settings.instance.client_window_size)
	DisplayServer.window_set_mode(DisplayServer.WindowMode.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	if Settings.instance.client_window_fullscreen:
		get_window().mode = Window.Mode.MODE_FULLSCREEN
	logs.clear()
	SignalBus.signals.log.connect(_log)
	SignalBus.signals.new_command.connect(_on_new_command)
	SignalBus.RegisterCommandHandler(-Command.NAME.PING, _on_pong)
	_setup_debug_buttons()

	# stats timer
	add_child(one_second_timer)
	one_second_timer.timeout.connect(_on_chrono_timer)
	one_second_timer.start(1.)
	_on_chrono_timer()
	# keep last
	connection_status_label.text = 'Connecting...'
	get_tree().create_timer(1).timeout.connect(_connect)

func _setup_debug_buttons() -> void:
	var debug_buttons_panel: Panel = %'debug-buttons-panel'
	debug_buttons_panel.hide()
	var show_hide_debug_button_btn: Button = %'show-hide-debug-button-btn'
	show_hide_debug_button_btn.toggled.connect(
		func(toggled_on :bool)->void:
			if toggled_on: debug_buttons_panel.show()
			else: debug_buttons_panel.hide()
	)
	var balast_settings: MenuButton = %'balast-settings'
	balast_settings.get_popup().id_pressed.connect(_on_balast_debug_button_item_pressed)
	var reverse_motors: MenuButton = %'reverse-motors'
	reverse_motors.get_popup().id_pressed.connect(_on_reverse_motors_debug_button_item_pressed)

func _on_balast_debug_button_item_pressed(item_id :int) -> void:
	match item_id:
		0:
			_log('balast.set_minimum()')
			SignalBus.signals.new_command.emit(Command.NAME.BALAST_SET_MIMIMUM, {})
		1:
			_log('balast.set_maximum()')
			SignalBus.signals.new_command.emit(Command.NAME.BALAST_SET_MAXIMUM, {})
		2:
			_log('balast.stop()')
			input_man.stop_balast()
		3:
			_log('balast.reset_balast_calibration()')
			input_man.reset_balast_calibration()

func _on_reverse_motors_debug_button_item_pressed(item_id :int) -> void:
	var payload := {}
	match item_id:
		0:
			payload['propulsion'] = true
		1:
			payload['rotation'] = true
		2:
			payload['balast'] = true
	_log('reverse motors(%s)'%[payload])
	SignalBus.signals.new_command.emit(Command.NAME.REVERSE_MOTORS, payload)

func _on_chrono_timer() -> void:
	byte_count_label.text = String.humanize_size(stream_man.byte_count)
	stream_man.byte_count = 0
	frame_count_label.text = '%s/%s'%[
		String.num_int64(stream_man.frame_count),
		String.num_int64(stream_man.skipped_frames_count),
	]
	stream_man.frame_count = 0
	stream_man.skipped_frames_count = 0
	resolution_label.text = '%sx%s'%[
		int(stream_man.resolution.x),
		int(stream_man.resolution.y),
	]
	if _socket != null and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		SignalBus.signals.new_command.emit(
			Command.NAME.PING, {
				tt=Time.get_unix_time_from_system(),
		})

func _on_pong(params :Dictionary) -> void:
	# we measure the half-roundtrip duration
	delta_t_label.text = '%sms'%int(
		1000.*(Time.get_unix_time_from_system()-params.get('tt', 0))/2.
	)

func _connect() -> void :
	if _socket != null and _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		_socket.disconnect_from_host()
	_socket = StreamPeerTCP.new()
	var settings := Settings.instance
	connection_status_label.text = 'Connecting to %s:%s...'%[
		settings.server_host,
		settings.server_port,
	]
	var err := _socket.connect_to_host(settings.server_host, settings.server_port)
	if err != OK :
		_log('Could not connect to server on %s:%s: %s/%s'%[
			settings.server_host,
			settings.server_port,
			error_string(err),
			err,
		])
		SignalBus.signals.disconnected.emit()
		_socket = null
		get_tree().create_timer(
			Settings.instance.reconnection_delay_s
		).timeout.connect(
			_connect
		)

func _process(_delta :float) -> void :
	if _socket != null :
		var last_socket_status := _socket.get_status()
		_socket.poll()
		match _socket.get_status() :
			StreamPeerTCP.STATUS_NONE :
				if last_socket_status != StreamPeerTCP.STATUS_NONE:
					_handle_connection_error('Lost server connection')
			StreamPeerTCP.STATUS_CONNECTING :
				pass
			StreamPeerTCP.STATUS_CONNECTED :
				if last_socket_status != StreamPeerTCP.STATUS_CONNECTED:
					_log('Connected to %s:%s'%[
						Settings.instance.server_host,
						Settings.instance.server_port,
					])
					connection_status_label.text = 'Connected'
					SignalBus.signals.connected.emit()
				_pull_message()
			StreamPeerTCP.STATUS_ERROR :
				_handle_connection_error('Could not connect to server')

func _handle_connection_error(reason :String) -> void :
	_log(reason)
	SignalBus.signals.disconnected.emit()
	_socket = null
	_log('Reconnecting in %ds...'%[Settings.instance.reconnection_delay_s])
	get_tree().create_timer(
		Settings.instance.reconnection_delay_s
	).timeout.connect(
		_connect
	)

func _pull_message() -> void :
	if _socket.get_available_bytes() == 0:
		return
	var payload_variant :Variant = _socket.get_var()
	if payload_variant == null :
		_log('Received a null variant payload')
		return
	var payload :Dictionary = payload_variant
	if payload == null :
		_log('Received variant is not a Dictionary')
		return
	SignalBus.Dispatch(payload)

func _on_new_command(command :Command.NAME, params :Dictionary) -> void:
	'''
	Other places in the codebase send commmands through the SignalBus.
	Those commands are picked up and sent through the pipe from here.
	'''
	if _socket == null:
		print('[CLI] CANCELLED RPC %s(%s)'%[SignalBus.CommandName(command), params])
		return
	if command not in [Command.NAME.PING]:
		print('[CLI] RPC %s(%s)'%[SignalBus.CommandName(command), params])
	_socket.put_var({
		_type=int(command),
		params=params,
	})
