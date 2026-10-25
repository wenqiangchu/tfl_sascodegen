# 设计决策记录

本文记录当前项目中已经获得用户确认的设计决定、被拒绝的替代方案，以及
仍然未决的问题。讨论中的建议不会自动成为批准决定。

## 第 1 组：应用入口、Bundle 导入导出与 SAS 输出

状态：已确认；serialization 于 2026-09-05 修订为 ZIP 多文件 bundle，并保留
最小 `manifest.yaml`。

### 已批准

1. 使用根目录的薄 `app.R` 作为 Shiny 启动入口；生产代码按职责放在
   `src/` 子目录。
2. Metadata bundle 采用 ZIP 压缩包，内部 YAML 文件使用 schema version 1；
   保留最小 `manifest.yaml`，仅包含 `schema_version: 1`。压缩包固定包含
   `populations.yaml`、`headers.yaml`，并使用 `tables/<table_id>.yaml` 和
   `templates/<template_id>.yaml` 保存独立对象文件。集合按文件名 ID 字典序形成
   顶层 sequence，每个对象显式保存 `id`；下载扩展名为 `.zip`。
3. 导入是原子替换：只有在整个 ZIP 的 manifest、catalog 和所有对象文件成功
   解析后才替换当前工作区；传输、entry 或 YAML 解析失败时保留原工作区；当前
   范围不支持 merge 导入。
4. 导出使用稳定 entry 顺序和稳定字段顺序的 canonical YAML，只包含已保存的
   工作区，不写入上传临时路径、session 信息或 UI 状态。每个 YAML 文件采用
   UTF-8、无 BOM、LF 换行、两空格缩进；sequence 保持业务顺序；单行字符串使用
   single-quoted scalar，多行代码使用 literal block scalar；缺省可选字段不输出
   为 null。
5. SAS 结果的产品边界是源代码文本。下载文件名采用清理后的
   `{table_id}.sas`，并提供源码预览。
6. 当前阶段不生成 ODS、PROC REPORT 或 RTF/PDF/HTML 等报表文件；具体分析和
   布局数据集字段由后续 emitter 子系统确定。
7. 不增加服务端持久化；session 结束时未下载的内存修改可以丢失。

### 被拒绝的替代方案

- JSON canonical bundle：已被 2026-09-02 的 YAML 决定替代；YAML 更适合人工
  阅读和编辑，canonical 规则承担跨实现稳定性。
- 单一 YAML 文件 bundle：已被 2026-09-05 的 ZIP 多文件 bundle 决定替代；独立
  template 文件便于跨研究复制和移动。
- 以 ID 为键的 mapping：未采用，原因是 sequence 能直接保留 UI 业务顺序，
  且避免额外的顺序字段。
- 合并导入：未采用，原因是会引入 ID 冲突、引用重写和回滚语义；当前产品
  只需要整体替换。
- 将上传临时文件名或路径写入 bundle：明确拒绝，传输适配器细节不得进入
  metadata。
- 生成报告文件或执行 SAS：明确超出当前产品边界。

### 实施阶段边界（不再是设计未决项）

- dirty draft 时导入、切换和生成的拦截规则已在第 9 组冻结；具体控件布局留到实现阶段。
- YAML parser/toolchain 已在 P0-1 锁定；后续只需在依赖恢复后重跑对应 gate。
- 四类 emitter 的完整输出 schema 和运行期失败处理已在 P0-8 冻结；后续子系统只实现
  已批准契约，不重新选择过程、字段或 warning 语义。

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

状态：已确认（2026-09-02；bundle transport 于 2026-09-05 修订）。采用方案 A：
沿用 ref 的稳定错误项和有序错误列表，并适配为 ZIP 多文件 YAML bundle 与只生成
SAS source text 的边界。

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

3. ZIP 多文件 bundle 的导入 profile 采用严格 entry 和单文档结构：

   - 顶层和嵌套字段按已批准 schema 检查，未知字段、重复 mapping key、未知
     chunk type、缺失/重复 ID 和 discriminator 不一致均失败；
   - 多文档、anchor/alias、tag 和 merge key 不属于支持的 bundle 表达；
   - canonical 下载中的每个 YAML 文件均固定为 UTF-8、无 BOM、LF；导入接受有效 UTF-8 的 BOM 或
     CRLF，并在内存中规范化后按 canonical 规则导出；无效 UTF-8 导入失败；
   - ZIP 必须包含 `manifest.yaml`、`populations.yaml` 和 `headers.yaml`；manifest
     只包含 `schema_version: 1`。`tables/` 和 `templates/` 下只允许直接的 `.yaml`
     文件，文件名 stem 必须与内部对象 `id` 一致；未知 entry、重复 entry、非法
     路径、嵌套目录和符号链接均失败；对象文件按 ID 字典序形成顶层 sequence；
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

6. 不生成 provenance comment、metadata hash、binding profile 或 sidecar；bundle 的
   `manifest.yaml` 仅用于声明 `schema_version`，不进入生成的 SAS source。
   生成 source 只包含第 7 组规定的系统代码、关键操作注释和用户
   提供的 custom code；`parse_diagnostic` 只保留最近的导入错误，不持久化生成错误
   或运行结果。

### 被拒绝的替代方案

- 采用 parser 原生的非确定性错误文本、warning/suggestion 列表或绝对上传路径：
  未采用，会使 UI、测试和跨实现错误契约不稳定。
- 导入成功后再异步修复引用，或在失败时部分替换 workspace：未采用，避免产生
  半份 metadata 状态；引用缺失留到生成前置阶段。
- 生成失败时返回已组装的部分 source：未采用，避免用户下载不可完整执行的程序。
- 将 provenance 或 binding profile 写入 SAS source、YAML 或 sidecar：未
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

   - `ImportRequest` 只包含 ZIP bundle bytes；
   - `BundleImportResult` 由 core 返回候选 workspace 或第 8 组错误项；
   - `GenerationRequest` 只包含已保存 snapshot、目标 `table_id` 和 registry；
   - 成功生成返回 SAS source text；UI 再构造 `DownloadPayload`（文件名、MIME 和
     内存内容）。

   core 不创建、读取、替换或删除用户文件；UI 适配器负责把上传 ZIP 立即读成 bytes，
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
   ZIP bytes 和 mock core 结果。P7/P8 还必须使用 `shinytest2` 验证按钮交互，包括
   Import、Save、Discard、Cancel、dirty guard、Delete/Confirm Delete、选择、
   Generate 以及 metadata/SAS 下载。
