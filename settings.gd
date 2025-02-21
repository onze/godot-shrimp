extends RefCounted
class_name Settings

var is_steam_os := OS.get_distribution_name().containsn("SteamOS")
static var instance :Settings = Settings.new()
## COMMON
# --server-port
var server_port := 6266
## SERVER
# --server
var is_server := false
## CLIENT
# --client
var is_client := true
# how long we wait after a disconnect before reconnecting
var reconnection_delay_s :float = 3
# frequency at which we send commands to the shrimp 
var command_flush_rate :float = 5.
# --server-host
const DESKTOP_IP := "192.168.0.108"
const LOCAL_IP := "127.0.0.1"
var server_host := DESKTOP_IP if is_steam_os else LOCAL_IP


func _init() ->void :
	assert(Settings.instance == null)
	Settings.instance = self


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

	#
	assert(is_client != is_server)