# SAS 描述性分析代码生成：Metadata 模型、Chunk 契约与内存工作区

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
- UI 技术栈继续使用 Shiny；population、header、table、template 的 UI 继续采用现有的编辑形式：
  列表、新建、删除、表单、嵌套行编辑、顺序调整和 dirty draft。
- 系统不包含 AI candidate、AI agent、retry、capability 或 AI review。

### 1.2 本文刻意不替实现决定的内容

以下内容仍需在实现中单独确认，本文只提供待确认的边界；本项目已批准的
bundle YAML、sequence 和导入替换语义记录在 `docs/design-decisions.md`：

- 外部 SAS 数据集引用的精确写法（例如 LIBREF.MEMBER、宏变量或绑定名）；
- 四类 chunk 的 SAS emitter、PROC 选择、中间数据集字段和最终输出字段；
- 分位数方法、四舍五入、格式化和不可估计值的具体 SAS 实现；
- cell_format 是生成字符型 cell 数据集、PROC REPORT 代码，还是两者都生成；
- 是否需要生成 ODS/报表代码。本文默认只返回 SAS 源码，不生成报告文件；
- 是否需要在 UI 中保留单 stub/层级布局限制。它不是 SAS 代码生成的必然限制。

### 1.3 明确不属于系统职责

- 上传、解析、检查或缓存 SAS 数据集；
- 读取数据字典、确认变量真实存在或推断变量类型；
- 执行 SAS 表达式、运行 SAS、检查日志或验证分析结果；
- 生成其他语言程序、RTF、reporter artifact、运行结果或结果审计文件；
- 维护 study 根目录、metadata 文件路径、程序输出路径；
- 自动修复重复 key、缺失 key、重叠分类或重复观测；
- 自动推断统计方法、分母或业务规则。

导入只需要最小的文件解析能力；若 bundle bytes 无法解析，导入可以返回传输/解析
失败。生成器也可以因为缺少必要的结构字段或无法解析对象引用而返回生成前置
失败。这些不是独立的 validation API，也不执行 SAS 语法或数据检查。

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

## 3. 单一 Metadata Bundle 文件

建议使用一个文件承载整个可编辑工作区。下面的 YAML 是逻辑示例，不绑定具体
文件扩展名，也不包含数据集内容：

~~~yaml
schema_version: 1

populations:
  - id: safety
    label: Safety population
    expression: 'SAFFL = "Y"'

headers:
  - id: treatment
    source_data: ADAM.ADSL
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

### 3.1 Bundle 顶层字段

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| schema_version | integer | bundle 格式版本；实现应固定并在导入时识别。 |
| populations | sequence 或 mapping | 可复用 population 定义。 |
| headers | sequence 或 mapping | 可复用 header 定义。 |
| tables | sequence 或 mapping | table 定义；table 是生成入口。 |
| templates | sequence 或 mapping | 可复用 template 定义。 |

bundle 不包含 datasets、数据文件、数据路径、study 根目录、生成目录、运行
结果、日志或 AI 状态。

### 3.2 导入与下载

- **导入**：UI 接收一个 bundle 文件，读取其内容并构造新的
  MetadataWorkspace。当前项目采用原子整体替换：只有整个 YAML bundle 成功
  解析后才替换当前工作区；失败时保留旧工作区；合并导入不在当前契约内。
- **编辑**：所有修改先进入当前 session 的 draft，再写回内存工作区；不写入
  物理 metadata 文档。
- **下载 metadata**：将当前内存工作区按 canonical YAML serialization 编码为
  一个 `.yaml` bundle 文件。下载内容不包含临时上传路径、session ID 或 UI 状态。
- **下载 SAS**：选择一个 table 后，生成器返回 SAS source text，UI 将其作为
  .sas 文件下载或显示预览。
- **会话边界**：浏览器/session 结束后，未下载的内存修改可以丢失；是否增加
  服务端持久化不属于当前契约范围。

上传控件产生的临时服务器文件名只能是传输适配器的内部细节，不能写入
MetadataBundle、任何对象字段或导出的文件。