8. 2026-09-09 确认 metadata 初始加载和全局工具栏行为：

   - `dashboardHeader` 标题右侧提供 `Upload metadata`、`Download metadata` 和
     `Download demo package`；sidebar 不再承载 bundle 上传和下载控件；
   - 上传按钮打开包含 ZIP `fileInput` 的 modal，而不是把 file input 直接放进 header；
   - UI ViewState 增加最小的 session-owned `metadata_loaded` 布尔状态，初始为 `FALSE`，
     仅在 bundle 完整解析并成功替换 workspace 后设为 `TRUE`；它不通过 population、
     header、table 或 template 的数量推导；
   - 首次成功导入前，主页面显示必须上传 metadata ZIP 的 welcome/empty state；依赖
     metadata 的编辑内容不渲染，Download metadata 禁用，但上传和 demo package 下载
     始终可用；
   - 成功导入后清空旧 active editor、draft、pending action 和动态 DT cache，刷新列表并
     激活第一个可用对象；导入失败不修改现有 workspace、editor 或 loaded 状态；
   - 已加载 workspace 的 clean re-import 需要 replacement confirmation；dirty re-import
     先执行现有 Discard changes / Cancel guard，确认丢弃后再执行 replacement confirmation；
   - Download metadata 只导出最近一次保存的 workspace snapshot，不隐式保存 draft；
     Download demo package 与 workspace 无关，包含 synthetic demo metadata ZIP 和用户指南；
   - 删除最后一个 metadata 对象不会把 `metadata_loaded` 改回 `FALSE`；该状态表示是否
     成功完成过本 session 的 bundle import，而不是 workspace 是否非空。

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

状态：已确认（2026-09-03；具体实现微契约见 P0-8）。连续统计采用 `PROC MEANS`，分类计数采用
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
   可接受由调用方根据 log 判断。具体 warning 字段顺序由 P0-8 固定。
8. host-side 的 table/reference/emitter 错误继续使用 `ErrorItem` 并可由 UI 立即提示。
   SAS compiler 或运行期 log 不由本应用执行、捕获或持久化；如需集成 SAS 编译/执行，
   必须另行扩大产品边界并确认新的 subsystem。

P0-8 已补充 warning 字段顺序、物理列类型、DATA/PROC 组合、render 转换和 source
regression fixture 边界；这些细节不进入用户 YAML。

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

## P0-8：SAS emitter 微契约与 source regression

状态：已确认（2026-09-04）。本组冻结生成期的 SAS 实现边界，但不把实现细节
暴露为 YAML 字段。emitter 仍只生成 source text；平台不执行 SAS、不读取数据、
不捕获 SAS log。

### 已批准

1. 所有运行期对象都位于 `WORK`，使用 `_TFL_` 加固定类型和三位 batch/sequence
   编号命名；用户提供的 table、chunk、row、column 或 dataset ID 不进入物理名称。
   首期使用以下对象类别：population、membership、chunk-filtered source、
   continuous input/precision/raw、categorical input/raw、hierarchical nodes、
   statistic、render 和 assembly。对象由生成器按确定顺序创建，直到
   `custom_code.after` 结束前不主动删除，由 `WORK` 生命周期回收。

2. 物理 long-form 结果字段固定如下；字段顺序也是 canonical DATA step 和 source
   regression 的顺序。emitter-owned 字符型 identity 字段使用显式 `LENGTH`，长度至少能容纳
   对应 metadata/runtime value；emitter 不截断 opaque ID 或 label，也不把长度
   约束新增到 YAML：

   | 对象 | 字段与 SAS 类型 |
   | --- | --- |
   | `ChunkStatisticValue` | `chunk_id` character、`row_id` character、`header_column_id` character、`statistic_id` character、`value` numeric 8-byte、`estimable` numeric 8-byte、`resolved_digits` numeric 8-byte |
   | `HierarchicalStatisticValue` | 在公共 statistic 字段之后追加 `analysis_id` character、`group_path` character、`node_key` character |
   | `ChunkRenderResult` | `chunk_id` character、`row_id` character、`label` character、`indent_level` numeric 8-byte、`header_column_id` character、`cell_text` character |
   | `HierarchicalRenderRow` | 在公共 render 字段之后追加 `runtime_row_id` character、`row_role` character |

   `value` 是 SAS numeric 8-byte double；不可估计时为 numeric missing，且
   `estimable=0`。`n` 的 `estimable` 始终为 1，`resolved_digits` 为 missing。
   字符字段使用显式 `LENGTH`，不得依赖 SAS 对首次赋值的隐式长度推断。外部数据键
   `USUBJID` 是例外：membership 和 chunk source 继承各自 source dataset 的类型与
   长度，emitter 不为它设置固定长度、不重编码或截断；不同 source 之间的 key 兼容性
   仍属于调用方的数据契约，平台不读取或检查。

3. population/header 阶段按以下固定顺序生成：

   ```text
   header.source_data -> population expression -> one DATA step per header column
   -> _TFL_MEM_<seq>
   ```

   `_TFL_MEM_<seq>` 至少包含继承自 `source_data` 的 `USUBJID`、显式长度的
   `header_column_id` character 和 `column_order` numeric，按 `display_order` 输出；
   `header_column_id` 使用确定性的 SAS character literal 编码。每个 column
   condition 独立求值，重叠 membership 保留；不命中任何 column 的 subject 不输出。
   生成前加入一个简短的 English operation comment。该步骤不对 `source_data` 或
   表达式做改写。

4. 每个 primitive chunk 先独立生成 source/filter/guard/merge，再写入专用 batch
   input。source/filter 使用 DATA step `SET <source_data>;` 和 `IF`/`DELETE`，其中
   `<source_data>` 是原样 source text；filter 缺省时不生成额外条件。subject-grain
   chunk 在 filter 后按 `USUBJID` 排序并生成非阻断重复 key warning，不使用
   `NODUPKEY`、first-record 选择或聚合。随后以 membership 为左侧输入执行显式
   `USUBJID` merge；缺失 source record 保留 scaffold 行，categorical row condition
   不在该缺失行上执行。每个关键操作前有一个确定性的 English comment。

