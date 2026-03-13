using Godot;
using Godot.Collections;

namespace YARD;


/// <summary>
/// A registry associating resources with stable, human-readable string IDs.
/// <para><c>Registry{TResource}</c> lets you reference resources by stable string IDs
/// (e.g. <c>"enemy_skeleton"</c>) instead of file paths, which can silently change when assets are moved.
/// It provides a bidirectional map between string IDs and UIDs, and helpers to resolve and load
/// entries individually or in bulk (synchronously or via threaded loading).</para>
/// <para>It also offers an optional property index for querying entries (resources) by their
/// properties at runtime, without loading them. Since the property index is baked into
/// the registry at editor time, querying is fast.</para>
/// <para>Example usage in C#:</para>
/// <code>
/// Registry&lt;Enemy&gt; ENEMIES = new Registry&lt;Enemy&gt;(&quot;res://data/enemy_registry.tres&quot;);
/// var WeaponsResource = ResourceLoader.Load&lt;Resource&gt;(&quot;res://data/weapon_registry.tres&quot;);
/// Registry&lt;Weapon&gt; WEAPONS = new Registry&lt;Weapon&gt;(WeaponsResource);
/// 
/// Enemy skeleton = ENEMIES.LoadEntry(&quot;skeleton&quot;);
/// sprite.Texture = skeleton.CreatureSprite;
/// var legendaryWeapons = WEAPONS.FilterByValue(&quot;rarity&quot;, Rarity.LEGENDARY);
/// </code>
/// <para>Registries and their entries are read-only at runtime and must be managed through
/// the dedicated editor tab.</para>
/// <para>See also:</para>
/// <list type="bullet">
///   <item><description><see cref="Godot.Resource"/> - Base class for serializable objects.</description></item>
///   <item><description><see cref="Godot.ResourceLoader"/> - A singleton for loading resource files.</description></item>
/// </list>
/// </summary>
/// <typeparam name="TResource">The type of Resource contained in the Registry.</typeparam>
public class Registry<[MustBeVariant] TResource> where TResource : Resource
{
	private readonly Resource _registry;

	/// <summary>
	/// Constructs a Registry wrapper from a resource path.
	/// Loads the Registry resource at the given path.
	/// </summary>
	/// <param name="path">Path to the Registry resource.</param>
	public Registry(string path)
	{
		_registry = ResourceLoader.Load<Resource>(path);
		if (_registry == null)
		{
			GD.PushError($"Registry not found: {path}");
		}
	}

	/// <summary>
	/// Constructs a Registry wrapper from an existing Registry resource instance.
	/// </summary>
	/// <param name="registry">Registry resource instance.</param>
	public Registry(Resource registry)
	{
		_registry = registry;
	}

	// -----------------------------
	// Lookup
	// -----------------------------

	/// <summary>
	/// Returns true if the given id exists in the registry.
	/// The id may be either a string ID (e.g. "enemy_skeleton") or a UID (e.g. "uid://dqtv77mng5dyh").
	/// </summary>
	/// <param name="id">String ID or UID to check.</param>
	public bool Has(StringName id) => _registry.Call("has", id).AsBool();

	/// <summary>
	/// Returns true if the given string ID is present in the registry.
	/// </summary>
	/// <param name="id">String ID to check.</param>
	public bool HasStringId(StringName id) => _registry.Call("has_string_id", id).AsBool();

	/// <summary>
	/// Returns true if the given UID is present in the registry.
	/// The UID must start with "uid://".
	/// </summary>
	/// <param name="id">UID to check.</param>
	public bool HasUid(StringName id) => _registry.Call("has_uid", id).AsBool();

	/// <summary>
	/// Resolves any identifier (string ID or UID) to its canonical UID form.
	/// If id is already a registered UID, it is returned unchanged.
	/// If id is a registered string ID, returns the corresponding UID.
	/// Returns an empty StringName when id cannot be resolved.
	/// </summary>
	/// <param name="id">String ID or UID to resolve.</param>
	public StringName GetUid(StringName id) => _registry.Call("get_uid", id).AsStringName();

	/// <summary>
	/// Returns the string ID associated with the given UID.
	/// Returns an empty StringName if uid is not found in the registry.
	/// </summary>
	/// <param name="uid">UID to resolve.</param>
	public StringName GetStringId(StringName uid) => _registry.Call("get_string_id", uid).AsStringName();

