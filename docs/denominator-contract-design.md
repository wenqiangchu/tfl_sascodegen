# 统一分母契约

日期：2026-10-31。

## 1. 状态与批准依据

用户在 session `01a182b8-5fd8-7271-bc73-8ed5ddafc291` 中认可了统一分母方案：
「好的，我觉得这个优化方案是合理清晰的」。对应方案包含三个范围和四个字段，
见第 2 节。此前该确认后的工具调用未发生，仓库仍采用旧模型。

用户在 session `01a19004-a9fc-73b2-987d-498188be499d` 明确确认第 7 节的三条
实施规则并要求继续。第 2 至第 6 节以及第 8 节作为实施依据；迁移方式、范围限制、
条件顺序和 emitter 对象映射均已确认。

## 2. 已批准的目标模型

两种 categorical primitive chunk 和 hierarchical categorical block 共用分母对象。
continuous analysis 的 n 仍是非缺失分析单位数，不引入 denominator。

| 字段 | 值或形状 | 职责 |
| --- | --- | --- |
| scope | header_population、chunk_source、current_group | 独立选择分母来源与范围。 |
| unit | distinct_subject、record、distinct_key | 独立声明分母计数单位，不继承分子 counting_unit。 |
| expression | 可选的 SAS logical expression | 指定该范围内的分母资格条件；缺省表示不额外筛选。 |
| distinct_key | unit=distinct_key 时必填的字段序列 | 分母自己的业务身份键，不借用分子的 distinct_key，不携带排序方向。 |

| scope | 已批准的分析含义 |
| --- | --- |
| header_population | 当前 Header 列的人群，保持受试者集合的含义。 |
| chunk_source | 顶层 chunk 完整 filter 后的 source，限定当前 Header 列，不限定当前动态节点。 |
| current_group | 当前 anchor 节点内的 source，限定当前 Header 列。 |

原 non_missing/custom 的资格筛选改由 expression 表达，不再作为范围。
计数身份和排序选记录仍是两个不同问题；该对象不自动派生最高严重程度。
父节点分母范围没有批准，本轮不增加。

## 3. 已确认：来源、处理顺序与结构约束

### 3.1 Header 人群与条件变量

Header 分母的条件变量来自 `header.source_data`，而不是 chunk source。
生成顺序为：

```text
header.source_data
  -> population.expression
  -> 当前 column.condition
  -> 当前 denominator.expression（可选）
  -> 按 USUBJID 去重
  -> 当前列的 denominator count
```

已有 membership 只保存 USUBJID、header_column_id 和 column_order，因此不能在它
上面判断 EVALFL 等源变量。已有 population 派生表保留 Header source 字段，可以
作为显式输入；分母条件必须在只剩身份字段之前生成。

如 Header source 同一受试者有多条记录，只有同时满足 population、当前列条件
和分母条件的记录才进入分母，然后按 subject 去重；存在至少一条这样的记录就计 1。
不能先任意保留一条再判断条件。

Header 上显示的 N 保持来自完整 membership。分母条件不修改该 N、不删除列、不改变
分析 source 的 membership。EVALFL 如果只存在于 ADAE，不能在 Header scope 中凭空
引用；应由调用方准备合适的 Header source，或明确选择 chunk_source。

header_population 只允许 unit=distinct_subject。record/distinct_key 对应的
事件、周期、评估等单位使用下面的 source 范围。

### 3.2 完整 source 与当前节点

```text
chunk.source_data
  -> chunk.filter（可选）
  -> 按 USUBJID 关联当前列 membership
  -> chunk_source：直接使用以上记录
     current_group：再限定 anchor 节点的记录
  -> denominator.expression（可选）
  -> 按 denominator.unit / denominator.distinct_key 形成计数事件
  -> 当前列或当前节点/列的 denominator count
```

chunk_source 的范围在动态 levels 的 missing_policy 排除记录之前确定。它不受
当前节点、后续 level 或 analysis row condition 限定。current_group 则使用建立
当前 anchor 节点时实际保留的 source records，沿用现有 level 的分组和缺失规则。

record 数真实 source records，不计空 membership scaffold，也不因输出多个分类行
重复计数。distinct_subject 在范围内按 USUBJID 去重；distinct_key 仅按自己的
字段序列去重，不暗中追加 USUBJID。所有身份仍由当前列和必要的节点维度限定。

顶层 primitive 允许 header_population/chunk_source；current_group 只允许
hierarchical block 使用。primitive 没有 anchor，不把 current_group 静默转换为
chunk_source。两个 source scope 均允许三种计数单位。

### 3.3 expression 与分子

先判断分母资格，再形成分母的 distinct units。同一 subject/key 的多条记录，
存在至少一条合格记录就进入分母；这是资格筛选，不是最高值选记录。

