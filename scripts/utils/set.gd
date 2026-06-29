class_name Set
extends Resource

#region Properties
# Provides amortized O(1) adding, removing, and presence-checking.
var hash_set: Dictionary
const DUMMY_VALUE = null
#endregion

#region Lifecycle
func _init(values: Array = []) -> void:
	hash_set = Dictionary()

	if !values.is_empty():
		add_all(values)
#endregion

#region Public API
func add_all(elements) -> Set:
	for element in elements:
		add(element)

	return self

func add(element) -> Set:
	hash_set[element] = DUMMY_VALUE
	return self

func remove(element) -> Set:
	hash_set.erase(element)
	return self

func remove_all(elements) -> Set:
	for element in elements:
		remove(element)

	return self

func clear()  -> Set:
	hash_set.clear()
	return self

func filter(condition: Callable) -> Set:
	var new_hash_set: Dictionary = {}

	for element in hash_set.keys():
		if condition.call(element):
			new_hash_set[element] = DUMMY_VALUE

	return Set.new(new_hash_set.keys())

func map(function: Callable) -> Set:
	var new_hash_set: Dictionary = {}
	for element in hash_set.keys():
		new_hash_set[function.call(element)] = DUMMY_VALUE

	return Set.new(new_hash_set.keys())

func reduce(function: Callable, default: Variant) -> Variant:
	if hash_set.size()==0: return default

	var result: Variant = hash_set.keys()[0]
	for val in hash_set.keys().slice(1):
		result = function.call(result, val)

	return result

func contains(element) -> bool:
	return hash_set.has(element)

func get_values() -> Array:
	return hash_set.keys()

func is_empty() -> bool:
	return hash_set.is_empty()

func size() -> int:
	return hash_set.keys().size()
#endregion

#region Constants
static var Empty: Set = Set.new([])
#endregion