当前项目的 canonical YAML profile 为 UTF-8、无 BOM、LF 换行、两空格缩进、
固定字段顺序和原有 sequence 顺序；单行字符串使用 single-quoted scalar，
多行 custom code 使用 literal block scalar；缺省可选字段不输出为 `null`。

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

默认语义（仍需确认）是：population expression 在 header 使用的 subject source
上求值，以便构造后续 header membership。实现必须确认是否保留这一语义；
如果 population 可以来自独立 SAS 数据集，应新增明确的 source_data 字段，
而不是隐式读取另一个对象。

平台将 expression 当作 SAS source text 传递给 generator，不执行、不翻译、不做
SAS parser 校验。表达式中引用的变量、格式和数据集由调用方保证。

## 5. Header 模型

~~~yaml
id: treatment
source_data: ADAM.ADSL
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
| source_data | string | 外部 SAS 数据集引用；不表示上传文件或物理路径。 |
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
列。`display_order` 必须在当前 header 内唯一、从 1 开始连续；保存时 columns
sequence 与 display order 一致，不按 ID 自动排序。`spanning_header_1` 只能引用
level 1，`spanning_header_2` 只能引用 level 2；同一 spanning header 引用的列在
最终顺序中必须连续。Overall 一类的无条件列使用 SAS 表达式 `1`，而不是其他
语言的 `TRUE`。

生成器通常需要构造一个逻辑 header membership 数据集，至少包含：

~~~text
USUBJID | header_column_id
~~~

这里的字段名和中间数据集名属于待确认的 SAS emitter contract。平台不读取
source_data，也不检查 USUBJID 是否存在、唯一或非缺失。

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
| source_data | string | 外部 SAS 数据集或 custom code 创建的数据集引用。 |
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
集合一致。具体的 SAS PUT、CATX、格式和字符缺失显示方式由 emitter 确认。

digits 支持绝对非负整数以及 `+n`/`-n` 相对精度字符串。continuous 的 relative
digits 使用当前 chunk 实际分析 subjects 的统一 `base_digits`：数值先按最多
15 位有效数字、非科学计数法、去除小数尾零的规则规范化，再计算
`resolved_digits = base_digits + offset`；负 resolved digits 失败，不自动截断。
`n` 不声明 digits，categorical `pct` 只接受非负绝对整数。具体 base_digits
如何从外部 SAS 数值/格式信息取得，以及等价 SAS emitter 实现，仍需确认。

### 8.3 统计结果的抽象表示

虽然平台不执行分析，generator 仍需要为每个 cell 定义目标逻辑字段。建议每个
统计请求至少携带：

| 字段 | 语义 |
| --- | --- |
| chunk_id | 来源 chunk。 |
| row_id | 目标行。 |
| header_column_id | 目标 header column。 |
| statistic_id | 统计量 ID。 |
| value 或 SAS expression | emitter 产生的 numeric/character 结果。 |

这些是生成器内部的抽象，不要求作为文件字段导出，也不表示平台已经得到真实
统计值。

## 9. 四类 Chunk 模型

四类 chunk 的分析意图可直接复用；但每类的 SAS 实现、输出 schema 和精确过程
必须在 emitter contract 中确认。以下字段是声明式输入。

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
- 目标分析粒度通常是 subject，subject key 通常为 USUBJID；这是生成代码的
  业务假设，不由平台读取数据验证。
- n 通常表示当前 header column 中 analysis variable 非缺失的唯一 subject
  数。
- mean、sd、分位数、min、max 通常排除 SAS numeric missing values。
- sd 通常表示 sample standard deviation；分母 n-1 的实现必须由 SAS emitter
  明确。
- 同一个 subject 出现多条记录时，平台不自动取第一条、最大值或平均值。调用方
  必须在外部准备符合预期粒度的数据，或在 custom before 中明确整理。

必须在 emitter contract 中确认：

