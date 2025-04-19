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
var stream_resolution := Vector2(400, 300)

## SERVER
# --server
var is_server := false
var camera_startup_delay_s :float = 2
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
var libcamera_stream_port := 6002

var ggpio_chipid := '0'
var propulsion_motor_phase_gpio := 6 # green
var propulsion_motor_enable_gpio := 12 # yellow
var rotation_motor_phase_gpio := 16 # grey
var rotation_motor_enable_gpio := 19 # white
var balast_motor_phase_gpio := 20 # green
var balast_motor_enable_gpio := 26 # blue

## CLIENT
# --client
var is_client := true
var client_window_size := Vector2i(1280, 800)
var client_window_fullscreen := false

# whether a successful connection to the server triggers a video stream request
var open_video_stream_upon_connection := true
# how long we try reconnections to the video stream before giving up and requesting a new stream
var connection_timeout_s :float = 15
# how long we wait after a disconnect before reconnecting
var reconnection_delay_s :float = 1
# frequency at which we send commands to the shrimp
var command_flush_rate :float = 5.
# --server-host
var server_host := '<set by preset>'
var disable_video_stream := false

func preset_desktop2desktop() -> void:
	#server_host = 'onze-desktop.local'
	server_host = DESKTOP_IP
	client_window_fullscreen = false
	stream_resolution = Vector2(800, 600)
func preset_rpi2desktop() -> void:
	#server_host = 'goshrimp.local'
	server_host = RPI_IP
	client_window_fullscreen = false
	stream_resolution = Vector2(400, 300)
func preset_rpi2steamdeck() -> void:
	#server_host = 'goshrimp.local'
	server_host = RPI_IP
	client_window_fullscreen = true
	stream_resolution = Vector2(400, 300)
func preset_desktop2steamdeck() -> void:
	#server_host = 'onze-desktop.local'
	server_host = DESKTOP_IP
	client_window_fullscreen = true
	stream_resolution = Vector2(400, 300)
	disable_video_stream = true

func _init() ->void :
	assert(Settings.instance == null)
	assert(is_client or camera_feed_info.is_empty(), 'Empty camera feed info on a server instance!')
	Settings.instance = self
	#preset_rpi2desktop()
	preset_rpi2steamdeck()

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
			#'--camera-feed-index' :
				#camera_feed_info['index'] = int(value)
			#'--camera-feed-format' :
				#camera_feed_info['format_index'] = int(value)
			'--fullscreen' :
				if value.to_lower() in ['on', '1', 'true', 't', 'y', 'yes']:
					client_window_fullscreen = true
					print('fullscreen: force enabled')
				elif value.to_lower() in ['off', '0', 'false', 'f', 'n', 'no']:
					client_window_fullscreen = false
					print('fullscreen: force disabled')
				else:
					print('Unsupported --fullscreen value: ', value)
			'--preset':
				match value:
					'desktop2desktop': preset_desktop2desktop()
					'desktop2steamdeck': preset_desktop2steamdeck()
					'rpi2desktop': preset_rpi2desktop()
					'rpi2steamdeck': preset_rpi2steamdeck()
			'--video':
				if value.to_lower() in ['off', '0', 'false', 'f', 'n', 'no']:
					open_video_stream_upon_connection = false

	#
	assert(is_client != is_server)

static func IsSteamOS() -> bool:
	return OS.get_distribution_name().containsn("SteamOS")

static func GetHostname() -> String:
	#if IsSteamOS():
		#return 'steamdeck'
	var hostname_out :Array = []
	OS.execute('/usr/bin/hostnamectl', ['hostname'], hostname_out, true)
	return ''.join(hostname_out).strip_edges()
