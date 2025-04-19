extends Node

@onready var peer :PacketPeerUDP = PacketPeerUDP.new()


func _ready()->void :
	print('##################')
	print('# OS: ', OS.get_name(), ' | version: ', OS.get_version())
	print('# Hostname: ', Settings.instance.hostname)
	print('# Distro: ', OS.get_distribution_name())
	print('# Processor: ', OS.get_processor_name(), ' | ', OS.get_processor_count(), ' cores')
	print('# User args: ', OS.get_cmdline_user_args())
	print('##################')

	Settings.instance.process_args()
	_load_client_server_scene.call_deferred()


func _load_client_server_scene()->void :
	if Settings.instance.is_client :
		print('starting as client')
		get_tree().change_scene_to_file('res://client/client.tscn')
	else :
		print('starting as server')
		get_tree().change_scene_to_file('res://server/server.tscn')


func _process(_delta :float)->void :
	if Input.is_key_pressed(Key.KEY_ESCAPE) :
		get_tree().quit()
