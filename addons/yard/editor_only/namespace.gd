const PluginCFG := "res://addons/yard/plugin.cfg"

# Static Util Classes
const RegistryIO := preload("res://addons/yard/editor_only/registry_io.gd")
const YardEditorCache := preload("res://addons/yard/editor_only/classes/yard_editor_cache.gd")
const ClassUtils := preload("res://addons/yard/editor_only/classes/class_utils.gd")
const EditorThemeUtils := preload("res://addons/yard/editor_only/classes/editor_theme_utils.gd")
const FuzzySearch := preload("res://addons/yard/editor_only/classes/fuzzy_search.gd")
const AnyIcon := preload("res://addons/yard/editor_only/classes/any_icon.gd")

# UI Scenes
const RegistryEditor := preload("res://addons/yard/editor_only/ui_scenes/registry_editor.gd")
const RegistryTableView := preload("res://addons/yard/editor_only/ui_scenes/registry_table_view.gd")
const DynamicTable := preload("res://addons/yard/editor_only/ui_scenes/components/dynamic_table.gd")
const RegistriesItemList := preload("res://addons/yard/editor_only/ui_scenes/components/registries_itemlist.gd")
const NewRegistryDialog := preload("res://addons/yard/editor_only/ui_scenes/components/new_registry_dialog.gd")
const REGISTRY_EDITOR_SCENE := preload("res://addons/yard/editor_only/ui_scenes/registry_editor.tscn")
const REGISTRY_TABLE_VIEW_SCENE := preload("res://addons/yard/editor_only/ui_scenes/registry_table_view.tscn")

# Misc
const FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN = preload("res://addons/yard/editor_only/editor_context_menu_plugin.gd")
const TRANSLATION_DOMAIN := "com.elliotfontaine.yard"
const TRANSLATIONS := {
	"fr_FR": "res://addons/yard/editor_only/locale/fr_FR.po",
}
