extends Node
class_name StreamManager
'''
Connects to a libcamera-vid mjpeg stream and updates its texture_rect.
'''

@onready var video_loading_label: Label = %'video-loading-label'
@onready var texture_rect :TextureRect = %texture
@onready var video_container :AspectRatioContainer = texture_rect.get_parent()

var _invalid_frames_count :int = 0
var byte_count :int = 0
var frame_count :int = 0
var skipped_frames_count :int = 0
var resolution := Vector2i.ZERO

var _host :String
var _port :int
var _socket :StreamPeerTCP = null
var _connection_tt_s :float = -1
var _buffer := PackedByteArray()

func _ready() -> void:
	SignalBus.signals.connected.connect(_request_stream)
	SignalBus.signals.disconnected.connect(_disconnect)
	SignalBus.RegisterCommandHandler(
		-Command.NAME.REQUEST_VIDEO_STREAM,
		_request_video_stream_response,
	)
	video_loading_label.visible = true
	video_loading_label.text = 'initialized, waiting for connection to shrimp...'

func _disconnect() -> void:
	if _socket != null:
		if _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_socket.disconnect_from_host()
		_socket = null
	video_loading_label.visible = true
	video_loading_label.text = 'waiting for main server connection...'

func _handle_connection_error(reason :String) -> void:
	SignalBus.log(reason)
	# retry after a moment
	get_tree().create_timer(Settings.instance.reconnection_delay_s).timeout.connect(_request_stream)
	video_loading_label.visible = true
	video_loading_label.text = 'reconnecting to stream in %ds'%Settings.instance.reconnection_delay_s

func _request_stream() -> void:
	'''ask the server to open a libcamera stream for us'''
	SignalBus.signals.new_command.emit(
		Command.NAME.REQUEST_VIDEO_STREAM, {
			width=400,
			height=300,
			fps=24,
		}
	)

func _request_video_stream_response(params :Dictionary) -> void:
	'''receive the camera video stream url'''
	var error :String = params.get('error', '')
	if not error.is_empty():
		return _handle_connection_error(
			'Could not get a video stream URL: %s. Rerying in %ss'%[
				error,
				Settings.instance.reconnection_delay_s,
		])

	var host :String = params.get('host', '')
	var port :int = params.get('port', -1)
	if host.is_empty() or port == -1:
		return _handle_connection_error(
			'Invalid video feed params:%s. Rerying in %ss'%[
				params,
				Settings.instance.reconnection_delay_s,
			])

	_start_streaming(host, port)

func _start_streaming(host :String, port :int) -> void:
	_host = host
	_port = port
	if _socket != null:
		if _socket.get_status() == StreamPeerTCP.STATUS_CONNECTED:
			_socket.close()
	_socket = StreamPeerTCP.new()
	_connection_tt_s = Time.get_unix_time_from_system()
	var err := _socket.connect_to_host(host, port)
	if err != OK :
		return _handle_connection_error('Could not connect to server on %s:%s'%[host, port])

func _process(_delta: float) -> void:
	if _socket != null:
		var last_socket_status := _socket.get_status()
		_socket.poll()
		match _socket.get_status() :
			StreamPeerTCP.STATUS_NONE :
				if last_socket_status != StreamPeerTCP.STATUS_NONE:
					_handle_connection_error('Lost stream connection')
			StreamPeerTCP.STATUS_CONNECTING :
				pass
			StreamPeerTCP.STATUS_CONNECTED :
				if last_socket_status != StreamPeerTCP.STATUS_CONNECTED:
					SignalBus.log('Connected to video stream on port %s'%[_port])
					video_loading_label.visible = false
					_socket.set_no_delay(true)
				_update_frame()
			StreamPeerTCP.STATUS_ERROR :
				var delay_s := Time.get_unix_time_from_system() - _connection_tt_s
				_socket = null
				if delay_s > Settings.instance.connection_timeout_s:
					_handle_connection_error(
						'Cannot access stream, retrying from scratch in %ss...'%Settings.instance.reconnection_delay_s
					)
				else:
					SignalBus.log('Stream connection error, retrying in %ss...'%Settings.instance.reconnection_delay_s)
					get_tree().create_timer(
						Settings.instance.reconnection_delay_s
					).timeout.connect(
						_start_streaming.bind(_host, _port)
					)


func _extract_frame() -> PackedByteArray:
	var bytes_available := _socket.get_available_bytes()
	if bytes_available == 0:
		return PackedByteArray()
	byte_count += bytes_available
	var ret := _socket.get_data(bytes_available)
	var err :Error = ret[0]
	if err != OK:
		SignalBus.log('Could read bytes')
		return PackedByteArray()
	_buffer.append_array(ret[1])
	# find start of image marker
	var soi :int = _find_marker_index(0xff, 0xD8)
	if soi == -1:
		# no start of image yet, let discard the buffer
		_buffer.clear()
		return PackedByteArray()
	# find end of image marker
	var eoi :int = _find_marker_index(0xff, 0xD9, soi)
	if eoi == -1:
		# no end of image yet, still receiving the frame, wait for next engine frame
		return PackedByteArray()
	var next_frames_index := eoi+2
	var frame_data := _buffer.slice(soi, next_frames_index)
	_buffer = _buffer.slice(next_frames_index)
	if frame_data.size() < 10:
		# the pi seems to return tiny frames every now and then
		return PackedByteArray()
	return frame_data

func _update_frame()->void:
	# extract as many frames as possible
	var frame_data :PackedByteArray = _extract_frame()
	var last_frame_data := frame_data
	while not frame_data.is_empty():
		last_frame_data = frame_data
		frame_data = _extract_frame()
		skipped_frames_count += 1
	frame_data = last_frame_data
	if frame_data.is_empty():
		# there was nothing to extract to begin with
		return
	skipped_frames_count -= 1
	var frame := Image.new()
	var err = frame.load_jpg_from_buffer(frame_data)
	if err != OK:
		_invalid_frames_count += 1
		if false:
			var INVALID_FRAMES_DIR := OS.get_cache_dir().path_join('invalid_frames')
			DirAccess.make_dir_recursive_absolute(INVALID_FRAMES_DIR)
			SignalBus.log('Could not build frame: %s/%s'%[error_string(err), err])
			var file := FileAccess.open(INVALID_FRAMES_DIR.path_join('%05d.jpeg'%_invalid_frames_count), FileAccess.WRITE)
			file.store_buffer(frame_data)
			file.close()
		return

	if frame.is_empty() :
		SignalBus.log('Empty frame')
		return
	texture_rect.texture = ImageTexture.create_from_image(frame)
	video_container.ratio = frame.get_size().aspect()
	frame_count += 1
	resolution = frame.get_size()

func _find_marker_index(m0 :int, m1 :int, index :int = 0) -> int:
	while index < _buffer.size():
		var m0_index := _buffer.find(m0, index)
		# checking against size -1 because we're goign to read one byte after m0_index
		if m0_index == -1 or m0_index >= _buffer.size()-1:
			break
		if _buffer[m0_index+1] == m1:
			return m0_index
		index = m0_index+1
	return -1
