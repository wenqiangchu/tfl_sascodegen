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

- dirty draft 时导入、切换和生成的拦截规则已在第 9 组冻结；具体控件布局留到实现阶段。
- YAML parser/toolchain 已在 P0-1 锁定；后续只需在依赖恢复后重跑对应 gate。
- 四类 emitter 的完整输出 schema 和运行期失败处理（后续子系统）；错误包络已在第 8 组
  冻结。

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

### 后续实现边界

- dirty draft 存在时导入、切换 active table 和生成 SAS 的拦截/提示策略，以及
  revision 字段已在第 9 组确认；具体 Shiny 控件布局留到实现阶段，不改变本组的
  单 session、单 active draft 语义。

## 第 4 组：`custom_code.before` / `custom_code.after`

状态：已确认（2026-09-02）。采用方案 A：custom code 被视为调用方提供的、可直接
插入生成程序的 SAS source text；平台不对其内容作任何假设或验证。

### 已批准

1. `TableSpec.custom_code` 是可选 mapping，包含可选的 `before` 和 `after` 字符串。
   非空文本原样保留；空或只含空白的字段按 canonical YAML 规则省略。不得增加
   `before_outputs` 或 runtime result 字段。
2. 生成顺序固定为：`before`、population/header 逻辑、template chunks、table
   assembly/cell formatting、`after`。`after` 是当前
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

1. `GenerationRequest` 的输入为 `workspace_snapshot`、目标 `table_id` 和代码注册的
   chunk registry/emitters。generator 不接收数据 bytes、数据文件路径、study roots、
   SAS 执行状态或输出 artifact path。
2. host-side 先解析目标 table 的 population/header/template 引用，形成内部的
   `ResolvedTableInput`；引用无法解析属于生成前置失败，使用第 8 组的稳定错误包络。
   emitter 只接收展开后的普通对象和 `source_data` 字符串，不读取 YAML 或物理文件。
3. Header 和 chunk 的 `source_data` 是必填的非空字符串，作为 opaque SAS source
   text 原样保留和插入。它可以是 `adsl`、`adam.adsl`、`&ADSL` 或
   `&lib..&member` 等调用方提供的引用；generator 不做 SAS 语法解析、宏变量展开、
   大小写/空白重写，也不检查 libref、member、宏变量、数据集或变量是否存在。
4. 内部 `SourceSection` 至少携带 `section_id`、`kind`、`owner_id`、确定性顺序和
   `text`；section map/source line map 只允许作为内存调试信息，不写入 bundle，也
   不作为用户下载产物。
5. `ChunkTypeDefinition` 的 code-owned contract 至少声明 type/capability、允许和
   必需字段、输入与 data-grain/merge contract、analysis/render contract、source
   emitter 以及显式中间对象名称和生命周期。不同 emitter 不得通过未声明的共享
   mutation 传递状态；hierarchical container 通过 registry 调用 primitive emitter。
6. 生成 section 的顺序固定为：

   `custom_code.before -> population -> header
   membership -> template chunks（按 sequence） -> table assembly/cell formatting
   -> custom_code.after`。

   `custom_code.after` 之后不再追加系统分析、报表或其他代码。
7. 系统在 population selection、header membership、chunk filter/merge、analysis
   和 table render/assembly 等关键数据操作阶段前加入简短、确定性的 English comment。
   注释只说明阶段意图，不逐句注释，不包含 provenance、session、路径或数据内容；
   用户提供的 `custom_code.before/after` 保持原样，不在其内部插入系统注释。
8. emitter 生成的内部 logical result 使用已确认的 identity：普通 chunk cell 携带
   `chunk_id`、`row_id`、`header_column_id`、`statistic_id`、raw value、estimable
   和 `resolved_digits`；hierarchical result 额外携带 `analysis_id`、`group_path`
   和 runtime row context。Render 再形成 row/cell text，所有运行期结果不落盘。
9. 对外 `GenerationResult` 只有 SAS source text；UI 再负责预览或以清理后的
   `{table_id}.sas` 下载。generator 不执行 SAS，不生成 R/RTF/PDF/HTML/ODS/PROC
   REPORT，不检查数据或 custom code。
