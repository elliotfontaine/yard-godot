<!--
SPDX-FileCopyrightText: 2025-2026, Elliot Fontaine <yard-godot@elliotfontaine.anonaddy.com>
SPDX-FileCopyrightText: 2026-present, YARD contributors (see AUTHORS.md)

SPDX-License-Identifier: CC0-1.0
-->

# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/2.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.3.2] - 2026-11-09

### Fixed

- **gui:** Accept registries dropped on the top of the registry list **[@elliotfontaine]**
- **model:** Match whole file extensions in scan filters **[@elliotfontaine]**
- **model:** Stop scans from emptying V1 registries without class restriction **[@elliotfontaine in [#196](https://github.com/elliotfontaine/yard-godot/pull/196)]**
- **table:** Allow assigning class-named scripts in table cells **[@elliotfontaine in [#189](https://github.com/elliotfontaine/yard-godot/pull/189)]**
- **table:** Stop UID cells from slowing down every table redraw **[@elliotfontaine]**
- **table:** Align all cell text on the same baseline **[@elliotfontaine]**
- **table:** Stop dictionary tooltips from erroring on non-string keys **[@elliotfontaine]**
- **table:** Redraw a range cell digit as soon as the bar reaches its edge **[@elliotfontaine in [#183](https://github.com/elliotfontaine/yard-godot/pull/183)]**
- **gui:** Stop leaking a submenu each time the File menu updates **[@elliotfontaine in [#182](https://github.com/elliotfontaine/yard-godot/pull/182)]**

## [1.3.1] - 2026-10-08

### Fixed

- **gui:** Stop shortcuts from triggering disabled menu actions **[@elliotfontaine]**
- **table:** Lock and gray out read-only properties **[@elliotfontaine]**
- **gui:** Stop "Can't find file" errors after changing editor scale **[@elliotfontaine]**
- **ui:** Render images and HTML paragraphs in release notes **[@elliotfontaine]**
- **ui:** Use correct "laugh" emoji in release notes reactions **[@elliotfontaine]**

## [1.3.0] - 2026-10-02

### Added

- Add a column context menu on header right-click **[@elliotfontaine in [#164](https://github.com/elliotfontaine/yard-godot/pull/164)]**
- Add update channel picker (stable/pre-release) synced with project setting **[@elliotfontaine]**
- Allow checking for and installing plugin updates from the editor **[@elliotfontaine in [#154](https://github.com/elliotfontaine/yard-godot/pull/154)]**
- Allow browsing sub-resource properties as a table **[@elliotfontaine in [#151](https://github.com/elliotfontaine/yard-godot/pull/151)]**
- Support Godot 4.4 **[@elliotfontaine in [#143](https://github.com/elliotfontaine/yard-godot/pull/143)]**
- Support Godot 4.8 (dev snapshots) **[@francoisdlt in [#123](https://github.com/elliotfontaine/yard-godot/pull/123)]**
- Make editor shortcuts configurable **[@elliotfontaine in [#127](https://github.com/elliotfontaine/yard-godot/pull/127)]**
- Add a multiline text editor to the table for `@export_multiline` properties **[@elliotfontaine in [#121](https://github.com/elliotfontaine/yard-godot/pull/121)]**
- Support `Registry.PROPERTY_HINT_CUSTOM` columns with a dropdown editor **[@elliotfontaine in [#120](https://github.com/elliotfontaine/yard-godot/pull/120)]**
- Add a bitflags editor for `@export_flags` properties **[@elliotfontaine in [#119](https://github.com/elliotfontaine/yard-godot/pull/119)]**
- Add a StringName editor to the table **[@elliotfontaine in [#116](https://github.com/elliotfontaine/yard-godot/pull/116)]**
- Add rich tooltips for color, resource, dict and array cells **[@elliotfontaine in [#109](https://github.com/elliotfontaine/yard-godot/pull/109)]**
- Allow hiding the UID and String ID columns **[@elliotfontaine in [#102](https://github.com/elliotfontaine/yard-godot/pull/102)]**
- Freeze arbitrary columns and add per-column hide/freeze menu **[@elliotfontaine in [#101](https://github.com/elliotfontaine/yard-godot/pull/101)]**
- Support undo/redo for property value edits **[@elliotfontaine in [#94](https://github.com/elliotfontaine/yard-godot/pull/94)]**
- Allow duplicating registry entries from the table view **[@elliotfontaine in [#84](https://github.com/elliotfontaine/yard-godot/pull/84)]**

### Changed

- Discard filter edits when pressing Escape **[@elliotfontaine]**
- Clicking a column header no longer sorts; use the header sort icon instead **[@elliotfontaine in [#168](https://github.com/elliotfontaine/yard-godot/pull/168)]**
- Hold Shift to scroll the registry table horizontally **[@ttencate in [#166](https://github.com/elliotfontaine/yard-godot/pull/166)]**
- Make toolbar less cluttered **[@elliotfontaine]**
- Convert pasted cell values to the target column's type **[@elliotfontaine in [#161](https://github.com/elliotfontaine/yard-godot/pull/161)]**
- Save entries to a folder picked in the Add Entry footer, no longer the FileSystem dock selection **[@elliotfontaine in [#145](https://github.com/elliotfontaine/yard-godot/pull/145)]**
- Remember Add Entry fields per registry **[@elliotfontaine in [#144](https://github.com/elliotfontaine/yard-godot/pull/144)]**
- Scan and index registries before run/export instead of on every filesystem change **[@elliotfontaine in [#141](https://github.com/elliotfontaine/yard-godot/pull/141)]**
- Improve cell text ellipsis performance **[@elliotfontaine in [#114](https://github.com/elliotfontaine/yard-godot/pull/114)]**

### Fixed

- Stop forcing an ellipsis on text cells in Godot 4.5 **[@elliotfontaine in [#176](https://github.com/elliotfontaine/yard-godot/pull/176)]**
- Stop overriding the UID of newly created registries **[@elliotfontaine in [#174](https://github.com/elliotfontaine/yard-godot/pull/174)]**
- Stop range cells from changing value on double-click **[@elliotfontaine in [#170](https://github.com/elliotfontaine/yard-godot/pull/170)]**
- Open cell popup menus under the cell instead of at the mouse **[@elliotfontaine in [#169](https://github.com/elliotfontaine/yard-godot/pull/169)]**
- Fix registry editor disappearing on Godot 4.8+ **[@ttencate in [#163](https://github.com/elliotfontaine/yard-godot/pull/163)]**
- Show columns that `Object._validate_property` hides only on some resources **[@elliotfontaine in [#156](https://github.com/elliotfontaine/yard-godot/pull/156)]**
- Allow export groups with a name prefix in registry resources **[@elliotfontaine in [#153](https://github.com/elliotfontaine/yard-godot/pull/153)]**
- Reduce progress bar contrast when using the modern editor theme **[@elliotfontaine]**
- Keep class restriction working after script file moves **[@elliotfontaine in [#138](https://github.com/elliotfontaine/yard-godot/pull/138)]**
- Repair RegistryLoadTracker and add example scene to test it **[@elliotfontaine in [#137](https://github.com/elliotfontaine/yard-godot/pull/137)]**
- Strip leading/trailing whitespace from new entry string IDs **[@elliotfontaine in [#118](https://github.com/elliotfontaine/yard-godot/pull/118)]**
- Stop row filtering from throwing an error **[@elliotfontaine in [#117](https://github.com/elliotfontaine/yard-godot/pull/117)]**
- Keep table filter state after editing a property **[@elliotfontaine in [#98](https://github.com/elliotfontaine/yard-godot/pull/98)]**

### New Contributors

- @ttencate made their first contribution in [#166](https://github.com/elliotfontaine/yard-godot/pull/166)
- @francoisdlt made their first contribution in [#123](https://github.com/elliotfontaine/yard-godot/pull/123)
- @Guihurt made their first contribution in [#134](https://github.com/elliotfontaine/yard-godot/pull/134)

## [1.2.0] - 2026-05-19

### Added

- Open subresource in inspector on cell selection **[@elliotfontaine in [#80](https://github.com/elliotfontaine/yard-godot/pull/80)]**
- Add `Registry.get_string_id_of()` for reverse resource lookup **[@elliotfontaine in [#75](https://github.com/elliotfontaine/yard-godot/pull/75)]**
- Allow adding multiple entries quickly via keyboard **[@Mar0Lard in [#69](https://github.com/elliotfontaine/yard-godot/pull/69)]**
- Support horizontal scrolling via mouse wheel in table view **[@elliotfontaine in [#55](https://github.com/elliotfontaine/yard-godot/pull/55)]**
- Add `filter()` and `where()` to Registry API, deprecate old filtering methods **[@elliotfontaine in [#50](https://github.com/elliotfontaine/yard-godot/pull/50)]**
- Add registry 'rulesets' with advanced scan features **[@skison in [#48](https://github.com/elliotfontaine/yard-godot/pull/48)]**
- Add specific error messages for add-entry failures **[@elliotfontaine]**
- Add resource thumbnail (when available) for path cells **[@elliotfontaine in [#40](https://github.com/elliotfontaine/yard-godot/pull/40)]**
- Add advanced scan options (auto, remove unlisted, regex filters) **[@elliotfontaine in [#38](https://github.com/elliotfontaine/yard-godot/pull/38)]**
- Add C# wrapper class **[@Verfeon in [#36](https://github.com/elliotfontaine/yard-godot/pull/36)]**
- Allow indexing by inner object property **[@elliotfontaine in [#29](https://github.com/elliotfontaine/yard-godot/pull/29)]**
- Add a progress bar editor to the table for range properties **[@elliotfontaine in [#26](https://github.com/elliotfontaine/yard-godot/pull/26)]**
- Add dropdown popup editor for enum cells **[@elliotfontaine in [#23](https://github.com/elliotfontaine/yard-godot/pull/23)]**

### Changed

- Warn when scan directory is set to project root (`res://`) **[@elliotfontaine in [#82](https://github.com/elliotfontaine/yard-godot/pull/82)]**
- Make `Registry.get_string_id()` idempotent **[@elliotfontaine]**
- Create resource files inline from Add Entry **[@elliotfontaine in [#66](https://github.com/elliotfontaine/yard-godot/pull/66)]**
- Improve property column ordering and add parent-first display option **[@elliotfontaine in [#53](https://github.com/elliotfontaine/yard-godot/pull/53)]**
- Show enum labels in collection cells **[@elliotfontaine in [#45](https://github.com/elliotfontaine/yard-godot/pull/45)]**
- Move Rescan button before the Reindex button in topbar **[@elliotfontaine]**
- Right-align numeric cells (int, float) **[@elliotfontaine]**
- Display resource filename in resource and collection cells **[@elliotfontaine in [#41](https://github.com/elliotfontaine/yard-godot/pull/41)]**
- Clarify unsaved resource error log with remediation steps **[@elliotfontaine in [#35](https://github.com/elliotfontaine/yard-godot/pull/35)]**
- Enhance logging format for entry property edits **[@elliotfontaine]**

### Fixed

- Allow selecting the first entry in @export_custom dropdown **[@elliotfontaine in [#74](https://github.com/elliotfontaine/yard-godot/pull/74)]**
- Refresh resource picker when class restriction changes **[@elliotfontaine in [#73](https://github.com/elliotfontaine/yard-godot/pull/73)]**
- Skip 'Remove Unlisted' when no scan directory is configured **[@elliotfontaine in [#71](https://github.com/elliotfontaine/yard-godot/pull/71)]**
- Allow deleting/reassigning entries with invalid UID **[@elliotfontaine in [#70](https://github.com/elliotfontaine/yard-godot/pull/70)]**
- Use nearest filter for pixel art textures in registry table **[@elliotfontaine in [#64](https://github.com/elliotfontaine/yard-godot/pull/64)]**
- Improve plugin UI consistency with the Godot editor **[@elliotfontaine]**
- Unlocalized cell editor strings (color picker, file dialog) due to overridden defaults **[@elliotfontaine]**
- Resource cell click failed to open quick load dialog in non-English locales due to node name translation **[@elliotfontaine]**
- Add missing i18n and l10n for registry settings input tabs **[@elliotfontaine]**
- Show more descriptive "Registry Settings" label in dialog title for non-English locales **[@elliotfontaine]**
- Contrast was too high when using "Classic" editor theme **[@elliotfontaine]**
- Progress bar rendered in wrong column with `or_less` hint **[@elliotfontaine in [#49](https://github.com/elliotfontaine/yard-godot/pull/49)]**
- Prevent res:// scan directory from being stripped to res:/ **[@elliotfontaine]**
- Use editor accent color for StringID column **[@elliotfontaine]**
- Add missing uid file for `Registry.cs` wrapper **[@elliotfontaine]**
- Missing format version in registry `.tres` files **[@elliotfontaine]**
- Don't try to use non-2D Texture resources as their own thumbnail **[@elliotfontaine]**
- Get thumbnails for filepath cells without loading the underlying resource **[@elliotfontaine]**
- Do not match partial resource paths against include filter **[@elliotfontaine]**
- Always left-align header text **[@elliotfontaine]**
- Quote string values in entry property edit logs **[@elliotfontaine]**
- Add en_US locale to prevent fallback to project's `internationalization/locale/fallback` **[@elliotfontaine in [#39](https://github.com/elliotfontaine/yard-godot/pull/39)]**
- Do not scan directory on registry selection, only on first opening **[@elliotfontaine]**
- Prevent copypasting from/to invalid cells **[@elliotfontaine]**
- Keep menu shortcuts in sync with registry state **[@elliotfontaine]**
- Pressing Enter on checkbox cell now toggles it **[@elliotfontaine]**
- Support string enums and implicit int values in enum cell rendering **[@elliotfontaine]**

### New Contributors

- @Mar0Lard made their first contribution in [#69](https://github.com/elliotfontaine/yard-godot/pull/69)
- @skison made their first contribution in [#48](https://github.com/elliotfontaine/yard-godot/pull/48)
- @Verfeon made their first contribution in [#36](https://github.com/elliotfontaine/yard-godot/pull/36)

## [1.1.0] - 2026-03-07

### Added

- **l10n:** Add Polish and Turkish translations **[@elliotfontaine]**
- **l10n:** Add French, Spanish, Brazilian Portuguese, German, Italian, Simplified Chinese and Russian translations **[@elliotfontaine]**
- Add shortcuts for `Registry Settings`, `Reindex`, and `Toggle Files Panel` **[@elliotfontaine]**
- Add custom inspector editor with enum-like dropdown for registry ids **[@elliotfontaine in [#15](https://github.com/elliotfontaine/yard-godot/pull/15)]**
- Add support for C#-defined resource scripts **[@Cer0reZ in [#4](https://github.com/elliotfontaine/yard-godot/pull/4)]**

### Changed

- Trigger cell edit on Enter key **[@elliotfontaine]**
- **i18n:** Make the editor plugin UI fully translatable **[@elliotfontaine]**
- Inform users that script paths in class restriction must be quoted **[@elliotfontaine in [#12](https://github.com/elliotfontaine/yard-godot/pull/12)]**
- Implement class restriction selection dialog **[@elliotfontaine in [#9](https://github.com/elliotfontaine/yard-godot/pull/9)]**

### Fixed

- Resolve UIDs to file paths in table path editor **[@elliotfontaine]**
- Disable 'inspect resource' item in context menu for empty resource cells **[@elliotfontaine]**
- Prevent add entry resource picker from clearing on file save **[@elliotfontaine]**
- Adapt quick load button detection for Godot 4.6 **[@elliotfontaine]**
- Preserve row or cell selection after table refresh **[@elliotfontaine]**
- Render table color editor at top level to prevent clipping **[@elliotfontaine]**
- Add 'metadata/\_custom_type_script' to disabled by default columns **[@elliotfontaine]**
- Properly load registry on creation and avoid uid cache race condition **[@elliotfontaine]**
- Keyboard shortcuts not adapting to platform (macOS vs Windows/Linux) **[@elliotfontaine in [#20](https://github.com/elliotfontaine/yard-godot/pull/20)]**
- Update resource picker base type handling for script-based class restrictions **[@elliotfontaine in [#18](https://github.com/elliotfontaine/yard-godot/pull/18)]**
- Handle script path return from popup_create_dialog in Godot 4.6 **[@elliotfontaine in [#16](https://github.com/elliotfontaine/yard-godot/pull/16)]**
- Populate line edits on file double-click, not only on "Confirm" **[@elliotfontaine in [#14](https://github.com/elliotfontaine/yard-godot/pull/14)]**

### New Contributors

- @Cer0reZ made their first contribution in [#4](https://github.com/elliotfontaine/yard-godot/pull/4)

## [1.0.1] - 2026-03-02

### Fixed

- Prevent duplicate error messages for invalid UIDs **[@elliotfontaine]**
- Properly handle path at setup for the "new registry" dialog **[@elliotfontaine]**
- Make the EditorContextMenuPlugin use our custom icon instead of the ResourcePreloader icon **[@elliotfontaine]**
- Make scrollbars offset be based on editor scale **[@elliotfontaine]**
- Drop deleted registry UIDs from history cache **[@elliotfontaine]**
- When creating a new registry, values in the "indexed properties" field were ignored **[@elliotfontaine]**
- Parent and siblings classes could be added to a registry with script path class restriction **[@elliotfontaine]**
- Handle class identity for unnamed scripts by recursively checking base scripts **[@elliotfontaine]**
- Table was hidden when searching on column yielded no result **[@elliotfontaine]**

## [1.0.0] - 2026-02-26

### Added

- Add custom project icon **[@elliotfontaine]**
- Add license file (MIT) **[@elliotfontaine]**
- Add README.md window using Markdown label support **[@elliotfontaine]**
- Add support for tracking opened registries between Godot editor sessions **[@elliotfontaine]**
- Add reindex button to topbar **[@elliotfontaine]**
- Add public method to Registry to get all indexed properties **[@elliotfontaine]**
- Allow reducing column width past text size and add text truncation for better readability **[@elliotfontaine]**
- Allow users to set indexed properties from the new/edit registry dialog **[@elliotfontaine]**
- Add a property index and add filtering methods to Registry API **[@elliotfontaine]**
- Allow (un)freezing id columns from menu **[@elliotfontaine]**
- Add floating window behavior (part 1) **[@elliotfontaine]**
- Allow copy-pasting between int and float cells, and from int/float to string cells **[@elliotfontaine]**
- Add shortcuts for Edit menu items (topbar and contextual) **[@elliotfontaine]**
- Add button to open the reference documentation for the Registry class **[@elliotfontaine]**
- Add a 'has()' to Registry API, taking either uid or string_id as parameter **[@elliotfontaine]**
- Add cut/copy/paste for cells, with dedicated cliboard **[@elliotfontaine]**
- Add support for enum cells (only view, no custom cell editor) **[@elliotfontaine]**
- Add context menu item to open selected cell resource in inspector **[@elliotfontaine]**
- Add logic to the Edit menu items **[@elliotfontaine]**
- Add entries context menu (partial implementation) **[@elliotfontaine]**
- Allow drag-and-drop of folders to the registry **[@elliotfontaine]**
- Add a bottom bar with an "Add Entry" resource picker and a button to hide the list of registries **[@elliotfontaine]**
- Allow changing an entry's UID **[@elliotfontaine]**
- Add path editor with file dialog **[@elliotfontaine]**
- Add resource editor with "Quick Load" dialog **[@elliotfontaine]**
- Allow changing Registry entries' string ids **[@elliotfontaine]**
- Allow user to toggle columns visibility **[@elliotfontaine]**
- Add Edit and Columns menu buttons, and Registry Setting button (unimplemented) **[@elliotfontaine]**
- Add custom class icon for Registry resources **[@elliotfontaine]**
- Add floating window button (unimplemented) **[@elliotfontaine]**
- Add button to report issues on github **[@elliotfontaine]**
- Add button to refresh table view **[@elliotfontaine]**
- Add custom editor for color cells **[@elliotfontaine]**
- Allow dropping mix-typed resources and only keep valid ones **[@elliotfontaine]**
- Allow dropping resources to a registry from the editor filesystem **[@elliotfontaine]**
- Add new registry dialog (skeleton) **[@elliotfontaine]**
- Add context menu item in filesystem dock, used to create a registry **[@elliotfontaine]**
- Add shortcuts matching the Script Editor ones **[@elliotfontaine]**
- **editor:** Add i18n support and French translation **[@elliotfontaine]**
- **ui:** Add dynamic table view scaffold (not yet bound to registry) **[@elliotfontaine]**
- Add barebore Registry custom resource **[@elliotfontaine]**
- Add ui skeleton **[@elliotfontaine]**

### Changed

- Improve ui preview in Registry docs **[@elliotfontaine]**
- Improve display of collections (array and dict) **[@elliotfontaine]**
- Implement "open recent" logic in file menu **[@elliotfontaine]**
- Increase grid contrast **[@elliotfontaine]**
- Implement RegistryCacheData for managing editor settings and column widths **[@elliotfontaine]**
- Improve icon design **[@elliotfontaine]**
- Better resolve registry icon in itemlist **[@elliotfontaine]**
- Use custom icon for plugin, use DPITexture for all icons **[@elliotfontaine]**
- **tweak:** Make horizontal scroll stop before frozen columns **[@elliotfontaine]**
- Freeze first 2 columns (String ID and UID) **[@elliotfontaine]**
- Show confirmation dialog when the new class restriction would exclude entries from the registry **[@elliotfontaine]**
- Improve context-based toggle of Edit menu items **[@elliotfontaine]**
- Show tip about drag and dropping resources **[@elliotfontaine]**
- **tweak:** Vertical slider does not overlap with table header **[@elliotfontaine]**
- Show class restriction icon in registries list **[@elliotfontaine]**
- Implement directory scan **[@elliotfontaine]**
- Update Add Entry resource picker when class restriction is changed **[@elliotfontaine]**
- Improve context-based disabling of File menu items **[@elliotfontaine]**
- Create new registry using filesystem context menu, at current directory **[@elliotfontaine]**
- Handle pan gesture **[@elliotfontaine]**
- Show previews and show rows based on scroll after refresh **[@elliotfontaine]**
- Ensure selected cell can be seen **[@elliotfontaine]**
- **ui:** Properly show selected cell **[@elliotfontaine]**
- **tweak:** Make the row selection overlay less bright **[@elliotfontaine]**
- Display invalid uids in red when viewing registry **[@elliotfontaine]**
- Make the first 2 columns more distinct visually **[@elliotfontaine]**
- Describe runtime API for Registry **[@elliotfontaine]**
- Implement 'Registry Settings' dialog (recycle 'New Registry' dialog) **[@elliotfontaine]**
- Display class icon in New Registry dialog **[@elliotfontaine]**
- Implement new registry dialog logic **[@elliotfontaine]**
- Sync table entries to their real resource counterparts **[@elliotfontaine]**
- Show preview (rather than a stringified value) for resource and color properties **[@elliotfontaine]**
- Display registry entries content (as string) **[@elliotfontaine]**
- Implement most menu options for the registry list **[@elliotfontaine]**
- Unify registries list UX with Godot open scripts list **[@elliotfontaine]**
- Make DynamicTable follow the Godot editor theme **[@elliotfontaine]**
- Make YARD a main screen plugin **[@elliotfontaine]**

### Fixed

- Last column could not be resized **[@elliotfontaine]**
- Ignore unused variable warning for Registry version tag **[@elliotfontaine]**
- Update editor_icon_button external resource uid in dependant scene files **[@elliotfontaine]**
- Reimport icons on editor scale change **[@elliotfontaine]**
- Scrolling to last columns not working after toggling visibility or disabling id column freeze **[@elliotfontaine]**
- Refactor sort logic to suppress errors when ordering resources **[@elliotfontaine]**
- Use correct key mask (ctrl/cmd) on Windows for cut, copy, etc **[@elliotfontaine]**
- Do not draw table if data is empty, even if there are columns **[@elliotfontaine]**
- Hide "make floating" button since it's unimplemented **[@elliotfontaine]**
- Make path editor for DynamicTable more reliable **[@elliotfontaine]**
- Improve path logic for "new registry" file dialogs **[@elliotfontaine]**
- Increase icon size in header **[@elliotfontaine]**
- Fix HTML header in readme **[@elliotfontaine]**
- Specify dictionary inner types for criteria parameter in `filter_by_values` function **[@elliotfontaine]**
- Don't draw cell content behind scrollbar **[@elliotfontaine]**
- Convert icon colors with editor theme **[@elliotfontaine]**
- Actually, use Texture2D for icons, with `scale_with_editor_scale` set to true **[@elliotfontaine]**
- Allow multiple types for resource editor (ResourcePicker), for exemple BaseMaterial3D & ShaderMaterial for PrimitiveMesh.material **[@elliotfontaine]**
- Stop v-separator between frozen columns and remaining ones at last row **[@elliotfontaine]**
- Do not run `_restore_selected_rows()` inside custom sort functions **[@elliotfontaine]**
- Make non-string cells editable again **[@elliotfontaine]**
- Make topbar buttons unfocusable **[@elliotfontaine]**
- Keep drag-and-drop info panel visible for empty registries when drag begin **[@elliotfontaine]**
- Disable broken "Progress" cells for now **[@elliotfontaine]**
- **ui:** Properly render mixed-class registries in table **[@elliotfontaine]**
- Do not reset scrollbars on refresh **[@elliotfontaine]**
- Pan gesture now reset accumulation when switching direction **[@elliotfontaine]**
- Handle minimal column width better **[@elliotfontaine]**
- Ensure last row is fully visible when vertical slider is at the bottom **[@elliotfontaine]**
- Move back scroller to minimum value when it disappear **[@elliotfontaine]**
- **ui:** Clarify visual difference between empty resource cells and invalid rows **[@elliotfontaine]**
- Update displayed registry size when adding/removing entries **[@elliotfontaine]**
- Make scan follow the "Recursive" registry setting **[@elliotfontaine]**
- Correctly save registry on edition **[@elliotfontaine]**
- Fix drag and drog **[@elliotfontaine]**
- Fix uid cache error when creating a new registry **[@elliotfontaine]**
- Center text better within cells **[@elliotfontaine]**
- **ui:** Fix behavior of the Registries List — Registry View horizontal split **[@elliotfontaine]**
- Properly read file extension in new registry dialog **[@elliotfontaine]**
- Add missing logic for the Save button in the Edit Registry dialog **[@elliotfontaine]**
- Do not draw header background if there are no columns **[@elliotfontaine]**
- Stop trying to save changes on virtual cell [-1, -1] **[@elliotfontaine]**
- Error when clicking outside row range **[@elliotfontaine]**
- Fix error when trying to drop resources without any registry in view **[@elliotfontaine]**
- Reset column widths when switching edited registry **[@elliotfontaine]**
- Order StringNames alphanumerically rather than by pointer's location **[@elliotfontaine]**
- Class restriction now works with built-in Resources **[@elliotfontaine]**
- Avoid out-of-bounds errors when reopening closed resources **[@elliotfontaine]**

### Removed

- Remove useless menu items about "saving" registries **[@elliotfontaine]**

### New Contributors

- @elliotfontaine made their first contribution

[1.3.2]: https://github.com/elliotfontaine/yard-godot/compare/v1.3.1...v1.3.2
[1.3.1]: https://github.com/elliotfontaine/yard-godot/compare/v1.3.0...v1.3.1
[1.3.0]: https://github.com/elliotfontaine/yard-godot/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/elliotfontaine/yard-godot/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/elliotfontaine/yard-godot/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/elliotfontaine/yard-godot/compare/v1.0.0...v1.0.1

<!-- generated by git-cliff -->