	/// <summary>
	/// Returns an Array of all registered string IDs.
	/// </summary>
	public Array<StringName> GetAllStringIds() => (Array<StringName>) _registry.Call("get_all_string_ids");

	/// <summary>
	/// Returns an Array of all registered UIDs.
	/// Each entry is a StringName in the form "uid://...".
	/// </summary>
	public Array<StringName> GetAllUids() => (Array<StringName>) _registry.Call("get_all_uids");

	/// <summary>
	/// Returns an Array of all property names that have been baked into the property index.
	/// <para>Each entry in the returned array is a <c>StringName</c> corresponding to a property key that can be queried using 
	/// <c>Registry.filter_by</c>, <c>Registry.filter_by_value</c>, or <c>Registry.filter_by_values</c></para>
	/// <para>Use this method to inspect which properties are available for fast lookup at runtime, without loading the underlying resources.</para>
	/// </summary>
	public Array<StringName> GetIndexedProperties() => (Array<StringName>) _registry.Call("get_indexed_properties");

	/// <summary>
	/// Returns the number of entries in the registry. Empty registries always return 0.
	/// See also IsEmpty.
	/// </summary>
	public int Size() => (int) _registry.Call("size");
	
	/// <summary>
	/// Returns true if the registry contains no entries.
	/// See also Size.
	/// </summary>
	public bool IsEmpty() => _registry.Call("is_empty").AsBool();

	// -----------------------------
	// Loading
	// -----------------------------

	/// <summary>
	/// Loads the resource associated with id (string ID or UID) and returns it.
	/// Returns null if the entry does not exist or cannot be loaded.
	/// typeHint and cacheMode are passed down to ResourceLoader.Load.
	/// </summary>
	/// <param name="id">String ID or UID to load.</param>
	/// <param name="typeHint">Optional type hint for ResourceLoader.</param>
	/// <param name="cacheMode">ResourceLoader cache mode.</param>
	public TResource LoadEntry(StringName id, string typeHint = "", ResourceLoader.CacheMode cacheMode = ResourceLoader.CacheMode.Reuse)
	{
		return _registry.Call("load_entry", id, typeHint, (int)cacheMode).As<TResource>();
	}

	/// <summary>
	/// Loads all registered resources in a blocking manner.
	/// <para>Returns a dictionary mapping string IDs to their loaded <c>Resource</c> instances.</para>
	/// <para>Missing or invalid entries are skipped.</para>
	/// <para><paramref name="typeHint"/> and <paramref name="cacheMode"/> are passed down to <see cref="ResourceLoader.Load"/>.</para>
	/// </summary>
	/// <param name="typeHint">Optional type hint for ResourceLoader.</param>
	/// <param name="cacheMode">ResourceLoader cache mode.</param>
	public Dictionary<StringName, TResource> LoadAllBlocking(string typeHint = "", ResourceLoader.CacheMode cacheMode = ResourceLoader.CacheMode.Reuse)
	{
		var rawDict = (Dictionary<StringName, Resource>)_registry.Call("load_all_blocking", typeHint, (int)cacheMode);
		var typedDict = new Dictionary<StringName, TResource>();
		foreach (var key in rawDict.Keys)
		{
			typedDict[key] = (TResource) rawDict[key];
		}
		return typedDict;
	}

	/// <summary>
	/// Requests threaded loading for all entries and returns a <see cref="RegistryLoadTracker"/>.
	/// <para>The returned tracker can be used to monitor progress, inspect statuses,
	/// and retrieve loaded resources as they become available.</para>
	/// <para>See also <see cref="ResourceLoader.LoadThreadedRequest"/>.</para>
	/// </summary>
	/// <param name="typeHint">Optional type hint for ResourceLoader.</param>
	/// <param name="useSubThreads">Whether to use sub-threads for loading.</param>
	/// <param name="cacheMode">ResourceLoader cache mode.</param>
	public RegistryLoadTracker LoadAllThreadedRequest(string typeHint = "", bool useSubThreads = false, ResourceLoader.CacheMode cacheMode = ResourceLoader.CacheMode.Reuse)
	{
		var tracker = (GodotObject) _registry.Call("load_all_threaded_request", typeHint, useSubThreads, (int)cacheMode);
		return new RegistryLoadTracker(tracker);
	}

