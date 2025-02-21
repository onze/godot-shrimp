extends Control
class_name ShrimpClient

@onready var texture_rect :TextureRect = %texture
@onready var video_container :AspectRatioContainer = texture_rect.get_parent()
@onready var connection_status_label :Label = %'connection-status'
@onready var delta_t_label :Label = %'delta-t'
@onready var byte_count_label :Label = %'byte-rate'
@onready var frame_count_label :Label = %'frame-rate'
@onready var resolution_label :Label = %'resolution'
@onready var logs :ItemList = %'logs'
@onready var log_scroll_container :ScrollContainer = %'log-scroll-container'

var peer :StreamPeerTCP
var byte_count :int = 0
var frame_count :int = 0
var one_second_timer := Timer.new()
signal connected()
signal disconnected()
var input_man :InputManager


func _log(text :String) -> void :
	print(text)
	logs.add_item(text)
	log_scroll_container.set_deferred(
		'scroll_vertical',
		int(log_scroll_container.get_v_scroll_bar().max_value)
	)


func _ready() -> void :
	name = 'client_root'
	DisplayServer.set_icon(preload('res://asset/icon.client.png').get_image())
	DisplayServer.window_set_title('Shrimp Client')
	DisplayServer.window_set_size(Settings.instance.client_window_size)
	DisplayServer.window_set_mode(DisplayServer.WindowMode.WINDOW_MODE_WINDOWED)
	DisplayServer.window_move_to_foreground()
	logs.clear()
	peer = StreamPeerTCP.new()
	_connect()
	input_man = InputManager.new(_log, connected, disconnected)
	add_child(input_man)
	add_child(one_second_timer)
	one_second_timer.timeout.connect(_on_chrono_timer)
	one_second_timer.start(1.)

	if Settings.IsSteamOS():
		get_window().mode = Window.Mode.MODE_FULLSCREEN


func _on_chrono_timer() -> void :
	byte_count_label.text = String.humanize_size(byte_count)
	byte_count = 0
	frame_count_label.text = String.num_int64(frame_count)
	frame_count = 0


func _process(_delta :float) -> void :
	if peer != null :
		peer.poll()
		match peer.get_status() :
			StreamPeerTCP.STATUS_NONE :
				_connect()
			StreamPeerTCP.STATUS_CONNECTING :
				pass
			StreamPeerTCP.STATUS_CONNECTED :
				_pull_frame()
			StreamPeerTCP.STATUS_ERROR :
				_log('TCP Peer errored, resetting now')
				disconnected.emit()
				peer = null
				_log('Reconnecting in %ss...'%[Settings.instance.reconnection_delay_s])
				get_tree().create_timer(Settings.instance.reconnection_delay_s).timeout.connect(
					func()->void :
						peer = StreamPeerTCP.new()
				)


func _connect() -> bool :
	var settings := Settings.instance
	connection_status_label.text = 'connecting to %s:%s...'%[
		settings.server_host,
		settings.server_port,
	]
	var err := peer.connect_to_host(settings.server_host, settings.server_port)
	if err != OK :
		_log('Could not connect to server on %s:%s'%[
		settings.server_host,
		settings.server_port,
		])
		return false
	peer.poll()
	if peer.get_status() == StreamPeerTCP.STATUS_CONNECTED :
		_log('Connected on %s:%s'%[
		settings.server_host,
		settings.server_port,
		])
		connection_status_label.text = 'connected'
		connected.emit()

	return true


func _pull_frame() -> void :
	var payload_variant :Variant = peer.get_var()
	if payload_variant == null :
		_log('Received a null variant payload')
		return
	var payload :Dictionary = payload_variant
	if payload == null :
		_log('Received variant is not a Dictionary')
		return

	# process frame
	var frame_size :Vector2i = payload.get('size', Vector2i.ZERO)
	if frame_size == Vector2i.ZERO :
		_log('Invalid frame size')
		return

	var frame_bytes :PackedByteArray = payload.get('data', PackedByteArray())
	#byte_count += peer.get_available_bytes()
	byte_count += frame_bytes.size()
	var frame := Image.create_from_data(
		frame_size.x,
		frame_size.y,
		false,
		payload.get('format', 0),
		frame_bytes,
	)
	if frame.is_empty() :
		_log('Could not rebuild frame')
		return
	texture_rect.texture = ImageTexture.create_from_image(frame)
	video_container.ratio = frame_size.aspect()
	frame_count += 1
	# process unix timestamp
	var tt :float = payload.get('unix_tt', -1.)
	delta_t_label.text = '%sms'%[
	int((Time.get_unix_time_from_system()-tt)*1000.)
	]
	resolution_label.text = '%sx%s'%[frame_size.x, frame_size.y]
