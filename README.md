<h1>
  <picture>
	<source media="(prefers-color-scheme: dark)" srcset="addons/yard/editor_only/assets/yard_dark.svg">
	<source media="(prefers-color-scheme: light)" srcset="addons/yard/editor_only/assets/yard_light.svg">
	<img src="addons/yard/editor_only/assets/yard.svg" width="24">
  </picture>
  YARD — Yet Another Resource Database
</h1>

A Godot 4 plugin for managing and querying collections of resources through a dedicated editor interface and runtime API.

## Overview

![preview of the registry editor](etc/preview_2.png)

YARD builds on Godot's [resource system](https://docs.godotengine.org/en/4.5/tutorials/scripting/resources.html). It has two parts:

**A table-based resource editor.** The YARD editor tab lets you create and manage registries: catalogues of resources, optionally restricted to a class. Each registry provides a spreadsheet-like view of your resources and their properties.

**A lightweight runtime API.** At runtime, a `Registry` is just a small `.tres` file holding UIDs and string IDs. It contains only the mapping, never the resources themselves. _You_ control when loading happens, and how.

## Features

- 🏷 Stable string IDs that survive file moves, with no autoload boilerplate to maintain
- 🔒 Restrict a registry to a class so only matching resources can be added
- 🔄 Sync a registry from a directory (recursively or not), with entries staying in sync as files appear or disappear
- 🥧 Bake a property index in the editor for zero-cost runtime filtering by property value
- 📦 Load entries individually, all at once (blocking), or asynchronously via threaded loading
- ⚡ All expensive operations happen in the editor, leaving no runtime overhead beyond what you explicitly request

## Installation

1. Copy the `addons/yard` folder into your project's `addons/` directory
2. Enable the plugin in **Project > Project Settings > Plugins**

## Usage

### Creating a registry

Open the **Registry** tab in the editor, click **File > New Registry**, and configure:

- **Class restriction**: only resources of this class (or its subclasses) will be accepted
- **Scan directory**: the registry will stay in sync with resource files in this folder
- **Indexed properties**: property names to bake into the index for runtime filtering

### Adding entries

If a scan directory is set, entries are managed automatically. Otherwise, you can add entries manually in two ways:

- **Drag and drop** resources from the FileSystem dock into the registry table. They must match the class restriction.
- **Create a new resource on the spot** using the resource picker at the bottom of the table. When you press **Add Entry**, it creates and saves the file, then immediately registers it.

### Inspector dropdown with `@export_custom`

`Registry.PROPERTY_HINT_CUSTOM` enables a dropdown in the inspector for any `StringName`, `String`, `Array[StringName]`, or `Array[String]` property, populated with the string IDs of a given registry.

```gdscript
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://data/item_registry.tres") var item: StringName
# With an <empty> option that maps to an empty string:
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://data/item_registry.tres,true") var item_or_empty: StringName
# For arrays (duplicates allowed by default, set to false to disable):
@export_custom(Registry.PROPERTY_HINT_CUSTOM, "res://data/item_registry.tres,true,false") var unique_items: Array[StringName]
```

### Loading entries at runtime

```gdscript
const ENEMIES: Registry = preload("res://data/enemy_registry.tres")

# Load a single entry by string ID
var skeleton: Enemy = ENEMIES.load_entry(&"skeleton")

# Load all entries at once (blocking)
var all_enemies: Dictionary[StringName, Resource] = ENEMIES.load_all_blocking()

# Load all entries via background threads
var tracker := ENEMIES.load_all_threaded_request()
# Poll tracker.progress (0.0–1.0) each frame; read tracker.resources when done
```

To look up the string ID of an already-loaded resource:

```gdscript
var string_id := ENEMIES.get_string_id_of(loaded_resource)
```

### Querying entries through the property index

Set up indexed properties in **Registry Settings** and press **Reindex** to bake the index. At runtime, queries run without loading any resource.

```gdscript
# Single property — exact value or predicate
var legendaries := WEAPONS.filter(&"rarity", Rarity.LEGENDARY)
var high_level  := WEAPONS.filter(&"level", func(v): return v >= 10)

# AND query across multiple properties (exact values or predicates)
var legendary_non_boss := ROOMS.where({
	&"biome": Biome.FOREST,
	&"tier": func(t): return t != RoomData.Tier.Boss,
})
```

Properties support dot notation for nested resources: `&"weapon.rarity"` resolves the `rarity` property of the resource stored in `weapon`.

> The full `Registry` API is documented in the in-editor class reference: **Help > Search Help > Registry**.

## How the property index works its magic

The index is simply a nested dictionary stored inside the registry `.tres` file:

```gdscript
_property_index = {
	&"rarity": {
		Rarity.LEGENDARY: { &"excalibur": true, &"mjolnir": true },
		Rarity.COMMON: { &"stick": true },
	},
	&"level": {
		1: { &"stick": true },
		10: { &"excalibur": true },
		12: { &"mjolnir": true },
	}
}
```

## Contributing

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request.

For major changes, [open an issue](https://github.com/elliotfontaine/yard-godot/issues/new?template=feature_request.yml) first to discuss what you have in mind.

## License

[MIT](LICENSE)
