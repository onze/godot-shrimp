extends Control

@onready var peer :PacketPeerUDP = PacketPeerUDP.new()


func _ready()->void :
	print('started with user args: ', OS.get_cmdline_user_args())
	Settings.instance.process_args()
	_load_client_server_scene.call_deferred()


func _load_client_server_scene()->void :
	if 1 and Settings.instance.is_client :
		get_window().title ='Shrimp Client'
		print('starting as client')
		add_child(preload('res://client/client.tscn').instantiate())
	else :
		get_window().title ='Shrimp Server'
		print('starting as server')
		add_child(preload('res://server/server.tscn').instantiate())


func _process(_delta :float)->void :
	if Input.is_key_pressed(Key.KEY_ESCAPE) :
		get_tree().quit()
