class_name FU

#region Public API
static func default_evaluate(callables: Array[Callable]) -> Callable:
	# Takes in an array of `Callable`s, and returns the first non-null result from each of their evaluations, or null otherwise
	var ret = func(c, t):
		for callable: Callable in callables:
			var candidate: Variant = callable.call(c, t)
			if candidate!=null: return candidate

		return null

	return ret
#endregion
