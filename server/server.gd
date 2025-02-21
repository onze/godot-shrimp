extends Node
class_name ShrimpServer

@onready var server := TCPServer.new()
@onready var camera_process: CameraProcess = $'camera-process'
@onready var motor_manager: MotorManager = %'motor-manager'

var status_timer := Timer.new()
var peers :Array[StreamPeerTCP] = []
var cam_tex := CameraTexture.new()
var _has_new_frame := false


func _ready() -> void :
	(func()->void:
		add_child(status_timer)
		status_timer.timeout.connect(_update_status)
		status_timer.start(10.)
		_update_status()
	).call_deferred()
	SignalBus.RegisterCommandHandler(Command.NAME.PING, _on_ping)
	SignalBus.signals.new_command.connect(_on_new_command)
	_setup_server()

func _on_ping(params :Dictionary) -> void :
	SignalBus.signals.new_command.emit(-Command.NAME.PING, params)

func _update_status() -> void :
	var items := PackedStringArray()
	# timestamp
	var time_data := Time.get_time_dict_from_system()
	items.append('[%s:%s:%s]'%[time_data['hour'], time_data['minute'], time_data['second']])

	# connection status
	if peers.is_empty() :
		items.append('listening on %s:%s'%[
			Settings.instance.server_host,
			Settings.instance.server_port,
		])
	else :
		items.append('%s peer%s'%[
			peers.size(),
			'' if peers.size() < 2 else 's',
		])

	# keep last
	print('[SRV]  | '.join(items))


func _setup_server() -> void :
	print('[SRV] setting up frame server...')
	var settings := Settings.instance

	var err := server.listen(settings.server_port)
	if err != OK :
		printerr('[SRV] error listening: %s/%s'%[err, error_string(err)])
		return
	print('[SRV] server is listening on port %s'%[server.get_local_port()])


func _process(_delta :float) -> void :
	if server.is_listening() :
		if server.is_connection_available() :
			var peer := server.take_connection()
			peer.set_no_delay(true)
			peers.append(peer)
			print('[SRV] new connection from %s'%[peer.get_connected_host()])
			_update_status()
			_has_new_frame = true
	_poll_peers()

func _poll_peers() ->void :
	var delete_queue :Array[StreamPeerTCP] = []
	for peer :StreamPeerTCP in peers :
		peer.poll()
		match peer.get_status() :
			StreamPeerTCP.STATUS_CONNECTED :
				_pull_message(peer)
			_ :
				print.call_deferred('Connection lost')
				delete_queue.append(peer)
				continue
	# delete disconnected peers
	for peer in delete_queue :
		peers.erase(peer)
	if not delete_queue.is_empty():
		_update_status()
		if peers.is_empty():
			SignalBus.signals.last_peer_quit.emit()


func _pull_message(peer :StreamPeerTCP) -> void :
	if peer.get_available_bytes() == 0:
		return
	var payload_variant :Variant = peer.get_var()
	if payload_variant == null :
		printerr('[SRV] Received a null variant payload from %s'%peer.get_connected_host())
		return
	var payload :Dictionary = payload_variant
	if payload == null :
		printerr('[SRV] Received variant is not a Dictionary, from %s'%peer.get_connected_host())
		return
	SignalBus.Dispatch(payload)

func _on_new_command(command :Command.NAME, params :Dictionary) -> void:
	'''
	Other places in the codebase send commmands through the SignalBus.
	Those commands are picked up and sent through the pipe from here.
	'''
	if command not in [-Command.NAME.PING]:
		print('[SRV] RPC %s(%s)'%[SignalBus.CommandName(command), params])
	for peer :StreamPeerTCP in peers :
		peer.put_var({
			_type=int(command),
			params=params,
		})
