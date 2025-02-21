extends Control

@onready var texture_rect :TextureRect = %texture
@onready var video_container: AspectRatioContainer = texture_rect.get_parent()
@onready var camera_feed_name_label :Label = %'camera-feed-name'
@onready var server_status_label :Label = %'server-status'
@onready var logs :ItemList = %'logs'
@onready var log_scroll_container :ScrollContainer = %'log-scroll-container'
@onready var server := TCPServer.new()

var peers :Array[StreamPeerTCP] = []
var cam_tex := CameraTexture.new()
var _has_new_frame := false


func _log(text :String) -> void :
	print(text)
	logs.add_item(text)
	log_scroll_container.set_deferred(
		'scroll_vertical',
		int(log_scroll_container.get_v_scroll_bar().max_value)
	)

func _ready() -> void :
	logs.clear()
	assert(video_container!=null)
	_setup_camera_feed()
	_setup_server()


func _setup_camera_feed() -> void :
	_log('Setting up camera feed...')
	var feeds := CameraServer.feeds()
	if feeds.is_empty() :
		_log('Found no camera feed!')
		return
	for feed :CameraFeed in feeds :
		_log('Using feed %s'%[feed.get_name()])
		camera_feed_name_label.text = feed.get_name()
		#print(feed.get_datatype()) # 1==FEED_RGB
		var findex := 0
		for format in feed.formats :
			print(findex, ': ', format)
			findex += 1
		# X 124: 640x360@30 Motion-JPEG
		# V 66: 800x600@24 YUYV 4:2:2
		# V 42: 640x380@30 YUYV 4:2:2
		feed.set_format(42, {})
		cam_tex.camera_feed_id = feed.get_id()
		cam_tex.camera_is_active = true
		feed.frame_changed.connect(
			(func()->void:
				video_container.ratio = cam_tex.get_size().aspect()
				),
			CONNECT_ONE_SHOT
		)
		feed.frame_changed.connect(_on_feed_frame_changed)
		texture_rect.texture = cam_tex
		break


func _setup_server() -> void :
	_log('setting up frame server...')
	var settings := Settings.instance

	var err := server.listen(settings.server_port)
	if err != OK :
		_log('error listening: %s/%s'%[err, error_string(err)])
		server_status_label.text = error_string(err)
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

		if peers.is_empty() :
			server_status_label.text = 'listening...'
		else :
			server_status_label.text = '%s peer%s'%[
			peers.size(),
			'' if peers.size() < 2 else 's',
			]
	_send_last_frame()


func _on_feed_frame_changed()->void :
	if peers.is_empty() :
		return
	_has_new_frame = true


func _send_last_frame() ->void :
	if peers.is_empty() or not _has_new_frame :
		return
	_has_new_frame = false
	var frame :Image = cam_tex.get_image().duplicate()
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