5. continuous batch 固定使用以下步骤：

   ```text
   per-chunk filtered/merged source
     -> _TFL_CIN_<batch> (chunk_order, column_order, analysis_value, source_row)
     -> _TFL_CPREC_<batch> (chunk_order, source_row, analysis_value)
     -> _TFL_CKEY_<batch> (all chunk/column keys)
     -> one PROC MEANS
     -> _TFL_CRAW_<batch>
     -> _TFL_STAT_<batch>
     -> _TFL_REND_<batch>
   ```

   `_TFL_CIN_<batch>` 的前三个字段固定为 `chunk_order` numeric 8-byte、
   `column_order` numeric 8-byte、
   `analysis_value` numeric 8-byte，并保留内部 `source_row` numeric 8-byte 以区分违反 subject grain 的
   source records。`PROC MEANS` 使用 `CLASS chunk_order column_order`、
   `VAR analysis_value` 和 `OUTPUT OUT=`，使用显式别名
   `N=_n MEAN=_mean STD=_sd MEDIAN=_median Q1=_q1 Q3=_q3 MIN=_min MAX=_max`；
   不设置 `PCTLDEF`，也不使用 FREQ 默认百分比。`STD` 是 sample SD。`_TFL_CKEY_`
   先提供每个 chunk/column 组合，raw wide output 由一个 DATA step 按统计量固定
   顺序展开为 long-form；缺失分析组补为 `n=0` 且其他 statistic 不可估计。
   row/statistic map 只生成声明的 analysis rows，label rows 生成空 cell。

   precision input 从 filtered source 与至少一个 membership column 的交集生成；
   同一个 source row 因多个 columns 重复时只保留一次，违反 subject grain 的不同
   source rows 不被静默合并。`base_digits` 使用已确认的 15 位有效数字、非科学
   计数法和去除小数尾零规则；所有 columns 共用该值，relative digits 按
   `base_digits + offset` 解析。P0-13 澄清负结果沿用生成 SAS 的 ERROR + NE，
   不终止当前提交；应用不读取分析值，也不会据此返回 generation 前置错误。

   hierarchical nested continuous block 在进入 precision 和 `PROC MEANS` 前显式
   materialize `counting_unit`。`record` 保留每条 source record；`distinct_subject`
   按 `node_key`、`column_order`、`USUBJID` 分组；`distinct_key` 将最后一个字段替换为
   metadata 声明的 typed key sequence。后两者允许一个非缺失 analysis value 加任意
   数量 missing records，并使用该唯一非缺失值；全部 missing 时保留一个 missing
   unit。两个或更多非缺失 records 写入
   `ERROR: [USER] continuous_unit_multiple_values ...` 后执行 `ABORT CANCEL`，不得隐式
   选择 first、最大值、最小值、平均值或其他聚合。unit materialization 后的输入使用
   `_TFL_CUNIT_<batch>`，仍由一次 `PROC MEANS` 按 node/header 计算统计量。

6. categorical batch 固定使用以下步骤：

   ```text
   per-chunk filtered/merged source
     -> _TFL_KIN_<batch> (chunk_order, row_order, column_order, counting event)
     -> optional exclusive overlap guard
     -> one PROC FREQ
     -> expected-cell skeleton + _TFL_KRAW_<batch>
     -> _TFL_STAT_<batch>
     -> _TFL_REND_<batch>
   ```

   `_TFL_KIN_<batch>` 的 `row_order=0` 是 denominator event，正数是 numerator
   event；其固定分析键为 numeric 8-byte 的 `chunk_order`、`row_order` 和
   `column_order`。
   counting-unit identity、必要的 source row/record key 和仅供诊断的 key text 可
   作为额外字段保留，但不通过字符串拼接替代 typed key 的排序或去重。每个
   denominator unit 每个 column 只产生一个 denominator event；nonexclusive 的
   一个 unit 可以产生多个 row events。`PROC FREQ` 使用
   `TABLES chunk_order*row_order*column_order / OUT=`，raw `COUNT` 是唯一采用的
   计数来源，FREQ 的 `PERCENT` 列被忽略。

   expected-cell skeleton 显式覆盖每个 batch chunk、每个 header column、denominator
   行和声明的 analysis rows；与 FREQ raw count 合并后，缺失 count 补为 0。分母
   大于 0 时 `pct=100*n/denominator`，分母为 0 时 `n=0`、`pct` 的
   `estimable=0`，render 为 `NE`。该补全不改变 nonexclusive overlap，也不隐藏
   exclusive warning。

7. `categorical_summary_exclusive` 在 FREQ 前对已 materialize 的 counting-unit
   events 做 guard。按 typed counting-unit key、`chunk_order` 和 `column_order`
   排序；一个 unit 命中多个正 `row_order` 时只写一条非阻断 warning，继续将原始
   events 送入 FREQ。warning 的稳定字段顺序为：

   ```text
   WARNING: [USER] exclusive_overlap chunk_order=<n> column_order=<n> unit=<text> row_orders=<list>.
   ```

   `unit` 是仅用于日志的确定性文本，`row_orders` 按数值升序并以逗号连接；未命中
   任何 row 不产生 warning。重复 subject/record key 的稳定文本为：

   ```text
   WARNING: [USER] duplicate_key chunk_order=<n> unit=<text> count=<n>.
   ```

   duplicate key warning 和 overlap warning 都不改变输入记录。

8. render 只消费 long-form statistic，不重新计算统计量。对每个 row/header cell，
   以 `cell_format` literal 初始化字符变量，再按 metadata statistic sequence 使用
   `TRANWRD` 替换 `{statistic_id}`：`estimable=0` 替换为 `NE`；`n` 使用无小数位
   `PUTN`；其他 numeric value 先用 `ROUND(value, 10 ** (-resolved_digits))`，
   将 rounded zero 归一化为正零，再用动态 `F<w>.<d>` 格式和 `PUTN` 输出固定小数
   位与尾随零。`w` 由 emitter 以 `resolved_digits` 确定性计算，literal `%` 不做
   特殊处理。每个 placeholder 独立替换，因此同一 cell 可以包含例如 `5.0 (NE)`。
   render 完成后保证 `cell_text` 为非 missing character；label row 对每个 column
   输出空字符串。

9. hierarchical emitter 不跨 container 合批，固定执行：source/filter/key guard、
   在所有展示 columns 的联合 eligible source 上发现 levels、按每个 level 的
   `order_variable`/`order_direction` 或 `result_sort` 排序、按
   `node_role`/`placement` 递归展开，再在节点 scope 内调用已注册 primitive emitter。
   动态节点以 length-prefixed component 方式生成 `group_path`/`node_key`，不使用
   可能碰撞的裸分隔符拼接；动态 label、runtime row ID 和 row role 只进入运行期
   hierarchical result。输出顺序固定为当前节点行、该 level 的 below static rows、
   下一级 dynamic children。primitive raw statistic 仍映射到公共字段，hierarchical
   扩展字段按第 2 项追加。

