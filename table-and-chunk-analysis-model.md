# SAS 描述性分析代码生成：Metadata 模型、Chunk 契约与内存工作区

生成边界更新（2026-09-13）：用户已确认支持 duplicate-check 选项，以及生成
`PROC REPORT` 或 `PROC COMPARE` 源码。以
[最新生成决定](docs/design-decisions.md#sas-生成选项与源码可读性) 为准；该决定替代下文
关于“不生成 PROC REPORT/ODS”以及 GenerationRequest 仅含三个字段的早期限制。
应用输出仍只有 SAS source text，不执行 SAS 或直接生成报告文件。

本文是面向独立实现的可移植契约。它只描述用于生成 SAS 分析程序的
population、header、table、template、chunk 以及内存态编辑工作区，不规定任何
仓库、目录、物理路径或具体实现语言。

本文的目标是让实现可以从空白工作区开始：

1. 导入一个 metadata bundle 文件；
2. 在 UI 中编辑 population、header、table、template 和 chunk；
3. 按 table 引用关系生成 SAS 源代码；
4. 下载更新后的 metadata 文件或生成的 SAS 文件。

## 1. 已确认的范围与边界

### 1.1 已确认

- 系统只负责生成 SAS 源代码，不负责执行 SAS 程序。
- 系统不读取、上传或管理分析数据集。source_data 只是生成代码时使用的
  外部 SAS 数据集引用。
- population、header、chunk filter、denominator 和 row condition 均使用
  SAS 表达式，不使用其他语言表达式。
- 缺失值语义采用 SAS 语义。
- custom_code.before 和 custom_code.after 是原样保留并插入生成程序的
  SAS 代码。
- custom_code.before_outputs 不属于模型。
- 编辑过程维护内存对象；不把 metadata 绑定到物理文档路径。
- 可以上传一个 metadata bundle 文件导入内存工作区，也可以把当前工作区下载
  为一个 metadata bundle 文件。
- 导入结构错误和生成前置错误使用稳定的有序错误包络；失败不产生部分工作区
  或部分 SAS source。
- UI 技术栈继续使用 Shiny；population、header、table、template 的 UI 继续采用现有的编辑形式：
  列表、新建、删除、表单、嵌套行编辑、顺序调整和 dirty draft。
- 系统不包含 AI candidate、AI agent、retry、capability 或 AI review。

### 1.2 本文刻意不替实现决定的内容

以下内容属于实现边界，不是用户 YAML 字段；当前项目的具体 SAS emitter 微契约已
记录在 `docs/design-decisions.md` 的 P0-8，bundle YAML、sequence 和导入替换语义
也记录在那里：

- source_data 仅要求为非空字符串；其 SAS 语法和宏变量含义由调用方保证；
- 四类 chunk 的具体 SAS emitter 步骤、中间 raw 输出字段和最终输出字段；兼容 batch
  的专用规范化输入字段和 `_TFL_` 命名边界由 P0-6/P0-8 冻结；
- 分位数方法、四舍五入、格式化和不可估计值的具体 SAS 实现由 P0-4/P0-8 冻结；
- `cell_format` 由 render DATA step 使用 `TRANWRD`、`ROUND` 和 `PUTN` 生成字符型
  logical cell；本项目不生成 PROC REPORT；
- ODS/报表代码明确不属于当前范围；本文只返回 SAS 源码，不生成报告文件；
- UI 的具体控件布局属于实施阶段，不改变已确认的单 stub/层级 row 语义。

### 1.3 明确不属于系统职责

- 上传、解析、检查或缓存 SAS 数据集；
- 读取数据字典、确认变量真实存在或推断变量类型；
- 执行 SAS 表达式、运行 SAS、检查日志或验证分析结果；
- 生成其他语言程序、RTF、reporter artifact、运行结果或结果审计文件；
- 维护 study 根目录、metadata 文件路径、程序输出路径；
- 自动修复重复 key、缺失 key、重叠分类或重复观测；
- 自动推断统计方法、分母或业务规则。

导入只需要最小的文件解析能力；若 bundle bytes 无法解析，导入返回结构化的
transport/解析错误。生成器也可以因为缺少必要的结构字段或无法解析对象引用而返回
生成前置错误。这些错误不构成独立的 validation API，也不执行 SAS 语法或数据检查。

## 2. 对象关系

~~~text
MetadataBundle
  ├─ populations[population_id] -> PopulationSpec
  ├─ headers[header_id]         -> HeaderSpec
  ├─ tables[table_id]           -> TableSpec
  └─ templates[template_id]     -> TemplateSpec

TableSpec
  ├─ population_id -> PopulationSpec
  ├─ header_id     -> HeaderSpec
  └─ template_id   -> TemplateSpec

TemplateSpec.body.chunks[]
  ├─ continuous_summary
  ├─ categorical_summary_nonexclusive
  ├─ categorical_summary_exclusive
  └─ hierarchical_summary
       └─ analysis_blocks[] -> registered primitive
~~~

一个 table 引用一个 population、一个 header 和一个 template。引用对象不内联
到 table 中。template 描述表正文、行结构和分析请求；population、header 和
table 级 custom code 不属于 template。

对象 ID 是工作区中的逻辑身份。导出文件可以使用带 id 的 sequence，也可以
使用以 ID 为键的 mapping；两种形式必须保持相同的对象字段和业务顺序。实现
应选择一种 canonical serialization 并固定下来。

## 3. Metadata Bundle 压缩包

Metadata bundle 使用一个 ZIP 压缩包承载整个可编辑工作区。压缩包保留最小的
`manifest.yaml`，用于声明 bundle 格式版本；population、header、table 和
template 使用独立 YAML 文件，便于 template 在不同研究之间复制和移动。压缩包
不包含数据集内容。

固定布局如下：

~~~text
manifest.yaml
populations.yaml
headers.yaml
tables/<table_id>.yaml
templates/<template_id>.yaml
~~~

`manifest.yaml` 只包含：

~~~yaml
schema_version: 1
~~~

`populations.yaml` 的根字段为 `populations`，`headers.yaml` 的根字段为
`headers`；每个 `tables/<table_id>.yaml` 和 `templates/<template_id>.yaml`
的根节点分别是一个 TableSpec 或 TemplateSpec 对象本身。

下面的 YAML 片段展示各文件中的逻辑内容，不表示单一文件布局：

~~~yaml
schema_version: 1

populations:
  - id: safety
    label: Safety population
    expression: 'SAFFL = "Y"'

headers:
  - id: treatment
    source_data: ADAM.ADSL
    orientation: landscape
    spanning_headers:
      - id: analysis_population
        level: 1
        label: Analysis population
    columns:
      - id: placebo
        label: Placebo
        condition: 'TRT01A = "Placebo"'
        display_order: 1
        width: 1.2
        alignment: center
        spanning_header_1: analysis_population
      - id: overall
        label: Overall
        condition: '1'
        display_order: 2
        width: 1.2
        alignment: center

tables:
  - id: t_demog
    population_id: safety
    header_id: treatment
    template_id: demog
    custom_code:
      before: |
        /* Optional SAS data preparation. */
      after: |
        /* Optional SAS post-assembly transformation. */

templates:
  - id: demog
    body:
      stub_header: Characteristic
      chunks:
        - id: demog_001
          type: continuous_summary
          source_data: ADAM.ADSL
          analysis_variable: AGE
          rows:
            - id: demog_001_001
              type: analysis
              label: Mean (SD)
              statistics:
                - id: mean
                  digits: 1
                - id: sd
                  digits: 1
              cell_format: '{mean} ({sd})'
~~~

### 3.1 Bundle 文件与对象字段

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| `manifest.yaml.schema_version` | integer | bundle 格式版本；当前固定为 1。 |
| `populations.yaml.populations` | sequence | 可复用 population 定义。 |
| `headers.yaml.headers` | sequence | 可复用 header 定义。 |
| `tables/<table_id>.yaml` | mapping | 单个 table 定义；table 是生成入口。 |
| `templates/<template_id>.yaml` | mapping | 单个可复用 template 定义。 |

bundle 不包含 datasets、数据文件、数据路径、study 根目录、生成目录、运行
结果、日志或 AI 状态。

### 3.2 导入与下载

- **导入**：UI 接收一个 ZIP bundle，读取压缩包 entries 并构造候选
  MetadataWorkspace。当前项目采用原子整体替换：只有 manifest、两个 catalog、
  所有 table/template 文件均成功读取、解析并通过结构解码后才替换当前工作区；
  失败时保留旧 metadata、active draft 和 revision；合并导入不在当前契约内。
- **导入错误**：导入结果使用 `passed`、候选 workspace 和有序 `errors`。YAML
  解析失败或无法继续遍历时只返回根路径 `$` 的错误；可继续遍历的结构错误按
  canonical 字段和 sequence 顺序返回。失败时只允许更新 workspace 的
  `parse_diagnostic`，成功时清除旧导入诊断并清空旧 draft/选择状态。
- **YAML 导入 profile**：每个 entry 都是严格单文档 YAML；canonical 文件内容为
  UTF-8、无 BOM、LF，导入接受有效 UTF-8 的 BOM 或 CRLF 并在内存中规范化。未知
  字段、重复 key、anchor/alias、tag、merge key、未知 chunk type、缺失/重复 ID
  和 discriminator 不一致均为结构错误。跨对象引用存在性留到生成前置阶段。
- **ZIP 导入 profile**：只接受固定根级文件、`tables/` 和 `templates/` 下的直接
  `.yaml` 文件；拒绝未知 entry、重复 entry、绝对路径、路径分隔符逃逸、嵌套目录
  和符号链接。table/template 文件名 stem 必须与文件内部 `id` 一致。catalog 和
  文件集合按文件名 ID 的字典序形成工作区 sequence；每个文件内部 sequence 保留
  业务顺序。
- **编辑**：所有修改先进入当前 session 的 draft，再写回内存工作区；不写入
  物理 metadata 文档。
- **下载 metadata**：将当前内存工作区按 canonical YAML serialization 编码为
  一个 `.zip` bundle 文件。导出 ZIP 使用上述固定布局和确定性 entry 顺序；内容不
  包含临时上传路径、session ID 或 UI 状态。独立 template 文件可直接复制到其他
  bundle 的 `templates/` 目录复用。
- **下载 SAS**：选择一个 table 后，生成器返回 SAS source text，UI 将其作为
  .sas 文件下载或显示预览。
- **会话边界**：浏览器/session 结束后，未下载的内存修改可以丢失；是否增加
  服务端持久化不属于当前契约范围。

上传控件产生的临时服务器文件名只能是传输适配器的内部细节，不能写入
MetadataBundle、任何对象字段或导出的文件。

当前项目的 canonical YAML profile 为 UTF-8、无 BOM、LF 换行、两空格缩进、
固定字段顺序和原有 sequence 顺序；单行字符串使用 single-quoted scalar，
多行 custom code 使用 literal block scalar；缺省可选字段不输出为 `null`。

### 3.2.1 Numeric scalar 规范

metadata numeric scalar 的 canonical 文件表示采用已确认的方案 A：

| 字段类别 | canonical 表示 |
| --- | --- |
| `schema_version`、`display_order`、`level`、`indent_level`、`column_order` | 有限整数的普通十进制表示；不带小数点或指数。 |
| `width` 等有限实数 | 最多 15 位有效数字的普通十进制；不使用科学计数法，去除小数尾零和末尾小数点，负零写为 `0`。 |
| absolute `digits`、categorical `pct` digits | 整数 numeric scalar。 |
| relative `digits`（`+n`/`-n`） | single-quoted string，保留相对精度语义。 |

有限实数超过 15 位有效数字时按上述规则规范化，不保留 binary floating-point tail。
`NaN`、`Inf`、`-Inf` 等非有限 metadata numeric 值导入或保存时返回
`bundle_value_invalid`，不写成 `null`。输入词法可以不同，但 canonical bytes 只由
schema-aware encoder 的统一输出决定。该文件表示规则不改变运行期
`base_digits`/relative precision 的分析语义。

实现使用 `yaml` 作为底层 UTF-8 parser，但不直接使用其默认 encoder。parser wrapper
固定关闭 expression evaluation，并在解析前拒绝 multi-document、anchor、alias、tag
和 merge key；重复 key 映射为稳定的 `bundle_duplicate_key`。canonical bytes 由
schema-aware encoder 生成；其 numeric scalar 规则已按 P0-2 锁定。当前工具链基线为
R 4.4.0、yaml 2.3.10、testthat 3.3.2、shiny 1.8.1.1 和
withr 3.0.2，使用 renv 1.2.3 锁定依赖。

### 3.3 错误包络

导入和生成前置错误共用以下最小错误项：

| 字段 | 语义 |
| --- | --- |
| stage | `import`、`workspace` 或 `generation`。 |
| code | 稳定的机器可读错误代码。 |
| message | 英文事实描述，不包含建议。 |
| path | 逻辑字段路径，例如 `$.tables[0].template_id`；根级错误使用 `$`。 |

导入结果 `BundleImportResult` 至少包含 `passed`、成功时的候选 workspace 和有序
`errors`。结构错误可一次返回多个，按 canonical 字段顺序、sequence 顺序和 path
稳定排序；编码/YAML 解析失败或无法继续遍历时只返回一个根级错误。生成成功时仍只
返回 SAS source text；生成前置失败返回同一错误项形状且不返回部分 source。

导入错误代码为：

`bundle_input_missing`、`bundle_encoding_invalid`、`bundle_yaml_invalid`、
`bundle_structure_invalid`、`bundle_schema_unsupported`、
`bundle_required_field_missing`、`bundle_unknown_field`、`bundle_value_invalid`、
`bundle_id_invalid`、`bundle_duplicate_key`、`bundle_chunk_type_unknown`。

生成前置错误代码为：

`generation_table_missing`、`generation_reference_missing`、
`generation_emitter_unavailable`、`generation_contract_invalid`。

错误项不包含 warning、suggestion、stack trace、服务器临时路径、session 信息、
原始数据或不稳定的 parser 文本。导入不执行 SAS expression/custom code，也不读取
SAS 数据；跨对象引用存在性由生成前置阶段处理。

## 4. Population 模型

~~~yaml
id: safety
label: Safety population
expression: 'SAFFL = "Y"'
~~~

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| id | string | 工作区内唯一的 population ID。 |
| label | string | UI 和生成代码注释可使用的展示标签。 |
| expression | string | SAS logical expression，定义 population 成员。 |

已确认的语义是：生成的 SAS 程序在所引用 header 的 `source_data` 上求值
population expression，再以该 population 结果构造 header membership。Population 不增加
独立的 `source_data` 字段；如果调用方需要准备或改变 source，应通过 table 的
`custom_code.before` 提供 SAS code，平台不对此作假设或验证。

平台将 expression 当作 SAS source text 传递给 generator，不执行、不翻译、不做
SAS parser 校验。表达式中引用的变量、格式和数据集由调用方保证。

## 5. Header 模型

~~~yaml
id: treatment
source_data: ADAM.ADSL
orientation: landscape
spanning_headers:
  - id: analysis_population
    level: 1
    label: Analysis population
columns:
  - id: placebo
    label: Placebo
    condition: 'TRT01A = "Placebo"'
    display_order: 1
    width: 1.2
    alignment: center
    spanning_header_1: analysis_population
~~~

### 5.1 Header 字段

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| id | string | 工作区内唯一的 header ID。 |
| source_data | non-empty string | 外部 SAS 数据集引用；原样保留，不表示上传文件或物理路径。可使用 `adsl`、`adam.adsl`、`&ADSL` 或 `&lib..&member` 等调用方提供的 SAS 文本。 |
| orientation | enum，必填 | portrait 或 landscape；Header 编辑器与 canonical YAML 保存该值，Report 源码据此计算 Letter 页面可用宽度。导入不推断默认值；该字段不属于 Table。 |
| spanning_headers | sequence，可选 | 跨列表头；每项有 id、level、label。 |
| columns | sequence | 有序展示列。 |
| columns[].id | string | header column 的逻辑 ID。 |
| columns[].label | string | 列展示标签。 |
| columns[].condition | string | SAS logical expression，判断 subject 是否属于该列。 |
| columns[].display_order | positive integer | 从 1 开始的连续列显示顺序；canonical sequence 按该顺序保存。 |
| columns[].width | positive number | 目标输出使用的真实英寸宽度（例如 1.2 表示 1.2 inches）。 |
| columns[].alignment | enum | left、center 或 right。 |
| columns[].spanning_header_1 | string，可选 | level 1 spanning header 引用。 |
| columns[].spanning_header_2 | string，可选 | level 2 spanning header 引用。 |

每个 column condition 独立用于生成筛选代码，因此一个 subject 可以属于多个
列。生成顺序按 `display_order`；该字段必须在当前 header 内唯一、从 1 开始连续，
保存时 columns sequence 与 display order 一致，不按 ID 自动排序。`spanning_header_1`
只能引用 level 1，`spanning_header_2` 只能引用 level 2；同一 spanning header
引用的列在最终顺序中必须连续。Overall 一类的无条件列使用 SAS 表达式 `1`，而不
使用其他语言的 `TRUE`。未命中任何 column condition 的 subject 不进入 membership
scaffold；系统不隐式添加 Overall 或去重。

### 5.2 Population 与 Header Membership 数据流

已确认的生成顺序为：

~~~text
header.source_data
    -> population.expression
    -> columns[].condition（按 display_order 生成）
    -> AnalysisScaffold(USUBJID, header_column_id)
~~~

`AnalysisScaffold` 是生成期的内部派生对象，不写回 metadata bundle。其最小字段为
`USUBJID` 与 `header_column_id`，同一组合必须唯一；同一 `USUBJID` 可以因为条件
重叠出现在多个 columns。Population/header expression 原样作为 SAS source text
使用，平台不执行、翻译、求值或验证 SAS 语法，也不读取 source dataset 或检查
`USUBJID` 前提。

生成器通常需要构造一个逻辑 header membership 数据集，至少包含：

~~~text
USUBJID | header_column_id
~~~

这里的字段名和中间数据集名属于已确认的 SAS emitter contract（具体物理字段见
P0-8）。平台不读取 source_data，也不检查其 SAS 语法、宏变量、libref、member、
数据集或变量是否存在，不检查 USUBJID 是否存在、唯一或非缺失。

## 6. Table 模型（精简版）

table 只保存引用和 custom code：

~~~yaml
id: t_demog
population_id: safety
header_id: treatment
template_id: demog
custom_code:
  before: |
    /* SAS code before population/header derivation. */
  after: |
    /* SAS code after table assembly. */
~~~

### 6.1 Table 字段

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| id | string | table 的工作区身份。若采用以 ID 为键的 mapping，可不在值中重复保存。 |
| population_id | string | 对 Population 的引用。 |
| header_id | string | 对 Header 的引用。 |
| template_id | string | 对 Template 的引用。 |
| custom_code | mapping，可选 | table 级 SAS 扩展代码。 |
| custom_code.before | string，可选 | 在 population/header/chunk 代码之前插入的 SAS code。 |
| custom_code.after | string，可选 | 在所有 chunk 结果组装之后插入的 SAS code。 |

以下字段明确不属于 TableSpec：

- orientation
- titles
- footnotes
- page_header
- page_footer
- roots
- study_id
- 任何数据路径、程序路径、输出路径或 artifact path
- before_outputs
- AI candidate、adapter、trace 或 acknowledgement 字段

before 可以创建或整理 SAS 数据集，后续 chunk 可以通过 source_data 引用
这些名称。由于平台不执行 SAS，也不维护 before_outputs，对象存在性、粒度和
字段正确性由生成代码的使用者负责。

after 与 before 在同一个生成 SAS 程序上下文中运行。平台不限制或假设 custom code
的输入、输出、依赖、可访问对象或副作用，也不检查语法、安全性或可执行性；after
位于 table assembly/cell formatting 之后，且之后不再追加系统代码。custom code
导致的运行时失败由调用方执行 SAS 时处理。

## 7. Template 模型

~~~yaml
id: demog
body:
  stub_header: Characteristic
  chunks:
    - <ChunkMetadata>
~~~

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| id | string | 工作区内唯一的 template ID。 |
| body | mapping | 表正文容器。 |
| body.stub_header | string，可选 | stub/label 区域的标题。 |
| body.chunks | non-empty sequence | 按输出顺序排列的 chunk。 |

template 不保存动态数据值。chunk、level、analysis block 和 row 的 ID 是编辑
器中的位置身份：插入、删除或移动后可以按 sequence 自动重编号。若实现需要
跨版本稳定引用，应另加稳定 UUID，不能把位置 ID 当作稳定数据库主键。

## 8. Chunk 通用模型

### 8.1 公共字段

~~~yaml
id: demog_001
type: continuous_summary
source_data: ADAM.ADSL
filter: 'not missing(AGE)'
rows:
  - <RowMetadata>
~~~

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| id | string | chunk 的位置/逻辑 ID。 |
| type | registered type ID | 四类 chunk 之一，或实现注册的扩展类型。 |
| source_data | non-empty string | 外部 SAS 数据集或 custom code 创建的数据集引用；作为 opaque SAS source text 原样保留。 |
| filter | string，可选 | SAS logical expression，作用于当前 chunk source。 |
| rows | sequence | primitive chunk 的静态行；hierarchical chunk 的行位于 analysis blocks。 |

chunk 不携带数据集路径、上传内容或运行结果。

### 8.2 RowMetadata

~~~yaml
- id: demog_001_001
  type: analysis
  label: Mean (SD)
  indent_level: 0
  statistics:
    - id: mean
      digits: 1
    - id: sd
      digits: 1
  cell_format: '{mean} ({sd})'
~~~

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| id | string | row 的位置 ID。 |
| type | enum | label 或 analysis。 |
| label | string | 行标签。 |
| indent_level | non-negative integer，可选 | 逻辑行缩进级别。 |
| condition | string，可选 | 分类 analysis row 的 SAS 分子条件。 |
| statistics | sequence | analysis row 请求的统计量。 |
| cell_format | string | 逻辑 cell 的占位符模板。 |

label row 只输出标签，不请求统计量。analysis row 必须有 statistics 和
cell_format；分类 row 还需要 condition。placeholder 集合应与 statistic ID
集合一致。字符 cell 使用 SAS `PUTN` 和 emitter 定义的格式化步骤生成；具体的内部
DATA step 仍不进入 metadata 契约。

digits 支持绝对非负整数以及 `+n`/`-n` 相对精度字符串。continuous 的 relative
digits 使用当前 chunk 实际分析 subjects 的统一 `base_digits`：数值先按最多
15 位有效数字、非科学计数法、去除小数尾零的规则规范化，再计算
`resolved_digits = base_digits + offset`；负 resolved digits 不自动截断。按 P0-13，
生成的 SAS 写入 ERROR 诊断、设置该 statistic 为不可估计并显示 NE，继续后续步骤；
它不执行 ABORT CANCEL，也不是应用根据分析数据返回的生成前置错误。
`n` 不声明 digits，categorical `pct` 只接受非负绝对整数。这里的 15 位规范化是
运行期 precision 语义的一部分，与 metadata numeric scalar 的 canonical 文件表示
规则相容但彼此独立；`base_digits` 从实际分析数值推导，不依赖原始 SAS format，
并由 emitter 在运行期 materialize。

### 8.3 统计结果的抽象表示

虽然平台不执行分析，generator 仍需要为每个 cell 定义目标逻辑字段。统一的 raw
statistic 对象为 `ChunkStatisticValue`：

| 字段 | 语义 |
| --- | --- |
| chunk_id | 来源 chunk。 |
| row_id | 目标 analysis row。 |
| header_column_id | 目标 header column。 |
| statistic_id | 统计量 ID。 |
| value | 未舍入 numeric value；不可估计时不承载伪造值。 |
| estimable | 当前 statistic 是否可估计；`n` 始终为 true。 |
| resolved_digits | render 使用的最终非负小数位；`n` 不适用。 |

continuous 和 categorical 都必须转换到该结构。categorical 的 denominator、numerator
和 overlap guard 计数可以保留在 emitter-private 对象中；公共结果只保存 `n` 或
`pct`，其中 `pct = 100 * n / denominator`，denominator 为零时 `n=0` 且 `pct`
不可估计。上述对象只在生成期存在，不作为文件字段导出，也不表示平台已经得到真实
统计值。

统一的逻辑展示结果为 `ChunkRenderResult`，至少包含：

| 字段 | 语义 |
| --- | --- |
| chunk_id | 来源 chunk。 |
| row_id | 目标 row。 |
| label | 行标签。 |
| indent_level | 逻辑行缩进级别。 |
| header_column_id | 目标 header column。 |
| cell_text | 最终非缺失字符型 cell 文本。 |

每个 row/header column 组合恰好一行；label row 对每个展示列输出空字符串。analysis
不拼接 cell text，render 按 `cell_format` 对每个 statistic 独立格式化后替换
placeholder。不可估计的 statistic 只替换为 `NE`，不使同一 cell 中其他 statistic
失效；`n` 使用无小数位整数，其他可估计值使用 `resolved_digits`、`ROUND`、`PUTN`、
固定小数位和尾随零，literal `%` 保持原样。

hierarchical result 在公共 statistic 字段上增加 `analysis_id`、`group_path` 和
`node_key`；hierarchical render row 增加 `runtime_row_id`、`row_role`、动态 label、
`indent_level` 和各 header column 的 `cell_text`。这些运行时值不写回 YAML，不替代
metadata position ID。所有 statistic/render 对象均只存在于 SAS `WORK` 的生成期对象中。

最终组装时，hierarchical render 的 `row_sequence` 是当前 container 按最终展示
顺序生成的连续行号，不沿用 nested block 的局部行号。同一动态逻辑行的所有 Header
columns 共享一个行号；不同节点或 block 的行即使 row_id/label 相同也不得合并。
table assembly 以 `chunk_order` 和 `row_sequence` 限定一条宽表行；跨 chunk 的行号
可以重新从 1 开始。该修复的责任边界与验收见当前项目 P0-12。

## 9. 四类 Chunk 模型

四类 chunk 的分析意图、数据粒度、merge 顺序、analysis/render 边界和 SAS emitter
微契约均已确认；以下字段是声明式输入。

### 9.1 continuous_summary

~~~yaml
id: demog_001
type: continuous_summary
source_data: ADAM.ADSL
filter: 'not missing(AGE)'
analysis_variable: AGE
rows:
  - id: demog_001_001
    type: analysis
    label: Mean (SD)
    statistics:
      - id: mean
        digits: 1
      - id: sd
        digits: 1
    cell_format: '{mean} ({sd})'
~~~

字段和语义：

- analysis_variable 是待分析的 SAS numeric variable。
- 支持的 statistic ID 为 n、mean、sd、median、q1、q3、min、max。
- 首期目标分析粒度固定为 subject，subject key 固定为 USUBJID；平台不读取数据
  验证该前提。
- n 表示当前 header column 中 analysis variable 非缺失的唯一 subject
  数。
- mean、sd、分位数、min、max 通常排除 SAS numeric missing values。
- sd 表示 sample standard deviation；分母为 n-1。
- 同一个 subject 出现多条记录时，平台不自动取第一条、最大值或平均值。调用方
  必须在外部准备符合预期粒度的数据，或在 custom before 中明确整理。

emitter 固定使用 `PROC MEANS` 生成上述统计量；不显式设置 `PCTLDEF`，直接采用
SAS 默认的 percentile definition。missing、n=0、n=1、rounding、digits 和最终字符
cell 的字段类型按 P0-8 的 emitter contract 处理。

### 9.2 categorical_summary_nonexclusive

~~~yaml
id: demog_002
type: categorical_summary_nonexclusive
source_data: ADAM.ADSL
filter: 'not missing(SEX)'
denominator:
  type: non_missing
  variable: SEX
rows:
  - id: demog_002_001
    type: analysis
    label: Female
    condition: 'SEX = "F"'
    statistics:
      - id: n
      - id: pct
        digits: 1
    cell_format: '{n} ({pct}%)'
~~~

字段和语义：

- denominator.type 为 header_population、non_missing 或 custom。
- non_missing 需要 variable；custom 需要 SAS expression。
- analysis row 的 condition 定义分子。
- 多个 row condition 可以命中同一个 counting unit；该类型不要求互斥。
- 支持 n 和 pct。通常 pct = 100 * numerator / denominator。
- header_population 使用当前 header column 的 population subjects；non_missing
  和 custom 在 filtered source 上构造分母。
- denominator 为零时，已确认 `n=0`、`pct` 为 not estimable，最终显示为 `NE`；具体
  SAS 字段和 DATA/PROC 实现按 P0-8 的 emitter contract 生成。

SAS emitter 按 P0-8 的 DATA step/PROC 实现 denominator、subject counting unit、
百分比精度和字符格式。平台不读取数据，也不检查 numerator 是否超过 denominator。

### 9.3 categorical_summary_exclusive

~~~yaml
id: demog_003
type: categorical_summary_exclusive
source_data: ADAM.ADSL
denominator:
  type: header_population
rows:
  - id: demog_003_001
    type: analysis
    label: Complete
    condition: 'STATUS = "COMPLETE"'
    statistics:
      - id: n
      - id: pct
        digits: 1
    cell_format: '{n} ({pct}%)'
~~~

该类型复用 nonexclusive 的 denominator、n/pct 和 row 字段，差异是业务声明
要求各 analysis row 对 counting unit 互斥。生成器/emitter 必须生成按此契约工作的
SAS overlap guard；平台不执行或校验数据，重叠异常只会在调用方执行生成的 SAS 时
以 `WARNING: [USER] ...` 暴露，不自动中止或修复。未命中任何 row 的 counting unit
允许存在。

独立使用时首期 subject-level counting identity 固定为 `USUBJID`；若嵌入
hierarchical block，`counting_unit` 由 block 显式声明为 `record`、
`distinct_subject` 或 `distinct_key`，并在需要时提供 `distinct_key`。

### 9.4 hierarchical_summary

hierarchical_summary 是分组和布局容器，不重复实现 continuous/categorical
统计。它在动态分组节点上调用一个已注册的 primitive analysis block。

~~~yaml
id: ae_001
type: hierarchical_summary
source_data: ADAE
filter: 'not missing(SOC)'
source_contract:
  grain: record
  subject_key: USUBJID
  record_key: [USUBJID, AESEQ]
  duplicate_policy: error
levels:
  - id: ae_001_level_001
    variable: SOC
    label_variable: SOC
    order_variable: SOCN
    order_direction: asc
    node_role: label
    missing_policy: exclude
analysis_blocks:
  - id: ae_001_analysis_001
    anchor_level: ae_001_level_001
    placement: below
    type: categorical_summary_nonexclusive
    counting_unit: distinct_subject
    denominator:
      scope: header_population
      unit: distinct_subject
    rows:
      - id: ae_001_analysis_001_row_001
        type: analysis
        label: Subjects
        condition: '1'
        statistics:
          - id: n
        cell_format: '{n}'
~~~

#### Source contract

| 字段 | 语义 |
| --- | --- |
| grain | subject、record 或 observation。 |
| subject_key | 通常为 USUBJID。 |
| record_key | record/observation grain 的逻辑 key 字段序列。 |
| duplicate_policy | 重复 key 违反 contract；当前 contract 固定为 `error`，但生成的 SAS 以
  `WARNING: [USER] ...` 记录，不自动去重或聚合。 |

这些字段告诉 SAS emitter 应按何种粒度生成排序、连接和计数代码。平台不读取
数据、不检查 key 是否存在或重复；duplicate policy 由生成的 SAS 以非阻断 warning
实现，调用方负责根据 log 判断结果。

#### Grouping level

| 字段 | 语义 |
| --- | --- |
| variable | 分组值变量。 |
| label_variable | 展示标签变量；缺省可使用 variable。 |
| order_variable | 必填的默认排序变量；非缺失 group value 必须有对应排序值。 |
| order_direction | 必填的默认排序方向，只能为 asc 或 desc。 |
| result_sort | 可选的统计结果驱动排序 mapping，结构见下文；声明后覆盖展示顺序但不删除默认排序字段。 |
| node_role | label 或 analysis。 |
| node_analysis_id | node_role 为 analysis 时引用 same-row block。 |
| missing_policy | exclude、label 或 error 的业务意图。 |
| missing_label | missing_policy 为 label 时的展示标签。 |

levels 按 sequence 形成父子层级。一个 level 最多一个 same-row block，可以有
多个 below block；默认输出顺序为：

~~~text
当前节点行
  -> 当前 level 的 below 静态分析行
  -> 下一级动态子节点
~~~

`result_sort` 仅引用当前 level 的 analysis block，避免父子 level 形成循环依赖：

~~~yaml
result_sort:
  metric:
    analysis_id: hierarchy_001_analysis_001
    row_id: hierarchy_001_analysis_001_row_001
    statistic_id: n
  column_order: [5, 4, 3, 2, 1, 0]
  direction: desc
~~~

`column_order` 是按 header `display_order` 排序后的 1-based 位置序列；`0` 表示
当前节点 label，最多出现一次且只能位于末尾。正数不能重复或越过当前列数。
排序比较 raw statistic value，NA/NE 排在有效值之后；label tie-break 使用稳定、
不依赖 locale 的 Unicode 大小写不敏感升序。

#### Analysis block

| 字段 | 语义 |
| --- | --- |
| anchor_level | 分析挂接的 level。 |
| placement | same_row 或 below。 |
| type | 三个 primitive 之一。 |
| counting_unit | record、distinct_subject 或 distinct_key。 |
| distinct_key | counting_unit 为 distinct_key 时使用的字段序列。 |
| analysis_variable | continuous block 的 numeric variable。 |
| denominator | categorical block 的显式分母声明。 |
| rows | block 内有序静态行。 |

continuous block 的 `counting_unit` 固定按以下语义 materialize 分析输入：

- `record`：每条 anchor node/header column 内的 source record 独立进入分析；numeric
  missing 由 SAS continuous procedure 按缺失值处理，不执行去重；
- `distinct_subject`：在每个 anchor node/header column/`USUBJID` 内至多保留一个
  非缺失 `analysis_variable`。一个非缺失值加任意数量缺失值时使用该唯一非缺失值；
  全部缺失时该 unit 贡献一个 missing analysis value；两个或更多非缺失记录是运行期
  contract failure；
- `distinct_key`：与 `distinct_subject` 相同，但 counting-unit identity 使用
  `distinct_key` 声明的 typed SAS 字段序列。

continuous unit 冲突不得通过 `FIRST.` 选择、最大值、最小值、平均值或其他隐式聚合
解决。生成的 SAS 写入稳定的
`ERROR: [USER] continuous_unit_multiple_values ...` 并终止当前 SAS 提交；调用方需要在
`custom_code.before` 或外部数据准备中派生唯一分析记录。

hierarchical categorical block 的 denominator 可声明：

~~~yaml
denominator:
  scope: header_population | current_group | non_missing | custom
  unit: record | distinct_subject | distinct_key
  variable: <required for non_missing>
  expression: '<required for custom>'
~~~

scope 表示生成代码应使用的业务范围，不由 generator 隐式推断。层级排序、
动态节点发现、record-to-subject 广播和最终单 stub row 的 SAS 实现按 P0-8 的
hierarchical emitter contract 执行。

## 10. SAS 表达式与缺失值语义

所有 metadata expression 都必须写成目标 SAS dialect 的表达式。推荐以 DATA
step WHERE/IF 可接受的语法为基准：

| 意图 | SAS 示例 |
| --- | --- |
| 字符比较 | TRT01A = "Placebo" |
| 数值比较 | AGE >= 65 |
| 逻辑与 | SAFFL = "Y" and SEX = "F" |
| 逻辑或 | SEX = "F" or SEX = "M" |
| 逻辑非 | not missing(AGE) |
| 无条件 | 1 |
| 自定义缺失分母 | not missing(AVAL) |

### 10.1 缺失值约定

- SAS 字符缺失通常是空白字符串。
- SAS 数值缺失包括普通缺失 .、下划线缺失 ._ 和特殊缺失 .A 至 .Z。
- missing(variable) 是判断字符或数值缺失的推荐表达式。
- SAS 数值缺失参与比较时有其自身排序规则；如果业务意图是“非缺失值”，
  必须显式写 not missing(variable)，不能依赖比较结果排除缺失。
- 连续统计通常排除缺失值；分类 row condition 返回缺失时通常不进入分子。
- denominator 为零的 categorical cell 使用 `n=0` 与 `pct` not estimable，并在 render
  中显示为 `NE`；其他统计量不可估计或 source 没有符合记录时，按对应 emitter contract
  生成 SAS numeric missing/`NE` 结果。平台只生成相应代码，不读取数据或执行代码。

表达式是 opaque SAS source text。平台不把 TRUE、NA、!is.na(x)、== 等其他语言
写入生成的 SAS 程序，也不尝试把其他语言表达式自动翻译成 SAS。

### 10.2 SAS 代码注入边界

表达式和 custom code 最终会进入生成的 SAS 程序。平台不限制 DATA step/PROC 语句、
`%INCLUDE`、宏定义、`X`、`SYSTASK`、`FILENAME PIPE` 或其他 SAS 作用，也不对
source text 做语法、安全、转义或可执行性验证；平台只负责按约定原样拼接源代码，
调用方负责执行环境和运行结果。

对于 emitter 能够在 SAS 内部检查的重复 key、subject cardinality、exclusive overlap
或排序一致性异常，生成代码可以使用 `PUTLOG` 输出确定性的
`WARNING: [USER] ...`。这些 warning 不由应用捕获或持久化，也不隐式改变输入数据。

## 11. 内存工作区模型

建议的工作区由以下对象组成：

~~~text
MetadataWorkspace
  ├─ schema_version
  ├─ populations
  ├─ headers
  ├─ tables
  ├─ templates
  ├─ active_draft
  ├─ import_status / parse_diagnostic
  └─ revision

UI-owned ViewState
  ├─ current_view
  ├─ selected_object / active_table
  ├─ pending_operation
  └─ source_preview
~~~

### 11.1 Workspace 对象职责

| 对象 | 职责 |
| --- | --- |
| populations | 保存 population 对象集合及其顺序。 |
| headers | 保存 header、columns 和 spanning header。 |
| tables | 保存 table 引用和 custom SAS code。 |
| templates | 保存 template、chunk、level、block 和 row。 |
| active_draft | 保存一个正在编辑对象的 base value、draft value、dirty 状态和 draft base revision。 |
| parse_diagnostic | 记录最近一次 bundle 传输/解析/结构解码错误项；不记录数据分析结果、生成错误或运行结果。 |
| revision | 保存 `saved_revision` 与 `draft_base_revision`；只用于当前 session 的 dirty guard 和状态展示。 |

工作区不包含 study、roots、source_files、dataset_paths、artifact_paths、SAS
数据集内容、SAS 执行状态或 AI state。

### 11.2 后端职责

后端应提供与 UI 无关的内存操作：

- 创建空工作区；
- 从 bundle bytes 导入工作区；
- 返回 `BundleImportResult` 和稳定、有序的 `ErrorItem`，不把失败的候选 workspace
  部分写入当前 workspace；
- 获取、创建、更新、删除 population/header/table/template；
- 对 template 中的 chunk、level、analysis block 和 row 做新增、删除、移动和
  位置 ID 重编号；
- 将工作区导出为 bundle bytes；
- 根据 table ID 解析引用并生成 SAS source text。

导入失败只更新 `parse_diagnostic` 侧状态；生成器是纯内存操作，生成前置失败返回
`ErrorItem` 列表且不修改 workspace、draft 或文件。Save 的结构错误使用同一
`ErrorItem` 形状并将 `stage` 设为 `workspace`。

这些操作只需要处理导入解析失败、对象 ID 缺失或引用无法定位等前置错误，
不提供独立 validation API；它们不读取数据、不执行 SAS、不做变量/重复/key/
统计正确性检查。

## 12. UI 契约

UI 使用 Shiny，保留现有编辑形式，但所有数据来自 MetadataWorkspace 和 draft，而不是
物理文档。

### 12.1 Population editor

- 左侧 population 列表；
- New/Delete；
- id、label、expression 表单；
- Save 只更新内存 workspace；
- expression 输入使用 SAS 语法提示。

### 12.2 Header editor

- 左侧 header 列表；
- New/Delete；
- id、source_data 表单及必选的 Page orientation（portrait/landscape）；
- columns 表格编辑 id、label、condition、display_order、width、
  alignment；
- spanning header label 可以继续通过相邻 column label 推导；
- source_data 输入是 SAS 数据集引用，不是文件路径；
- 保存后只更新内存 header 对象。

### 12.3 Table editor

Table editor 只显示：

- table ID；
- Population 下拉选择；
- Header 下拉选择；
- Template 下拉选择；
- custom_code.before SAS text area；
- custom_code.after SAS text area；
- Save。

不显示也不保存 orientation、titles、footnotes、page header/footer、roots、
study 或 artifact path。

### 12.4 Template/chunk editor

- 左侧 template 列表；
- template ID、stub header；
- chunk card 按 registry 渲染公共字段和专属字段；
- primitive chunk 编辑 source_data、SAS filter、analysis variable 或
  denominator；
- hierarchical chunk 编辑 source contract、levels、analysis blocks 和
  nested rows；
- rows 支持 label/analysis、SAS condition、statistics、digits、cell format；
- chunk、level、block、row 支持新增、删除、上移、下移；
- 位置 ID 由 sequence 自动重编号，不能手工改写；
- UI 不把动态 group values 写回 metadata。

### 12.5 全局导入、下载和生成

- Import metadata：上传一个 bundle 文件并替换当前工作区；
- Download metadata：下载当前内存快照；
- Generate SAS：选择 table，返回 SAS source text；
- Download SAS：将 source text 保存为 .sas 文件；
- 不提供 Run SAS、查看运行结果或 AI 按钮。

### 12.6 Draft 与导航

- 一个 session 可以维护一个 active draft；
- draft dirty 时切换对象、导入或清空工作区应提示 Save/Discard；
- Save 将 draft 应用到内存 workspace，不写磁盘；
- Import 成功后清空旧 draft 和选择状态；
- Download 不改变 dirty 状态；
- Generate 只使用当前已保存到 workspace 的值；dirty draft 必须先 Save，不能
  直接生成。

### 12.7 UI 与 Core 边界

`app.R` 只负责启动 Shiny。UI server 读取上传 bytes、调用 core、更新 reactive
`ViewState`、展示 `ErrorItem` 并创建下载 handler；core 不接收 `session`、`input`、
`output`、`reactiveVal`、上传临时路径或下载路径。

UI-owned `ViewState` 至少包含当前 view、selected object/active table、待处理的
Save/Discard/Cancel 操作和 source preview 状态；这些值不写入 YAML。每个 Shiny
session 独占一个 `MetadataWorkspace`，不使用跨 session 的全局 workspace 或共享
可变 metadata。

UI/core 只传递显式值对象：`ImportRequest` 只含 bundle bytes；成功的
`BundleImportResult` 提供候选 workspace；`GenerationRequest` 只含已保存 snapshot、
table ID 和 registry；生成成功返回 source text，UI 再构造
包含文件名、MIME 和内存内容的 `DownloadPayload`。core 不创建、读取、替换或删除
用户文件。

Import、清空 workspace、切换编辑对象或 active table 时，dirty draft 统一提示
`Save / Discard / Cancel`。Save 成功后继续原操作，失败保留 draft，Discard 后继续，
Cancel 不变更 workspace。Download metadata 始终导出最近一次已保存 snapshot；
Generate SAS 必须先 Save。

revision 使用 `saved_revision` 和 `draft_base_revision`：空 workspace 的 saved
revision 为 0，没有 draft 时 draft base 为 null；成功 Import/Save 递增 saved revision，
draft 编辑不递增，Discard、Cancel 和失败操作不改变 saved revision。Save 结构错误
复用第 3.3 节的 `ErrorItem`，`stage` 为 `workspace`；不执行 SAS、不求值表达式、
不读取数据。

## 13. SAS 代码生成数据流

~~~text
创建空 workspace 或上传 metadata bundle
  -> 解析 bundle 为内存对象
  -> UI 编辑 draft
  -> 将 draft 保存回内存 workspace
  -> 选择 table
  -> 解析 population/header/template 引用
  -> 生成 SAS source sections
   1. table.custom_code.before
   2. population selection
   3. header column membership
   4. template chunks（按 sequence）并按兼容性分成分析 batch
   5. 每个 batch 的规范化输入与一次类型专属分析过程
   6. 按 template/chunk/row/header 顺序 render、Table assembly / cell formatting
   7. table.custom_code.after
  -> 返回 SAS source text
  -> 用户预览或下载 .sas
~~~

### 13.1 生成器输入

生成器只需要：

- 一个已保存的 MetadataWorkspace snapshot；
- 目标 table_id；
- 四类 chunk 的 registry/emitters。

它不需要数据 bytes、数据路径或 study roots。

### 13.2 生成器输出

必需输出只有：

~~~text
SAS source text
~~~

可选的 section map、source line map 或生成失败上下文只能作为内部内存返回值，
不属于产品输出，也不写入 metadata bundle。除非另行批准，平台不生成 provenance
comment、manifest、RTF、HTML、SAS 日志或执行结果。系统只在关键数据操作阶段前加入
简短、确定性的 English operation comment；用户提供的 custom code 保持原样。

### 13.3 SourceSection 与 Emitter Contract

generator 先将各阶段输出组织为内部 `SourceSection`，每个 section 至少包含：

| 字段 | 语义 |
| --- | --- |
| section_id | 当前生成程序内唯一的 section 身份。 |
| kind | custom、population、header、chunk 或 assembly。 |
| owner_id | 负责该 section 的 table/chunk/analysis identity。 |
| sequence | 确定性的源代码顺序。 |
| text | 原样 SAS source text。 |

每个代码注册的 `ChunkTypeDefinition` 至少声明：

- type/capability（primitive 或 container）；
- allowed/required metadata fields；
- data grain、source/filter 和 merge contract；
- analysis/render contract；
- source emitter 绑定；
- 生成的中间对象名称、输入、输出和生命周期。

emitter 只能返回自己的 source fragment 和声明的 logical result，不读取 YAML、不访问
物理路径、不执行 SAS，也不通过未声明的共享 dataset mutation 传递状态。具体 PROC、
DATA step 和临时对象命名是 emitter 实现细节，不写入 metadata。

#### PrimitiveBatchPlan 与专用规范化输入

`PrimitiveBatchPlan` 只存在于生成期间，至少保存 `batch_order`、`chunk_type`、有序
`chunk_orders`、`input_dataset` 和 `raw_dataset`；continuous batch 另外保存
`precision_dataset`。`batch_order` 按 template 中首个 chunk 的出现顺序确定。

continuous batch 的规范化输入至少包含：

| 字段 | 语义 |
| --- | --- |
| `chunk_order` | 原 template 中的 chunk 顺序身份。 |
| `column_order` | header `display_order` 的 1-based 列位置。 |
| `analysis_value` | 当前 chunk analysis variable 映射后的 numeric value。 |

每个 chunk 先独立完成 source/filter、重复 key warning 和 scaffold merge，再写入上述
输入。precision input 至少保存 `chunk_order` 与 `analysis_value`，只包含至少命中一个
展示列的 subject；同一 subject 属于多个列时只参与一次该 chunk 的 `base_digits`。
兼容 continuous chunk 通过一次 `PROC MEANS` 按 `chunk_order`/`column_order` 分组
分析 `analysis_value`，raw output 再映射回原 chunk/row/column/statistic identity。

categorical batch 的规范化输入至少包含：

| 字段 | 语义 |
| --- | --- |
| `chunk_order` | 原 template 中的 chunk 顺序身份。 |
| `row_order` | `0` 表示 denominator event，正数表示 analysis row。 |
| `column_order` | header `display_order` 的 1-based 列位置。 |

每条记录表示一个 counting event；各 chunk 的 filter、denominator、row condition 和
counting unit 在规范化阶段处理。`categorical_summary_nonexclusive` 与
`categorical_summary_exclusive` 分别形成自己的 batch，并各自只调用一次 `PROC FREQ`。
expected-cell skeleton 负责补回零计数；分母为零时 `n=0`、`pct` 为 not estimable，
最终显示为 `NE`。规范化数据集和 raw 数据集使用确定性的 `_TFL_` 类型/序号命名并
位于 `WORK` 库；用户 ID 不进入物理名称。

### 13.4 Chunk 生成顺序与 Table 内批处理

1. 先生成 population/header 相关的 subject membership 逻辑；
2. 按 `template.body.chunks` 的 sequence 读取顶层 chunk，并为每个 chunk 独立生成
   `source -> filter -> filtered source -> type-specific merge` 规范化步骤；
3. 对 type、grain、counting unit、merge/cardinality、输入值类型以及 analysis/render
   语义兼容的同类 primitive chunk，按首次出现顺序组成 batch。每个 chunk 的 source
   和 analysis variable 不同并不妨碍合批，但必须先映射为共同的 batch analysis 维度，
   并保留 chunk/row/header/statistic identity；不兼容 chunk 分入不同 batch；
4. 一个 continuous batch 生成一次 `PROC MEANS`，一个 categorical batch 生成一次
   `PROC FREQ`。批处理只复用过程调用，不改变每个 chunk 自己的 denominator、row
   condition、counting unit、digits、`NE` 或 warning 契约；
5. `hierarchical_summary` 不跨 container 合批。其动态节点发现与 node scope 保持独立；
   同 container、同 anchor level、sequence 相邻且 counting unit、typed distinct_key
   与 continuous definition 兼容的 continuous blocks，按 P0-11 共用一次 PROC MEANS。
   各 block 独立完成 counting-unit materialization、precision、expected-cell 和
   raw/precision join；共享分析使用 analysis_order/node_key/column_order 身份，
   raw 仍拆回原 block namespace。P0-13 仅将完成关联后的 value/digits 转换共用
   一次 DATA step，通过输入 IN 标志输出到各 block 原有 STAT。随后继续逐 block
   render 与布局映射；不增加共享结果表或 SAS 宏。其他 blocks 独立调用 primitive；
6. 分析完成后将 long-form logical result 转为 render rows，并继续按原 template/chunk/
   row/header sequence 组装最终 table；批次的执行顺序不得改变可见输出顺序；
7. 最后插入 `custom_code.after`。

不同 chunk 不应通过隐式修改共享数据集互相传递状态。原始 `source_data` 不直接做无
条件 `SET`；各 chunk 必须先由 emitter 生成显式规范化对象。批次输入、输出、临时对象
名称和生命周期由 SAS emitter contract 明确，不能用隐式类型转换、去重或聚合强行合批。

### 13.5 错误与可复现性

生成器不计算或输出 `GenerationProvenance`、metadata hash 或 binding profile。成功
source 只包含系统生成的 SAS code、关键数据操作的简短 English operation comments
和用户提供的 custom code；SAS source 不包含 provenance comment、sidecar 或 manifest，
也不生成持久化日志或结果文件。相同的 canonical snapshot、registry 和 generator contract 应生成相同的
source。生成前置失败时不返回部分 source；SAS 执行期间的 `WARNING: [USER] ...` 只
写入调用方的 SAS log。

## 14. 四类 SAS Emitter 实施契约矩阵

以下清单用于实现和回归测试；具体 SAS 语句和内部物理对象已在 P0-8 冻结为
code-owned 实现，不成为用户 YAML 契约：

| Chunk | 已确认的 SAS 实现 | 已确认的 logical output |
| --- | --- | --- |
| continuous_summary | `PROC MEANS` 默认 percentile、兼容 batch 的规范化输入（`chunk_order`/`column_order`/`analysis_value`）、排序、subject 去重假设、mean/sd、missing、digits/rounding | 每个 row × header column 的 numeric/raw 和字符 cell 字段；batch identity 不改变 logical-cell identity |
| categorical_summary_nonexclusive | `PROC FREQ`、兼容 batch 的规范化输入（`chunk_order`/`row_order`/`column_order`）、denominator、分子条件、n/pct、百分比 scale、missing | numerator、denominator、n、pct 和最终 cell 字段；batch identity 不改变 logical-cell identity |
| categorical_summary_exclusive | `PROC FREQ`、兼容 batch 的规范化输入（`chunk_order`/`row_order`/`column_order`）、按 typed counting unit 生成非阻断 overlap guard 和固定字段顺序的 `WARNING: [USER] ...` | 同上，以及 counting unit 语义 |
| hierarchical_summary | 动态节点发现、排序、record grain、嵌套 primitive、行展平 | group path、indent、row order、header cells 的字段结构 |

实现不得根据 YAML 注入 handler，也不得把 PROC、percentile definition 或物理临时
表名反向写入 metadata；应以已确认的业务语义和 focused source regression tests
锁定每个 emitter 的实现。

## 15. 启动前的确认清单

P0-1 至 P0-8 已完成启动前设计确认。emitter 实现使用 P0-1 已锁定的 R/YAML 工具
链和无新增运行时依赖的 SAS 基础 DATA step/PROC；后续按 `plans/implementation-plan.md`
的 DAG 实施，并以 P0-8 的 source regression fixture 作为 gate。