expression 只作用于分母，分子仍由自己的 row condition 和 counting_unit 决定。
分子、分母可以声明不同的单位；使用者负责该比例的分析解释。不得自动把分子限制为
分母子集，也不得因分母为零把实际 n 改为零。需要两者共同过滤时使用 chunk.filter
或在各自条件中明确声明规则。

scope/unit 必填，不推断默认值；expression 提供时必须是非空字符串。
distinct_key 仅在 denominator.unit=distinct_key 时存在，必须非空、字段不重复，
使用现有计数键的结构约束。缺失独立分母键应返回已有结构错误，不能退回分子的键。
canonical 字段顺序为 scope、unit、expression、distinct_key；缺省可选字段省略。

平台只保存表达式并生成 SAS，不检查实际变量存在性、不读取数据、不求值表达式。

## 4. 已确认：业务示例

以下是 v2 模型示例，随本次解析器与生成器实施。

```yaml
# PT subject incidence among the full safety population.
denominator:
  scope: header_population
  unit: distinct_subject
```

```yaml
# Evaluable subjects within the header population; displayed header N is unchanged.
denominator:
  scope: header_population
  unit: distinct_subject
  expression: "EVALFL = 'Y'"
```

```yaml
# Known highest severity within the current SOC.
denominator:
  scope: current_group
  unit: distinct_subject
  expression: 'not missing(SOC_MAX_SEV)'
```

```yaml
# Event composition against all events passing the container filter.
denominator:
  scope: chunk_source
  unit: record
```

```yaml
# Unique subject/cycle units with an evaluable assessment.
denominator:
  scope: chunk_source
  unit: distinct_key
  expression: "EVALFL = 'Y'"
  distinct_key:
    - USUBJID
    - CYCLE
```

## 5. 已确认：旧配置迁移与版本策略

### 5.1 语义对照

| 旧宿主与配置 | 新配置 | 注意事项 |
| --- | --- | --- |
| primitive type=header_population | scope=header_population、unit=distinct_subject | 保持旧 Header 人数分母。 |
| primitive type=non_missing、variable=X | scope=chunk_source、unit=distinct_subject、expression=not missing(X) | 旧 primitive 分母实际按 subject 计数，不能继承新的分子单位。 |
| primitive type=custom、expression=E | scope=chunk_source、unit=distinct_subject、expression=E | 保留 E 的原文本。 |
| hierarchical header_population、unit=distinct_subject | 同名 scope/unit | 保持完整 Header 人群。 |
| hierarchical header_population、unit=record | scope=chunk_source、unit=record | 保持旧完整容器 source 记录数，不转成 Header source 记录数。 |
| hierarchical header_population、unit=distinct_key | scope=chunk_source、unit=distinct_key，加独立分母键 | 必须明确键，见下文。 |
| hierarchical current_group | 同名 scope/unit | 保持 anchor 节点范围；distinct_key 需要独立键。 |
| hierarchical non_missing、variable=X | scope=current_group、保留 unit、expression=not missing(X) | distinct_key 需要独立键。 |
| hierarchical custom、expression=E | scope=current_group、保留 unit、expression=E | 保留 E；distinct_key 需要独立键。 |

旧 denominator.unit=distinct_key 只有在确实提供了可用的分子 distinct_key、且该键
符合原分析意图时，才能明确复制到新的 denominator.distinct_key。原配置没有可用
键时不能宣称等价迁移成功：旧行为可能只按位置去重，须由用户补齐业务键。

### 5.2 已确认版本策略

Bundle schema_version 升为 2，新应用严格接受和导出 v2；旧 v1 返回已有
bundle_schema_unsupported，不在导入时猜测或静默转换。按上表显式更新 metadata
及 manifest 后再导入。独立 template 仍由所在 bundle 的 manifest 声明版本。

这样没有双模型、自动迁移状态或兼容分支，符合严格、原子导入边界；已有 bundle
需要显式迁移。自动转换 v1 不在当前契约内。

## 6. 已确认：所有权与验收边界

分母声明随其 categorical chunk/block 保存，draft 编辑与 Save 沿用已有 workspace
生命周期。生成器只读已保存 snapshot；分母派生对象存在于生成程序的 SAS WORK
生命周期内，不写回 workspace、不修改共享 membership 或容器 source。

生成器显式交付 Header population source、完整 chunk source、必要的 anchor source
及对应 membership。分母计数输入与分子输入可以不同，不能只换 scope 名称而仍使用
同一张 node source。具体对象字段和消费者见第 8 节 emitter 实施映射。

Header N 仅可在 header_population + distinct_subject 且没有额外资格筛选时复用。
存在 expression 时必须生成资格分母；不能只看 scope/unit 就走原 use_header_n 分支。
不同 denominator expression 和独立键不得在 batch grouping 中被丢失或错用。

实现验收覆盖：

