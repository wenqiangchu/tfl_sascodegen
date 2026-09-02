# 设计决策记录

本文记录当前项目中已经获得用户确认的设计决定、被拒绝的替代方案，以及
仍然未决的问题。讨论中的建议不会自动成为批准决定。

## 第 1 组：应用入口、Bundle 导入导出与 SAS 输出

状态：已确认；第 2 项及第 4 项的 serialization 部分于 2026-09-02 根据 ref
对齐请求修订。

### 已批准

1. 使用根目录的薄 `app.R` 作为 Shiny 启动入口；生产代码按职责放在
   `src/` 子目录。
2. Metadata bundle 采用 YAML，`schema_version` 从 1 开始；集合使用有序
   sequence，每个对象显式保存 `id`；下载扩展名为 `.yaml`。
3. 导入是原子替换：只有在整个 bundle 成功解析后才替换当前工作区；传输或
   解析失败时保留原工作区；当前范围不支持 merge 导入。
4. 导出使用稳定字段顺序的 canonical YAML，只包含已保存的工作区，不写入
   上传临时路径、session 信息或 UI 状态。采用 UTF-8、无 BOM、LF 换行、
   两空格缩进；sequence 保持业务顺序；单行字符串使用 single-quoted
   scalar，多行代码使用 literal block scalar；缺省可选字段不输出为 null。
5. SAS 结果的产品边界是源代码文本。下载文件名采用清理后的
   `{table_id}.sas`，并提供源码预览。
6. 当前阶段不生成 ODS、PROC REPORT 或 RTF/PDF/HTML 等报表文件；具体分析和
   布局数据集字段由后续 emitter 子系统确定。
7. 不增加服务端持久化；session 结束时未下载的内存修改可以丢失。

### 被拒绝的替代方案

- JSON canonical bundle：已被 2026-09-02 的 YAML 决定替代；YAML 更适合人工
  阅读和编辑，canonical 规则承担跨实现稳定性。
- 以 ID 为键的 mapping：未采用，原因是 sequence 能直接保留 UI 业务顺序，
  且避免额外的顺序字段。
- 合并导入：未采用，原因是会引入 ID 冲突、引用重写和回滚语义；当前产品
  只需要整体替换。
- 将上传临时文件名或路径写入 bundle：明确拒绝，传输适配器细节不得进入
  metadata。
- 生成报告文件或执行 SAS：明确超出当前产品边界。

### 留待后续子系统确认

- dirty draft 时导入、切换和生成的拦截规则（第 3 组）。
- YAML 解析器的具体 R 包和版本留到实施阶段锁定；不改变上述 canonical profile。
- SAS 数据集绑定约定、emitter 输出 schema 及错误包络（后续子系统）。

## 第 3 组：Session-owned Workspace 与 Draft 生命周期

状态：已确认（2026-09-02）。本组确认普通 R list workspace、单一 active draft、
revision 机制，以及删除影响控制采用方案 A。

### 已批准

1. Workspace 使用普通 R list 表示，由当前 Shiny session 独占；session 内只有一
   个 active draft，并通过 revision 记录已保存 snapshot 与当前 draft 的关系。
2. Save 采用“结构严格、跨对象引用可延迟”：结构、必填字段、ID、discriminator
   等不合格时保存失败；结构合法但暂时无法解析的跨对象引用可以保存。保存失败
   保留原 draft，不自动重试；Save 不执行 SAS，也不求值或验证表达式。
3. dirty draft 存在时，导出只导出最近一次已保存 snapshot；导出不自动保存，也不
   改变 dirty 状态。
4. 删除采用方案 A：删除前展示受影响的引用；被 table 引用的 population、header
   或 template 不允许直接删除；不自动清空或改写引用，用户必须先解除引用。

### 被拒绝的替代方案

- 保存时强制解析并拒绝所有跨对象引用：未采用，以允许分步编辑和先保存结构合法
  的 draft。
