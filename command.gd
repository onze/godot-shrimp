class_name Command

# By convention, a handler is registered with an enum value, and a handler to
# its response can be registered with the negative of the enum value.
enum NAME {
	# COMMON
	NOOP = 0,
	PING = 1,
	####################################
	# COMMANDS IMPLEMENTED ON THE SERVER
	REQUEST_VIDEO_STREAM = 10,
	INITIALIZE_MOTORS = 11,

	# values are momentum (not position, not acceleration)
	# args: {
	# 'd': Vector3 - each dimension set to INF if not set/unchanged
	#	z: forward/backward
	#	x: left/right - INF if not set
	#	y: upward/downward (balast) - INF if not set
	# }
	TRANSLATE = 20,

	BALAST_SET_MIMIMUM = 30,
	BALAST_SET_MAXIMUM = 31,
	BALAST_RESET_CALIBRATION = 32,

	REVERSE_MOTORS = 40,

	####################################
	# COMMANDS IMPLEMENTED ON THE CLIENT
	# payload schema:
	# {
	#	balast_energy_ratio: float in [0, 1],
	# }
	SERVER_STATUS = 100,
}