10. 具体 PROC/DATA-step 组合、临时 dataset 的物理命名以及等价 SAS 语句是 emitter
   的实现细节，不进入 YAML，不形成第二套用户可编辑契约；实现必须以第 2、5、6
   组冻结的语义和 focused source regression tests 为准。

### 被拒绝的替代方案

- 用全局 type switch 和直接字符串拼接取代 code-owned emitter contract：未采用，
  会使 section 顺序、类型职责和输出字段分散并容易漂移。
- 把 emitter handler、PROC 名称或临时表名写入用户 YAML：未采用，YAML 只描述
  metadata，不注入实现。
- 在 generator 内执行生成的 SAS，或迁移 ref 的 R runtime/RTF reporter：未采用，
  当前产品交付物只有 SAS source text。

## 第 8 组：结构性导入错误、生成前置错误与可复现性

状态：已确认（2026-09-02）。采用方案 A：沿用 ref 的稳定错误项和有序错误列表，
但将其适配为单文件 YAML bundle 与只生成 SAS source text 的边界。

### 已批准

1. 导入和生成错误共用最小 `ErrorItem` 形状：

   - `stage`：`import`、`workspace` 或 `generation`；
   - `code`：稳定的机器可读错误代码；
   - `message`：英文、只描述事实，不提供建议；
   - `path`：逻辑字段路径，例如 `$.tables[0].template_id`。

   根级传输或解析错误使用 `$` 作为 path。错误项不包含 warning、suggestion、
   stack trace、服务器临时路径、session 信息、原始数据或不稳定的 parser 文本。

2. `BundleImportResult` 采用 `passed`、候选 `workspace` 和有序 `errors`：

   - bytes 先解析为候选 workspace；只有整体结构成功时才替换当前 workspace；
   - YAML 解析失败、编码失败或无法继续遍历的错误返回单个根级错误；
   - 可继续遍历的结构错误一次返回多个，按 canonical 字段顺序、sequence 顺序和
     字段路径稳定排序；
   - 失败时保留当前 metadata、active draft 和 revision，只允许更新
     `parse_diagnostic` 这一侧的导入状态；成功时清除旧导入诊断并清空旧 draft/选择；
   - 不提供独立 validation API；导入只做 transport、YAML 和 metadata structure
     decode，不读取 SAS 数据、不执行表达式或 custom code。

3. 单文件 YAML 的导入 profile 采用严格单文档结构：

   - 顶层和嵌套字段按已批准 schema 检查，未知字段、重复 mapping key、未知
     chunk type、缺失/重复 ID 和 discriminator 不一致均失败；
   - 多文档、anchor/alias、tag 和 merge key 不属于支持的 bundle 表达；
   - canonical 下载仍固定为 UTF-8、无 BOM、LF；导入接受有效 UTF-8 的 BOM 或
     CRLF，并在内存中规范化后按 canonical 规则导出；无效 UTF-8 导入失败；
   - 跨对象引用是否存在不在结构导入阶段强制解析，继续沿用“结构严格、引用可
     延迟”的决定。

4. 导入结构错误使用以下稳定代码：

   `bundle_input_missing`、`bundle_encoding_invalid`、`bundle_yaml_invalid`、
   `bundle_structure_invalid`、`bundle_schema_unsupported`、
   `bundle_required_field_missing`、`bundle_unknown_field`、
   `bundle_value_invalid`、`bundle_id_invalid`、`bundle_duplicate_key`、
   `bundle_chunk_type_unknown`。

5. 生成前置失败使用同一 `ErrorItem` 形状，但不返回部分 SAS source。下列情况
   可以在 source assembly 前报告：

    `generation_table_missing`、`generation_reference_missing`、
    `generation_emitter_unavailable`、`generation_contract_invalid`。

   host-side 能确定的多个前置错误按 request、table 引用、template/chunk sequence
   的确定性顺序返回；生成器不因数据内容、SAS expression 或 custom code 的语法、
   安全性和执行结果产生错误。成功时第 7 组的对外结果仍只有 SAS source text。

6. 不生成 provenance comment、metadata hash、binding profile、sidecar、manifest、
   日志或结果文件。生成 source 只包含第 7 组规定的系统代码、关键操作注释和用户
   提供的 custom code；`parse_diagnostic` 只保留最近的导入错误，不持久化生成错误
   或运行结果。