- dirty draft 导出时隐式保存：未采用，以避免下载动作改变 draft/revision 状态。
- 删除时自动清空引用或级联改写：未采用，以避免静默改变其他 metadata 对象。

### 留待后续子系统确认

- dirty draft 存在时导入、切换 active table 和生成 SAS 的拦截/提示策略。
- revision 的具体字段、并发模型和 UI 展示细节留到实现阶段；不改变本组的
  单 session、单 active draft 语义。

## 第 4 组：`custom_code.before` / `custom_code.after`

状态：已确认（2026-09-02）。采用方案 A：custom code 被视为调用方提供的、可直接
插入生成程序的 SAS source text；平台不对其内容作任何假设或验证。

### 已批准

1. `TableSpec.custom_code` 是可选 mapping，包含可选的 `before` 和 `after` 字符串。
   非空文本原样保留；空或只含空白的字段按 canonical YAML 规则省略。不得增加
   `before_outputs` 或 runtime result 字段。
2. 生成顺序固定为：外部 SAS binding/caller setup 占位、`before`、population/header
   逻辑、template chunks、table assembly/cell formatting、`after`。`after` 是当前
   产品生成的最后一个 custom section，不再追加系统分析或报表代码。
3. `before` 与 `after` 均在同一个生成 SAS 程序上下文中插入并执行；平台不建立
   sandbox，也不推断或自动加载宏、变量、库、数据集、package 或其他依赖。
4. 平台不限制或假设 custom code 的输入、输出、访问对象、数据集粒度、名称冲突、
   副作用或执行结果。`before` 可以创建、修改或删除对象，`after` 也可以修改、
   替换或删除可见对象；后续 chunk 只有在其自身契约明确引用时才依赖某个名称。
5. 导入阶段只检查字段类型和 bundle 结构，不检查 SAS 语法、静态安全性或可执行性；
   生成阶段只原样拼接文本，不执行 SAS。custom code 引起的运行时失败完全由调用方
   执行 SAS 时处理。

### 被拒绝的替代方案

- 为 custom code 增加声明式输入/输出或 `before_outputs`：未采用，会改变现有字段
  契约并要求平台对代码行为作额外假设。
- 对 custom code 做 AST/语法/安全扫描或放入隔离执行环境：未采用，当前产品只
  生成 SAS source text，不执行或验证 SAS。

## 第 5 组：Population Selection 与 Header Membership

状态：已确认（2026-09-02）。采用方案 A，沿用 ref 的 subject scaffold 数据流；
population 和 header 条件均保留为 SAS source text。

### 已批准

1. 生成的 SAS 程序在所引用 `HeaderSpec.source_data` 上求值
   `PopulationSpec.expression`；PopulationSpec 不增加独立的 `source_data` 字段。
   先应用 population expression，再构造 header membership。
2. Header columns 按 `display_order` 的连续顺序生成。每个 column 的 `condition`
   独立作用于 population 结果；同一个 subject 可以同时属于多个 columns。需要
   Overall 或其他无条件列时，metadata 必须显式提供 SAS expression `1`，系统不
   隐式添加列。
3. 未命中任何 header column 的 subject 不进入 membership scaffold。内部 scaffold
   的最小字段为 `USUBJID` 与 `header_column_id`，同一组合不得重复；它是生成期
   派生对象，不写回 YAML、workspace 或导出 bundle。
4. Population/header expression 原样作为 SAS expression 拼接，采用 SAS 原生逻辑和
   missing-value 语义；平台不执行、翻译、求值、静态检查或语法验证。平台也不读
   `source_data`，不检查 `USUBJID` 的存在、唯一性、非缺失或实际列 membership，
   不做隐式去重或补列；这些前提由调用方和 SAS 执行环境负责。
5. 生成器不修改外部 source dataset；只生成局部的 population/membership/scaffold
   逻辑。header condition 的重叠不是错误，source 中不在 scaffold 的 subject 不
   参与后续 chunk 分析。

### 被拒绝的替代方案

