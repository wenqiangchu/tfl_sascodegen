# 分析契约讨论记录

日期：2026-10-30，状态更新至 2026-11-01。本文区分已确认的行为、已修复的缺陷与
待确认的模型方案，不将讨论建议写成已批准的新 schema。

## 1. 当前确认状态

| 事项 | 状态 |
| --- | --- |
| 统一 primitive 与 hierarchical denominator | 已实现 `scope/unit/expression/distinct_key`；来源规则、v2 迁移和 emitter 契约已落地并通过全量测试 |
| 保留实际分类分子，分母为零时仅 pct 不可估计 | 已确认并修复 |
| 模板编辑和 Save 保留已声明的 result_sort | 已有契约的维护缺陷，已修复 |
| SOC 下显示严重程度分布与 PT，PT 下显示严重程度分布 | 已由线性 hierarchical levels 和 analysis blocks 表达；最高程度由调用方预处理 |
| 同一受试者在 SOC/PT 内取最高严重程度 | 已确认通过 `custom_code.before` 或预先准备的 ADaM source 实现，不新增字段 |
| 用自定义 SAS format 定义节点值域和显示标签 | P-2d parser、UI、hierarchical emitter 已实现；format 运行期由调用方 SAS 环境提供 |

## 2. 两种列需求的区别

### 2.1 基线与基线后分类交叉表

如果先按分析规则准备一人一条记录，例如：

| USUBJID | BASECAT | POSTCAT |
| --- | --- | --- |
| S01 | Normal | High |
| S02 | Low | Normal |
| S03 | Normal | Normal |

可以使用：

- Header source：该分析用的受试者级交叉表数据，保留 population 所需变量；
- Header column condition：`BASECAT = 'Low'`、`BASECAT = 'Normal'` 等；
- categorical row condition：`POSTCAT = 'Low'`、`POSTCAT = 'Normal'`、`POSTCAT = 'High'`；
- counting unit：`distinct_subject`；
- denominator：按基线分类的列内受试者数，或 SAP 明确指定的其他分析分母。

当前模型能表达这种需求。POSTCAT 是最近一次、最差一次还是指定访视的分类，
仍需在分析数据准备中明确；Header 不替用户作该选择。

### 2.2 按访视匹配记录的列

另一类表是「Week 1 与 Week 2 为列，同一受试者的各次测量值必须进入对应列」。
当前 Header membership 只保存 USUBJID 与列身份，并按 USUBJID 广播 source records。
如果某人同时属于两列，其所有 source records 会进入两列，并不会自动按记录的
AVISITN 匹配各列。这与基线分类交叉表不同。

将分析值或统计量本身作为不同列，也需要列与分析请求之间的对应关系；不能把这类
限制泛化为「所有交叉表都不能做」。

## 3. SOC/PT 的最高严重程度分布

### 3.1 业务分组

示例分析记录：

| USUBJID | SOC | PT | AESEVN |
| --- | --- | --- | --- |
| S01 | GI | Nausea | 1 |
| S01 | GI | Nausea | 3 |
| S01 | GI | Diarrhoea | 2 |
| S02 | GI | Nausea | 1 |

其中 AESEVN 的数值排序表达严重程度，不能假定任意字符标签的字典序就是临床顺序。

- SOC 分布：在每个 USUBJID/SOC 内取最高程度。S01 为 3，S02 为 1。
- PT 分布：在每个 USUBJID/SOC/PT 内取最高程度。Nausea 中 S01 为 3、S02 为 1；
  Diarrhoea 中 S01 为 2。

只先取每个 PT 的最严重记录，还不足以计算 SOC 分布：S01 的两个 PT 仍会留下程度
3 与 2，SOC 内需要独立选择一次，才能保证 S01 在 SOC 严重程度分布中只进入一个类别。

### 3.2 现有结构能表达的部分

SOC 和 PT 可以作为两个动态 levels；分别在 SOC 与 PT 上挂接严重程度分析 blocks。
严重程度为固定的 Mild/Moderate/Severe rows 时，当前输出顺序已经是：

```text
SOC
  SOC 的严重程度分布
  PT
    PT 的严重程度分布
```

