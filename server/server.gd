extends Control
class_name ShrimpServer

@onready var label: RichTextLabel = %label
@onready var server := TCPServer.new()

var status_timer := Timer.new()
var peers :Array[StreamPeerTCP] = []
var cam_tex := CameraTexture.new()
var _has_new_frame := false

var _camera_frames_received := 0
var _camera_frames_sent := 0

func _log(text :String) -> void :
	print(text)

func _ready() -> void :
	get_window().title ='Shrimp Server'
	get_window().size = Settings.instance.server_window_size
	if Settings.instance.server_window_starts_visible:
		DisplayServer.window_set_mode(DisplayServer.WindowMode.WINDOW_MODE_WINDOWED)
		DisplayServer.window_move_to_foreground()

	add_child(status_timer)
	status_timer.timeout.connect(_update_status)
	status_timer.start(1.)
	_setup_camera_feed()
	_setup_server()

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

	# camera frame rate
	items.append('fps: %s/%s'%[_camera_frames_received, _camera_frames_sent])
	_camera_frames_received = 0
	_camera_frames_sent = 0

	# keep last
	label.text = ' | '.join(items)

static func ListCameraFeeds() -> void :
	var feeds := CameraServer.feeds()
	var feed_index := 0
	for feed :CameraFeed in feeds :
		print('######### %s: %s'%[feed_index, feed.get_name()])
		var findex := 0
		for format in feed.formats :
			print(findex, ': ', format, ' data type: ', feed.get_datatype())
			findex += 1
		feed_index += 1

func _setup_camera_feed() -> void :
	_log('Setting up camera feed...')
	var feeds := CameraServer.feeds()
	if feeds.is_empty() :
		_log('Found no camera feed!')
		return
	var selected_feed :CameraFeed = null
	var feed_index :int = Settings.instance.camera_feed_info.get('index', -1)
	var selected_feed_index :int = feed_index
	if feed_index < 0:
		for feed :CameraFeed in feeds :
			if selected_feed == null:
				if feed_index == Settings.instance.camera_feed_info.get('index', -1):
					selected_feed_index = feed_index
					selected_feed = feed
				elif feed.get_name() == Settings.instance.camera_feed_info.get('name', ''):
					selected_feed_index = feed_index
					selected_feed = feed
			feed_index += 1
	else:
		selected_feed = feeds[feed_index]
	if selected_feed == null:
		_log('Camera feed not found: %s'%[Settings.instance.camera_feed_info.get('name')])
		return

	var format_index :int = Settings.instance.camera_feed_info.get('format_index', 0)
	_log('Using feed index %s (%s id %s) / index %s'%[
		selected_feed_index,
		selected_feed.get_name(),
		selected_feed.get_id(),
		format_index,
	])
	selected_feed.set_format(format_index, {})
	cam_tex.camera_feed_id = selected_feed.get_id()
	cam_tex.camera_is_active = true
	selected_feed.frame_changed.connect(_on_feed_frame_changed)


func _setup_server() -> void :
	_log('setting up frame server...')
	var settings := Settings.instance

	var err := server.listen(settings.server_port)
	if err != OK :
		_log('error listening: %s/%s'%[err, error_string(err)])
		return
	_log('server is listening on port %s'%[server.get_local_port()])


func _process(_delta :float) -> void :
	if server.is_listening() :
		if server.is_connection_available() :
			var peer := server.take_connection()
			peer.set_no_delay(true)
			peers.append(peer)
			_log('new connection from %s'%[peer.get_connected_host()])
			_has_new_frame = true
	_send_last_frame()


func _on_feed_frame_changed()->void :
	_camera_frames_received += 1
	if peers.is_empty() :
		return
	_has_new_frame = true


func _send_last_frame() ->void :
	if peers.is_empty() or not _has_new_frame :
		return
	_has_new_frame = false
	var cam_image := cam_tex.get_image()
	if cam_image == null:
		print('Could not retrieve image from camera')
		return
	var frame :Image = cam_image.duplicate()
	if frame == null :
		return
	var payload :Dictionary = {
		size = frame.get_size(),
		format = int(frame.get_format()),
		data = frame.get_data(),
		unix_tt = Time.get_unix_time_from_system(),
	}
	var delete_queue :Array[StreamPeerTCP] = []
	for peer :StreamPeerTCP in peers :
		match peer.get_status() :
			StreamPeerTCP.STATUS_CONNECTED :
				pass
			_ :
				_log.call_deferred('Lost a connection')
				delete_queue.append(peer)
				continue
		peer.put_var(payload)
	# delete disconnected peers
	for peer in delete_queue :
		peers.erase(peer)
	_camera_frames_sent += 1