### 被拒绝的替代方案

- 采用 parser 原生的非确定性错误文本、warning/suggestion 列表或绝对上传路径：
  未采用，会使 UI、测试和跨实现错误契约不稳定。
- 导入成功后再异步修复引用，或在失败时部分替换 workspace：未采用，避免产生
  半份 metadata 状态；引用缺失留到生成前置阶段。
- 生成失败时返回已组装的部分 source：未采用，避免用户下载不可完整执行的程序。
- 将 provenance 或 binding profile 写入 SAS source、YAML、manifest 或 sidecar：未
  采用，当前产品只需要简洁的 SAS source text 和关键操作注释。
- 为 source_data 增加 SAS 语法解析、宏展开、libref 映射或数据集存在性检查：未采用，
  这些责任属于调用方执行环境。

## 第 9 组：Shiny UI 与 Core Logic 边界

状态：已确认（2026-09-02）。采用方案 A：薄 Shiny 适配层、session-owned workspace
以及不依赖 UI 运行时的 core 操作。

### 已批准

1. `app.R` 只负责启动 Shiny；UI server 负责读取输入、调用 core、更新 reactive
   view state、展示结果和创建下载 handler。core 不接收 Shiny `session`、`input`、
   `output`、`reactiveVal`、上传临时路径或下载路径。
2. 每个 Shiny session 独占一个 `MetadataWorkspace` 实例，不使用跨 session 的全局
   workspace、服务端持久化或共享可变 metadata。workspace 保存 metadata、
   `active_draft`、`parse_diagnostic` 和 revision；当前页面、选中对象、待处理的
   Save/Discard/Cancel 操作、源码预览状态属于 UI-owned `ViewState`，不进入 YAML。
3. UI/core 之间只传递显式值对象：

   - `ImportRequest` 只包含 bundle bytes；
   - `BundleImportResult` 由 core 返回候选 workspace 或第 8 组错误项；
   - `GenerationRequest` 只包含已保存 snapshot、目标 `table_id` 和 registry；
   - 成功生成返回 SAS source text；UI 再构造 `DownloadPayload`（文件名、MIME 和
     内存内容）。

   core 不创建、读取、替换或删除用户文件；UI 适配器负责把上传文件立即读成 bytes，
   并负责源码预览和 `{table_id}.sas` 下载。上传路径和下载路径不得进入 workspace
   或 generator。
4. dirty draft 的拦截由 UI 统一处理：

   - Import、清空 workspace、切换编辑对象或 active table 时，dirty 状态触发
     `Save / Discard / Cancel`；不自动保存、不自动丢弃；
   - Save 成功后继续原操作，Save 失败保留 draft，Discard 后继续，Cancel 不变更
     workspace；
   - Generate SAS 必须先 Save，不允许直接从 dirty draft 生成；
   - Download metadata 始终导出最近一次已保存 snapshot，不改变 dirty 状态。

   core 的生成接口只接受已保存 snapshot，因此不依赖 UI 是否存在 draft。
5. revision 使用普通内存字段：

   - `saved_revision` 为非负整数，空 workspace 从 0 开始；
   - `draft_base_revision` 为 draft 建立时的 saved revision，没有 draft 时为 null；
   - 成功 Import 或 Save 将 `saved_revision` 加 1；draft 编辑不改变 saved revision；
   - Discard、Cancel 和失败操作不改变 saved revision；
   - revision 只用于 session 内 dirty guard 和状态展示，不构成跨 session 并发或持久化
     版本协议。

6. Save 的结构错误复用第 8 组 `ErrorItem`，其 `stage` 为 `workspace`，沿用相同的
   code/message/path 规则和严格结构、引用可延迟语义。Save 不执行 SAS、不求值表达式、
   不读取数据；失败时原 draft 保持不变。
7. UI 只展示 core 返回的英文事实型错误项，不建立第二套验证、翻译或建议模型。core
   测试不启动 Shiny、不读取真实上传路径，也不依赖 session state；UI 测试使用内存
   bytes 和 mock core 结果。

### 被拒绝的替代方案

- 让 core 直接持有 Shiny reactive 对象或调用 `downloadHandler`/上传路径：未采用，
  会使核心逻辑无法独立测试并把传输细节带入 metadata。
