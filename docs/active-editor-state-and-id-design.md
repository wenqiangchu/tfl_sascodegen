# Active editor state, draft comparison, and user-entered IDs

状态：已确认（2026-09-08）。本文是 Shiny 编辑器状态和顶层 metadata ID
交互的权威补充说明。它不改变 YAML、SAS emitter 或 bundle 契约。

## 1. 最小内存对象

### 1.1 已保存 workspace

`workspace` 是当前 session 独占的已保存 metadata 快照：

```r
list(
  schema_version = 2L,
  populations = list(),
  headers = list(),
  tables = list(),
  templates = list(),
  revision = list(saved_revision = 0L)
)
```

它不保存 UI 控件值、session 信息、pending action 或运行期结果。

### 1.2 当前编辑入口

只保留一个 `active_editor`：

```r
list(
  panel = "population",        # population | header | table | template
  document_type = "population",
  document_id = "fas"
)
```

不维护四个 panel 的 `selected_ids`。非活动 panel 的选择由对应 UI 控件持有，
只有在该 panel 成为活动编辑器或执行边界动作时才读取。

### 1.3 当前 draft

`active_draft` 只保存操作类型、目标和进入编辑时的原始快照：

```r
list(
  operation = "update",        # update | create
  target = list(
    document_type = "population",
    document_id = "fas"
  ),
  original = <metadata object or NULL>
)
```

不保存实时 `current` 副本，也不把每个 input 事件连接到 draft。`current` 在
Save、Discard、Switch、Delete、Import 或 Generate 等边界动作发生时，由当前
panel 的 collector 一次性读取、类型转换并标准化空值。

### 1.4 待执行动作

dirty guard 出现时，可暂存一个 `pending_action`（例如目标 panel/id 的 switch
或 delete）。它只用于 guard 通过后恢复动作，不属于 metadata，也不参与 dirty
比较；动作完成或取消后清空。

## 2. 顶层对象 ID 与 New

- Population、Header、Table、Template 的顶层 `id` 必须由用户输入。
- 点击 New 时先打开 ID 对话框；用户确认后才创建 pending object，并将其设为
  `active_editor`。
- ID 对话框取消不会创建对象，也不会改变 workspace、draft 或 revision。
- 空 ID、重复 ID 或不符合结构契约的 ID 在创建边界报错，并保持已有 workspace
  不变。
- 顶层对象创建后 ID 不可 rename；编辑已有对象时 ID 控件只读。
- Chunk、row、statistic、level、analysis block、spanning header 等内部位置
  标识可由系统按 sequence 自动生成或重建；重建时同步更新引用。

新建对象在 Save 前始终是 `create_pending`，即使用户尚未修改其他字段。Save
才会把它正式写入已保存 workspace。

## 3. Dirty 判定

用户编辑控件时只改变浏览器中的 UI 值；workspace 和 draft 不立即改变。执行
边界动作前，collector 产生 `current`，然后使用
`workspace_canonical_equal(original, current)`：

| 情况 | 状态 | 是否拦截切换 |
| --- | --- | --- |
| 没有 active draft | `none` | 否 |
| 已有对象，current 等于 original | `update_clean` | 否 |
| 已有对象，current 不等于 original | `update_dirty` | 是 |
| 新对象尚未 Save | `create_pending` | 是 |

因此，用户改动后再恢复到原值，视为 clean，不显示未保存警告。

## 4. 边界动作

- **Switch**：先收集当前 UI 并比较；clean 时直接切换。dirty 时显示两个选项：
  `Discard changes` 或 `Cancel`。Cancel 恢复原选择；Discard 重新渲染原始对象后
  切换到目标。
- **Save**：只在按钮点击时读取当前 UI。内容有变化才写入 workspace 并递增
  `saved_revision`；无变化不产生新 revision。
- **Discard**：已有对象重新渲染 original 并清除 draft；新对象直接移除整个
  pending object。