- 使用 PROC MEANS、PROC SUMMARY、PROC UNIVARIATE、DATA step 或组合；
- q1/median/q3 使用的 SAS percentile definition；
- missing、n=0、n=1 时的输出值和显示文本；
- rounding、digits 和最终字符 cell 的字段类型。

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
- header_population 通常使用当前 header column 的 population subjects；
  non_missing 和 custom 通常在 filtered source 上构造分母。
- denominator 为零时，目标 SAS 结果应为 missing 或项目约定的不可估计标记；
  具体字段和显示方式待确认。

SAS emitter 必须确认 denominator 的 DATA step/SQL 实现、subject 去重方式、
百分比精度和字符格式。平台不读取数据，也不检查 numerator 是否超过
denominator。

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
要求各 analysis row 对 counting unit 互斥。生成器只生成按此假设工作的 SAS 代码；
由于平台不执行或校验数据，不自动加入 overlap 检查。任何额外的数据检查都不
属于当前系统生成的 SAS 源码。

独立使用时 counting unit 通常为 USUBJID。若嵌入 hierarchical block，计数
单位由 block 声明。

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
| duplicate_policy | 重复 key 的处理策略；当前 contract 固定为 error，不自动去重或聚合。 |

这些字段告诉 SAS emitter 应按何种粒度生成排序、连接和计数代码。平台不读取
数据、不检查 key 是否存在或重复，也不执行 duplicate policy。

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

hierarchical categorical block 的 denominator 可声明：

~~~yaml
denominator:
  scope: header_population | current_group | non_missing | custom
  unit: record | distinct_subject | distinct_key
  variable: <required for non_missing>
  expression: '<required for custom>'
~~~

scope 表示生成代码应使用的业务范围，不由 generator 隐式推断。层级排序、
动态节点发现、record-to-subject 广播和最终单 stub/报表布局的具体 SAS 实现，
均属于待确认的 emitter contract。

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
- denominator 为零、统计量不可估计或 source 没有符合记录时，应使用 SAS
  numeric missing 或实现定义的字符标记。平台只生成相应代码，不决定最终显示
  文本。

表达式是 opaque SAS source text。平台不把 TRUE、NA、!is.na(x)、== 等其他语言
写入生成的 SAS 程序，也不尝试把其他语言表达式自动翻译成 SAS。

### 10.2 SAS 代码注入边界

表达式和 custom code 最终会进入生成的 SAS 程序。实现必须确认：

- 是否只允许 DATA step/PROC 内的受限语句；
- 是否允许 %INCLUDE、宏定义、X、SYSTASK、FILENAME PIPE 等外部作用；
- 是否需要对 source text 做转义或静态扫描。

本文不提供安全扫描，也不承诺执行隔离；平台只负责按约定拼接源代码。

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
  ├─ selected_object
  └─ revision
~~~

### 11.1 Workspace 对象职责

| 对象 | 职责 |
| --- | --- |
| populations | 保存 population 对象集合及其顺序。 |
| headers | 保存 header、columns 和 spanning header。 |
| tables | 保存 table 引用和 custom SAS code。 |
| templates | 保存 template、chunk、level、block 和 row。 |
| active_draft | 保存一个正在编辑对象的 base value、draft value、dirty 状态和解析诊断。 |
| parse_diagnostic | 只记录 bundle 传输/解析失败，不记录数据分析结果或 validation 结果。 |
| revision | 可选的内存版本号，用于 dirty guard 或并发 UI 保护。 |

工作区不包含 study、roots、source_files、dataset_paths、artifact_paths、SAS
数据集内容、SAS 执行状态或 AI state。

### 11.2 后端职责

后端应提供与 UI 无关的内存操作：

- 创建空工作区；
- 从 bundle bytes 导入工作区；
- 获取、创建、更新、删除 population/header/table/template；
- 对 template 中的 chunk、level、analysis block 和 row 做新增、删除、移动和
  位置 ID 重编号；
- 将工作区导出为 bundle bytes；
- 根据 table ID 解析引用并生成 SAS source text。

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
- id、source_data 表单；
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
- Generate 使用当前已保存到 workspace 的值，是否允许直接生成 dirty draft
  由实现确认；建议要求先 Save。