	// -----------------------------
	// Filtering
	// -----------------------------

	/// <summary>
	/// Returns the string IDs of all entries whose property equals <paramref name="value"/>.
	/// <para>Requires the property index to have been baked for <paramref name="property"/>.</para>
	/// <para>Returns an empty array if the property is not indexed or no entry has that value.</para>
	/// </summary>
	/// <param name="property">Property name to filter by.</param>
	/// <param name="value">Value to match.</param>
	public Array<StringName> FilterByValue(StringName property, Variant value) => (Array<StringName>) _registry.Call("filter_by_value", property, value);

	/// <summary>
	/// Returns the string IDs of all entries whose property satisfies <paramref name="predicate"/>.
	/// <para>Predicate receives the property value and must return a bool.</para>
	/// <para>Requires the property index to have been baked for <paramref name="property"/>.</para>
	/// <para>Returns an empty array if the property is not indexed or no value matches the predicate.</para>
	/// </summary>
	/// <param name="property">Property name to filter by.</param>
	/// <param name="predicate">Predicate to apply to property values.</param>
	public Array<StringName> FilterBy(StringName property, Callable predicate) => (Array<StringName>) _registry.Call("filter_by", property, predicate);

	/// <summary>
	/// Returns the string IDs of all entries matching all criteria (AND logic).
	/// <para><paramref name="criteria"/> is a <c>Dictionary</c> mapping property names to their expected values.</para>
	/// <para>Requires the property index to have been baked for each property.</para>
	/// <para>Returns an empty array if any property is not indexed or if the intersection yields no results.</para>
	/// </summary>
	/// <param name="criteria">Dictionary of property names and expected values.</param>
	public Array<StringName> FilterByValues(Dictionary<StringName, Variant> criteria) => (Array<StringName>) _registry.Call("filter_by_values", criteria);

	/// <summary>
	/// Returns true if <paramref name="property"/> has been baked into the property index.
	/// <para>Use this to guard calls to <see cref="FilterByValue"/>, <see cref="FilterBy"/>, and <see cref="FilterByValues"/>
	/// when indexing of a given property is not guaranteed.</para>
	/// </summary>
	/// <param name="property">Property name to check.</param>
	public bool IsPropertyIndexed(StringName property) => _registry.Call("is_property_indexed", property).AsBool();
	
	// -----------------------------
	// Wrapper for RegistryLoadTracker
	// -----------------------------

	/// <summary>
	/// Loading tracker used with <see cref="Registry.LoadAllThreadedRequest"/>.
	/// Provides information about asynchronous resource loading.
	/// All its <c>Dictionary</c> properties use resource String IDs as keys:
	/// <list type="bullet">
	///   <item><description><c>Progress</c> is the overall load progress (0.0–1.0).</description></item>
	///   <item><description><c>Status</c> matches an entry string ID to its current <c>ResourceLoader.ThreadLoadStatus</c>.</description></item>
	///   <item><description><c>Resources</c> holds loaded <c>Resource</c> objects as they become ready.</description></item>
	///   <item><description><c>Uids</c> matches an entry string ID to its UID.</description></item>
	///   <item><description><c>Requested</c> tells if the entry was successfully requested through <c>ResourceLoader.LoadThreadedRequest</c>.</description></item>
	/// </list>
	/// Note: Accessors automatically poll and update internal loading states before returning.
	/// </summary>
	public class RegistryLoadTracker
	{
		private readonly GodotObject _tracker;

		public RegistryLoadTracker(GodotObject tracker)
		{
			_tracker = tracker;
		}

		public float Progress => (float)_tracker.Get("progress");

		public Dictionary<StringName, TResource> GetLoadedResources()
		{
			var rawResources = (Dictionary<StringName, Resource>)_tracker.Get("resources");
			var typedResources = new Dictionary<StringName, TResource>();
			foreach (var key in rawResources.Keys)
			{
				if (rawResources[key] != null)
				{
					typedResources[key] = (TResource)rawResources[key];
				}
			}
			return typedResources;
		}

		public Dictionary<StringName, bool> Requested => (Dictionary<StringName, bool>) _tracker.Get("requested");

		public Dictionary<StringName, ResourceLoader.ThreadLoadStatus> Status => (Dictionary<StringName, ResourceLoader.ThreadLoadStatus>)_tracker.Get("status");
	}
}
