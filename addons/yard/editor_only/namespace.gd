const DynamicTable = preload("res://addons/yard/editor_only/classes/dynamic_table.gd")
const RegistriesItemList = preload("res://addons/yard/editor_only/ui_scenes/registries_itemlist.gd")
const FuzzySearch = preload("res://addons/yard/editor_only/classes/fuzzy_search.gd")
const FuzzySearchResult = FuzzySearch.FuzzySearchResult

const MainView := preload("res://addons/yard/editor_only/ui_scenes/main_view.gd")
const MAIN_VIEW_SCENE := preload("res://addons/yard/editor_only/ui_scenes/main_view.tscn")

const RegistryView := preload("res://addons/yard/editor_only/ui_scenes/registry_view.gd")
const REGISTRY_VIEW_SCENE := preload("res://addons/yard/editor_only/ui_scenes/registry_view.tscn")

const TRANSLATION_DOMAIN := "com.elliotfontaine.yard"
const TRANSLATIONS := {
	"fr_FR": "res://addons/yard/editor_only/locale/fr_FR.po",
}
