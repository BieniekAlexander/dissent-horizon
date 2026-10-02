class_name AU


#region Public API
static func comp_value(a, b) -> bool:
	return a["value"] < b["value"]


static func sort_on_key(key: Callable, array: Array) -> Array:
	var arr_keyed = array.map(func(a): return {"item": a, "value": key.call(a)})
	arr_keyed.sort_custom(comp_value)
	return arr_keyed.map(func(a): return a["item"])


## push into an array as a priority queue, returning the index at which it was inserted
static func priority_queue_push(key: Callable, item: Variant, queue: Array) -> int:
	# O(n) implementation because I'm lazy
	var item_key: Variant = key.call(item)

	for i in range(0, queue.size()):
		if item_key < key.call(queue[i]):
			queue.insert(i, item)
			return i

	queue.append(item)
	return queue.size() - 1


static func concat(a1: Array, a2: Array) -> Array:
	var ret: Array = a1.duplicate()

	for item in a2:
		ret.append(item)

	return ret


static func all(a1: Array, check: Callable) -> bool:
	for a in a1:
		if not check.call(a):
			return false

	return true


static func any(a1: Array, check: Callable) -> bool:
	for a in a1:
		if check.call(a):
			return true

	return false


static func sum(array: Array) -> float:
	var ret: float = 0

	for a in array:
		ret += a

	return ret


static func median(array: Array) -> float:
	# TODO write a faster implementation of this
	var array_sorted: Array = array.duplicate()
	array_sorted.sort()

	if array_sorted.size() % 2 == 1:
		return array_sorted[array_sorted.size() / 2]
	else:
		return (array_sorted[array_sorted.size() / 2] + array_sorted[array_sorted.size() / 2]) / 2.0


static func mean(array: Array) -> float:
	return AU.sum(array) * 1.0 / array.size()
#endregion