- 使用跨 session 全局 workspace、后台持久化或共享 draft：未采用，当前产品是单
  session 内存工作区。
- dirty draft 下自动 Save、自动 Discard 或直接 Generate：未采用，避免下载/生成
  动作隐式改变用户编辑状态。
- 由 UI 自己解析 YAML、解析 SAS expression 或生成第二套错误：未采用，解析、结构
  错误和生成前置错误由 core 统一处理。
- 让 core 写入 `.yaml` 或 `.sas` 文件，或把 `ViewState`/revision 写入 bundle：
  未采用，文件传输和 UI 状态属于适配层。

## P0-1：R/YAML 工具链与严格解析边界

状态：已确认（2026-09-03）。采用方案 A：`yaml` 作为底层 parser，项目自有严格
封装和 schema-aware canonical encoder。

### 已批准

1. 当前实现基线为 R 4.4.0；脚本和测试统一通过 `Rscript` 执行。直接依赖版本
   基线为 `yaml` 2.3.10、`shiny` 1.8.1.1；开发测试依赖
   为 `testthat` 3.3.2 和 `withr` 3.0.2；`renv` 1.2.3 用于依赖锁定而不是
   业务运行时。transitive dependencies 由 lockfile 一并记录。
2. `yaml::yaml.load()` 只负责把已读取的 UTF-8 bytes 转成普通 R list。调用时固定
   `eval.expr = FALSE`；core 不允许 YAML `!expr` 或其他 tag 触发代码执行。
3. parser wrapper 在解析前规范化可接受的 UTF-8 BOM/CRLF，并执行严格单文档的
   feature gate：拒绝 multi-document、anchor、alias、tag 和 merge key；quoted
   scalar 与 literal block 中的普通文本不应被误判为控制语法。重复 mapping key
   统一映射为 `bundle_duplicate_key`，parser 原始错误文本不进入对外错误包络。
4. canonical YAML 不直接使用 `yaml::as.yaml()`。项目自有 schema-aware encoder
   负责固定字段顺序、两空格缩进、LF、无 BOM、single-quoted 单行字符串、literal
   block 多行 custom code、可选字段省略和业务 sequence 顺序，并输出 canonical
   UTF-8/LF bytes；numeric scalar 规则见已确认的 P0-2。
5. YAML parser、canonical encoder 和错误 wrapper 属于 core；UI 不自行解析或序列化
   YAML。P0-1 不实现 metadata model、workspace 或 generator business logic。
6. P0 gate 必须在依赖恢复后重新运行 parser/round-trip focused tests；当前环境中
   `yaml` package 显示 built under R 4.4.3，但在 R 4.4.0 下已完成可用性实测，这
   一点不改变 R 4.4.0 的当前基线。

### 被拒绝的替代方案

- 直接把 `yaml::as.yaml()` 作为 canonical encoder：未采用，因为默认不强制
  single quote，且可能输出 scientific notation。
- 接受 parser 默认的 multi-document、anchor/alias、tag 或 merge 行为：未采用，
  会超出已确认的 strict single-document bundle profile。
- 让 UI 或各业务模块各自解析/序列化 YAML：未采用，会产生多套类型和 canonical
  规则。
- 现在为了绕过 package build warning 改用未实测的 parser 或升级 R：未采用；先以
  当前可验证基线锁定，恢复依赖时再执行 gate。

## P0-2：Canonical YAML 数值序列化

状态：已确认（2026-09-03）。采用方案 A：面向人工阅读的有限精度十进制规范化。

### 已批准

1. 本规则只约束 metadata bundle 中 numeric scalar 的文件表示；运行期的
   `base_digits`、relative `digits` 解析和 SAS 结果精度语义不由 YAML 文件表示
   改写。
2. `schema_version`、`display_order`、`level`、`indent_level` 和 `column_order`
   是整数语义字段。它们必须是有限的整数值；canonical YAML 使用普通十进制整数，
   不使用小数点、指数或多余的前导形式。
3. `width` 等有限实数使用确定性的普通十进制表示，最多保留 15 位有效数字；
   不使用科学计数法，去除小数尾零和末尾小数点，并将负零规范化为 `0`。超过
   15 位有效数字的有限输入按该规则规范化，不保留 binary floating-point tail。
