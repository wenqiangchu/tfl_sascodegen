# SAS Code Generator 用户指南

## 应用简介

本应用用于导入 YAML metadata ZIP bundle、编辑描述性分析 metadata，并生成 SAS
source text。应用只生成代码，不读取、验证或执行 SAS 分析数据集。

## 启动应用

在 Windows 上双击 `start_app.bat`。脚本会自动选择可用的本地端口并尝试在 Chrome
中打开应用。也可以在项目目录中运行 `shiny::runApp('.')`。

首次打开时需要点击 `Upload metadata` 并选择 metadata ZIP。也可以先下载
`Download demo package`，使用其中的示例 bundle 进行体验。

## ZIP 文件结构

bundle 是一个 ZIP 文件，包含：

```text
manifest.yaml
populations.yaml
headers.yaml
tables/<table-id>.yaml
templates/<template-id>.yaml
```

每个 table 和 template 都是独立的 YAML 文件，便于在不同研究之间复制和复用。
`manifest.yaml` 当前用于声明 schema version。

## Metadata 编辑

- 左侧列表显示当前类型的 metadata 对象；点击对象后，右侧显示详细内容。
- 点击 `New` 后输入对象 ID，再编辑新建的草稿。
- 点击对应的 `Save` 按钮提交修改。
- `Discard changes` 恢复到最近一次保存的版本；如果对象尚未保存，则直接移除该新对象。
- 在存在未保存修改时切换对象或 dashboard，会出现 `Discard changes` 和 `Cancel`。
- 删除已有对象时，系统会根据需要进行确认和引用检查。

## Population 和 Header

Population 的表达式使用 SAS 语法保存。Header 的 columns 和 spanning headers 在同一个
DT 中编辑。DT 中显示 spanning label，保存时根据连续 label 区间生成 canonical span ID
并写回 YAML。

Header 必须声明 `orientation: portrait` 或 `orientation: landscape`。新建 Header 时
通过 `Page orientation` 选择朝向后保存。Demo 的 FAS Header 为纵向，Safety Header 为
横向；旧 bundle 需要补上该字段，导入时不自动推断。

## Table 和 Template

Table 用于关联 population、header 和 template，并保存 custom code。Template 由多个独立
chunk card 组成。

Rows 和 statistics 使用同一个 DT：DT 中一行对应 RTF 中的一行；statistics 和 digits
使用空格分隔，例如：

```text
statistics: n mean sd
digits:     0 1 1
```

Hierarchical chunk 还包含多层 levels 和 analysis blocks，可以编辑 parent level、分析
类型和结构化 denominator。

## 计数单位（counting unit）

每个分析 chunk 和每个 hierarchical analysis block 都必须声明
`counting_unit`。它决定「一条被计数的观察」是什么，因此是必填项：缺少该字段的
bundle 会在导入时被拒绝。

| `counting_unit` | 一个单位是 | 重复检查 | 去重 |
| --- | --- | --- | --- |
| `record` | 一条 source record | 不检查 | 不去重 |
| `distinct_subject` | 一个 `USUBJID` | 按 `USUBJID` | 合并重复 subject |
| `distinct_key` | 声明的一组 `distinct_key` 字段组合 | 按 `distinct_key` | 合并重复键 |

`record` 把每条记录视为独立单位，其键就是 source 行号，天然唯一，重复检查永远
不会报告任何内容，因此不生成检查也不去重。需要按观察计数时用 `record`，要求每个
subject 只贡献一次时用 `distinct_subject`。

`distinct_key` 需要同时填写 `distinct_key`，按顺序列出键变量，例如
`USUBJID, AVISITN`。另外两种单位下该字段应留空；若非空但单位不是
`distinct_key`，导入会被拒绝。

重复检查默认开启，每个重复键最多报告一次。它不删除记录，只在 SAS log 中写入
`WARNING: [USER] duplicate_key`。生成时关闭该开关只移除检查本身。

### 连续统计与多值冲突