10. source regression fixture 只包含 synthetic metadata YAML、目标 table ID 和
    expected SAS source assertions/golden text，不包含 SAS 数据、数据路径、用户文件、
    运行日志或 report artifact。最低覆盖：单个 continuous、compatible continuous
    batch、nonexclusive categorical 的 zero/denominator-zero、exclusive overlap
    warning、hierarchical static-before-dynamic、macro `source_data` passthrough、
    relative digits/cell formatting，以及 host-side prerequisite failure 不返回
    partial source。测试只比较 source text、section order、关键语句出现次数和
    deterministic bytes；不执行 SAS。

11. P0-8 不增加 R 或 SAS 运行时依赖；emitter 只使用 P0-1 已锁定的 R/YAML 工具链
    生成标准 DATA step、`PROC MEANS` 和 `PROC FREQ` source。具体 SAS 版本、宏库和
    外部数据绑定仍由调用方执行环境负责。

### 被拒绝的替代方案

- 为每个 chunk 生成独立的 `PROC MEANS/FREQ`：未采用，兼容 chunk 共用一次过程。
- 直接无条件 `SET` 多个原始 source，或用隐式类型转换、`NODUPKEY`、first-record
  选择和聚合掩盖粒度错误：未采用；chunk 先独立规范化，重复只 warning。
- 依赖 `PROC FREQ` 默认百分比或 `SPARSE` 代替 expected-cell skeleton：未采用，
  百分比必须使用显式分母，零 cell 必须由 skeleton 补回。
- 在 render 阶段直接拼接 wide cell 或让 analysis 计算字符文本：未采用，analysis
  与 render 继续通过公共 long-form 对象分离。
- 将 SAS 过程名、物理 dataset 名、warning 文本或 fixture 内容写入 YAML：未采用，
  这些属于 code-owned emitter 和测试实现。


## 第 2 组补充：参考文档对齐与相对精度

状态：已确认（2026-09-02）。用户要求本项目重叠字段的含义与 ref 一致；以下
语义已按该要求冻结，R 生成实现和超出本项目范围的 ref 内容除外。

### 已确认

1. 与 `ref/阶段02-Chunk扩展模型与注册机制.md` 一致，continuous statistic 的
   `digits` 支持非负绝对整数以及 `+n`/`-n` 相对精度字符串；`n` 不声明
   `digits`，categorical `pct` 只接受非负绝对整数。
2. relative digits 使用当前 chunk 实际分析 subjects 的统一 `base_digits`，
   先按 ref 的 15 位有效数字、非科学计数法、去除小数尾零规则解析，再计算
   `resolved_digits = base_digits + offset`；负结果按 P0-13 写入 ERROR 并将该
   statistic 显示为 NE，继续后续步骤，不静默截断。
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
# Draft lifecycle and deletion semantics

- `workspace_draft_status()` is the canonical state classification. An update
  draft whose value equals its base is clean and must not trigger a guard.
- New objects remain `create_pending` until the user explicitly saves them.
- Deletion is immediate after confirmation and does not create a user-visible
  dirty draft. Deleting a pending create discards that create draft.
- UI metadata lists render the effective workspace so pending creates are
  visible before save.

## Active editor state and user-entered IDs

状态：已确认（2026-09-08）。本节冻结 Shiny 编辑器所需的最小内存对象和
边界动作语义。实现不得把每个输入控件的即时事件当作 draft 事实来源。

### 已批准的最小内存对象

1. `workspace` 是 session-owned 的已保存 metadata 快照，包含
   `schema_version`、`populations`、`headers`、`tables`、`templates` 和
   `revision.saved_revision`。它不保存 UI 控件值、session 状态或运行期结果。
2. `active_editor` 只记录当前编辑入口：

   ```r
   list(
     panel = "population",        # population | header | table | template
     document_type = "population",
     document_id = "fas"
   )
   ```

   不维护 `selected_ids$population`、`selected_ids$header`、
   `selected_ids$table` 或 `selected_ids$template`；非活动 panel 的列表选择由
   其 UI 控件持有，需要时再读取。
3. `active_draft` 只保存编辑操作、目标和进入编辑时的原始快照：

   ```r
   list(
     operation = "update",        # update | create
     target = list(document_type = "population", document_id = "fas"),
     original = <metadata object or NULL>
   )
   ```

   不持久化实时 `current` 副本。`current` 仅在 Save、Discard、Switch、Delete、
   Import 或 Generate 等边界动作发生时由 collector 从当前 UI 一次性读取。
4. `pending_action` 仅在 dirty guard 出现后暂存待继续的动作（例如 switch 或
   delete），完成或取消后清空；它不是 metadata，也不参与 dirty 比较。

### 顶层 ID 与 New 对话框

- Population、Header、Table 和 Template 的顶层 `id` 由用户输入，不能由系统
  静默生成。点击 New 时先显示 ID 对话框；确认后创建带该 ID 的 pending object，
  并将其设为 active editor。
- Chunk、row、statistic、level、analysis block 和 spanning header 等内部位置
  标识可以由系统按 sequence 自动生成或重建；重建时同步更新引用。
- ID 对话框取消不会创建对象，也不会改变 workspace、active draft 或 revision。
  空 ID、重复 ID 或不符合结构契约的 ID 在创建边界返回明确错误，不修改已有对象。

### Dirty 判定和边界动作

用户编辑控件时只改变浏览器中的 UI 值，不更新 workspace，也不创建或更新
`active_draft`。在边界动作执行前，按目标 panel 的 collector 完成类型转换和空值
标准化，再与 `active_draft$original` 做 `workspace_canonical_equal()`：

- 没有 active draft：`none`；
- `operation = update` 且 current 等于 original：`update_clean`，不拦截切换；
- `operation = update` 且 current 不等于 original：`update_dirty`，显示丢弃/取消；
- `operation = create`：在 Save 前始终为 `create_pending`，即使 UI 尚未填写其他字段。

Discard 对已有对象重新渲染 original 并清除 draft；对新对象直接移除整个 pending
object。Save 只在点击时收集并写入 workspace；无变化时不产生新 revision。程序同步
只负责重新渲染 UI，不改变 dirty 事实。删除在通过 dirty guard 和引用检查后即时生效，
不创建新的用户可见 delete draft；删除 pending create 等同于丢弃该新对象。

## SAS 生成选项与源码可读性

状态：本轮用户已确认（2026-09-13）。要求为 Header membership 合并为一个 DATA step、
生成界面提供 duplicate record check 和 Report/QC 选项，以及 key map 改用
`INPUT + DATALINES`。本节替代早期“不生成 PROC REPORT/ODS”和生成请求仅包含
snapshot/table/registry 的限制。应用仍只输出 SAS source text，不读取分析数据、
运行 SAS、检查比较结果或直接生成报告文件。

### 数据对象、所有权和生命周期

`GenerationRequest` 的完整字段如下：