4. `digits` 的绝对值和 categorical `pct` 的 digits 以整数 scalar 表示；relative
   digits（例如 `+1`、`-1`）始终以 single-quoted string 表示，不把它们解析为
   YAML numeric scalar。
5. `NaN`、`Inf`、`-Inf` 及其他非有限 metadata numeric 值属于
   `bundle_value_invalid`；不序列化为 `null`，也不静默替换为缺省值。
6. decoder 可以接受语义上有效但词法不同的 numeric scalar，encoder 统一输出上述
   canonical 形式。canonical bytes 的稳定性以 encoder 输出为准，不以输入文件的
   原始词法为准。

### 被拒绝的替代方案

- 使用 17 位或更高位的 binary round-trip 表示：未采用，会把实现细节和难读的尾数
  暴露给人工编辑；本项目选择 15 位有效数字的人类可读规范化。
- 允许 numeric scalar 使用科学计数法或保留 `-0`/尾随零差异：未采用，会增加
  canonical bytes 的非必要变体。
- 将 relative digits 当作 numeric scalar：未采用，`+n`/`-n` 的相对精度语义必须
  保留为字符串。

## P0-3：`source_data` 与生成注释

状态：已确认（2026-09-03）。采用最小方案：保留调用方提供的 source text，不建立
binding profile 或 provenance 输出。

### 已批准

1. Header 和 chunk 的 `source_data` 是必填的非空字符串。典型值包括 `adsl`、
   `adam.adsl`、`&ADSL` 和 `&lib..&member`；具体 SAS 数据集引用语义由调用方保证。
2. 导入和 Save 只检查字段存在、值类型为 string 且内容非空；不检查 SAS 语法、
   libref/member、宏变量定义、数据集或变量存在性。
3. generator 和 emitter 原样保留并插入 `source_data`，不做宏展开、解析、大小写或
   空白重写，不生成 `LIBNAME`、映射代码或 binding placeholder。
4. 生成的 SAS source 不包含 provenance comment、metadata hash、binding profile、
   sidecar 或 manifest。系统仅在 population selection、header membership、chunk
   filter/merge、analysis 和 table render/assembly 等关键阶段前加入简短、确定性的
   English operation comment；用户 custom code 原样保留。

### 被拒绝的替代方案

- 为 `source_data` 建立逻辑 ID 到实际 SAS 名称的映射：未采用，会增加当前需求不需要
  的运行期对象和配置。
- 由 generator 生成 `LIBNAME`、宏定义或其他绑定代码：未采用，调用方负责准备执行
  环境。
- 在 SAS source 中输出 provenance comment 或 binding profile：未采用，保持生成代码
  简洁；可追踪性由 metadata 和版本控制承担。

## P0-4：SAS emitter 过程、内部长表与数值格式

状态：部分确认（2026-09-03）。连续统计采用 `PROC MEANS`，分类计数采用
`PROC FREQ`；内部结果使用 long-form SAS 数据集；运行期数据契约异常采用 SAS log
warning。应用可以提示自身的生成错误，但当前不执行 SAS，不能自动捕获 SAS compiler
error。

### 已批准

1. `continuous_summary` 使用 `PROC MEANS` 生成 `n`、`mean`、`sd`、`median`、
   `q1`、`q3`、`min` 和 `max`。不在生成的 SAS source 中显式设置 `PCTLDEF`，
   直接采用 `PROC MEANS` 的 SAS 默认分位数定义；这覆盖此前“与 ref 的 R
   `quantile(type = 2)` 等价”的实现建议。字段名称、统计边界和 n=0/n=1 语义仍按
   已确认的 metadata contract 处理。
2. `categorical_summary_nonexclusive` 和 `categorical_summary_exclusive` 使用
   `PROC FREQ` 生成 counting-unit 的 numerator/denominator counts。必要的 DATA
   step 或其他简单准备步骤只负责 materialize counting unit、header membership 和
   row match；百分比按显式分母计算为 `100 * n / denominator`，不依赖 FREQ 默认的
   百分比含义。
3. emitter 的 statistic output 使用内部 long-form 结构：每行对应一个
   `chunk_id`、`row_id`、`header_column_id`、`statistic_id` 组合，并携带 raw value、
   estimable 和 resolved digits。render output 同样按一个 logical cell 一行保存，
   最终 assembly 再按 row/column 顺序组织。上述数据集只存在于生成 SAS 的运行期，
   不进入 YAML、workspace 或下载产物。