- **Delete**：先执行 dirty guard 和引用检查；通过后立即删除，不创建新的用户可见
  delete draft。删除 pending create 等同于丢弃该新对象。
- **Import**：在需要时先执行当前 editor 的边界收集和 dirty guard；成功导入是
  原子替换并清空旧 draft/选择，失败则保留原 workspace。
- **Generate**：在需要时先执行当前 editor 的边界收集和 dirty guard；生成不会
  隐式保存 metadata。

程序同步只负责重新渲染 UI 控件值，不改变 dirty 事实；技术性 input token（若
实现仍需要）不能作为 dirty 状态来源。

## 5. 未决事项核对

截至 2026-09-08，没有其他需要用户确认的设计事项。后续工作属于实现、测试和
可用性优化，不得在未重新确认的情况下改变本文件定义的状态或交互语义。

## 6. Dashboard 总体布局

应用采用 `shinydashboard` 风格的 `dashboardPage`：sidebar 负责主导航，body
负责当前 dashboard，顶部 notification 区域显示导入、保存、删除和生成结果。
主菜单固定为四项：

1. **Metadata**：包含两个独立 tab/panel：`Population` 和 `Header`；
2. **Table Metadata**：编辑 table 及其对象引用和 custom SAS code；
3. **Template Editor**：编辑 template、chunk、row、statistic 和 hierarchical
   结构；
4. **Generate SAS**：选择已保存 table、生成并预览 SAS source、下载 `.sas`。

全局操作位于 sidebar 或顶部工具区：

- `fileInput` 上传 ZIP metadata bundle；选择文件后自动导入，不需要第二个
  `Import metadata` 按钮；如果已有 workspace，导入前按 dirty 规则提示将覆盖；
- `Download metadata` 下载最近一次已保存 workspace 的 ZIP；不会隐式保存当前
  编辑，也不会清除 dirty 状态；
- workspace status/revision 只读显示；
- 不提供 study selector、数据集上传、Run SAS、结果文件查看或 AI 菜单。

每个 metadata dashboard 均遵循相同的左右分栏：左侧为对象列表和对象级操作，右侧
为当前对象编辑器和对象级操作。左侧列表是切换对象的唯一入口；不再额外提供与
列表双向同步的 select input。

## 7. Population dashboard

### 左侧对象列表

- 有序 population 列表（DT 或等价列表）；
- 列表右上角放置 `New` 和 `Delete`；
- `New` 打开 ID 对话框；确认后将新对象加入列表并进入编辑状态；
- `Delete` 针对列表当前选中对象执行即时删除流程；删除前检查 dirty 和引用。

### 右侧编辑卡片

- `ID`：已有对象只读；新对象在 ID 对话框确认后只读；
- `Label`：单行文本输入；
- `Expression`：多行 SAS expression 输入；
- `Save`：仅在点击时收集字段并保存；
- `Discard changes`：恢复原始对象；新对象则移除整个 pending object。

Population 切换、New、Delete、Import 和 Generate 都先执行当前编辑器边界收集。
只有 canonical compare 判定为 dirty 时才显示 `Discard changes`/`Cancel` 对话框。

## 8. Header dashboard

Header 是 Metadata dashboard 中独立于 Population 的 panel。

### 左侧对象列表

- 有序 header 列表；
- 列表右上角放置 `New` 和 `Delete`；
- `New` 使用 ID 对话框；
- `Delete` 删除当前选中的 header，但被 table 引用时显示引用错误并保持 workspace。

### 右侧编辑区域

- `ID`：只读；
- `Source data`：opaque SAS dataset reference，可填写 `adsl`、`adam.adsl` 或宏变量；
- `Save`；
- `Discard changes`；
- header columns DT；
- DT 上方或右上方放置 `Add row` 和 `Delete selected row`。

Header columns 和 spanning headers 必须在同一个 DT 中展示。DT 列至少包括：
`id`、`label`、`condition`、`display_order`、`width`、`alignment`、
`spanning_header_1`、`spanning_header_2`。spanning 列显示 label，不显示内部 span ID。