- 为 population 增加独立数据集引用：未采用，以保持 ref 的 `expression` 语义并避免
  引入额外跨数据集身份匹配契约。
- 让 population 和 header 分别在不同 source 上求值：未采用，当前 scaffold 以
  header source 的同一 subject identity 为边界。
- 在应用侧执行、翻译或验证 SAS expression，或自动生成 Overall/去重记录：未采用，
  这些动作超出只生成 SAS source text 的产品边界。

## 第 6 组：Chunk 扩展、数据粒度、Merge、Analysis 与 Render

状态：已确认（2026-09-02）。采用方案 A，冻结 chunk 的业务边界和声明式 registry
职责；具体 SAS PROC/DATA step、中间 dataset 名称和最终输出字段留到第 7 组。

### 已批准

1. `ChunkMetadata` 的公共字段为 `id`、`type`、`source_data`、可选 `filter` 和
   有序 `rows`；类型专属字段由代码注册的 `ChunkTypeDefinition` 声明。YAML 只能
   提供数据，不能注入函数或 handler。
2. `RowMetadata` 保留 `id`、`type`、`label`、可选 `indent_level`、`condition`、
   `statistics` 和 `cell_format`；label row 不请求统计，analysis row 才能声明
   statistics/cell format，分类 analysis row 需要 condition。位置 ID、sequence、
   statistic ID 唯一性和 placeholder 一致性属于结构契约。
3. `continuous_summary`、`categorical_summary_nonexclusive` 和
   `categorical_summary_exclusive` 是 analysis primitive；`hierarchical_summary`
   是 layout/container。container 负责 group discovery、节点遍历、analysis
   placement 和结果展平，不复制 primitive 的统计实现。
4. 首期 subject-level primitive 使用 `USUBJID`；filter 后每个 subject 最多一条
   source record。`hierarchical_summary` 可以显式声明 `subject`、`record` 或
   `observation` grain；后两者必须声明 `record_key`，`duplicate_policy` 固定为
   `error`，不得隐式 distinct、取第一条、取最大值、平均或其他聚合。
5. 所有 chunk 固定遵循 `source -> filter -> filtered source -> type-specific
   merge -> analysis -> render`。filter 只作用于当前 chunk source，先于 merge，
   不修改原始 source，也不影响其他 chunk。分类 row condition 和 denominator
   expression 在对应 filtered source 上、merge 前计算；hierarchical 的 nested
   条件在当前节点 scope 中计算。
6. 首期 primitive 的 subject merge key 为 `USUBJID`，cardinality 为每个 filtered
   subject 一条记录；scaffold 中无 source record 的 subject 保留并按空数据规则
   处理，source 中不属于 scaffold 的 subject 不参与分析。Record/observation
   source 通过 `USUBJID` 广播到 header columns，不为每条 record 重新计算
   population/header membership。
7. categorical non-exclusive 允许多个 row condition 命中同一 counting unit；
   exclusive 是独立 type，要求每个声明的 counting unit 最多命中一个 analysis
   row，但不要求所有 unit 必须命中 row。`counting_unit` 必须显式声明为
   `record`、`distinct_subject` 或 `distinct_key`，不得由实现推断。
8. hierarchical 使用有序 `levels`、`analysis_blocks`、显式 source contract、
   missing policy、`same_row`/`below` placement 和 nested denominator scope；
   动态节点在所有展示 header columns 的联合 eligible source 上发现，static
   analysis 先于 dynamic children，运行时 group value、node key 和 row ID 不写回
   YAML。`order_variable`/`order_direction` 和已确认的 `result_sort` 规则继续有效。
9. Analysis 输出内部 `ChunkStatisticValue`/`HierarchicalAnalysisResult`，负责 raw
   statistic、estimability、statistic identity 和 resolved digits；Render 输出内部
   `ChunkRenderResult`/`HierarchicalRenderRow`，负责 label、indent、row/column order、
   `cell_format` 和 `NE` 文本。两者都不执行 RTF、报表或文件写入，运行期结果不写入
   bundle。