4. 中间对象使用 `_TFL_` 系统前缀和确定性 sequence 名称，位于 SAS `WORK` 库，
   不使用用户 ID 作为物理名称；系统不在 `custom_code.after` 之前主动清理这些对象，
   由 SAS `WORK` 生命周期管理。
5. relative digits 继续使用当前 chunk 的统一 `base_digits`。最终显示先用 SAS
   `ROUND` 按 `10 ** (-resolved_digits)` 舍入，再用 `PUTN` 和动态 `F<w>.<d>` 格式
   输出固定小数位和尾随零；不可估计字段直接输出 `NE`，`n` 不输出小数位。
6. 15 位有效数字只用于 `base_digits` 的十进制规范化，避免 SAS double 的二进制
   尾数被误判为真实小数位；不改变 raw statistic 的计算精度，也不替代最终的
   `ROUND`。
7. 对生成代码能够检查的运行期重复性或其他数据契约异常，使用 SAS `PUTLOG` 输出
   `WARNING: [USER] ...`，不执行 `ABORT CANCEL`。warning 只提供诊断，不隐式去重、
   聚合、跳过或改写输入；在没有其他 SAS 错误时，代码继续沿既定路径运行，结果是否
   可接受由调用方根据 log 判断。例如生成代码可输出
   `putlog "WARNING: [USER] Duplicate subject key in chunk=c001.";`。
8. host-side 的 table/reference/emitter 错误继续使用 `ErrorItem` 并可由 UI 立即提示。
   SAS compiler 或运行期 log 不由本应用执行、捕获或持久化；如需集成 SAS 编译/执行，
   必须另行扩大产品边界并确认新的 subsystem。

### 待确认

1. warning 文本的具体字段顺序和每类 emitter 的 source regression fixture；不改变
   `WARNING: [USER]` 前缀、非阻断和不自动修复的边界。

## P0-5：Table 内兼容 Chunk 的批处理

状态：已确认（2026-09-03）。采用方案 A：在不改变 chunk 业务语义和最终输出顺序的
前提下，对同一 table 内契约兼容的同类顶层 primitive chunk 进行批量分析。

### 已批准

1. 批处理只适用于同一 table 内的 primitive chunk。兼容性至少同时要求 type/capability、
   data grain、适用时的 counting unit、merge/cardinality contract、emitter/output
   semantics 以及所需的 SAS 值类型兼容。兼容性由 metadata contract 和 code-owned
   registry 决定；平台不读取 SAS 数据来推断或确认兼容性。
2. 每个 chunk 仍独立执行 `source -> filter -> filtered source -> type-specific
   merge`。之后由该 chunk 的 emitter 将 source/analysis variable/row match 等信息
   规范化为批次约定的共同逻辑输入，并保留 chunk、row、header 和 statistic identity。
   不直接把可能存在变量类型冲突的原始 `source_data` 做无条件 `SET`，也不通过隐式
   类型转换、去重或聚合来强行合批。
3. 一个兼容的 continuous batch 只生成一次 `PROC MEANS`，一个兼容的 categorical
   batch 只生成一次 `PROC FREQ`。不同 chunk 的 source 或 analysis variable 可以
   不同，但必须先映射到共同的 batch analysis 维度；denominator、row condition、
   counting unit、digits 和 `NE` 语义仍按各自 chunk contract 保持独立。
4. batch grouping 以 template chunk sequence 为输入，按兼容性 key 和首次出现顺序
   确定性分组。分析代码可以按 batch 集中生成，但 logical statistic/render 结果和
   最终 table assembly 必须继续按 template/chunk/row/header 的原有顺序输出；批处理
   不得改变可见行、列、cell 或统计值语义。
5. 首期不跨 `hierarchical_summary` container 合批。hierarchical 的动态节点发现和
   container scope 保持独立；其 analysis block 在自身 scope 内调用已注册的 primitive
   contract。后续若要跨 container 批处理，必须另行确认兼容性和动态节点边界。
