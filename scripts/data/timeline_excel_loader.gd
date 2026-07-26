class_name TimelineExcelLoader
extends RefCounted

const CONFIG_SHEET: String = "配置"
const EVENTS_SHEET: String = "事件"
const EXPECTED_SCHEMA_ID: String = "xiaochuxi.encounter_timeline"
const EXPECTED_SCHEMA_VERSION: int = 1


class LoadResult:
	extends RefCounted

	var timeline: EncounterTimeline
	var loaded_from_excel: bool = false
	var used_fallback: bool = false
	var error_message: String = ""
	var source_path: String = ""


# 严格校验工作簿并生成运行时 Resource；失败时保留调用方提供的安全回退。
static func load_from_excel(path: String, fallback: EncounterTimeline = null) -> LoadResult:
	var result: LoadResult = LoadResult.new()
	result.source_path = path
	var read_result: ExcelReader47.ReadResult = ExcelReader47.read(path)
	if not read_result.is_ok():
		return _fallback(result, fallback, read_result.error_message)
	var config_sheet: ExcelReader47.ExcelSheet = read_result.workbook.get_sheet_by_name(CONFIG_SHEET)
	var events_sheet: ExcelReader47.ExcelSheet = read_result.workbook.get_sheet_by_name(EVENTS_SHEET)
	if config_sheet == null or events_sheet == null:
		return _fallback(result, fallback, "时间轴 Excel 必须包含“配置”和“事件”工作表")

	var config_values: Dictionary = {}
	for record: Dictionary in config_sheet.to_records():
		var parameter_id: String = String(record.get("参数ID", "")).strip_edges()
		if not parameter_id.is_empty():
			config_values[parameter_id] = record.get("数值")
	var schema_id: String = String(config_values.get("schema_id", ""))
	if schema_id != EXPECTED_SCHEMA_ID:
		return _fallback(result, fallback, "时间轴 Excel schema_id 不匹配: %s" % schema_id)
	var schema_version_value: Variant = config_values.get("schema_version")
	if not _is_number(schema_version_value) or int(schema_version_value) != EXPECTED_SCHEMA_VERSION:
		return _fallback(result, fallback, "时间轴 Excel schema_version 必须为 %d" % EXPECTED_SCHEMA_VERSION)

	var errors: PackedStringArray = []
	var appetite_start: float = _required_number(config_values, "baseline_appetite_start", errors)
	var appetite_end: float = _required_number(config_values, "baseline_appetite_end", errors)
	var appetite_end_time: float = _required_number(config_values, "baseline_appetite_end_time", errors)
	var appetite_exponent: float = _required_number(config_values, "baseline_appetite_exponent", errors)
	if appetite_start <= 0.0:
		errors.append("baseline_appetite_start 必须大于 0")
	if appetite_end <= 0.0:
		errors.append("baseline_appetite_end 必须大于 0")
	if appetite_end < appetite_start:
		errors.append("baseline_appetite_end 不能小于 baseline_appetite_start")
	if appetite_end_time <= 0.0:
		errors.append("baseline_appetite_end_time 必须大于 0")
	if appetite_exponent <= 0.0:
		errors.append("baseline_appetite_exponent 必须大于 0")

	var event_times: PackedFloat32Array = []
	var event_ids: PackedStringArray = []
	var previous_time: float = -INF
	var event_row: int = 1
	for record: Dictionary in events_sheet.to_records():
		event_row += 1
		var time_value: Variant = record.get("请求时间(s)")
		var event_id: String = String(record.get("事件ID", "")).strip_edges()
		if not _is_number(time_value):
			errors.append("事件表第 %d 行请求时间不是数字" % event_row)
			continue
		var event_time: float = float(time_value)
		if event_time < 0.0:
			errors.append("事件表第 %d 行请求时间不能为负数" % event_row)
		if event_time < previous_time:
			errors.append("事件表第 %d 行请求时间早于上一行" % event_row)
		if event_id.is_empty():
			errors.append("事件表第 %d 行事件ID不能为空" % event_row)
		elif not _is_supported_event_id(event_id):
			errors.append("事件表第 %d 行事件ID不受支持: %s" % [event_row, event_id])
		previous_time = event_time
		event_times.append(event_time)
		event_ids.append(event_id)
	if event_times.is_empty():
		errors.append("事件表至少需要一条事件")
	if not errors.is_empty():
		return _fallback(result, fallback, "；".join(errors))

	var timeline: EncounterTimeline = EncounterTimeline.new()
	timeline.event_times = event_times
	timeline.event_ids = event_ids
	timeline.baseline_appetite_start = appetite_start
	timeline.baseline_appetite_end = appetite_end
	timeline.baseline_appetite_end_time = appetite_end_time
	timeline.baseline_appetite_exponent = appetite_exponent
	result.timeline = timeline
	result.loaded_from_excel = true
	return result


static func _fallback(result: LoadResult, fallback: EncounterTimeline, message: String) -> LoadResult:
	result.timeline = fallback
	result.used_fallback = fallback != null
	result.error_message = message
	return result


static func _required_number(values: Dictionary, key: String, errors: PackedStringArray) -> float:
	if not values.has(key) or not _is_number(values[key]):
		errors.append("配置缺少数值参数 %s" % key)
		return 0.0
	return float(values[key])


static func _is_number(value: Variant) -> bool:
	var value_type: int = typeof(value)
	return value_type == TYPE_INT or value_type == TYPE_FLOAT


static func _is_supported_event_id(event_id: String) -> bool:
	if event_id in ["start_gate", "basic", "fast", "ranged", "elite", "boss"]:
		return true
	if not event_id.begins_with("gate_"):
		return false
	return event_id.trim_prefix("gate_").is_valid_int()
