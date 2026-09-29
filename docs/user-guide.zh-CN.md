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
减去 Header 各列宽度之和。字体、边框沿用 RTF 样式。每列表头显示来自对应
population/header membership 的 `(N = xx)`，空列显示 `(N = 0)`。

源码顺序为 `custom_code.before → population/header → 分析与表组装 → custom_code.after
→ PROC REPORT → ODS RTF CLOSE`。Demo 已包含 before 和 after 示例。报告固定读取
`WORK._TFL_ASM_001`；after 修改结果时应写回同名数据集，并保留以下字段：

| 字段 | 用途 |
| --- | --- |
| `report_order` | 数值型展示顺序，每个物理行唯一。 |
| `label` | 字符型行标签，可包含用户填写的 RTF。 |
| `indent_level` | 数值型缩进层级，每级增加 `\li200`。 |
| `col_001`、`col_002` 等 | 按 Header 列顺序排列的字符型单元格。 |

数据集中同时保留 `chunk_order`、`row_sequence`、`chunk_id`、`row_id`、
`runtime_row_id`、`row_role`、`hierarchy_level` 和 `node_key`，供自定义代码定位行。
这些 SAS 运行期字段不写入 metadata。

Label 行不加粗。Chunk 边界和不同层级的切换处各留一行空白；边界重合只插入一行，
同级连续行不额外插空。跨页重复列标题。暂不生成标题、脚注、自动标签换行或
层级标题与下一行同页的规则；用户标签中的 RTF 内容保留。

`Download metadata` 下载最近一次保存的 metadata，不会隐式保存当前未保存修改。
`Download demo package` 与当前 workspace 无关。

## 测试

在项目根目录运行：

```text
Rscript test/run_tests.R
```

测试覆盖 YAML/ZIP round-trip、source generation、workspace draft 行为以及 shinytest2
交互流程。
