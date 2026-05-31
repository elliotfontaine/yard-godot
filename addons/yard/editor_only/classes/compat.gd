extends Object
## Engine version compatibility helpers and version-gated ResourceUID API wrappers.

## Return true if the current engine version is equal or newer compared to the values provided.
static func is_engine_version_equal_or_newer(major: int, minor: int = 0, patch: int = 0) -> bool:
	var engine_ver: Dictionary = Engine.get_version_info()
	return engine_ver.major >= major and engine_ver.minor >= minor and engine_ver.patch >= patch


## Return true if the current engine version is older compared to the values provided.
static func is_engine_version_older(major: int, minor: int = 0, patch: int = 0) -> bool:
	return not is_engine_version_equal_or_newer(major, minor, patch)


## Returns the UID string for a resource path (works on Godot 4.4 and >= 4.5).
static func path_to_uid(path: String) -> String:
	if is_engine_version_equal_or_newer(4, 5):
		return ResourceUID.call(&"path_to_uid", path)
	else:
		var uid: int = ResourceLoader.get_resource_uid(path)
		return ResourceUID.id_to_text(uid) if uid != -1 else path


## Returns the resource path for a UID string (works on Godot 4.4 and >= 4.5).
static func uid_to_path(uid: String) -> String:
	if is_engine_version_equal_or_newer(4, 5):
		return ResourceUID.call(&"uid_to_path", uid)
	else:
		var id: int = ResourceUID.text_to_id(uid)
		return ResourceUID.call(&"get_id_path", id)


## Returns a resource path, resolving a UID string if needed (works on Godot 4.4 and >= 4.5).
static func ensure_path(path_or_uid: String) -> String:
	if is_engine_version_equal_or_newer(4, 5):
		return ResourceUID.call(&"ensure_path", path_or_uid)

	if path_or_uid.begins_with("res://"):
		return path_or_uid
	elif path_or_uid.begins_with("uid://"):
		return uid_to_path(path_or_uid)
	else:
		return path_or_uid
