extends RefCounted
class_name Settings

static var instance :Settings = Settings.new()

const LOCAL_IP := "127.0.0.1"
const DESKTOP_IP := "192.168.0.108"
const STEAMDECK_IP := "192.168.0.173"
const RPI_IP := "192.168.0.166"

## COMMON
var hostname := GetHostname()
# --server-port
var server_port := 6266

## SERVER
# --server
var is_server := false
var server_window_size := Vector2i(800, 32)
var server_window_starts_visible := hostname in ['onze-desktop']
var camera_feed_info :Dictionary = {
	# 254: 480x320@? 16-bit RGB 8-8-8
	# 411: 800x600@? 16-bit RGB 8-8-8
	# 417: 1280x720@? 16-bit RGB 8-8-8
	# 254: 480x320@? 24-bit RGB 8-8-8
	# 261: 800x600@? 24-bit RGB 8-8-8
	# 267: 1280x720@? 24-bit RGB 8-8-8
	'goshrimp' = {
		index=0,
		#name='/base/soc/i2c0mux/i2c@1/imx708@',
		format_index=254
	},
	# ? 1: 640x480@24 YUYV 4:2:2
	# X 124: 640x360@30 Motion-JPEG
	# V 66: 800x600@24 YUYV 4:2:2
	# V 42: 640x380@30 YUYV 4:2:2
	# V 43: 640x380@24 YUYV 4:2:2
	# V 46: 640x380@10 YUYV 4:2:2
	'onze-desktop' = { name='HD Webcam C615', format_index=66},
}.get(hostname, {})

## CLIENT
# --client
var is_client := true
var client_window_size := Vector2i(1280, 800)
# how long we wait after a disconnect before reconnecting
var reconnection_delay_s :float = 3
# frequency at which we send commands to the shrimp
var command_flush_rate :float = 5.
# --server-host
var server_host := '<set by preset>'

func preset_desktop2desktop() -> void:
	server_window_starts_visible = true
	server_host = DESKTOP_IP
func preset_rpi2desktop() -> void:
	server_window_starts_visible = false
	server_host = RPI_IP
func preset_rpi2steamdeck() -> void:
	server_window_starts_visible = false
	server_host = STEAMDECK_IP

func _init() ->void :
	assert(Settings.instance == null)
	assert(is_client or camera_feed_info.is_empty(), 'Empty camera feed info on a server instance!')
	Settings.instance = self
	preset_desktop2desktop()
	#preset_rpi2desktop()
	#preset_rpi2steamdeck()


func process_args() -> void :
	for arg :String in OS.get_cmdline_user_args() :
		var tokens := Array(arg.split('='))
		var key :String = tokens[0]
		tokens.remove_at(0)
		var value := '='.join(tokens)
		match key :
			'--client' :
				is_client = true
				is_server = false
			'--server' :
				is_client = false
				is_server = true
			'--server-host' :
				server_host = value
			'--server-port' :
				server_port = int(value)
			'--list-camera' :
				ShrimpServer.ListCameraFeeds()
			'--camera-feed-index' :
				camera_feed_info['index'] = int(value)
			'--camera-feed-format' :
				camera_feed_info['format_index'] = int(value)
			'--preset':
				match value:
					'desktop2desktop': preset_desktop2desktop()
					'rpi2desktop': preset_rpi2desktop()
					'rpi2steamdeck': preset_rpi2steamdeck()

	#
	assert(is_client != is_server)

static func IsSteamOS() -> bool:
	return OS.get_distribution_name().containsn("SteamOS")

static func GetHostname() -> String:
	if IsSteamOS():
		return 'steamdeck'
	var hostname_out :Array = []
	OS.execute('hostname', [], hostname_out)
	return ''.join(hostname_out).strip_edges()
