extends Object

# MIT LICENSE
# Copyright (c) 2025 Wagner GFX
# https://github.com/WagnerGFX/gdscript_utilities

## Provides utility functions to handle types directly, instead of instances or variables.
##
## This class supports user-created [Script]s and Native Classes like [Object], [Resource] and [Node].
## [br]Scripts without class_name, as inner classes or generated in runtime are [b]NOT[/b] supported,
## they will probably show as a basic type, like [RefCounted] or [GDScript].
## [br]Only Native Classes exposed to GDScript are supported.

const _SCRIPT_BODY_EDITOR := "static func eval():
	var class_type = %s
	var _class_object : %s
	return class_type"

const _SCRIPT_BODY_RUNTIME := "static func eval(): return %s"

static var _script: GDScript = GDScript.new()


## Returns the inheritance tree of a class type reference or name.
static func get_inheritance_list(class_type: Variant, include_self: bool = false) -> Array[String]:
	var final_class_name: String

	if class_type is String:
		final_class_name = class_type

	elif class_type is Script or class_type is Object:
		final_class_name = get_type_name(class_type)

	# Script name > Base Script name > Base Native Class name
	if final_class_name == "" and class_type is Script:
		include_self = true
		var base_script: Script = class_type.get_base_script()

		if base_script:
			final_class_name = get_type_name(base_script)
		else:
			final_class_name = class_type.get_instance_base_type()

	var inheritance_list: Array[String]
	if include_self:
		inheritance_list.append(final_class_name)

	# Search custom script
	var keep_searching := true
	var parent_script := final_class_name

	while keep_searching:
		keep_searching = false

		for inner_script in ProjectSettings.get_global_class_list():
			if inner_script["class"] == parent_script:
				parent_script = inner_script["base"]
				inheritance_list.append(parent_script)
				keep_searching = true
				break

	# Search native node classes
	keep_searching = true

	while keep_searching:
		keep_searching = false
		parent_script = ClassDB.get_parent_class(parent_script)

		if not parent_script == "":
			inheritance_list.append(parent_script)
			keep_searching = true

	return inheritance_list


## Returns the type name of any given type or it's instance.
## [br][br][param obj]: Accepts anything other than built-in Variant types directly.
## [br] This includes Native Classes, user-defined Scripts,
## instances of Node/Resource or any Variant value, including [code]null[/code].
static func get_type_name(obj: Variant) -> String:
	var class_type_name: String

	if (obj is Node or obj is Resource) and obj.get_script():
		obj = obj.get_script()

	if obj is GDScript:
		if is_engine_version_equal_or_newer(4, 3):
			class_type_name = obj.get_global_name()
		else:
			for inner_script in ProjectSettings.get_global_class_list():
				if inner_script["path"] == obj.resource_path:
					class_type_name = inner_script["class"]
					break

		if class_type_name.is_empty():
			class_type_name = obj.get_class()

	elif obj is Object and is_native(obj):
		# TODO: replace properly.
		#class_type_name = GDScriptUtilities.native_classes.get((obj as Object).get_instance_id(), "")
		return "GDScriptNativeClass"

	elif obj is Object:
		class_type_name = obj.get_class()

	elif typeof(obj) == TYPE_ARRAY:
		class_type_name = _get_typed_array_name(obj)

	elif typeof(obj) == TYPE_DICTIONARY:
		class_type_name = _get_typed_dictionary_name(obj)

	else:
		class_type_name = type_string(typeof(obj))

	return class_type_name


## Returns an [Object] that represents the type of a Native Class or user-defined Script.
## [br]It produces a result similar to [code]var class_type = Node as Object[/code].
static func get_type(classname: String) -> Object:
	var result: Object

	if is_script(classname):
		for inner_script in ProjectSettings.get_global_class_list():
			if inner_script["class"] == classname:
				result = load(inner_script["path"])
				break

	elif (
		ClassDB.class_exists(classname)
		and ClassDB.is_class_enabled(classname)
		#and not GDScriptUtilities.native_classes_invalid.has(classname)
	):
		result = get_type_unsafe(classname)

	return result


## Used by [method get_type] and core plugin features. Executes with minimal validation.
static func get_type_unsafe(classname: String) -> Object:
	if Engine.is_editor_hint():
		_script.set_source_code(_SCRIPT_BODY_EDITOR % [classname, classname])
	else:
		_script.set_source_code(_SCRIPT_BODY_RUNTIME % [classname])

	var error := _script.reload()
	var result: Object

	if error == OK:
		result = _script.eval()

	return result


## Checks if [param class_type] is the same or inherits from [param base_class_type].
## [br]Similar to [method Object.is_class], but searches the entire inheritance,
## including Native Classes and user-created Scripts.
## [br][br]Both parameters accept String names, instances and types of Scripts or Native Classes.
static func is_class_of(class_type: Variant, base_class_type: Variant) -> bool:
	var class_type_name: String
	if class_type is String:
		class_type_name = class_type
	elif class_type is Object:
		class_type_name = get_type_name(class_type)
	else:
		return false

	var base_class_type_name := ""
	if base_class_type is String:
		base_class_type_name = base_class_type
	elif base_class_type is Object:
		base_class_type_name = get_type_name(base_class_type)
	else:
		return false

	if not is_valid(class_type_name) or not is_valid(base_class_type_name):
		return false

	var inheritance_list := get_inheritance_list(class_type_name, true)
	return inheritance_list.has(base_class_type_name)


