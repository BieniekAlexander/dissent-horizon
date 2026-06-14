class_name FSU

#region Public API
static func get_data_from_csv_file(path: String) -> Array:
	return Array(
		FileAccess.open(
			path,
			FileAccess.READ
		).get_as_text().split("\n")
	).filter(
		func(line): return line!=""
	).map(
		func(line): return line.split(",")
	)

static func get_data_from_json_file(path: String) -> Variant:
	return JSON.parse_string(
		FileAccess.open(
			path,
			FileAccess.READ
		).get_as_text()
	)
#endregion