`distinct_subject` 与 `distinct_key` 的 continuous chunk 会先把每个计数单位归约成一个
值，再执行 `PROC MEANS`，因此 `n` 统计的是单位数而不是记录数。当一个单位贡献了不止
一个非缺失值时，生成器不会凭空发明取值规则，而是向 SAS log 写入
`WARNING: [USER] continuous_unit_multiple_values`，并保留输入顺序中第一条非缺失
记录（即 `source_row` 最小者）的值，继续执行。

因此结果依赖输入行顺序，而这由前置排序完全决定。该 warning 是数据质量信号而不是
致命错误：请检查 log，如分析要求每个单位唯一，应先让 source 满足该条件。

### 旧 bundle 迁移

在计数单位出现之前导出的 bundle 没有 `counting_unit` 字段，无法再导入。请为每个
分析 chunk 和每个 hierarchical analysis block 补上
`counting_unit: distinct_subject`，可复现此前按 subject 计数的行为。已移除的
`source_contract` 块应直接删除而不是翻译：其 subject key 现固定为 `USUBJID`，
而 duplicate policy 只接受过一个取值。

## 生成 SAS

进入 `Generate SAS`，选择 table 和本次生成选项后点击 `Generate SAS`。生成的 SAS source
可以在页面中预览，也可以下载为 `.sas` 文件。

- `Include duplicate record checks` 默认勾选。取消后，源码不包含 source key 重复检查
  及其 `WARNING: [USER] duplicate_key` 提示，适用于 primitive chunk 和 hierarchical
  source。该选项不改变分析计数、merge 规则，也不关闭 exclusive category overlap 提示。
- `Source report (PROC REPORT)` 为默认模式，生成下面说明的报告与 ODS RTF 代码。
- `QC compare (PROC COMPARE)` 在组装和 custom code after 之后生成
  `proc compare base=tables.<table_id> compare=WORK._TFL_ASM_001 listvar;`。
  调用方需要先绑定 `TABLES` 库并准备 source 侧数据集，保证待比较字段和观察顺序一致。
  例如 table ID 为 `14.1.2` 时使用 `tables.'14.1.2'n` 并启用 `VALIDMEMNAME=EXTEND`。
  生成器不会创建或重排 source 侧数据集。QC 模式不添加系统生成的 ODS RTF 或 PROC REPORT
  语句，也不受 RTF 页宽限制。

两个模式共用分析和组装过程，随后原样插入 `custom_code.after`，最后生成所选 procedure。
生成选项只属于当前 UI session 和生成请求，不写入 metadata bundle。切换 table 或选项后，
旧预览隐藏、SAS 下载禁用；重新生成成功后恢复。

Header membership 在一个 DATA step 内用各列独立的 `IF ... THEN DO / OUTPUT` 完成，
允许同一受试者同时进入治疗列和 Overall 列。`_TFL_KEY_MAP_*` 使用 `INPUT + DATALINES`
读取带引号的分隔文本；含分号时采用 `DATALINES4`，字符字段使用显式 informat。
每个 chunk/row/statistic 只写一次，通过与共享 Header 列目录 `_TFL_HCOLS_001` 做
`CROSS JOIN` 展开为 `_TFL_KEY_*`。没有受试者的已声明列仍会保留；层级分析还会与
当前 scope 的节点目录做 `CROSS JOIN`。

INPUT 按字段分行；Header 和计数等短规则采用“一条规则一行”，复杂计算和错误
处理保持展开。生成器不保存、切换或恢复 CARDIMAGE，inline records 按调用方
SAS 会话的现有设置读取。

应用会原样保留 `source_data`、filter、condition、denominator expression 和 custom code。
这些内容不会在 R 或 Shiny 中执行，实际语法和数据集是否存在由调用方负责。

生成程序面向 SAS 9.4。以下报告约定适用于 Source report 模式，其源码包含 `ODS RTF`
和 `PROC REPORT`。将 `.sas` 保存到临床项目后，
由使用者把 SAS 当前工作目录设为程序目录；执行时输出 `<table_id>.rtf`，覆盖同名文件。
SAS 执行、结果正确性和 RTF 外观由使用者手动验收。