## 13. SAS 代码生成数据流

~~~text
创建空 workspace 或上传 metadata bundle
  -> 解析 bundle 为内存对象
  -> UI 编辑 draft
  -> 将 draft 保存回内存 workspace
  -> 选择 table
  -> 解析 population/header/template 引用
  -> 生成 SAS source sections
       1. 外部数据集引用/调用方 setup 占位
       2. table.custom_code.before
       3. population selection
       4. header column membership
       5. template chunks（按 sequence）
       6. Table assembly / cell formatting
       7. table.custom_code.after
  -> 返回 SAS source text
  -> 用户预览或下载 .sas
~~~

### 13.1 生成器输入

生成器只需要：

- 一个完整的 MetadataWorkspace；
- 目标 table_id；
- 四类 chunk 的 registry/emitters；
- 实现约定的外部 SAS binding convention。

它不需要数据 bytes、数据路径或 study roots。

### 13.2 生成器输出

必需输出只有：

~~~text
SAS source text
~~~

可选的 section map、source line map 或生成失败上下文只能作为内部内存返回值，
不属于产品输出，也不写入 metadata bundle。除非另行批准，平台不生成 manifest、RTF、HTML、SAS
日志或执行结果。

### 13.3 Chunk 生成顺序

1. 先生成 population/header 相关的 subject membership 逻辑；
2. 按 template.body.chunks 的顺序生成每个 chunk；
3. hierarchical chunk 在其内部按 levels、analysis blocks 和固定遍历顺序
   生成逻辑行；
4. 将各 chunk 的逻辑结果合并为实现约定的分析/布局数据集；
5. 最后插入 custom_code.after。

不同 chunk 不应通过隐式修改共享数据集互相传递状态。若需要中间数据集，
名称和生命周期应由 SAS emitter contract 明确。

## 14. 四类 SAS Emitter 待确认矩阵

这是实现必须确认的实施清单，而不是本文已经承诺的实现：

| Chunk | 需要确认的 SAS 实现 | 需要确认的输出 |
| --- | --- | --- |
| continuous_summary | PROC/排序、subject 去重假设、mean/sd/分位数、missing、digits/rounding | 每个 row × header column 的 numeric/raw 和字符 cell 字段 |
| categorical_summary_nonexclusive | denominator、分子条件、n/pct、百分比 scale、missing | numerator、denominator、n、pct 和最终 cell 字段 |
| categorical_summary_exclusive | 与 nonexclusive 的差异；是否完全不生成 overlap check | 同上，以及 counting unit 语义 |
| hierarchical_summary | 动态节点发现、排序、record grain、嵌套 primitive、行展平 | group path、indent、row order、header cells 的字段结构 |

确认这些内容后，才可以把抽象 ChunkTypeDefinition 冻结为具体 SAS
emitter registry。不要根据当前文档自行猜测 PROC、percentile definition 或
最终字段名。

## 15. 启动前的确认清单

以下项目确认后，文档才可作为完整的 SAS 生成实施契约：

1. bundle 的 canonical 格式、版本、sequence/mapping 表示和下载扩展名；
2. population expression 的 source scope；
3. 外部 SAS dataset reference 和调用方提供的 libref/macro convention；
4. SAS 缺失值、日期/时间变量、字符比较和 logical expression dialect；
5. 四类 chunk 的 SAS emitter、PROC 选择和中间/最终输出 schema；
6. sd、分位数、n/pct、零分母、missing 和 rounding 的精确定义；
7. cell_format 的 SAS 代码生成方式；
8. hierarchical 的动态行、排序、counting unit 和是否保留单 stub 约束；
9. import 的替换/合并语义、download 的 canonical serialization 和 session
    丢失策略；
10. 传输/解析失败和生成前置引用失败的最小错误返回格式；
11. 是否需要生成 PROC REPORT/ODS 代码，或只生成分析数据集代码。

在上述确认完成前，本文可以作为模型和 UI 设计底稿，但不能被当作已经冻结的
SAS 代码生成实现规范。