10. 平台不读取 SAS 数据、不执行表达式、不做数据级校验或隐式修复。上述 grain、
    key、cardinality、exclusive overlap 和 counting-unit 规则是 generator/emitter
    必须遵守的业务契约；实际数据错误由生成的 SAS 程序和调用方执行环境处理。

### 被拒绝的替代方案

- 让每个 chunk 自行决定是否先 filter 或 merge：未采用，以保持统一的
  filter-before-merge 顺序。
- 让 hierarchical 复制 continuous/categorical 统计逻辑：未采用，以避免两套统计
  语义漂移。
- 在平台或 generator 中隐式去重、选择记录、聚合或把动态运行值写回 metadata：未
  采用，调用方必须通过显式 source contract 或 custom code 提供所需数据。
- 将 Analysis 与 Render 合并，或让 chunk 直接写报表文件：未采用，以保持统计、
  展示和产品输出边界独立。

## 第 7 组：SAS Source Generation、Section Ordering 与 Emitter Contract

状态：已确认（2026-09-02）。采用方案 A：generator 是只生成 SAS source text 的
纯 host-side 组装器，emitter 由代码 registry 按类型负责；不迁移 ref 的 R 程序、
Rscript、study roots 或报表执行模型。

### 已批准

1. `GenerationRequest` 的输入为 `workspace_snapshot`、目标 `table_id`、代码注册的
   chunk registry/emitters 和外部 SAS binding convention。generator 不接收数据 bytes、
   数据文件路径、study roots、SAS 执行状态或输出 artifact path。
2. host-side 先解析目标 table 的 population/header/template 引用，形成内部的
   `ResolvedTableInput`；引用无法解析属于生成前置失败，具体错误包络留到第 8 组。
   emitter 只接收展开后的普通对象和 opaque SAS references，不读取 YAML 或物理文件。
3. 内部 `SourceSection` 至少携带 `section_id`、`kind`、`owner_id`、确定性顺序和
   `text`；section map/source line map 只允许作为内存调试信息，不写入 bundle，也
   不作为用户下载产物。
4. `ChunkTypeDefinition` 的 code-owned contract 至少声明 type/capability、允许和
   必需字段、输入与 data-grain/merge contract、analysis/render contract、source
   emitter 以及显式中间对象名称和生命周期。不同 emitter 不得通过未声明的共享
   mutation 传递状态；hierarchical container 通过 registry 调用 primitive emitter。
5. 生成 section 的顺序固定为：

   `caller setup/binding placeholder -> custom_code.before -> population -> header
   membership -> template chunks（按 sequence） -> table assembly/cell formatting
   -> custom_code.after`。

   `custom_code.after` 之后不再追加系统分析、报表或其他代码。
6. emitter 生成的内部 logical result 使用已确认的 identity：普通 chunk cell 携带
   `chunk_id`、`row_id`、`header_column_id`、`statistic_id`、raw value、estimable
   和 `resolved_digits`；hierarchical result 额外携带 `analysis_id`、`group_path`
   和 runtime row context。Render 再形成 row/cell text，所有运行期结果不落盘。
7. 对外 `GenerationResult` 只有 SAS source text；UI 再负责预览或以清理后的
   `{table_id}.sas` 下载。generator 不执行 SAS，不生成 R/RTF/PDF/HTML/ODS/PROC
   REPORT，不检查数据或 custom code。
8. 具体 PROC/DATA-step 组合、临时 dataset 的物理命名以及等价 SAS 语句是 emitter
   的实现细节，不进入 YAML，不形成第二套用户可编辑契约；实现必须以第 2、5、6
   组冻结的语义和 focused source regression tests 为准。

### 被拒绝的替代方案

- 用全局 type switch 和直接字符串拼接取代 code-owned emitter contract：未采用，
  会使 section 顺序、类型职责和输出字段分散并容易漂移。
- 把 emitter handler、PROC 名称或临时表名写入用户 YAML：未采用，YAML 只描述
  metadata，不注入实现。
