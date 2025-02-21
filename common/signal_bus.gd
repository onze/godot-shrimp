extends RefCounted
class_name SignalBus

class _Signals:
	# main client / server
	@warning_ignore('unused_signal')
	signal connected()
	# main client / server
	@warning_ignore('unused_signal')
	signal disconnected()

	signal log(s:String)

	@warning_ignore('unused_signal')
	signal new_command(cmd :Command.NAME, params :Dictionary)

	@warning_ignore('unused_signal')
	signal last_peer_quit()

static var signals := _Signals.new()

static func log(s :String) -> void:
	signals.log.emit(s)

#region custom commands
# stores signals created dynamically whenever an object registers a Command handler
static var __command_register := Object.new()

static func CommandName(command :int) -> String:
	var prefix := '-' if command < 0 else ''
	for i :int in Command.NAME.values().size():
		var cmd :int = Command.NAME.values()[i]
		if cmd == absi(command):
			return prefix+Command.NAME.keys()[i]
	return ''

static func _MakeSignalName(command :int) -> String:
	var suffix = '_response' if command < 0 else ''
	return '_rpc_signal__'+CommandName(command)+suffix

static func RegisterCommandHandler(command :int, callback :Callable) -> void:
	'''NOTE: `callback` MUST take a dict as SINGLE argument.'''
	var signal_name := _MakeSignalName(command)
	if not __command_register.has_signal(signal_name):
		__command_register.add_user_signal(signal_name, [{name='params', type=TYPE_DICTIONARY}])
	var registered_signal := Signal(__command_register, signal_name)
	registered_signal.connect(callback)

static func Dispatch(payload :Dictionary) -> void:
	var command :int = payload.get('_type', Command.NAME.NOOP)
	var signal_name := _MakeSignalName(command)
	if not __command_register.has_signal(signal_name):
		printerr('Signal not found for command _type: %s/%s'%[command, _MakeSignalName(command)])
		# add the signal with no handler, just to mute the error
		__command_register.add_user_signal(signal_name, [{name='params', type=TYPE_DICTIONARY}])
		return
	var registered_signal := Signal(__command_register, signal_name)
	if abs(command) not in [Command.NAME.PING]:
		print('RPC DISPATCH: %s'%CommandName(command))
	registered_signal.emit(payload.get('params', {}))
#endregion
