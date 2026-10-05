class_name GeneratedMapCache
extends RefCounted
## Generated maps for map-generation tests that ask different questions of the SAME few maps.
## One generation is seconds of work, so each (parameter set, seed) is generated once per test
## file and every test after the first reads it back. Hold one in a `static var` per test file.
##
## A determinism test must NOT use this: comparing a cached map with itself proves nothing.
## A test must not mutate a map it gets from here, since the next test reads the same object.

var _maps: Dictionary[String, GeneratedMap] = {}


## The map [param a_params_of] makes at [param a_seed]. [param a_variant] names that parameter
## set and is the cache key, so two different parameter sets in one file need two names.
func generated(a_variant: StringName, a_params_of: Callable, a_seed: int) -> GeneratedMap:
	var key: String = "%s/%d" % [a_variant, a_seed]
	if not _maps.has(key):
		_maps[key] = MapGenerator.generate(a_params_of.call(), a_seed)
	return _maps[key]