纸张固定为 Letter，使用内置 `Styles.Rtf`（`style=rtf`）。左右页边距显式设为各
1 英寸，因此纵向可用宽度为 6.5 英寸，横向为 9 英寸；左侧行标签列宽为可用宽度
减去 Header 各列宽度之和、两侧外框（各 0.75 pt）以及 0.25 英寸的 fit reserve。
外框固定 0.75 pt；fit reserve 存在的原因是单元格内边距与边框都不在声明的列宽里，
栅格没有余量时经典 ODS RTF 会把表格拆成横向重复的面板。字体、边框沿用 RTF 样式。
每列表头显示来自对应 population/header membership 的 `(N = xx)`，空列显示 `(N = 0)`。

源码顺序为 `custom_code.before → population/header → 分析与表组装 → custom_code.after
→ 分页 → PROC REPORT → ODS RTF CLOSE`。Demo 已包含 before 和 after 示例。
after 代码需原地修改 `WORK._TFL_ASM_001`，并保留以下字段：

| 字段 | 用途 |
| --- | --- |
| `report_order` | 数值型展示顺序，每个物理行唯一。 |
| `label` | 字符型行标签，可包含用户填写的 RTF。 |
| `indent_level` | 数值型缩进层级，每级增加 `\li200`。 |
| `col_001`、`col_002` 等 | 按 Header 列顺序排列的字符型单元格。 |

数据集中同时保留 `chunk_order`、`row_sequence`、`chunk_id`、`row_id`、
`runtime_row_id`、`row_role`、`hierarchy_level` 和 `node_key`，供自定义代码定位行。
这些 SAS 运行期字段不写入 metadata。

分页在 custom code **after** 之后执行，因此 after 的修改会进入页面。分页会先按
`report_order` 对 `WORK._TFL_ASM_001` 重新排序再划分块，因此 after 代码可以追加或插入
行，不必保证物理顺序与 `report_order` 一致（必要时用 `proc append ... force`）。分页读取
`WORK._TFL_ASM_001` 并写出 `WORK._TFL_PAGED_001`，由 `PROC REPORT` 渲染；
`_TFL_PAGED_001` 额外增加 `page_group`（页码）与 `_tfl_print_order`（该行在整张表中的
打印顺序，报告按它排序；它是最终排序后的 `_n_`，跨页连续编号，不按页重新计数）。也就是说报告**不再**直接读 `_TFL_ASM_001`。分页的其余
内部变量都已从该数据集丢弃。
QC compare 模式不分页，直接比对 `WORK._TFL_ASM_001`，因此版式不影响 QC 路径。

Label 行不加粗。一行空白标记一个**块边界**：新 chunk、顶层节点、或刚结束自身 below
行的节点。边界重合只插入一行。同深度的连续节点不插空，因为缩进已表达嵌套关系；
带 below 行的节点才插空，因为那些行与下一个同级节点缩进相同。跨页重复列标题。

分页由 Header 的 `page_rows` 控制，在 Header 标签页上显示为 **Page capacity**（默认 22
个打印行，`0` 关闭分页，否则最小为 4）。该值**始终**保存在 bundle 中（包括等于默认值时），
因此 bundle 自己声明自己的版式，而不是继承当前的默认值。每页首尾各一行
空白行，因此正文最多 `page_rows - 2` 行；重复列标题不计入。块不跨页，唯一例外是
单块本身高于一整页——它无处可放，因此填满当前页后继续。每页页脚为右对齐、罗马体
10pt 的 `Page x of Y`。暂不生成标题、自动标签换行或层级标题与下一行同页的规则；
用户标签中的 RTF 内容保留。

`Download metadata` 下载最近一次保存的 metadata，不会隐式保存当前未保存修改。
`Download demo package` 与当前 workspace 无关。

## 测试

在项目根目录运行：

```text
Rscript test/run_tests.R
```

测试覆盖 YAML/ZIP round-trip、source generation、workspace draft 行为以及 shinytest2
交互流程。