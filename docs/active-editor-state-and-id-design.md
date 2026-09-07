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
