# Adapted for Godot 4.7 from godot_excel_reader by johnnash2017 (MIT).
class_name ExcelReader47
extends RefCounted


class ExcelCell:
	extends RefCounted

	var reference: String = ""
	var row: int = 0
	var column: int = 0
	var cell_type: String = ""
	var value: Variant = null
	var formula: String = ""


class ExcelSheet:
	extends RefCounted

	var name: String = ""
	var normalized_name: String = ""
	var max_row: int = 0
	var max_column: int = 0
	var _rows: Dictionary = {}

	func _init(sheet_name: String = "") -> void:
		name = sheet_name
		normalized_name = sheet_name.strip_edges().to_lower()

	func add_cell(cell: ExcelCell) -> void:
		var row_cells: Dictionary = _rows.get(cell.row, {})
		row_cells[cell.column] = cell
		_rows[cell.row] = row_cells
		max_row = maxi(max_row, cell.row)
		max_column = maxi(max_column, cell.column)

	func get_cell(row: int, column: int) -> ExcelCell:
		var row_cells: Dictionary = _rows.get(row, {})
		var cell_value: Variant = row_cells.get(column)
		return cell_value as ExcelCell

	func get_value(row: int, column: int, default_value: Variant = null) -> Variant:
		var cell: ExcelCell = get_cell(row, column)
		return default_value if cell == null else cell.value

	# 按指定表头行生成记录，供不同项目的业务适配器按列名读取。
	func to_records(header_row: int = 1, first_data_row: int = 2) -> Array[Dictionary]:
		var headers: Dictionary = {}
		for column: int in range(1, max_column + 1):
			var header: String = String(get_value(header_row, column, "")).strip_edges()
			if not header.is_empty():
				headers[column] = header
		var records: Array[Dictionary] = []
		for row: int in range(first_data_row, max_row + 1):
			var record: Dictionary = {}
			var has_value: bool = false
			for column_value: Variant in headers.keys():
				var column: int = int(column_value)
				var value: Variant = get_value(row, column, "")
				record[String(headers[column])] = value
				if value != null and not String(value).strip_edges().is_empty():
					has_value = true
			if has_value:
				records.append(record)
		return records


class ExcelWorkbook:
	extends RefCounted

	var sheets: Array[ExcelSheet] = []

	func get_sheet_names() -> PackedStringArray:
		var names: PackedStringArray = []
		for sheet: ExcelSheet in sheets:
			names.append(sheet.name)
		return names

	func get_sheet_by_name(sheet_name: String) -> ExcelSheet:
		var normalized: String = sheet_name.strip_edges().to_lower()
		for sheet: ExcelSheet in sheets:
			if sheet.normalized_name == normalized:
				return sheet
		return null


class ReadResult:
	extends RefCounted

	var workbook: ExcelWorkbook
	var error_code: Error = OK
	var error_message: String = ""

	func is_ok() -> bool:
		return error_code == OK and workbook != null


# 读取工作簿；只使用 Excel 已保存的值，不在 Godot 中计算公式。
static func read(path: String) -> ReadResult:
	var result: ReadResult = ReadResult.new()
	if not FileAccess.file_exists(path):
		return _fail(result, ERR_FILE_NOT_FOUND, "Excel 文件不存在: %s" % path)
	var zip: ZIPReader = ZIPReader.new()
	var open_error: Error = zip.open(path)
	if open_error != OK:
		return _fail(result, open_error, "Excel ZIP 打开失败: %s" % path)
	var shared_strings: PackedStringArray = _load_shared_strings(zip)
	var relations: Dictionary = _parse_workbook_relations(zip)
	var workbook: ExcelWorkbook = _parse_workbook(zip, relations, shared_strings)
	zip.close()
	if workbook.sheets.is_empty():
		return _fail(result, ERR_FILE_CORRUPT, "Excel 未包含可读取的工作表: %s" % path)
	result.workbook = workbook
	return result


static func _fail(result: ReadResult, error_code: Error, message: String) -> ReadResult:
	result.error_code = error_code
	result.error_message = message
	return result


static func _load_shared_strings(zip: ZIPReader) -> PackedStringArray:
	var strings: PackedStringArray = []
	const SHARED_STRINGS_PATH: String = "xl/sharedStrings.xml"
	if not zip.file_exists(SHARED_STRINGS_PATH):
		return strings
	var parser: XMLParser = XMLParser.new()
	if parser.open_buffer(zip.read_file(SHARED_STRINGS_PATH)) != OK:
		return strings
	var current_string: String = ""
	var in_string_item: bool = false
	var in_text: bool = false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name: String = parser.get_node_name().to_lower()
				if node_name == "si":
					in_string_item = true
					current_string = ""
				elif node_name == "t" and in_string_item:
					in_text = true
			XMLParser.NODE_TEXT:
				if in_text:
					current_string += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var node_name: String = parser.get_node_name().to_lower()
				if node_name == "t":
					in_text = false
				elif node_name == "si":
					strings.append(current_string)
					in_string_item = false
	return strings


static func _parse_workbook_relations(zip: ZIPReader) -> Dictionary:
	var relations: Dictionary = {}
	const RELATIONS_PATH: String = "xl/_rels/workbook.xml.rels"
	if not zip.file_exists(RELATIONS_PATH):
		return relations
	var parser: XMLParser = XMLParser.new()
	if parser.open_buffer(zip.read_file(RELATIONS_PATH)) != OK:
		return relations
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name().to_lower() != "relationship":
			continue
		var relation_type: String = _attribute(parser, "type").to_lower()
		if not relation_type.ends_with("/worksheet"):
			continue
		var relation_id: String = _attribute(parser, "id")
		var target: String = _normalize_workbook_target(_attribute(parser, "target"))
		if not relation_id.is_empty() and not target.is_empty():
			relations[relation_id] = target
	return relations