| 字段 | 职责 |
| --- | --- |
| `workspace_snapshot` | 本次使用的已保存 metadata 值快照。 |
| `table_id` | 本次生成入口的 table ID。 |
| `registry` | 四类 chunk 的代码注册定义和 emitter。 |
| `include_duplicate_check` | 单个非缺失 logical，默认 `TRUE`；控制 source duplicate-key guard 是否生成。 |
| `auto_dedup` | 单个非缺失 logical，默认 `FALSE`；控制是否在分析前删除重复 source 记录。 |
| `output_mode` | `report` 或 `compare`，默认 `report`；选择最后的 SAS procedure。 |

`GenerationResult` 仍只有 `passed`、`source`、`errors`：成功返回完整源码，失败返回
有序错误且 `source = NULL`。选项不增加工作区、TableSpec、HeaderSpec 或 bundle 字段，
不修改 revision、已保存 metadata、draft 或外部文件。

Shiny 的当前控件值与最近一次生成时捕获的 `generated_options` 都归当前 session 所有。
`generated_options` 只含 `include_duplicate_check`、`auto_dedup` 和 `output_mode`，
成功生成时更新；
预览和下载还必须同时匹配当前 table 与成功状态。切换选项后旧预览隐藏、下载失效，
重新生成成功才恢复。空 UI 输入使用相同默认值，不把未初始化 checkbox 当作关闭。

### 已确认的源代码行为

1. Header 的 `_TFL_MEM_001` 只通过一个 DATA step 读取 `_TFL_POP_001`。按已保存的
   Header 列顺序输出独立的 `if (<condition>) then do; ... output; end;`，
   保留各列的 `header_column_id` 和 `column_order`。条件仍为原样 SAS expression；
   同一 subject 命中多个列时输出多条 membership，不使用互斥的 `ELSE IF`。
   Header N 的独立计数和空列补零逻辑保持不变。
2. duplicate check 默认开启。关闭时省略专用 guard 的排序副本、计数 DATA step 和
   `WARNING: [USER] duplicate_key`，不删除记录、不改变 merge、counting unit、
   denominator、层级发现或分类 overlap warning。primitive source 按 subject key 检查；
   hierarchical source 按其 source contract 检查，nested analysis 不重复检查展开后的行。
3. auto dedup 默认关闭，与 duplicate check 为两个独立开关。开启时在 duplicate check
   之前插入一次 `PROC SORT ... NODUPKEY`，每个键只保留一条记录，
   后续 merge、counting unit、denominator、层级发现与 overlap warning 均基于保留记录。
   保留哪一条由 `PROC SORT` 在排序结果中的首条决定；SAS 不保证相同 BY 值记录
   的相对顺序，生成器也不设置 `EQUALS`、不控制调用方的排序线程选项，因此结果依赖
   调用方对 source 的预排序。去重键沿用 duplicate check 的键：primitive 与 categorical
   使用 batch subject key，hierarchical 使用 source contract 的 `subject_key` 或 `record_key`。
   两个开关的选择顺序固定为先去重后检查；同时开启时检查针对保留记录，因此不再
   报告已删除的重复。
4. `report` 模式在 analysis、assembly 和 `custom_code.after` 后添加 `PROC REPORT`
   与既有 ODS RTF 源码。`compare` 模式在同一位置添加：

   ```sas
   proc compare base=tables.<table_id> compare=WORK._TFL_ASM_001 listvar;
   run;
   ```

   source 侧库和数据集由调用方准备，生成器不写入 `TABLES`。比较沿用 SAS 的观察序
   对齐，不新增 metadata compare key、不自动排序。需要 name literal 的 ID 使用
   `tables.'<table_id>'n`（内部单引号按 SAS 规则处理）并启用 `VALIDMEMNAME=EXTEND`。
   QC 模式不添加系统报告语句，也不执行仅对 RTF 必需的页宽检查；用户的两个 custom
   code 字段始终原样保留。
5. 按后续确认，`_TFL_KEY_MAP_*` 的 `INPUT + DATALINES` 只保存一次
   chunk/row/statistic metadata，不逐 Header 列重复写入。SAS 通过 `CROSS JOIN`
   将其与完整 Header 列目录展开为 `_TFL_KEY_*`；最终 logical-cell schema 和业务顺序
   保持不变。字符字段使用 DSD 引号规则，保留空值、空格、竖线、引号、
   百分号和宏样式文本；包含分号时使用 `DATALINES4`，字符字段使用显式 informat。
   按 2026-09-29 用户后续决定，生成器不再保存、修改或恢复 CARDIMAGE；沿用调用方
   SAS 会话的选项，长 inline records 的读取受该设置影响。
   实际 CR/LF 或四个连续分号不能直接进入 inline record，使用少量按记录定位的
   hex 字符赋值还原；普通 key-map 行不恢复逐字段赋值形式。字符 informat 的
   宏分隔点与格式结尾点分别保留，例如 `:$&_TFL_LABEL_LEN..`。

### Key map 的 Header 维度展开

状态：用户后续确认使用 `CROSS JOIN`，避免在 key-map 文本中重复列维度。

| SAS 对象 | 字段与职责 |
| --- | --- |
| `_TFL_HCOLS_001` | 每个已声明 Header 列一条记录：`header_column_id` 为 metadata 列 ID，`column_order` 为展示位置。Header 阶段从 metadata 构造一次，供 Header N 和所有 batch 共用，不从实际 membership 推导。 |
| `_TFL_KEY_MAP_<batch>` | 每个 chunk/row/statistic 一条记录。保存 `chunk_order`、`chunk_id`、`row_order`、`row_id`、`row_type`、`label`、`indent_level`、`statistic_id`、`statistic_order`、`digits_mode`、`digits_value`、`use_header_n`、`cell_format`；不包含 Header 维度。 |
| `_TFL_KEY_<batch>` | 将 compact map 与 Header 列目录 `CROSS JOIN`，得到完整 expected-cell key。普通 chunk 的 `node_key`、`group_path`、`node_label`、`node_order_path` 为空，`hierarchy_level` 为 0；nested analysis 继续与其 scope 的节点表 `CROSS JOIN`，由节点提供这些字段。 |

`PrimitiveBatchPlan.header_columns_dataset` 显式声明 `_TFL_HCOLS_001` 依赖，nested plan
继承该引用。Header 列目录在分析前创建，存活于本次生成程序的 WORK 中，发射器只读取它。
host-side `result_map` 保留完整 logical-cell 契约；序列化时仅取一份列间相同的行/统计量
metadata。展开按 chunk、row、Header column、statistic 顺序排序，nested map 再使用
node order path 确保顺序确定。没有受试者的 Header 列仍在目录中，继续参与空单元格补全。

