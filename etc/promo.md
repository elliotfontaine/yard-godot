I've been working on a Godot 4 plugin for a while and figured it was time to share it properly.

**What is it?**

YARD gives you a table-based editor interface to create and manage registries (catalogues of resources grouped by class) and a lightweight runtime API to query them. Think of it less as a database and more as a structured way to organize your resources, reference them by stable string IDs, and filter them at runtime without loading anything you didn't ask for.

Not familiar with Godot resources and custom resources? They are a core Godot concept and a great way to store data. The [official documentation](https://docs.godotengine.org/en/stable/tutorials/scripting/resources.html) is a good starting point.

**Why another one?**

Honestly, because nothing out there hit the right balance for me. [Some existing solutions](https://github.com/don-tnowe/godot-resources-as-sheets-plugin/tree/Godot-4) offer only a table view with no real runtime features. [Others try to go full database](https://github.com/DarthPapalo/ResourceDatabases), which is great until you're fighting the tool since the UX isn't so great.

There's a gap I wanted to fill. On one end: an autoload stuffed with preloaded resources and enums, or a helper that builds a path from a string name and calls `load()` on it. It works, until it doesn't. On the other end: SQLite, powerful but takes you outside the Godot resource workflow most of the time. YARD sits in between, and is designed to drop into a project already in progress. Add the plugin, create a registry, point it at a directory, and you're done.

**Key features**

- Reference resources by string IDs instead of file paths scattered around
- Restrict registries to a specific class (or don't)
- Sync a registry from a directory automatically
- Bake a property index in the editor for zero-cost runtime filtering
- Load entries individually, all at once, or asynchronously

The filtering part is probably the most useful piece. The index is baked in the editor, so at runtime `filter_by_value` and friends can query it directly. No resource is loaded, there isn't any overhead.

```swift
const WEAPONS: Registry = preload("res://data/weapon_registry.tres")
const ENEMIES: Registry = preload("res://data/enemy_registry.tres")

func _on_fight_started() -> void:
    var skeleton: Enemy = ENEMIES.load_entry(&"skeleton")
    var all_enemies := ENEMIES.load_all_blocking()

    # Filter without loading any resource, returns matching string IDs
    var legendaries := WEAPONS.filter_by_value(&"rarity", Rarity.LEGENDARY)
    var high_level := WEAPONS.filter_by(&"level", func(v): return v >= 10)
    var legendary_swords := WEAPONS.filter_by_values({
        &"rarity": Rarity.LEGENDARY,
        &"type": "sword",
    })
```

**YARD is open source, MIT licensed.**

Repo is here: [https://github.com/elliotfontaine/yard-godot](https://github.com/elliotfontaine/yard-godot)

Feedback, issues, and contributions are very welcome. I've been using it in my own project and it's been solid, but more eyes are always better.
