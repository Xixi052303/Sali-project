---
name: food-td-excel-workbook-maintainer
description: >-
  “小厨西”项目专用的 Excel 工作簿安全维护 Skill。负责对领域 Skill 指定的项目 .xlsx
  人工编辑主源执行读取、局部更新、表结构同步、原子保存和复核。任何项目 Skill 需要写入 .xlsx、
  向单元格写入大段中文文本、批量更新既有行，或曾遇到命令行引号解析、工作簿占用、
  保存失败、部分修改、错表错行风险时使用；只执行已确认的数据变更，不登记具体工作簿、
  不裁决玩法、不直接维护导出 JSON。
---

# 小厨西 Excel 工作簿维护

## 职责边界

- 由所属领域 Skill 决定写什么；本 Skill 只负责安全地写入、保存和验证。
- 保留既有工作表、列、公式、样式、合并单元格和数据验证；任务没有要求时不整理格式、不新增字段。
- 不直接修改 Excel 的确定性导出 JSON，不运行 Godot 资源生成器。
- 不把历史表、导出物或副本误当作人工编辑主源。

## 强制写入规则

1. 首次读取与所有 JSON 载荷均显式使用 UTF-8；JSON 推荐 `ensure_ascii=false`。
2. 禁止把单元格正文、整行数据或 Python 程序拼进 `python -c`、PowerShell `-Command`、命令行参数、here-string 或 heredoc。命令行只传脚本路径和短文件路径。
3. 使用 `scripts/patch_workbook.py` 执行确定性局部更新。把长文本和每个目标单元格的旧值前置条件写入 UTF-8 JSON 载荷；载荷用 `apply_patch` 创建，不用 shell 字符串拼接。
4. 每项更新必须提供 `expect`。旧值不匹配、工作表不存在、单元格无效或同一单元格重复更新时立即停止，不保存。
5. 先运行 `--dry-run`；确认命中数量和前置条件后再正式写入。
6. 脚本必须保存到原工作簿同目录的临时文件，重新打开并逐格验证后才原子替换原文件。任何异常都保持原文件不变。
7. 正式写入后再次运行领域导出器或校验器，并检查 Git diff/文件摘要。不得以脚本退出码代替内容复核。
8. 删除临时载荷；最终交付不得残留一次性脚本、载荷、备份或临时工作簿。
9. Excel“表”不是普通单元格区域。修改表头、增删表列或调整表范围时必须使用 `table_updates`，同步更新工作表表头、表范围和 `tableColumns`；禁止只改单元格后依赖 Excel 自动修复。
10. 每次保存都必须检查表头与列定义一致、列数与范围宽度一致、表 ID/名称唯一、同页表不重叠，以及工作表关系指向的 `xl/tables/*.xml` 均存在。只用 `openpyxl` 重开成功不算通过。

## 载荷格式

先定位包含 `project.godot` 的“小厨西”项目根目录，并从该目录运行脚本。通过项目资料或
`rg --files -g '*.xlsx'` 确认人工编辑主源的真实位置；不得假设工作簿位于 `docs/` 或沿用
其他项目的目录。`workbook` 使用相对于项目根目录的现有文件路径；`expect` 也可显式写为
`null` 表示期望空单元格。

```json
{
  "workbook": "<项目内实际路径>/<数据主源>.xlsx",
  "expected_sheets": ["<工作表>"],
  "updates": [
    {
      "sheet": "<工作表>",
      "cell": "H12",
      "expect": "旧说明",
      "value": "包含中文、换行和引号的新说明",
      "kind": "text"
    }
  ]
}
```

- `kind` 可省略，默认 `text`；数值、布尔值或空值使用 `scalar`；只有明确要写 Excel 公式时才使用 `formula`。
- 需要清空单元格时令 `value` 为 `null` 且使用 `scalar`。
- 一次载荷只修改一个工作簿。大批量更新仍逐格列出前置条件，不使用模糊查找替换。

## 表结构更新

以下变化都属于表结构更新：修改表头、在表头相邻位置新增列、改变表的末行或末列、增删表列、改变汇总行或计算列。普通 `updates` 一旦触碰表头或疑似邻接扩列，脚本必须停止；不要改用临时脚本绕过。

`table_updates` 必须同时声明旧表范围、旧列定义、目标范围、当前工作表表头和目标列定义。`expect_headers` 按目标范围宽度读取当前工作表表头，允许安全修复“单元格已经变化、表定义仍是旧值”的受损工作簿；任一前置条件不符都不保存。

```json
{
  "workbook": "balance_tables/<数据主源>.xlsx",
  "expected_sheets": ["<工作表>"],
  "table_updates": [
    {
      "sheet": "<工作表>",
      "table": "<表名称>",
      "expect_ref": "A1:B16",
      "ref": "A1:C14",
      "expect_columns": ["旧列1", "旧列2"],
      "expect_headers": ["新列1", "新列2", "新增列3"],
      "columns": ["新列1", "新列2", "新增列3"]
    }
  ]
}
```

- 三个列数组必须与各自范围宽度完全一致；示例为说明字段含义，实际载荷不得省略中间列。
- 表的起始单元格不可移动；需要移动或重建整张表时停止，先由领域负责人确认迁移方案。
- 结构更新会保留既有列对象的样式和计算列元数据，并为新增列建立新的 `TableColumn`；仍须复核新增列格式、公式和数据验证是否符合原表。
- 如果工作簿打开时出现“发现部分内容有问题”或“已修复 `/xl/tables/table*.xml`”，先读取 Excel 修复日志并精确定位表；不要把 Excel 修复后的副本直接覆盖人工主源。

## 执行顺序

```text
<python> .agents/skills/food-td-excel-workbook-maintainer/scripts/patch_workbook.py <payload.json> --dry-run
<python> .agents/skills/food-td-excel-workbook-maintainer/scripts/patch_workbook.py <payload.json>
<python> <对应领域导出器>
```

- 优先使用已确认可运行且安装 `openpyxl` 的 Python 解释器；不要假设 `python` 或 `py` 在 `PATH`。
- 找不到解释器、缺少 `openpyxl`、工作簿被占用或验证失败时停止并如实报告，不改用不受验证的临时命令绕过。

## 交付检查

- 报告目标工作簿、工作表和实际更新单元格数量。
- 报告 dry-run、原子保存、重新打开验证和领域导出器的结果。
- 报告 JSON 是否发生预期变化；未执行的验证必须明确说明。