已有 column 的 `id` 不可修改。DT 编辑事件在 adapter 中完成 JavaScript 0-based 到
R 1-based 的转换、类型转换和空值标准化。保存时按 DT 行顺序（并以
`display_order` 作为 canonical 列顺序）扫描连续非空 spanning label，生成
`spanning_headers` 和 column 引用；不连续但同名的 label 生成不同 span。

## 9. Table Metadata dashboard

### 左侧对象列表

- 有序 table 列表；
- 列表右上角放置 `New` 和 `Delete`；
- `New` 使用 ID 对话框并创建 pending table；
- `Delete` 先执行 dirty guard，再执行引用检查和确认。

### 右侧编辑卡片

- `ID`：只读；
- `Population`：对象 ID 下拉框；
- `Header`：对象 ID 下拉框；
- `Template`：对象 ID 下拉框；
- `custom_code.before`：SAS source text area；
- `custom_code.after`：SAS source text area；
- `Save`；
- `Discard changes`。

引用下拉框仅提供 workspace 中已有对象 ID；平台不读取或验证外部 SAS 数据集。
custom code 原样保存，不作语法、安全性或依赖验证。

## 10. Template Editor dashboard

### 左侧对象列表

- 有序 template 列表；
- 列表右上角放置 `New` 和 `Delete`；
- `New` 使用 ID 对话框；
- `Delete` 删除当前 template（若存在引用则阻止）。

### 右侧 template 编辑器

- `ID`：只读；
- `Stub header`：模板级输入；
- `Save`；
- `Discard changes`；
- 每一个 chunk 都是独立 card，不把所有 chunk 放在一个总 card 内；
- chunk card 按 sequence 从上到下排列。

每个 chunk card 内直接展示并编辑该 chunk 的字段，不通过全局“选择 chunk 后再编辑”
的下拉框。chunk `type` 由 metadata/registry 决定且不可编辑；chunk 内部位置 ID
由系统维护，不提供用户输入框。

### Chunk card 公共内容

- `Source data`；
- 可选 `Filter`；
- 类型专属字段；
- `Add row`、`Delete row`、`Move up`、`Move down`；
- rows/statistics 使用嵌套 DT 或等价嵌套编辑器；
- row、statistic 的新增/删除/排序按钮位于对应 card 内。

### 类型专属内容

- **Continuous summary**：`analysis_variable`、rows、statistics、cell format；
- **Categorical summary**：结构化 denominator；`non_missing` 时显示 variable，
  `custom` 时显示 SAS expression；rows 允许 condition、statistics 和 cell format；
- **Hierarchical summary**：
  - source contract；
  - 有序 levels，每个 level 显式选择 parent level；
  - level 的新增、删除、排序；
  - analysis blocks 的新增、删除、排序和类型选择；
  - 结构化 denominator；
  - nested rows/statistics 的新增、删除、排序；
  - 多层 parent-child 关系编辑；
  - `same_row`/`below` placement、missing policy、order variable/direction 等字段。

hierarchical 的运行时 group values、node key、runtime row ID 和动态 label 只在
生成 SAS 时产生，不写回 template metadata。

## 11. 统一按钮与交互规则

对象列表级按钮统一放在左侧列表右上方：`New`、`Delete`。右侧编辑区只放与当前
对象有关的操作：`Save`、`Discard changes`，以及 Header 的 `Add row`/
`Delete selected row`、Template chunk/row/level/block 的结构操作。

任何切换、New、Delete、Import 或 Generate 都遵循：

```text
读取当前 UI -> 类型转换/空值标准化 -> canonical compare
  -> clean: 继续动作
  -> dirty/create_pending: Discard changes 或 Cancel
```

对话框只保留两个选项：`Discard changes` 和 `Cancel`。首次 Import 或 clean 状态下
不应弹出 dirty 提示。Cancel 必须恢复原列表选择；Discard 必须重新渲染原始值后
继续目标动作。程序同步只重新渲染控件，不触发保存或 dirty 状态变化。