## Checks if [param class_type] is a reference or name that represents a valid Native Class.
static func is_native(class_type: Variant) -> bool:
	if not class_type:
		return false

	if class_type is String:
		return ClassDB.class_exists(class_type) and ClassDB.is_class_enabled(class_type)
	elif class_type is Object and (class_type as Object).get_class() == "GDScriptNativeClass":
		return true
	else:
		return false


## Checks if a [param class_type] is a reference or name that matches an existing user-defined Script.
## Similar to [code]is GDScript[/code], but also accepts string names.
static func is_script(script: Variant) -> bool:
	var script_name: String

	if script is GDScript:
		return true
	elif script is String:
		script_name = script

	if not script or script_name.is_empty():
		return false

	var result := false
	for inner_script in ProjectSettings.get_global_class_list():
		if inner_script["class"] == script_name:
			result = true
			break

	return result


## Checks if a given type ID represents any built-in type except TYPE_OBJECT.
## Can receive other type IDs to exclude.
static func is_type_builtin(type_id: Variant.Type, exclusions: Array[int] = []) -> bool:
	if type_id == TYPE_OBJECT:
		return false

	return not exclusions.has(type_id)


## Checks if a string represents an existing Native Class or user-defined Script
static func is_valid(classname: String) -> bool:
	return is_script(classname) or is_native(classname)


static func _get_typed_array_name(value: Array) -> String:
	var array_name := type_string(typeof(value))

	# Not a typed Array
	if not value.is_typed():
		return array_name

	var typed_array_name := ""
	if is_type_builtin(value.get_typed_builtin()):
		typed_array_name = type_string(value.get_typed_builtin())
	elif value.get_typed_script() != null:
		typed_array_name = get_type_name(value.get_typed_script())
	else:
		typed_array_name = value.get_typed_class_name()

	return "%s[%s]" % [array_name, typed_array_name]


static func _get_typed_dictionary_name(value: Dictionary) -> String:
	var dictionary_name := type_string(typeof(value))

	# Before Godot v4.4
	if is_engine_version_older(4, 4):
		return dictionary_name

	# Not a typed Dictionary
	if not value.is_typed():
		return dictionary_name

	# Key
	var dictionary_key_type_name := ""
	if not value.is_typed_key():
		dictionary_key_type_name = "any"
	elif is_type_builtin(value.get_typed_key_builtin()):
		dictionary_key_type_name = type_string(value.get_typed_key_builtin())
	elif value.get_typed_key_script() != null:
		dictionary_key_type_name = get_type_name(value.get_typed_key_script())
	else:
		dictionary_key_type_name = value.get_typed_key_class_name()

	# Value
	var dictionary_value_type_name := ""
	if not value.is_typed_value():
		dictionary_value_type_name = "any"
	elif is_type_builtin(value.get_typed_value_builtin()):
		dictionary_value_type_name = type_string(value.get_typed_value_builtin())
	elif value.get_typed_value_script() != null:
		dictionary_value_type_name = get_type_name(value.get_typed_value_script())
	else:
		dictionary_value_type_name = value.get_typed_value_class_name()

	return "%s[%s,%s]" % [dictionary_name, dictionary_key_type_name, dictionary_value_type_name]


## Return true if the current engine version is equal or newer compared to the values provided
static func is_engine_version_equal_or_newer(major: int, minor: int = 0, patch: int = 0) -> bool:
	var engine_ver: Dictionary = Engine.get_version_info()
	return engine_ver.major >= major and engine_ver.minor >= minor and engine_ver.patch >= patch


## Return true if the current engine version is older compared to the values provided
static func is_engine_version_older(major: int, minor: int = 0, patch: int = 0) -> bool:
	return not is_engine_version_equal_or_newer(major, minor, patch)


## Retourne le type déclaré (annotation/export/ressource) d'une propriété.
## [param target]: instance d'objet, type (Object) retourné par get_type(), ou nom de classe (String).
## [param property_name]: nom de la propriété dont on veut connaître le typage déclaré.
## Retour: chaîne vide si introuvable, sinon un String décrivant le type (ex: "int", "String", "Texture", "Array[int]", ...).
static func get_property_declared_type(target: Variant, property_name: String) -> String:
	var target_obj: Object = null
	if target is String:
		target_obj = get_type(target)
	elif target is Object:
		target_obj = target
	else:
		return ""

	if not target_obj or not target_obj.has_method("get_property_list"):
		return ""

	var props: Array = target_obj.get_property_list()

	for p: Dictionary in props:
		if p["name"] != property_name:
			continue

		# 1) Cas où le moteur fournit un nom de type explicite (type_name)
		if p.has("type_name") and p["type_name"] != "":
			return str(p["type_name"])

		# 2) Cas générique : type numérique (Variant.Type)
		if p.has("type"):
			var t := int(p["type"])
			# Si type builtin connu -> retourne la chaîne (int, String, Array, Dictionary, ...)
			if t != TYPE_OBJECT:
				return type_string(t)

			# TYPE_OBJECT : il peut s'agir d'une Resource/Node ou d'un type précisé dans hint_string
			# Priorité aux hints (ressource ou class)
			if p.has("hint") and p.has("hint_string") and str(p["hint_string"]) != "":
				# Exemple: PROPERTY_HINT_RESOURCE_TYPE -> "Texture"
				return str(p["hint_string"])

			# S'il existe un "class" ou "class_name" dans la propriété, l'utiliser
			if p.has("class") and str(p["class"]) != "":
				return str(p["class"])

			# fallback
			return "Object"

		# 3) Cas où le type est indiqué via hint_string seulement (enum, resource, etc.)
		if p.has("hint_string") and str(p["hint_string"]) != "":
			return str(p["hint_string"])

	# Si on arrive là, propriété non trouvée
	return ""