6. 不兼容的 chunk 分入不同 batch，而不是生成新的隐式兼容规则。重复 key、cardinality、
   exclusive overlap 等运行期异常继续按 P0-4 以 `WARNING: [USER] ...` 非阻断地写入
   SAS log，不因批处理自动修复输入或中止程序。

### 被拒绝的替代方案

- 对每个 chunk 固定生成独立的 `PROC MEANS/FREQ`：未采用，会重复执行相同类型的分析
  过程；兼容 chunk 应共享一次过程调用。
- 直接合并所有原始 `source_data`，或依赖隐式类型转换、去重和聚合解决冲突：未采用，
  各 chunk 必须先经过显式的 source/chunk 级规范化。
- 跨不兼容 grain、counting unit、cardinality 或 hierarchical container 强行合批：
  未采用，以免改变统计和动态布局语义。
- 按 batch 顺序重排最终 table 行或 cell：未采用，batch 只优化分析过程，template
  sequence 仍是最终输出顺序的事实来源。

## P0-6：Primitive Batch 的专用规范化输入

状态：已确认（2026-09-03）。采用方案 A：按分析类型使用专用的规范化 SAS 输入
数据集，不建立包含所有类型字段的通用宽表。

### 已批准

1. `PrimitiveBatchPlan` 是生成期间的内部规划对象，不进入 YAML、workspace 或下载
   产物。它至少保存 `batch_order`、`chunk_type`、有序 `chunk_orders`、批次
   `input_dataset` 和 `raw_dataset`；continuous batch 另外保存 `precision_dataset`。
   batch order 按 template 中首个 chunk 的出现顺序确定。
2. continuous batch 的规范化输入至少包含 `chunk_order`、`column_order` 和统一的
   numeric `analysis_value`。每个 chunk 仍先独立完成 source/filter、重复 key
   warning、scaffold merge，再把自身 analysis variable 映射到 `analysis_value`。
   `precision_dataset` 至少包含 `chunk_order` 和 `analysis_value`，只保留 filtered
   source 与至少一个展示 header column 的 subject 交集；同一 subject 即使属于多个
   columns，也只参与一次该 chunk 的 base-digits 计算。
3. 一个 continuous batch 通过一次 `PROC MEANS` 按 `chunk_order` 和 `column_order`
   分组分析 `analysis_value`。批次规范化不改变各 chunk 的 statistic identity、
   resolved digits、`n=0/n=1` 或 `NE` 语义；raw output 再按保留的 chunk/row/header/
   statistic identity 映射回 logical result。
4. categorical batch 的规范化输入至少包含 `chunk_order`、`row_order` 和
   `column_order`，每行表示一个 counting event：`row_order = 0` 表示 denominator
   event，正数表示对应 analysis row 的 numerator event。各 chunk 自己的 filter、
   denominator、row condition 和 counting unit 在规范化阶段处理；不同 source 或
   analysis variable 不直接做无条件 `SET`。
5. `categorical_summary_nonexclusive` 与 `categorical_summary_exclusive` 是不同的
   batch type，各自使用一次 `PROC FREQ`。最终 expected-cell skeleton 负责补回未被
   FREQ 产生的零计数；denominator 为零时 `n` 为 0，`pct` 为 not estimable 并渲染为
   `NE`。该补全不改变 nonexclusive 的 row overlap 语义，也不替 exclusive 隐藏
   overlap warning。
6. 规范化对象使用确定性的 `_TFL_` 系统前缀和类型/序号命名，位于 SAS `WORK` 库；
   例如 continuous 的 input/precision/raw 对象和 categorical nonexclusive/exclusive
   的 input/raw 对象均按 batch order 生成。用户 chunk、row 或 table ID 不进入物理
   dataset 名称。系统不在 `custom_code.after` 前主动清理这些对象，由 `WORK` 生命周期
   管理。
7. 平台不读取 SAS 数据来检查 `analysis_value` 的实际类型，也不把规范化步骤变成
   隐式类型转换、去重或聚合规则。调用方将非 numeric source variable 用于
   continuous 等输入错误，由生成的 SAS 编译/运行环境负责；系统仍只生成 source text。

### 被拒绝的替代方案

- 建立同时包含 continuous、categorical、denominator、numerator 和 display 字段的
  通用宽批次输入表：未采用，会引入大量空字段和类型分支。
