# ExcelReader47

Godot 4.7 纯 GDScript `.xlsx` 读取器。无需 C#、GDExtension 或第三方动态库，可直接复制
`addons/excel_reader_47/` 到其他 Godot 4.7 项目。

本实现基于 johnnash2017 的 `godot_excel_reader`（MIT）改造，保留原许可证，并补充：

- Godot 4.7 静态类型。
- 工作表真实行列号与稀疏单元格。
- 共享字符串、富文本片段、`inlineStr`、布尔值、错误值和公式缓存值。
- 明确的读取结果与错误信息。
- 按表头转换为记录数组的通用接口。

## 使用

```gdscript
var result: ExcelReader47.ReadResult = ExcelReader47.read("res://balance_tables/时间轴.xlsx")
if not result.is_ok():
	push_error(result.error_message)
	return

var sheet: ExcelReader47.ExcelSheet = result.workbook.get_sheet_by_name("事件")
var records: Array[Dictionary] = sheet.to_records()
```

## 边界

- 读取 Excel 已保存的值，不在 Godot 内计算公式。数据主表应优先填写常量。
- 日期仍按 Excel 保存值返回；业务层负责按项目约定转换。
- `.xlsx` 必须通过导出预设的非资源过滤器包含到发布包中。
- 读取器只解析工作簿，不包含任何项目业务字段或单例。
