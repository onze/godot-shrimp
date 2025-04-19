extends Node
class_name CameraProcess

static var PID_FILE := OS.get_cache_dir().path_join('libcamera.pid')
var process_thread :Thread = null

func _init() -> void:
	SignalBus.RegisterCommandHandler(
		Command.NAME.REQUEST_VIDEO_STREAM,
		_on_stream_requested,
	)
	SignalBus.signals.last_peer_quit.connect(_stop_libcamera)
	_stop_libcamera()

func _get_libcamera_pid() -> int:
	var file := FileAccess.open(PID_FILE, FileAccess.READ)
	if file == null:
		return -1
	if file.get_length() == 0:
		return -1
	var pid := file.get_64()
	return pid

func _stop_libcamera() -> void:
	var pid := _get_libcamera_pid()
	if pid < 0:
		return
	print('[SRV] Killing libcamera on %s'%pid)
	if not OS.is_process_running(pid):
		return
	var err := OS.kill(pid)
	if err != OK:
		printerr('[SRV] Could not kill libcamera process: %s/%s'%[err, error_string(err)])
		return
	if process_thread != null:
		process_thread.wait_to_finish()
	process_thread = null
	DirAccess.remove_absolute(PID_FILE)


func _on_stream_requested(args :Dictionary)->void:
	_start_libcamera(
		args.get('width', 400) as int,
		args.get('height', 300) as int,
		args.get('fps', 24) as int,
	)
	# wait 3 seconds before responding, for the cam to start
	get_tree().create_timer(Settings.instance.camera_startup_delay_s).timeout.connect(
		func()->void:
			SignalBus.signals.new_command.emit(
				-Command.NAME.REQUEST_VIDEO_STREAM,
				{
					host=Settings.instance.server_host,
					port=Settings.instance.libcamera_stream_port,
				}
			)
	)

func _monitor_libcamera_process() -> void:
	var pid := _get_libcamera_pid()
	while true:
		if OS.is_process_running(pid):
			await get_tree().create_timer(1).timeout
			continue
		print('[SRV] libcamera stopped')
		break

func _start_libcamera(width :int, height :int, fps :int) -> void:
	if process_thread != null:
		_stop_libcamera()

	var binary_path := ''
	var args := PackedStringArray()
	if Settings.instance.hostname == 'goshrimp':
		binary_path = '/usr/bin/rpicam-vid'
		args.append_array([
			'-n',
			'-t0',
			'--low-latency=1',
			'--flush',
			'--inline',
			'--listen',
			'--width', String.num_int64(width),
			'--height', String.num_int64(height),
			'--framerate', String.num_int64(fps),
			'--codec', 'mjpeg',
			'--quality=10',
			'-o', 'tcp://0.0.0.0:%s'%Settings.instance.libcamera_stream_port,
		])
	else:
		binary_path = '/usr/bin/ffmpeg'
		args.append_array([
			'-r', String.num(fps),
			'-f', 'video4linux2',
			'-i', '/dev/video0',
			'-f', 'mjpeg',
			'-vf', 'scale=%s:%s'%[String.num_int64(width), String.num_int64(height)],
			'-preset', 'ultrafast',
			'-tune', 'zerolatency',
			'-movflags', '+faststart',
			'-fflags', 'nobuffer',
			# https://fotoforensics.com/analysis.php showed that ffmpeg defaults to subpixel sampling
			# with YCbCr4:2:2 (2 1), which godot won't load. While a random jpeg is subsampled
			# with YCbCr4:2:0 (2 2). This flag fixes it for Godot.
			'-pix_fmt', 'yuvj420p',
			'tcp://0.0.0.0:%s?listen'%Settings.instance.libcamera_stream_port,
		])
	print('[SRV] starting libcamera: %s %s'%[binary_path, ' '.join(args)])
	var pid := OS.create_process(binary_path, args, false)
	var file := FileAccess.open(PID_FILE, FileAccess.WRITE)
	file.store_64(pid)
	file.close()
	process_thread = Thread.new()
	process_thread.start(_monitor_libcamera_process)