static func _parse_workbook(
	zip: ZIPReader,
	relations: Dictionary,
	shared_strings: PackedStringArray
) -> ExcelWorkbook:
	var workbook: ExcelWorkbook = ExcelWorkbook.new()
	const WORKBOOK_PATH: String = "xl/workbook.xml"
	if not zip.file_exists(WORKBOOK_PATH):
		return workbook
	var parser: XMLParser = XMLParser.new()
	if parser.open_buffer(zip.read_file(WORKBOOK_PATH)) != OK:
		return workbook
	while parser.read() == OK:
		if parser.get_node_type() != XMLParser.NODE_ELEMENT:
			continue
		if parser.get_node_name().to_lower() != "sheet":
			continue
		var sheet_name: String = _attribute(parser, "name")
		var relation_id: String = _attribute(parser, "r:id")
		if relation_id.is_empty():
			relation_id = _attribute(parser, "id")
		var sheet_path: String = String(relations.get(relation_id, ""))
		if not sheet_path.is_empty() and zip.file_exists(sheet_path):
			workbook.sheets.append(_parse_sheet(zip, sheet_path, sheet_name, shared_strings))
	return workbook


static func _parse_sheet(
	zip: ZIPReader,
	path: String,
	sheet_name: String,
	shared_strings: PackedStringArray
) -> ExcelSheet:
	var sheet: ExcelSheet = ExcelSheet.new(sheet_name)
	var parser: XMLParser = XMLParser.new()
	if parser.open_buffer(zip.read_file(path)) != OK:
		return sheet
	var current_row: int = 0
	var previous_row: int = 0
	var previous_column: int = 0
	var current_cell: ExcelCell
	var raw_value: String = ""
	var inline_text: String = ""
	var formula_text: String = ""
	var in_value: bool = false
	var in_inline_text: bool = false
	var in_formula: bool = false
	while parser.read() == OK:
		match parser.get_node_type():
			XMLParser.NODE_ELEMENT:
				var node_name: String = parser.get_node_name().to_lower()
				match node_name:
					"row":
						current_row = _integer_attribute(parser, "r", previous_row + 1)
						previous_row = current_row
						previous_column = 0
					"c":
						current_cell = ExcelCell.new()
						current_cell.reference = _attribute(parser, "r")
						current_cell.row = _row_from_reference(current_cell.reference, current_row)
						current_cell.column = _column_from_reference(current_cell.reference)
						if current_cell.column <= 0:
							current_cell.column = previous_column + 1
						previous_column = current_cell.column
						current_cell.cell_type = _attribute(parser, "t")
						raw_value = ""
						inline_text = ""
						formula_text = ""
					"v":
						in_value = true
					"t":
						if current_cell != null:
							in_inline_text = true
					"f":
						in_formula = true
			XMLParser.NODE_TEXT:
				if in_value:
					raw_value += parser.get_node_data()
				elif in_inline_text:
					inline_text += parser.get_node_data()
				elif in_formula:
					formula_text += parser.get_node_data()
			XMLParser.NODE_ELEMENT_END:
				var node_name: String = parser.get_node_name().to_lower()
				match node_name:
					"v":
						in_value = false
					"t":
						in_inline_text = false
					"f":
						in_formula = false
					"c":
						if current_cell != null:
							current_cell.formula = formula_text
							current_cell.value = _parse_cell_value(
								raw_value,
								inline_text,
								current_cell.cell_type,
								shared_strings
							)
							sheet.add_cell(current_cell)
							current_cell = null
	return sheet


static func _parse_cell_value(
	raw_value: String,
	inline_text: String,
	cell_type: String,
	shared_strings: PackedStringArray
) -> Variant:
	var cleaned: String = raw_value.strip_edges()
	match cell_type:
		"s":
			if cleaned.is_valid_int():
				var index: int = cleaned.to_int()
				if index >= 0 and index < shared_strings.size():
					return shared_strings[index]
			return ""
		"inlineStr":
			return inline_text
		"b":
			return cleaned == "1"
		"str", "e", "d":
			return cleaned
	if cleaned.is_empty():
		return ""
	if cleaned.is_valid_int():
		return cleaned.to_int()
	if cleaned.is_valid_float():
		var number: float = cleaned.to_float()
		return int(number) if number == floorf(number) else number
	return cleaned


static func _attribute(parser: XMLParser, name: String) -> String:
	for index: int in range(parser.get_attribute_count()):
		if parser.get_attribute_name(index).to_lower() == name.to_lower():
			return parser.get_attribute_value(index)
	return ""


static func _integer_attribute(parser: XMLParser, name: String, fallback: int) -> int:
	var value: String = _attribute(parser, name)
	return value.to_int() if value.is_valid_int() else fallback


static func _normalize_workbook_target(target: String) -> String:
	var normalized: String = target.replace("\\", "/").trim_prefix("/")
	while normalized.begins_with("../"):
		normalized = normalized.trim_prefix("../")
	return normalized if normalized.begins_with("xl/") else "xl/" + normalized


static func _column_from_reference(reference: String) -> int:
	var letters: String = ""
	for character: String in reference:
		if character.is_valid_int():
			break
		letters += character
	var column: int = 0
	for character: String in letters.to_upper():
		column = column * 26 + character.unicode_at(0) - 64
	return column


static func _row_from_reference(reference: String, fallback: int) -> int:
	var digits: String = ""
	for character: String in reference:
		if character.is_valid_int():
			digits += character
	return digits.to_int() if digits.is_valid_int() else fallback