- primitive/nested 共用对象的严格解析、canonical round trip 与 draft Save。
- Header 范围条件在保留源变量时判断，Header N 和 membership 保持原值。
- chunk_source 不被当前节点或 level missing_policy 限制，current_group 保持 anchor。
- 独立分母键与分子键不同、分子为 subject 而分母为 distinct_key 的情况。
- 筛选发生在单位归约之前；record 不计空 scaffold，列重叠时每列独立计数。
- 分母为零仍保留实际 n，pct 为 NE；条件不隐式改写分子。
- 旧配置对照的语义与新版本结构错误；无法确定旧分母键时显式失败。
- 同类 batch 保留各分析自己的 scope、expression、unit/key 和结果身份。

这些验收以 synthetic metadata 和生成源码为对象，不执行真实 SAS 数据集。

## 7. 当前会话批准的实施规则

1. Header 分母条件使用 Header source，在判断资格后按 subject 去重，header_population
   只允许 distinct_subject；source 范围与表达式顺序采用第 3 节规则。
2. primitive 的 current_group 配置返回结构错误；source 范围允许独立分母键，所有
   分母筛选只作用于分母，不隐式过滤分子。
3. schema_version 升为 2，严格导入/导出 v2，旧 bundle 按对照显式迁移，不自动转换。

用户已确认上述三条。后续实现依照以下责任映射，不增加分析范围或迁移分支。


## 8. Emitter 实施映射

现有 generator、categorical emitter、hierarchical container 和 render 的职责不变。
分母的独立计数输入按已批准的范围单独准备，不将分母键传播到分子输入。

| 输入或对象 | 字段、来源与消费者 | 生命周期与所有权 |
| --- | --- | --- |
| plan.header_population_dataset | _TFL_POP_001，保留 Header source 经 population 筛选后的所有源变量 | generator 创建；categorical 只读，用于 Header 资格判定。 |
| plan.header_columns | 已解析 columns，包括 condition、id、display_order | snapshot 只读，用于 Header 分母按相同列规则展开。 |
| plan.membership_dataset | _TFL_MEM_001；nested 沿用 _TFL_HMEM_<container> | generator/container 创建；所有分析只读，不被分母条件缩减。 |
| _TFL_KSRC_<batch>_<chunk> | 顶层 primitive 的完整 filtered source，含 source_row | 当前 categorical chunk 创建；分子和 source 分母共同只读。 |
| plan.chunk_source_dataset | nested 的 _TFL_HSRC_<container>，在 level 排除之前已应用 container filter | hierarchical 创建并显式交付；分母只读。 |
| plan.node_source_dataset | 现有 _TFL_HLEVEL_<container>_<level>，用于未广播的 duplicate guard | container 创建；block 只读。 |
| nested chunk.source_data | 现有 _TFL_HMERGE_<container>_<level>，含 node_key、column_order 和实际源字段 | container 创建；current_group 分母和分子各自只读。 |
| _TFL_KDQUAL_<batch>_<chunk> | 当前范围的合格记录投影；column_order、必要 node_key 及分母身份字段 | categorical 独占；资格判断后才投影，之后供单位归约。 |
| _TFL_KDUNIT_<batch>_<chunk> | 按 column_order、必要 node_key、独立分母键形成的单位 | categorical 独占；distinct 单位使用 typed NODUPKEY，record 直接保留真实记录。 |
| _TFL_KDEN_<batch>_<chunk> | chunk_order、row_order=0、column_order、node_key，每单位一个事件 | categorical 独占；Header/chunk_source 的 node_key 为空，current_group 为实际节点。 |
| _TFL_KPRE_* / _TFL_KIN_* / _TFL_KNUM_* | 现有分子事件及其身份键，row_order>0 | categorical 独占；不带独立分母键，不生成 Header 假记录。 |
| _TFL_KEVENT_<batch> / _TFL_KRAW_<batch> | 合并已归约的分母、分子位置事件；由一次 PROC FREQ 计数 | categorical 独占；raw 交付现有 expected-cell join 和 render。 |

Header 没有额外条件时仍可复用 _TFL_HN_001；有条件时读取 _TFL_POP_001，按
Header column condition 和分母 expression 输出合格 subject 后去重。source 范围
使用 membership inner join，空 scaffold 不产生事件；current_group 使用已有
HMERGE 的真实记录。原始 typed keys 在事件合并前完成归约，避免分母键和分子键
互相污染。新分母表都属于当前 chunk/block，不修改共享输入。

batch signature 保留分子键及分母 scope/unit/key；expression 在每个 chunk 独立
处理，条件不同仍可复用一次 FREQ。nested 非 current_group 分母按列计算一次，
在 expected-cell join 中用空 node_key 广播到各现有节点；不复制分析记录或产生新节点。
最终输出、n/NE、exclusive overlap、duplicate-check 和渲染责任沿用既有契约。
