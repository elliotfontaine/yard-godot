# SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
# SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)
#
# SPDX-License-Identifier: MIT

@tool
extends EditorInspectorPlugin
## Edits [constant Registry.PROPERTY_HINT_CUSTOM] properties with Godot's native editors.
##
## String and StringName properties get the enum dropdown, filled with the registry string IDs.
## Arrays and dictionaries get the collection editors, with the registry hint passed down to their
## elements: collection editors create element editors through the inspector plugins, so each
## element comes back here as a String or StringName property.

const Namespace := preload("res://addons/yard/editor_only/namespace.gd")
const RegistryIO := Namespace.RegistryIO
const YardLogger := Namespace.YardLogger

const STRING_TYPES: Array[Variant.Type] = [TYPE_STRING, TYPE_STRING_NAME]
## Dictionary sides named by each value of the dict= option, for warnings.
const DICTIONARY_SIDE_NAMES: Dictionary[String, String] = {
	"": "keys or values",
	"keys": "keys",
	"values": "values",
	"both": "keys and values",
}

## Warnings already shown, so that inspector refreshes don't repeat them.
var _shown_warnings: Dictionary[String, bool] = { }


func _can_handle(_object: Object) -> bool:
	return true


func _parse_property(
	object: Object,
	type: Variant.Type,
	name: String,
	hint: PropertyHint,
	hint_text: String,
	usage: int,
	wide: bool,
) -> bool:
	if hint != Registry.PROPERTY_HINT_CUSTOM:
		return false

	var custom_hint := RegistryIO.CustomHint.parse(hint_text)
	var registry := custom_hint.load_registry()
	if not registry:
		return false

	# Created before add_property_editor(), as instantiate_property_editor() runs every
	# inspector plugin again, this one included, and takes the first editor they added.
	var editor: EditorProperty = null
	match type:
		TYPE_STRING, TYPE_STRING_NAME:
			# Also reached for the elements of the collection editors below, with the
			# collection editor as object and an empty name.
			editor = EditorInspector.instantiate_property_editor(
				object,
				type,
				name,
				PROPERTY_HINT_ENUM_SUGGESTION if custom_hint.suggestion else PROPERTY_HINT_ENUM,
				_get_enum_hint_string(registry, custom_hint.sort),
				usage,
				wide,
			)
		TYPE_ARRAY, TYPE_PACKED_STRING_ARRAY:
			var element_type := TYPE_STRING
			if type == TYPE_ARRAY:
				var array: Variant = object.get(name)
				element_type = array.get_typed_builtin() as Variant.Type if array is Array else TYPE_NIL
			if element_type not in STRING_TYPES:
				return false

			editor = EditorInspector.instantiate_property_editor(
				object,
				type,
				name,
				PROPERTY_HINT_ARRAY_TYPE,
				_get_registry_element_hint(element_type, hint_text),
				usage,
				wide,
			)
		TYPE_DICTIONARY:
			var dictionary: Variant = object.get(name)
			if dictionary is not Dictionary:
				return false

			var key_type := dictionary.get_typed_key_builtin() as Variant.Type
			var value_type := dictionary.get_typed_value_builtin() as Variant.Type
			var side := _get_dictionary_registry_side(key_type, value_type, custom_hint.dict_side)
			if side.is_empty():
				_warn_once(
					"Cannot apply Registry.PROPERTY_HINT_CUSTOM to '%s': its %s must be String or StringName."
					% [name, DICTIONARY_SIDE_NAMES[custom_hint.dict_side]]
				)
				return false

			var key_hint := (
				_get_element_type_hint(
					key_type,
					dictionary.get_typed_key_class_name(),
					dictionary.get_typed_key_script(),
				)
				if side == "values"
				else _get_registry_element_hint(key_type, hint_text)
			)
			var value_hint := (
				_get_element_type_hint(
					value_type,
					dictionary.get_typed_value_class_name(),
					dictionary.get_typed_value_script(),
				)
				if side == "keys"
				else _get_registry_element_hint(value_type, hint_text)
			)
			editor = EditorInspector.instantiate_property_editor(
				object,
				type,
				name,
				PROPERTY_HINT_DICTIONARY_TYPE,
				"%s;%s" % [key_hint, value_hint],
				usage,
				wide,
			)

	if not editor:
		return false

	add_property_editor(name, editor)
	return true


## Hint string of the enum dropdown: the registry string IDs, comma-separated.
func _get_enum_hint_string(registry: Registry, sort_spec: String) -> String:
	var string_ids := PackedStringArray()
	for string_id: StringName in RegistryIO.get_string_ids_sorted_by(registry, sort_spec):
		if string_id.contains(","):
			_warn_once(
				"Cannot show '%s' of %s in dropdowns, as string IDs can't contain commas. Rename it to use it."
				% [string_id, registry.resource_path.get_file()]
			)
			continue
		string_ids.append(string_id)
	return ",".join(string_ids)


func _warn_once(message: String) -> void:
	if _shown_warnings.has(message):
		return
	_shown_warnings[message] = true
	YardLogger.warn(message)


## Hint of a collection element holding string IDs, in the "type/hint:hint_string" format of
## collection hints. Its editor comes back to this plugin with the registry hint.
static func _get_registry_element_hint(element_type: Variant.Type, hint_text: String) -> String:
	return "%d/%d:%s" % [element_type, Registry.PROPERTY_HINT_CUSTOM, hint_text]


## Hint of a typed dictionary side that doesn't hold string IDs, rebuilt from its type, as
## @export_custom replaces the hint Godot would give.
static func _get_element_type_hint(
	element_type: Variant.Type,
	native_class: StringName,
	typed_script: Script,
) -> String:
	if element_type == TYPE_NIL:
		return ""
	if element_type != TYPE_OBJECT:
		return "%d:" % element_type

	var typed_class: StringName = (
		typed_script.get_global_name()
		if typed_script and typed_script.get_global_name()
		else native_class
	)
	var object_hint := (
		PROPERTY_HINT_NODE_TYPE
		if ClassDB.is_parent_class(native_class, &"Node")
		else PROPERTY_HINT_RESOURCE_TYPE
	)
	return "%d/%d:%s" % [TYPE_OBJECT, object_hint, typed_class]


## Returns the side of a typed dictionary holding string IDs: "keys", "values" or "both", or an
## empty string if none can. [param forced_side] comes from the dict= option of the hint.
static func _get_dictionary_registry_side(
	key_type: Variant.Type,
	value_type: Variant.Type,
	forced_side: String,
) -> String:
	var keys_are_strings := key_type in STRING_TYPES
	var values_are_strings := value_type in STRING_TYPES
	match forced_side:
		"keys":
			return "keys" if keys_are_strings else ""
		"values":
			return "values" if values_are_strings else ""
		"both":
			return "both" if keys_are_strings and values_are_strings else ""

	# The String or StringName side. If both are, the StringName one, else the keys.
	if not keys_are_strings:
		return "values" if values_are_strings else ""
	if value_type == TYPE_STRING_NAME and key_type != TYPE_STRING_NAME:
		return "values"
	return "keys"