- 在 generator 内执行生成的 SAS，或迁移 ref 的 R runtime/RTF reporter：未采用，
  当前产品交付物只有 SAS source text。

## 第 2 组补充：参考文档对齐与相对精度

状态：已确认（2026-09-02）。用户要求本项目重叠字段的含义与 ref 一致；以下
语义已按该要求冻结，R 生成实现和超出本项目范围的 ref 内容除外。

### 已确认

1. 与 `ref/阶段02-Chunk扩展模型与注册机制.md` 一致，continuous statistic 的
   `digits` 支持非负绝对整数以及 `+n`/`-n` 相对精度字符串；`n` 不声明
   `digits`，categorical `pct` 只接受非负绝对整数。
2. relative digits 使用当前 chunk 实际分析 subjects 的统一 `base_digits`，
   先按 ref 的 15 位有效数字、非科学计数法、去除小数尾零规则解析，再计算
   `resolved_digits = base_digits + offset`；负结果失败，不静默截断。
### 已确认的 ref 对齐语义

1. 沿用 ref 的 precision、统计和显示语义：continuous 使用 sample SD、与 ref R
   quantile type 2 等价的分位数定义、n=0/n=1 边界、非有限值失败、half-away-
   from-zero、固定小数位、尾随零和 `NE`；这些语义必须在 SAS emitter 中实现
   等价结果，而不是复制 R 实现。
2. 沿用 ref 的 chunk 边界：filter 先于 merge；subject-level 首期规则为
   `USUBJID` 且 filtered source 每个 subject 至多一条；analysis 与 render
   分离；categorical nonexclusive 允许 row condition 重叠。
3. 沿用 ref 的 hierarchical 字段含义：有序 `levels`、`analysis_blocks`、
   `source_contract`、显式 `order_variable`/`order_direction`、missing policy、
   `same_row`/`below`、显式 nested denominator、动态值不写回 metadata；新增
   `duplicate_policy: error` 和 `result_sort` 的明确结构。

4. 沿用 ref 的 position-ID 语义：sequence 是事实来源，chunk、level、analysis
   block 和 row 的 ID 在编辑操作后按位置重建；引用随重编号同步更新。
5. 沿用 ref 的 strict discriminator contract：未知字段/未知 chunk type、缺失
   discriminator-specific 字段、重复 statistic ID 和不匹配的 cell placeholder
   属于结构性导入错误；不执行数据检查或表达式求值。
6. 沿用 ref 的 hierarchical `result_sort` 结构：`metric.analysis_id`、
   `metric.row_id`、`metric.statistic_id`、整数 `column_order` 和 `direction`；
   `0` 表示 label 且只能位于末尾，NA/NE 排在有效值之后，比较 raw statistic。

7. 采用 ref 的普通 R list 值语义加类型标记作为解析对象表示；不把 session、
   runtime result 或 source location 写入 metadata。
8. 采用 strict unknown-field 和 discriminator contract；缺失/重复 ID、类型结构
   无法表示、未知 chunk type、重复 statistic ID、placeholder 不一致和
   denominator/level/block 条件不满足时，bundle 导入失败；不自动修复。
9. 可选字段保持缺省；只有已定义语义的缺省值在后续生成/渲染阶段解释，缺省字段
   不序列化为 `null`。
10. Header 的 `display_order` 是列顺序权威；canonical YAML 的 `columns` sequence
    按该顺序规范化，且 spanning header 引用的 columns 必须连续。

### 本决定的适用边界

- 上述决定冻结的是字段和分析语义，不冻结 R 的函数名、包、data.frame 实现
  或 RTF 输出。
- ref 中的 R expression 改写为 SAS expression；平台仍只保存和拼接 source
  text，不执行表达式或读取数据。
- ref 中的 study roots、datasets catalog、磁盘多文件布局、orientation/titles/
  footnotes、R program、Rscript、RTF 和 run artifacts 不进入本项目 bundle 或
  生成产品，除非另行批准。