也可以另外使用 same_row block 在 SOC/PT 节点行显示总人数。这种表示方式需与用户
确认；它不等同于已经实现任意分支的 parent_level。

### 3.3 为什么当前 distinct_key 不能完成最高程度选择

当前 categorical emitter 先根据每条记录的 row condition 生成计数事件，再按
node/column/row/counting-unit 去重。因此同一人先命中 Mild、又命中 Severe 时，
这两个类别的事件分别保留。给原始数据排序，不会移除 Mild 的事件。

如果将 AESEVN 加入去重身份，不同程度反而成为不同身份，也不会合并为一条。
正确步骤是：先在目标分组内按严重程度降序排列并选首条，再判断分类 row conditions。

现有机制仍然可以实现这张表：在 `custom_code.before` 或已经准备好的 ADAM 数据中
分别派生 `SOC_MAX_SEV` 与 `PT_MAX_SEV`，各 block 用对应的分类字段作 row condition。
这些分类字段在各自 subject/SOC 或 subject/SOC/PT 内恒定，`distinct_subject` 对
同一分类内的多条源记录只计一次，因此不必为了分类人数把共享 source 全局删成
每人一条。

例如，SOC block 的 Mild 条件为 `SOC_MAX_SEV = 1`，PT block 的 Mild 条件为
`PT_MAX_SEV = 1`；其他程度同理。S01 的 Diarrhoea 记录虽然 AESEVN=2，但其
SOC_MAX_SEV=3，所以在 SOC 层进入 Severe，在 PT 层进入 Moderate。这正是两个
不同分析 scope 的要求。

以下 preparation 示例使用现有 custom_code.before，不增加 metadata 字段。
work.teae 是按已经确认的事件筛选规则准备的输入；最高程度计算只使用该输入。

```sas
proc sql;
  create table work.soc_severity as
  select USUBJID, SOC, max(AESEVN) as SOC_MAX_SEV
  from work.teae
  group by USUBJID, SOC;

  create table work.pt_severity as
  select USUBJID, SOC, PT, max(AESEVN) as PT_MAX_SEV
  from work.teae
  group by USUBJID, SOC, PT;

  create table work.ae_analysis as
  select a.*, s.SOC_MAX_SEV, p.PT_MAX_SEV
  from work.teae as a
  left join work.soc_severity as s
    on a.USUBJID = s.USUBJID and a.SOC = s.SOC
  left join work.pt_severity as p
    on a.USUBJID = p.USUBJID and a.SOC = p.SOC and a.PT = p.PT;
quit;
```

hierarchical source_data 可以引用 work.ae_analysis。当前不新增 metadata 记录选择
对象；需要显式排序并取首条时，由 `custom_code.before` 或调用方预先准备的 ADaM
source 生成派生源。

示意 SAS，仅说明选记录规则，不是当前生成器已提供的接口：

```sas
proc sort data=work.teae out=work.pt_ordered;
  by USUBJID SOC PT descending AESEVN AESEQ;
run;

data work.pt_worst;
  set work.pt_ordered;
  by USUBJID SOC PT descending AESEVN AESEQ;
  if first.PT;
run;

proc sort data=work.teae out=work.soc_ordered;
  by USUBJID SOC descending AESEVN AESEQ;
run;

data work.soc_worst;
  set work.soc_ordered;
  by USUBJID SOC descending AESEVN AESEQ;
  if first.SOC;
run;
```

AESEQ 是本例的并列优先级示意。实际 tie-break、全部严重程度缺失时的处理和分析
记录过滤条件应由分析规则明确。不要使用含严重程度的整个 BY 列表作为 NODUPKEY
的身份键，否则不同程度不会被归约。

### 3.4 已确认的实现边界：不新增记录选择字段

| 对象或字段 | 当前职责 | 状态 |
| --- | --- | --- |
| 计数身份 | 沿用 `counting_unit`/`distinct_key`；nested 时由 anchor node 限定 scope | 已有对象 |
| 记录选择 | 由 `custom_code.before` 或外部 ADaM preparation 完成 | 已确认，不进 metadata |
| SOC 最高程度 | 在 `USUBJID + SOC` 内派生 `SOC_MAX_SEV`，或生成 SOC worst-record source | 已确认 |
| PT 最高程度 | 在 `USUBJID + SOC + PT` 内派生 `PT_MAX_SEV`，或生成 PT worst-record source | 已确认 |
| 并列和缺失规则 | 由 preparation 中的 SAS `ORDER BY`/`BY` 顺序及过滤条件明确 | 调用方责任 |