### 回归边界

自动化测试使用 synthetic metadata，检查单步 Header、多列 membership、两种输出模式
与 duplicate 开关的四种组合、custom-code 顺序、dotted table ID、key-map 文本往返、
长记录、嵌入换行和 Shiny 预览/下载失效。Header 维度展开回归另外检查 key-map 文本不随
列数重复、展开后与完整 logical map 一致、空列保留和 nested node 连接。
测试不运行真实分析数据，也不声称验证
SAS 统计结果或 source/QC 数据一致性。

## P0-9：Continuous batch 的集中 source merge

状态：已确认（2026-09-14）。本决定只优化 top-level continuous primitive batch，
不采用 SAS runtime metadata、`CALL EXECUTE` 或跨类型通用 source 表。

### 已批准

1. 每个 continuous chunk 仍使用一个 DATA step 独立读取其 `source_data`、应用自己的
   `filter` 并直接投影为 batch 共同的窄 schema：`chunk_order`、继承类型的 `USUBJID`、
   `source_row`、numeric `analysis_value` 和可选的 `node_key`。chunk-specific
   analysis variable 在该投影阶段解析；不得把原始 source 的 `s.*` 直接 append 到
   共同表。
2. 同一 continuous batch 的投影结果先按 template 顺序 append 到一个集中 source
   对象（`_TFL_CPRE_<batch>`）。只有 data grain、merge key、SAS key 类型/长度由调用方
   保证兼容的 chunk 才能进入同一集中对象；平台不读取 SAS 数据推断兼容性。
3. duplicate check 在集中对象上执行一次，BY 顺序为 `chunk_order` 加 batch 的
   declared subject key。检查只报告重复，不使用 `NODUPKEY`、first-record 选择、
   去重或聚合；关闭 duplicate option 时整个 guard 均省略。auto dedup（默认关闭）
   是独立开关：开启时在检查之前对同一集中对象执行一次 `NODUPKEY` 并每个键保留一条
   记录（保留哪一条由 `PROC SORT` 决定，见生成选项一节），
   后续 scaffold 与 merge 读取去重后的对象。
4. Header membership merge 在 batch 级执行一次。生成一个 batch chunk-order 目录并
   与 `_TFL_MEM_<seq>` 构造 scaffold，再 left join 集中 source；这样每个
   `chunk_order × membership` 组合在缺少 filtered source record 时仍保留。后续
   expected-cell skeleton、统计和 render 契约不变。
5. 集中 merge 只适用于 top-level continuous batch。categorical 仍按其 counting-unit
   和 typed key contract 独立设计；hierarchical 继续保持 container scope 和 nested
   primitive 的独立 source/merge。
6. 生成期物理对象继续位于 `WORK`，使用 `_TFL_` 固定命名；`_TFL_CIN_<batch>` 仍是
   进入 `PROC MEANS` 的最终 normalized input，`_TFL_CPRE_<batch>` 和
   `_TFL_CMERGE_<batch>` 仅作为集中 source/merge 中间对象。

### 被拒绝的替代方案

- 直接 `SET` 所有原始 `source_data`：会引入变量类型/长度冲突并改变 source contract。
- 全 table 跨 continuous、categorical、hierarchical 共用一个 source 表：不同 grain、
  counting unit、typed key 和动态节点边界无法保持统一。
- 用字符化的通用 key 替代 typed key：可能改变 SAS 缺失值、前导零和排序语义。
- 用集中 merge 省略 chunk scaffold：缺失 source 时可能改变 downstream expected-cell
  和 denominator 语义。

### P0-9 categorical extension

状态：已确认（2026-09-14）。categorical batch 采用 counting-event 集中 merge，
不把原始 categorical source 直接 append。

1. 每个 top-level categorical chunk 使用一个 DATA step 读取 source 并执行 filter，
   同时输出 filtered source key 表和 denominator/row-condition 事件窄表
   `_TFL_KPRE_<batch>_<chunk>`，避免为两种投影重复读取 source。事件至少保留
   `chunk_order`、`USUBJID`、`source_row`、`row_order`、`node_key` 和该 chunk
   counting unit 所需的 typed key；`row_order=0` 表示 denominator，正数表示
   numerator。
2. 每个 chunk 同时投影一个只含 `chunk_order`、`USUBJID` 和 `source_row` 的 filtered
   source key 表。同一 categorical batch 的事件表按 template 顺序 append 到
   `_TFL_KPRE_<batch>`；key 表 append 后只执行一次 source duplicate guard（BY
   `chunk_order USUBJID`）。guard 不在已展开的 event 表上运行，避免同一 subject 的
   denominator/numerator events 被误报为重复。该 guard 仅报告重复，不去重、不聚合；
   duplicate option 关闭时整个 key append/guard 均省略。auto dedup 开启时在事件投影
   之前对 filter 后的 source 执行一次 `NODUPKEY`，事件表与 key 表都从去重后的 source
   生成，因此 `source_row` 重新按保留记录编号。
3. Header membership expansion 在 batch 级执行一次。事件先与 `_TFL_MEM_<seq>`
   inner join；同时为每个 batch chunk 与 membership 生成 header-population denominator
   scaffold，再 union 到 `_TFL_KMERGE_<batch>`。后续 `_TFL_KIN_<batch>`、counting-unit
   dedup、exclusive overlap guard、`PROC FREQ`、expected-cell skeleton 和 render
   契约保持不变。
4. hierarchical nested primitive 继续沿用独立 source/merge。不同 counting unit 或
   typed key contract 的 categorical chunk 不应进入同一 batch；后续需要在 batch
   planner 中增加显式 key-compatibility 分组，而不是把 key 字符化。

## P0-10：Hierarchical 按 anchor level 集中 Header membership expansion

状态：已确认（2026-09-16）。本决定只消除同一 hierarchical container、同一
`anchor_level` 下多个 analysis block 重复执行的 Header membership join；不合并
primitive analysis procedure，也不跨 container 或 level 共享运行期对象。

### 数据对象与职责

| 对象 | 字段与职责 |
| --- | --- |
| `_TFL_HLEVEL_<container>_<level>` | record-grain level source。保留 container filtered source 字段、`source_row`、`node_key`、`group_path`、`node_label`、`node_order_path`、`parent_node_key` 和 `hierarchy_level`；不含 Header column expansion。 |
| `_TFL_HMEM_<container>` | subject-grain Header membership，至少包含 `USUBJID`、`header_column_id` 和 `column_order`。 |
| `_TFL_HMERGE_<container>_<level>` | 该 level 的共享 expanded source。由 `_TFL_HMEM_*` 与 `_TFL_HLEVEL_*` 按声明的 subject key inner join，一条 level source record 对每个适用 Header column 输出一条记录，并保留原始 `source_row` 与 typed source fields。 |
| nested primitive input | 每个 block 从共享 `_TFL_HMERGE_*` 独立投影自己的 `analysis_variable`、row events、counting-unit typed keys 和 denominator eligibility。 |

