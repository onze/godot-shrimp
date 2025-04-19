class_name Utils

static func Cache(key :String, value :Variant) -> Variant:
	var abs_path := 'user://'+key
	DirAccess.make_dir_absolute(abs_path.get_base_dir())
	var file := FileAccess.open(abs_path, FileAccess.WRITE)
	file.store_var(value, true)
	return value

static func Uncache(key :String, default :Variant) -> Variant:
	var abs_path := 'user://'+key
	var file := FileAccess.open(abs_path, FileAccess.READ)
	if file == null:
		return default
	return file.get_var(true)

static func ClearCache(key :String) -> void:
	var abs_path := 'user://'+key
	DirAccess.remove_absolute(abs_path)
