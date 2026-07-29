class_name TimelineExcelLoader
extends RefCounted

const CONFIG_SHEET: String = "配置"
const EVENTS_SHEET: String = "事件"
const EXPECTED_SCHEMA_ID: String = "xiaochuxi.encounter_timeline"
const EXPECTED_SCHEMA_VERSION: int = 3


class LoadResult:
	extends RefCounted

	var timeline: EncounterTimeline
	var loaded_from_excel: bool = false
	var used_fallback: bool = false
	var error_message: String = ""
	var source_path: String = ""


# 版本3把普通流程改为路程驱动；事件页只维护精英、Boss和压力切换节点。
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

	var config: Dictionary = _records_to_values(config_sheet)
	if str(config.get("schema_id", "")) != EXPECTED_SCHEMA_ID:
		return _fallback(result, fallback, "时间轴 Excel schema_id 不匹配")
	var version: Variant = config.get("schema_version")
	if not _is_number(version) or int(version) != EXPECTED_SCHEMA_VERSION:
		return _fallback(
			result,
			fallback,
			"时间轴 Excel schema_version 必须为 %d" % EXPECTED_SCHEMA_VERSION
		)

	var errors: PackedStringArray = []
	var timeline: EncounterTimeline = EncounterTimeline.new()
	timeline.baseline_appetite_start = _required_number(config, "baseline_appetite_start", errors)
	timeline.baseline_appetite_mid = _required_number(config, "baseline_appetite_mid", errors)
	timeline.baseline_appetite_end = _required_number(config, "baseline_appetite_end", errors)
	timeline.appetite_mid_progress = _required_number(config, "appetite_mid_progress", errors)
	timeline.baseline_appetite_exponent = _required_number(
		config, "baseline_appetite_exponent", errors
	)
	timeline.baseline_appetite_late_exponent = _required_number(
		config, "baseline_appetite_late_exponent", errors
	)
	timeline.target_active_duration = _required_number(config, "target_active_duration", errors)
	timeline.target_boss_duration = _required_number(config, "target_boss_duration", errors)
	timeline.normal_gate_count = int(_required_number(config, "normal_gate_count", errors))
	timeline.normal_wave_count = int(_required_number(config, "normal_wave_count", errors))
	timeline.headwind_factor = _required_number(config, "headwind_factor", errors)
	timeline.max_crosswind_speed = _required_number(config, "max_crosswind_speed", errors)
	timeline.minimum_cart_base_speed_factor = _required_number(
		config, "minimum_cart_base_speed_factor", errors
	)

	var event_progresses: PackedFloat32Array = []
	var event_ids: PackedStringArray = []
	var pressure_progresses: PackedFloat32Array = PackedFloat32Array([0.0])
	var speed_multipliers: PackedFloat32Array = PackedFloat32Array([1.0])
	var previous_row_progress: float = -INF
	var row_number: int = 1
	for record: Dictionary in events_sheet.to_records():
		row_number += 1
		var progress_value: Variant = record.get("路程进度")
		if not _is_number(progress_value):
			continue
		var progress: float = float(progress_value)
		if progress < previous_row_progress:
			errors.append("事件表第 %d 行路程进度早于上一行" % row_number)
		if progress < 0.0 or progress > 1.0:
			errors.append("事件表第 %d 行路程进度必须位于0到1" % row_number)
		previous_row_progress = progress
		var event_id: String = str(record.get("事件ID", "")).strip_edges()
		if not event_id.is_empty():
			if not event_id in ["start_gate", "elite", "boss"]:
				errors.append("事件表第 %d 行事件ID不受支持: %s" % [row_number, event_id])
			else:
				event_progresses.append(progress)
				event_ids.append(event_id)
		var row_type: String = str(record.get("类型", "")).strip_edges()
		var multiplier_value: Variant = record.get("前进倍率")
		if "压力" in row_type and _is_number(multiplier_value):
			var multiplier: float = float(multiplier_value)
			if progress <= 0.0 or multiplier <= 1.0:
				errors.append("事件表第 %d 行后续前进倍率必须在正进度且大于1" % row_number)
			else:
				pressure_progresses.append(progress)
				speed_multipliers.append(multiplier)
	if event_ids.count("start_gate") != 1:
		errors.append("事件表必须且只能包含一道start_gate")
	if event_ids.count("elite") != 6:
		errors.append("事件表必须包含6只精英")
	if event_ids.count("boss") != 2:
		errors.append("事件表必须包含2场Boss")
	if pressure_progresses.size() != 6:
		errors.append("事件表必须包含5次后续压力切换")
	timeline.event_progresses = event_progresses
	timeline.event_ids = event_ids
	timeline.pressure_progresses = pressure_progresses
	timeline.forward_speed_multipliers = speed_multipliers
	if not errors.is_empty() or not timeline.is_valid():
		if errors.is_empty():
			errors.append("时间轴参数未通过正式距离流程校验")
		return _fallback(result, fallback, "；".join(errors))
	result.timeline = timeline
	result.loaded_from_excel = true
	return result


static func _records_to_values(sheet: ExcelReader47.ExcelSheet) -> Dictionary:
	var values: Dictionary = {}
	for record: Dictionary in sheet.to_records():
		var parameter_id: String = str(record.get("参数ID", "")).strip_edges()
		if not parameter_id.is_empty():
			values[parameter_id] = record.get("数值")
	return values


static func _required_number(values: Dictionary, key: String, errors: PackedStringArray) -> float:
	var value: Variant = values.get(key)
	if not _is_number(value):
		errors.append("配置缺少数值参数 %s" % key)
		return 0.0
	return float(value)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _fallback(result: LoadResult, fallback: EncounterTimeline, message: String) -> LoadResult:
	result.timeline = fallback
	result.used_fallback = fallback != null
	result.error_message = message
	return result