### 生命周期和边界

1. hierarchical container 完成所有 level discovery 后，收集被 analysis block 引用的
   anchor levels，并按 level 首次出现顺序各生成一次 `_TFL_HMERGE_*`。
2. 同一 level 的 continuous/categorical blocks 只读取共享 expanded source，不再重复
   membership SQL，也不重新赋值 `source_row`。不同 level 必须使用不同对象。
3. block 继续拥有独立的 nested batch namespace、expected-cell map、counting unit、
   denominator、`PROC MEANS`/`PROC FREQ`、statistic 和 render 输出；本决定不合并过程调用。
4. source duplicate guard 仍只在 container filtered source 上执行一次；expanded source
   不重复检查。Header membership、node discovery、global denominator 和 failure 行为不变。
5. `_TFL_HMERGE_*` 只存在于当前生成 SAS 的 `WORK` 生命周期，不写回 metadata、bundle
   或 workspace，也不增加新的 YAML 字段。

## P0-11：相邻兼容 Hierarchical continuous blocks 共用 PROC MEANS

状态：已确认（2026-09-29）。用户批准按
[完整设计](hierarchical-continuous-batching-proposal.md) 实施。该设计包含全部对象字段、
兼容 key、所有权、生命周期和验收条件。本决定仅替代 P0-10 对以下 blocks 不合并
procedure 的限制；不更改 YAML、workspace、UI、统计量或 categorical 契约。

### 已批准的决定

1. 仅合并同 container、同 anchor level、原 sequence 相邻、counting_unit 和 typed
   distinct_key 字段及顺序一致、使用同一内置 continuous definition 的 blocks。
   不同 analysis_variable、rows、digits 或 placement 不阻止合批。其他 blocks 与
   替代注册 emitter 沿用独立执行路径；单 block 不创建共享对象。
2. 每个 block 保留原 nested batch 编号，独立完成 counting-unit materialization
   和 precision。共享输入 `_TFL_HCIN_<container>_<first-block>` 仅包含 numeric
   `analysis_order`、`column_order`、`analysis_value` 及 character `node_key`；
   analysis_order 是原 block 位置，typed keys 不进入共享表。
3. 一次 PROC MEANS 按 analysis_order/column_order/node_key 分析，共享 raw
   `_TFL_HCRAW_<container>_<first-block>` 保留上述身份及既有八项 numeric statistics。
   按 analysis_order 拆回各 block 原有 raw dataset，移除 analysis_order，恢复
   chunk_order=1；然后执行各自 expected-cell 与 raw/precision join。P0-13 仅共用
   value/digits DATA step，输出各自 STAT，再逐块 render 和 hierarchical 映射。
4. result_sort、same_row、below 继续消费原 block 独立结果，所有 namespace、
   analysis_id 和 row/header identity 保持原责任边界。
5. 全组 preparation 成功后才执行共享 MEANS。若后一个 block 出现多个非缺失记录，
   原 guard 写入 continuous_unit_multiple_values 并 ABORT CANCEL，较早 block 的
   statistic/render 也可能尚未产生。这一部分 WORK 表及诊断时序变化已确认；
   单项错误内容、字段顺序和终止语义不变，duplicate-check 开关不关闭该 guard。

### 未采用的替代方案

- 跨 categorical、不兼容块、level 或 container 重排，以避免扩大执行时序变化。
- 全面改为多 block primitive plan，合并 materialization 与 render；当前无此需要。
- 字符化 typed keys、改变 counting unit、共享 base_digits 或增加 YAML 合批开关。

### 与 auto dedup 的层级约束

auto dedup 必须发生在 P0-11 共享 MEANS 的上游，即在 hierarchical container
filtered source（`_TFL_HSRC_<container>`）这一层完成，不得下沉到共享输入
`_TFL_HCIN_<container>_<first-block>` 或 P0-11 的 counting-unit materialization
之内。原因：`continuous_unit_multiple_values` 是全组 preparation 阶段的硬性
ABORT（本决定第 5 条），若在 `_TFL_HCIN_*` 层去重，guard 会先于任何去重触发并
ABORT CANCEL，去重选项在该路径上永久无效；同时该 guard 不受 duplicate-check
开关控制，因此也不能靠开关组合绕过。当前实现把去重放在 `_TFL_HSRC_*` 之后、
level discovery 之前，共享 MEANS 读取的是已经去重的层级来源，语义一致。
后续若调整去重位置，必须先修改本约束并重新确认第 5 条的失败时序。

减少 procedure 次数并不保证运行更快；新增窄表 append 和 raw 拆分的成本需要另行测量。

