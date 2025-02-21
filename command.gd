class_name Command

# By convention, a handler is registered with an enum value, and a handler to
# its response can be registered with the negative of the enum value.
enum NAME {
	# COMMON
	NOOP = 0,
	PING = 1,
	# COMMANDS IMPLEMENTED ON THE SERVER
	REQUEST_VIDEO_STREAM = 10,
	INITIALIZE_MOTORS = 11,

	TRANSLATE = 20,
	SET_BALAST_LEVEL = 21,

	# COMMANDS IMPLEMENTED ON THE CLIENT
}