选择逻辑必须发生在 row condition 之前。SOC 与 PT 的选择范围独立；不能在共享 source
上全局删记录。严重程度字段不得加入 `distinct_key`，否则不同严重程度会变成不同
计数身份而无法归约。

## 4. format 值域与空节点

### 4.1 SAS 能提供什么

用户确认动态 level 可以引用调用方已提供的 format。format 必须已经在调用方的
format catalog 中定义，或由 `custom_code.before` 定义；应用不读取 catalog，也不
检查 format 是否存在、原始变量类型是否匹配或格式化结果是否为字符型。指定 format
后，动态节点使用 format 产生的字符型格式化值同时作为节点身份、节点值和显示标签；
此时不使用 `label_variable`。未指定 format 时，才使用 `label_variable`（或其缺省
变量）作为显示标签。原始变量可以是 numeric 或 character。

用户要求 format 值域中的未观察值也生成动态节点，并显示频数 0。一个 level 的
format 值域要在每个父节点下展开；父节点自身没有观测时，只有父 level 的 format
值域将它纳入时才存在。父子 level 都使用 format 时，完整的格式化值组合是允许的。

SAS MEANS 的 CLASS `PRELOADFMT` 配合 `PROC COMPLETETYPES`，可将已指定 format
中的未观察水平及其组合纳入输出。PROC FREQ 没有 CLASS 语句，使用 TABLES；它的
`SPARSE` 用于已有水平的零频组合，不能替代 format 值域预载。因此不能仅靠 FREQ
完成该节点目录需求。

用户确认分类频数统一由 PROC MEANS 计算，不再使用 PROC FREQ 结果再与完整骨架 merge
的路径。每个进入某个分类计数输入的记录先设置 `flag=1`，然后以 `N(flag)` 计数；不
符合该 row condition 或分母条件的记录在进入对应输入前排除。不能把不符合条件的记录
设置为 0 后直接使用 `N`，因为 0 也是非缺失值。distinct subject/distinct_key 仍须
在计数前按既有 counting unit 规则归约；nonexclusive rows 需要允许一条源记录分别
进入多个命中的 row event 输入。

来源：