- 让每个 batch 直接读取或无条件 `SET` 原始 `source_data`：未采用，各 chunk 必须先
  形成专用规范化输入。
- 让 `PROC FREQ` 自动决定零计数或百分比：未采用，零 cell 由 expected skeleton
  补齐，百分比继续按显式分母计算。
- 在生成器中验证 SAS 变量类型或提前执行批次：未采用，平台不读取数据、不执行 SAS。

## P0-7：统一 Long-form Statistic 与 Render 结果

状态：已确认（2026-09-04）。采用方案 A：所有 primitive emitter 使用统一的
long-form raw statistic 和 render 结果；hierarchical 只增加节点与运行时行上下文。

### 已批准

1. `ChunkStatisticValue` 是统一的 raw statistic 逻辑对象，每行对应一个
   `chunk_id`、`row_id`、`header_column_id`、`statistic_id` 组合，并至少包含：
   `value`、`estimable` 和 `resolved_digits`。`value` 是未舍入 numeric value；不可
   估计时不填充伪造数值；`n` 的 `estimable` 始终为 true，`resolved_digits` 对 `n`
   不适用。它是生成期内部结果，不进入 YAML、workspace 或下载产物。
2. continuous 和 categorical 都必须转换到上述公共结构。categorical 的 denominator、
   numerator 和 overlap guard 所需计数可以保留在 emitter-private 中间对象；公共结果
   只保存 `n` 或 `pct` 的 logical statistic。`pct` raw value 为显式的
   `100 * n / denominator`；denominator 为零时 `n=0`、`pct` 不可估计。
3. `ChunkRenderResult` 是统一的 logical cell 结果，每行至少包含 `chunk_id`、`row_id`、
   `label`、`indent_level`、`header_column_id` 和非缺失字符型 `cell_text`。每个
   row/header column 组合恰好一行；label row 对每个展示列输出空字符串。
4. render 按 metadata 的 `cell_format` 对每个 statistic 独立格式化后替换 placeholder。
   不可估计的 statistic 只替换为 `NE`，不使同一 cell 中其他 statistic 失效；`n` 为
   无小数位整数，其他可估计值使用 `resolved_digits`、`ROUND`、`PUTN`、固定小数位和
   尾随零，literal `%` 保持原样。analysis 不拼接 cell text，render 不重新计算 raw
   statistic，也不执行通用表达式。
5. hierarchical 的 statistic 结果在公共字段上增加 `analysis_id`、`group_path` 和
   `node_key`；hierarchical render 行增加 `runtime_row_id`、`row_role`、动态 label、
   `indent_level` 和各 header column 的 `cell_text`。这些运行时值不写回 metadata，
   不替代 position ID，也不进入导出 bundle。
6. raw statistic、render 和 hierarchical 结果均只存在于 SAS `WORK` 的生成期对象中，
   使用 P0-6 的确定性 `_TFL_` 类型/序号命名。最终 assembly 继续按
   template/chunk/row/header 顺序输出，不按 batch 或 raw dataset 的物理顺序输出。
7. 对外 `GenerationResult` 仍只有 SAS source text；long-form 结果不成为第二种下载
   产物，不触发 RTF、HTML、ODS、PROC REPORT 或持久化结果存储。

### 被拒绝的替代方案

- 为 continuous、categorical 和 hierarchical 定义互不兼容的 raw/result shape：未采用，
  会使 batch 映射和 table assembly 产生多套逻辑。
- 用宽表或在 analysis 阶段直接拼接字符 cell：未采用，无法稳定表达可变 statistic
  列表，也会混合统计与展示职责。
- 把 denominator、batch ID、SAS 物理 dataset 名或 runtime node value 暴露到 YAML：未
  采用，这些属于 emitter 或生成期内部状态。
- 将整个 cell 统一替换为 `NE`：未采用，字段级 `NE` 允许例如 `5.0 (NE)` 的结果。

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

1. 沿用 ref 的 precision、统计和显示语义：continuous 使用 sample SD、n=0/n=1
   边界、非有限值失败、half-away-from-zero、固定小数位、尾随零和 `NE`；分位数在
   本项目中由 `PROC MEANS` 的 SAS 默认定义产生，而不是复制 R 的 type 2 实现。
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
