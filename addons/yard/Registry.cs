using Godot;
using Godot.Collections;

namespace YARD;

/// <summary>
/// Wrapper for a YARD Registry for a specific resource type TResource.
/// See "registry.gd" for more info.
/// </summary>
/// <typeparam name="TResource">The type of Resource contained in the Registry.</typeparam>
public class Registry<[MustBeVariant] TResource> where TResource : Resource
{
	private readonly Resource _registry;

	public Registry(string path)
	{
		_registry = ResourceLoader.Load<Resource>(path);
		if (_registry == null)
		{
			GD.PushError($"Registry not found: {path}");
		}
	}

	public Registry(Resource registry)
	{
		_registry = registry;
	}

	// -----------------------------
	// Lookup
	// -----------------------------
	public bool Has(StringName id) => _registry.Call("has", id).AsBool();
	public bool HasStringId(StringName id) => _registry.Call("has_string_id", id).AsBool();
	public bool HasUid(StringName id) => _registry.Call("has_uid", id).AsBool();
	public StringName GetUid(StringName id) => _registry.Call("get_uid", id).AsStringName();
	public StringName GetStringId(StringName uid) => _registry.Call("get_string_id", uid).AsStringName();
	public Array<StringName> GetAllStringIds() => (Array<StringName>) _registry.Call("get_all_string_ids");
	public Array<StringName> GetAllUids() => (Array<StringName>) _registry.Call("get_all_uids");
	public int Size() => (int) _registry.Call("size");
	public bool IsEmpty() => _registry.Call("is_empty").AsBool();

	// -----------------------------
	// Loading
	// -----------------------------
	public TResource LoadEntry(StringName id, string typeHint = "", ResourceLoader.CacheMode cacheMode = ResourceLoader.CacheMode.Reuse)
	{
		return _registry.Call("load_entry", id, typeHint, (int)cacheMode).As<TResource>();
	}

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
	
	public RegistryLoadTracker LoadAllThreadedRequest(string typeHint = "", bool useSubThreads = false, ResourceLoader.CacheMode cacheMode = ResourceLoader.CacheMode.Reuse)
	{
		var tracker = (GodotObject) _registry.Call("load_all_threaded_request", typeHint, useSubThreads, (int)cacheMode);
		return new RegistryLoadTracker(tracker);
	}

	// -----------------------------
	// Filtering
	// -----------------------------
	public Array<StringName> FilterByValue(StringName property, Variant value) => (Array<StringName>) _registry.Call("filter_by_value", property, value);

	public Array<StringName> FilterBy(StringName property, Callable predicate) => (Array<StringName>) _registry.Call("filter_by", property, predicate);

	public Array<StringName> FilterByValues(Dictionary<StringName, Variant> criteria) => (Array<StringName>) _registry.Call("filter_by_values", criteria);

	public bool IsPropertyIndexed(StringName property) => _registry.Call("is_property_indexed", property).AsBool();
	
	// -----------------------------
	// Wrapper for RegistryLoadTracker
	// -----------------------------
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