- [SAS MEANS CLASS statement](https://support.sas.com/documentation/cdl/en/proc/61895/HTML/default/a000146731.htm)
- [SAS FREQ missing combinations](https://support.sas.com/documentation/cdl/en/procstat/63104/HTML/default/procstat_freq_sect016.htm)

### 4.2 对当前生成流程的影响

当前层级节点由内部 `node_key`、节点目录、层级布局和排序共同驱动。仅给源变量绑定
format 不足以让一个从未出现的访视自动产生 node_key；批准的生成方向是先由
`PROC MEANS` 的 format 预载和完整类型输出建立节点及零频组合，再将其直接提供给
后续统计和 render。

节点目录由 PROC MEANS 的 CLASS、PRELOADFMT、COMPLETETYPES 生成；分类计数使用
该目录与 metadata/header 构成的完整 CLASSDATA，以及 `flag=1` 的计数输入。
CLASSDATA 同时覆盖展示位置与 row_order=0 的分母位置，全局分母保留空 node_key，
current_group 分母保留实际 node_key。零频 class 组合直接由过程输出，不再采用
PROC FREQ 原始结果与 expected-cell 完整骨架的补零路径。类别目录仍不是带假受试者的
分析记录；零频组合是过程输出，不向计数源注入 dummy observations。

节点目录输入允许使用 `flag=.` 的父节点占位记录，以展开没有实际观测的父节点；
它们不进入分析计数源。missing_policy=label 时，仅保留有真实缺失记录支持的 Missing
节点，排除占位记录带来的零频缺失类别；普通非缺失 format 零频类别仍完整保留。

已决定：在 `levels[]` 增加可选字符串字段 `format`，保存不带末尾句点的 SAS format
名称；字符型 format 使用 `$` 前缀。emitter 负责补句点并生成 FORMAT 绑定。字段不
保存 catalog 路径，应用不解析或检查 format 的存在性和类型匹配。指定 format 时，
`order_variable` 不参与节点排序；节点顺序按 format 的存储顺序生成，调用方需要声明
顺序时在 PROC FORMAT 中使用 `NOTSORTED`。`result_sort` 仍可覆盖最终展示顺序。未
指定 format 时沿用现有 `label_variable`、`order_variable` 和 `order_direction`。

parser 只做结构约束：`format` 必须是非空字符串且不得以句点结尾，不解析名称是否为
SAS 合法 format。未指定 format 时，`order_variable` 和 `order_direction` 必填；指定
format 时可以省略或保留这两个字段，但生成时忽略。`label_variable` 始终可选，指定
format 时忽略。

当前版本中 format 只负责提供完整节点列表和原始值到显示值的映射。ranges、`OTHER`、
特殊 missing 或 multilabel format 不增加专门语义；需要这些效果时，调用方必须在分析
前自行准备数据或 format 结果。本文不增加应用内 SAS catalog 读取功能。

## 5. 三处实际错配的具体含义

### 5.1 parent_level 与当前线性层级决定

用户确认保留当前线性层级，不在本轮引入树形分支。`levels` sequence 定义
`SOC -> PT` 这样的 level chain；运行时每个 SOC 节点仍可有多个由数据产生的 PT
子节点。当前 SOC/PT 频数和严重程度分析通过对应 level 的 `same_row`/`below`
blocks 与固定 analysis rows 表达。

树形分支表示同一个父 level 下有多个不同的动态 child level，例如 `SOC -> PT` 与
`SOC -> Severity`。只有多个由数据决定的不同维度需要作为 sibling paths、各自拥有
节点值域和分析范围时才需要。它不是多个 PT 值，也不是固定 Mild/Moderate/Severe
分析行。

未来若出现这种业务需求，tree level graph 是可能的优化方向；它需要统一重构父子
metadata、节点身份、source/anchor 范围、排序/遍历和布局，涉及 parser、UI、emitter
与 render。当前不继续探讨该方向。现有生成器仍按 levels sequence 构造线性链，单独
设置 `parent_level` 不改变 SAS 生成结果。

### 5.2 result_sort

导入模板包含 result_sort，但 UI 表单采集重新建立 level 对象时漏掉该字段。
因此修改一个无关标题并 Save，就可能将「按 Overall 人数降序」变成默认排序。
本次修复保留原有 result_sort，并用实际 Shiny server 测试验证采集、Save 和
位置 ID 重编号后的引用仍正确；未新增专属排序编辑控件。

### 5.3 denominator 的 distinct_key

当前 denominator 可以写 unit=distinct_key，但键实际来自分析块自身的 distinct_key。
分析块又规定，只有分子 counting_unit=distinct_key 时才能提供该字段。结果是：

- 分子 distinct_subject、分母 distinct_key，不提供键时可以通过解析，却无法得到
  所声明的分母身份；分母 NODUPKEY 仅剩位置维度；
- 为该分母补键时，又因为分子不是 distinct_key 被拒绝。

这说明「分子单位」与「分母单位」表面独立，键契约实际上耦合。用户随后已认可
scope/unit/expression/distinct_key 统一对象，独立分母键包含在批准范围内；具体来源
细则、迁移和 emitter 契约已按[统一分母契约](denominator-contract-design.md)落地。
该统一模型已在当前实现中落地；本段保留原始错配作为设计背景。

## 6. 零计数与零分母

| 情况 | 正确含义 |
| --- | --- |
| Header 列没有受试者 | membership join 后没有事件，实际 numerator=0 |
| 有受试者，但 SEX 全缺失；分母为 non_missing(SEX) | denominator=0，但 Missing row 的 numerator 可以非零 |
| 自定义分母谓词不匹配任何记录 | denominator=0，不能据此改写独立 row condition 的实际 numerator |

当前程序先计算 row counting events，通过 PROC MEANS 和 expected-cell join 得到实际
numerator；本次只移除了 denominator=0 分支中覆盖 numerator 的赋值。pct 在分母
为零时不可估计，仍渲染为 NE。这不增加数据级验证，也不改变 population membership。
