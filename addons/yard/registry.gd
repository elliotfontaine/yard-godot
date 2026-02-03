@tool
class_name Registry
extends Resource

## Invalid resources are not fetched and don't push errors.
const INVALID_RESOURCE_ID := &"<invalid>"
const REGISTRY_FILE_EXTENSION := "reg"

@export var valid_classes: Array[StringName]
@export_dir var source_folder: String

var _uids_to_string_ids: Dictionary[StringName, StringName]
var _string_ids_to_uids: Dictionary[StringName, StringName]


func is_empty() -> bool:
	return _uids_to_string_ids.is_empty()


func size() -> int:
	return _uids_to_string_ids.size()


## Given an [param id] (either StringID or UID), returns the associated Resource in the Registry.
func load_entry(id: StringName) -> Resource:
	var uid := get_uid(id)
	if uid == &"":
		return null
	else:
		return load(uid)


func load_all() -> Dictionary[StringName, Resource]:
	var dict: Dictionary[StringName, Resource] = { }

	for uid in _uids_to_string_ids:
		if not uid == &"":
			dict[_uids_to_string_ids[uid]] = load(uid)

	return dict


## Given an [param id] (either StringID or UID),
## always returns the UID text ("uid://..."), or "" if [param id] is invalid
## (i.e. not in the registry).
func get_uid(id: StringName) -> StringName:
	if id == INVALID_RESOURCE_ID:
		return &""

	if id.is_empty():
		return &""

	if id.begins_with("uid://"):
		return id if _uids_to_string_ids.has(id) else &""

	var string_id := StringName(id)
	return _string_ids_to_uids.get(string_id, &"")


func get_stringid(uid: StringName) -> StringName:
	if _uids_to_string_ids.has(uid):
		return _uids_to_string_ids[uid]
	else:
		return &""


## add a new Resource to the Registry from a UID.
## If no string_id is given, it will use the file basename.
## If the string_id is already used in the Registry, it will append a number to it.
func _add_entry(uid: StringName, string_id: String = "") -> bool:
	var cache_id: int = ResourceUID.text_to_id(uid)
	if not ResourceUID.has_id(cache_id):
		return false

	if not string_id:
		string_id = ResourceUID.get_id_path(cache_id).get_file().get_basename()

	if string_id in _string_ids_to_uids:
		string_id = _make_string_unique(string_id)

	if uid in _uids_to_string_ids:
		return false

	_uids_to_string_ids[uid] = string_id as StringName
	_string_ids_to_uids[string_id] = uid
	return true


func _make_string_unique(string_id: String) -> String:
	if not string_id in _string_ids_to_uids:
		return string_id

	var id_to_try := string_id
	var n := 2
	while id_to_try + "_" + str(n) in _string_ids_to_uids:
		n += 1
	return id_to_try + "_" + str(n)


func _validate_uids() -> Dictionary[StringName, bool]:
	var ret: Dictionary[StringName, bool] = { }
	for uid in _uids_to_string_ids:
		ret[uid] = _is_uid_valid(uid)
	return ret


func _is_uid_valid(uid: StringName) -> bool:
	if uid == &"" or uid == INVALID_RESOURCE_ID:
		return false

	var uid_str := String(uid)
	if not uid_str.begins_with("uid://"):
		return false

	var cache_id: int = ResourceUID.text_to_id(uid_str)
	return ResourceUID.has_id(cache_id)


func _validate_resource_classes() -> void:
	for uid in _uids_to_string_ids:
		if not ResourceLoader.exists(uid):
			continue
		var is_valid := _is_resource_class_valid(load(uid))
		if not is_valid:
			pass
			#set_invalid_resource(uid)
	#_emit_registry_entries_changed()


func _is_resource_class_valid(res: Resource) -> bool:
	if res == null:
		return false
	if valid_classes.is_empty():
		return true

	var class_stringname: StringName
	var res_script: Script = res.get_script()
	if res_script != null:
		var global_name := StringName(res_script.get_global_name())
		if not global_name.is_empty():
			class_stringname = global_name
		else:
			class_stringname = StringName(res.get_class())
	else:
		class_stringname = StringName(res.get_class())

	for valid_class in valid_classes:
		if class_stringname == valid_class:
			return true
		if res.is_class(String(valid_class)):
			return true
		if ClassDB.is_parent_class(String(class_stringname), String(valid_class)):
			return true

	return false
