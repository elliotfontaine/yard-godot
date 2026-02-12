const PluginCFG := "res://addons/yard/plugin.cfg"
const RegistryIO := preload("res://addons/yard/editor_only/registry_io.gd")
const DynamicTable := preload("res://addons/yard/editor_only/classes/dynamic_table.gd")
const RegistriesItemList := preload("res://addons/yard/editor_only/ui_scenes/registries_itemlist.gd")
const NewRegistryDialog := preload("res://addons/yard/editor_only/ui_scenes/new_registry_dialog.gd")
const EditorThemeUtils := preload("res://addons/yard/editor_only/classes/editor_theme_utils.gd")
const EditorIconButton := preload("res://addons/yard/editor_only/classes/editor_icon_button.gd")
const FuzzySearch := preload("res://addons/yard/editor_only/classes/fuzzy_search.gd")
const FuzzySearchResult := FuzzySearch.FuzzySearchResult

const FILESYSTEM_CREATE_CONTEXT_MENU_PLUGIN = preload("res://addons/yard/editor_only/editor_context_menu_plugin.gd")

const MainView := preload("res://addons/yard/editor_only/ui_scenes/main_view.gd")
const MAIN_VIEW_SCENE := preload("res://addons/yard/editor_only/ui_scenes/main_view.tscn")

const RegistryView := preload("res://addons/yard/editor_only/ui_scenes/registry_view.gd")
const REGISTRY_VIEW_SCENE := preload("res://addons/yard/editor_only/ui_scenes/registry_view.tscn")

const TRANSLATION_DOMAIN := "com.elliotfontaine.yard"
const TRANSLATIONS := {
	"fr_FR": "res://addons/yard/editor_only/locale/fr_FR.po",
}