2026-09-29 目标澄清与维护：用户明确优先减少生成代码量、提升可读性，接受无运行
加速。现有契约内将单 nested continuous chunk 的两个同结构输入在同一 DATA step
创建，并将 shared raw 的逐 block 拆分合为一个显式 OUTPUT DATA step。名称、字段、
统计/布局身份及失败边界保持；范围和代码量记录见
[源码精简维护](hierarchical-continuous-batching-proposal.md#7-源码精简维护2026-09-29)。

## P0-12：Hierarchical 最终行身份与组装修复

状态：已确认（2026-09-29）。用户在 session
`01a0e8c4-3963-7960-8a3b-1656ace9dddc` 批准先修复最终行编号和组装，
补充明确预期结果的 fixture，再开展性能测量。本项修复既有行语义，不新增 YAML
字段、UI 行为或 SAS 执行功能。

### 对象、字段与责任

| 对象或字段 | 责任与边界 |
| --- | --- |
| nested render 的 `row_order` / `row_sequence` | primitive block 内的静态行位置；不同 block 和 node 可重复，不能直接作为 container 最终行号。 |
| `node_key`、`runtime_row_id` | 动态节点及其逻辑行身份。相同 `row_id` 或相同 label 出现在不同节点、block 时仍须保留各自的行；跨 chunk 身份由 `chunk_id` 限定。 |
| `_TFL_HFLAT_<container>.order_key` | 按最终 node display path、placement、block order 和 row order 排列的逻辑行键；同一行的所有 Header columns 共用一个键。 |
| hierarchical render 的 `row_sequence` | container 独占的连续最终行号，从 1 开始；仅在 `first.order_key` 时递增。输入 `SET` 必须排除旧的 block-local `row_sequence`，避免覆盖 retained counter。 |
| `chunk_order`、`column_order` | 分别限定 table 内 chunk 顺序和行内 Header column 位置；不同 container 可各自从 row_sequence=1 开始。 |
| `_TFL_CELLS_001` / `_TFL_WIDE_001` | 按 chunk_order / row_sequence / column_order 排序，再按 chunk_order / row_sequence 将每行所有列组装为一条宽表记录。 |
| `WORK._TFL_ASM_001` | 在宽表基础上按既有 chunk/level 边界插入 spacer；非 spacer 行必须完整保留宽表顺序、身份、label、indent 和 cells。 |

`_TFL_HFLAT_*` 及 nested result 保持只读；新的 row_sequence 只写入 container
render output，再由 table assembly 消费。上述对象仅存在于生成 SAS 的 WORK
生命周期内，不修改 metadata、workspace 或各 block 的统计结果。

### 已批准的修复与验收

1. 在展平 DATA step 的输入 dataset option 中 `drop=row_sequence`，保留既有
   `RETAIN row_sequence 0` 和 `first.order_key` 递增；仅使用 RETAIN 无法防止 SET
   每条 observation 再次覆盖计数器。不得改成按 observation 编号，否则同一行
   的各 Header columns 会被拆开。
2. 保持既有顺序：当前节点行、当前 level 的 below 静态行、动态子节点。
   result_sort 确定展示路径之后才编号；same_row 不额外添加重复 label 行。
3. 源码回归覆盖相同 row ID 的多个 blocks、多层级、标签行、categorical 子节点、
   多 container 与普通 chunk 混排、空输入，以及 report/compare 两条输出路径。
4. 独立预期 fixture 固定最终行数、顺序、runtime identity、label、indent、所有列值
   和 spacer 位置。基线为 2 nodes × 2 rows × 3 columns，即 12 cells、4 wide rows；
   不能再仅以共享/独立统计路径相互一致作为最终组装正确性的证据。

未采用按 row_id 或 label 合并的方式，因为它们可在不同节点及 block 重复；也未
改变 table assembly 的既有分组键。R 自动化验收仍遵循 source-only 边界；手写
synthetic SAS fixture 提供给外部 SAS 环境执行，构建 source 不代表运行期验证通过。

2026-09-29 验证更新：用户随后批准继续外部 synthetic SAS 验证与性能测量。
5 个行组装场景已在 SAS 9.4 通过；运行证据与测量边界见
[验证记录](hierarchical-runtime-verification.md)。该授权不改变应用产品边界或
常规 R 测试的 source-only 约定。

## P0-13：兼容 continuous blocks 只共享 value/digits 转换

状态：已确认（2026-09-29）。用户批准按
[完整边界](hierarchical-result-sharing-proposal.md) 实施，并明确可读性优先、
不增加共享中间表或宏封装。

1. 仅对 P0-11 已形成且至少两个 members 的 continuous group，共用一次统计值
   转换和 digits 解析 DATA step；group 范围、preparation、precision、MEANS、
   raw 拆分、expected-cell、raw/precision join、render 和布局责任保持原契约。
2. 先完成各 block 原有 `_TFL_CJOIN_*`，再按原 member 顺序通过 SET 读取；IN=
   临时标志明确将每条记录 OUTPUT 到原 `_TFL_STAT_*`。保留全部 32 列及属性，
   不增加共享编号、表或宏，不按局部 row ID 推断归属。
3. 所有 block 的转换完成后，继续按原顺序执行各自 render/HSMAP。用户接受这项
   创建时机变化及异常时部分 WORK 表可能不同；正常统计、cell 和布局结果不变。
4. 负相对精度明确沿用当前源码的 ERROR + NE：每条受影响 statistic 写入原诊断、
   设置 estimable=0 和 missing resolved_digits，继续运行，不去重、不新增 ABORT。
   R 的显式精度解析 helper 仍可对非法参数抛错，不能据此称应用已检查实际数据精度。
5. 原 KEY_MAP、KEY、CJOIN、STAT、RSTAT、REND 名称保留；单 block、不兼容块、
   其他 primitive 和替代 emitter 沿用原路径。复杂逻辑保持展开；边界明确的短规则
   按下述后续排版决定允许一条一行。

未采用整组 expected-cell/join/render 流水线或生成 SAS 宏：本轮认为额外中间表、
身份追踪和定义/调用跳转会增加阅读成本。

2026-09-29 排版维护：compact map 的 INPUT 每个字段/informat 单独一行，使用
清晰缩进，末尾单独结束分号。字段与 informat 原文及其顺序、inline data records、
还原语句均保持。增加物理行数是为便于阅读，不改变共享边界。后续 CARDIMAGE
处理以以下决定为准。

### 后续维护：删除 CARDIMAGE 防御，短规则按边界合行

2026-09-29，用户明确要求删除 CARDIMAGE 防御，并将 Header 派生等有明确边界的
重复模式合为单行。已删除保存选项、OPTIONS NOCARDIMAGE、恢复选项和清理临时
宏变量四条语句，不替换为程序全局选项或其他保护机制。

采用“一条规则一行”，不把整个 DATA step 合为一行：

- 每个 Header column 的独立 IF、两个身份赋值及 OUTPUT/END 在同一行；不同列
  另起一行，仍为独立 IF，重叠 membership 不改为互斥 ELSE IF。
- 每个 categorical numerator 条件、row_order 和 OUTPUT 在同一行；denominator
  的 row_order=0 输出也是单独一行。外层 source_row 判断保持展开。
- continuous/categorical chunk catalog 每个 chunk_order + OUTPUT 一行。
- 层级标签展开时，每个 Header 的 column_order、header_column_id、OUTPUT 一行。

原有 INPUT 按字段分行保持。复杂嵌套分支、计数单元冲突处理、精度解析及 cell_text
累积不压成单行。metadata 表达式与字符串原样保留；其中原有换行不被强行删除。
本次只调整上述源代码边界的排版，不引入通用压缩器、新状态或配置。

### 收尾文档对齐：现有 Header orientation

2026-09-29，核对已实现并写入用户指南的 Header 契约：orientation 必填，取值为
portrait 或 landscape；canonical YAML 位于 source_data 之后。导入不推断默认值，
Header editor 必须明确选择；Table 仍不含此字段。Report 使用它计算 Letter 页面
可用宽度，QC 沿用同一 metadata 结构但不应用 Report 页宽检查。本次补齐便携契约
中的遗漏，不修改 schema、生成器或 UI 行为。
