package hrt.prefab2;

class Resource extends hxd.res.Resource {

	var prefab : Prefab;
	var cacheVersion : Int;

	override function watch( onChanged: Null<Void -> Void> ) {
		if( entry == null )
			return;
		if( onChanged == null ) {
			super.watch(null);
			return;
		}
		super.watch(function() {
			if( prefab != null ) {
				var data = try loadData() catch( e : Dynamic ) return; // parsing error (conflict ?)
				// TODO(ces) : Handle Reloading ?
                //prefab.reload(data);
				onPrefabLoaded(prefab);
			}
			onChanged();
		});
	}

	function loadData() {
		var isBSON = entry.fetchBytes(0,1).get(0) == 'H'.code;
		return isBSON ? new hxd.fmt.hbson.Reader(entry.getBytes(),false).read() : haxe.Json.parse(entry.getText());
	}

	public function load() : Prefab {
		if( prefab != null && cacheVersion == CACHE_VERSION )
			return prefab;
		var data = loadData();
        prefab = Prefab.createFromDynamic(data);
		prefab.proto = new ProtoPrefab(prefab, entry.path);
		cacheVersion = CACHE_VERSION;
		onPrefabLoaded(prefab);
		watch(function() {}); // auto lib reload
		return prefab;
	}

	public static function make( p : Prefab ) {
		if( p == null ) throw "assert";
		var r = new Resource(null);
		r.prefab = p;
		return r;
	}

	public static var CACHE_VERSION = 0;
	public static dynamic function onPrefabLoaded(p:Prefab) {
	}

}