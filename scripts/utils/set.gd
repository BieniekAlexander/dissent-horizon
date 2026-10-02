class_name Set
extends Resource

#region Properties
# Provides amortized O(1) adding, removing, and presence-checking.
var hash_set: Dictionary
const DUMMY_VALUE = null
#endregion


#region Lifecycle
func _init(a_values: Array = []) -> void:
	hash_set = Dictionary()

	if !a_values.is_empty():
		add_all(a_values)


#endregion


#region Public API
func add_all(a_elements) -> Set:
	for element in a_elements:
		add(element)

	return self


func add(a_element) -> Set:
	hash_set[a_element] = DUMMY_VALUE
	return self


func remove(a_element) -> Set:
	hash_set.erase(a_element)
	return self


func remove_all(a_elements) -> Set:
	for element in a_elements:
		remove(element)

	return self


func clear() -> Set:
	hash_set.clear()
	return self


func filter(a_condition: Callable) -> Set:
	var new_hash_set: Dictionary = {}

	for element in hash_set.keys():
		if a_condition.call(element):
			new_hash_set[element] = DUMMY_VALUE

	return Set.new(new_hash_set.keys())


func map(a_function: Callable) -> Set:
	var new_hash_set: Dictionary = {}
	for element in hash_set.keys():
		new_hash_set[a_function.call(element)] = DUMMY_VALUE

	return Set.new(new_hash_set.keys())


func reduce(a_function: Callable, a_default: Variant) -> Variant:
	if hash_set.size() == 0:
		return a_default

	var result: Variant = hash_set.keys()[0]
	for val in hash_set.keys().slice(1):
		result = a_function.call(result, val)

	return result


func contains(a_element) -> bool:
	return hash_set.has(a_element)


func get_values() -> Array:
	return hash_set.keys()


func is_empty() -> bool:
	return hash_set.is_empty()


func size() -> int:
	return hash_set.keys().size()


#endregion

#region Constants
static var EMPTY: Set = Set.new([])
#endregion
