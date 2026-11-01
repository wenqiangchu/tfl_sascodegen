# 分析契约讨论记录

日期：2026-10-30。本文区分已确认的行为、已修复的缺陷与待确认的模型方案，
不将讨论建议写成已批准的新 schema。

## 1. 当前确认状态

| 事项 | 状态 |
| --- | --- |
| 统一 primitive 与 hierarchical denominator | 三个 scope 与 scope/unit/expression/distinct_key 四字段已确认；来源细则、迁移和 emitter 契约待确认，尚未实现 |
| 保留实际分类分子，分母为零时仅 pct 不可估计 | 已确认并修复 |
| 模板编辑和 Save 保留已声明的 result_sort | 已有契约的维护缺陷，已修复 |
| SOC 下显示严重程度分布与 PT，PT 下显示严重程度分布 | 业务需求已确认；表示方式和记录选择字段待确认 |
| 同一受试者在 SOC/PT 内取最高严重程度 | 业务需求已明确；当前无内建排序选记录入口 |
| 用自定义 SAS format 定义节点值域和显示标签 | 用户提出的方向；字段、分组语义和过程适配待确认 |

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

hierarchical source_data 可以引用 work.ae_analysis。若希望通过 metadata 配置排序
键并自动选记录，而不编写 preparation，则需下面的独立记录选择对象；当前
distinct_key 本身没有升降序或「保留首条」配置。

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

### 3.4 待确认的最小记录选择对象

| 对象或字段 | 建议职责 | 状态 |
| --- | --- | --- |
| 计数身份 | 沿用 counting_unit/distinct_key；nested 时由 anchor node 限定 scope | 已有对象 |
| record_selection | 可选的每分析块记录选择请求，不修改共享 container source | 待确认名称与应用范围 |
| record_selection.order_by | 有序的排序键，决定同一身份内保留哪条记录 | 待确认 |
| order_by[].variable | 该 source 中的排序变量，例如 AESEVN、AESEQ | 待确认 |
| order_by[].direction | asc 或 desc | 待确认 |

候选表示：

```yaml
counting_unit: distinct_subject
record_selection:
  order_by:
    - variable: AESEVN
      direction: desc
    - variable: AESEQ
      direction: asc
```

选择应发生在 row condition 之前。SOC 与 PT blocks 各自从其节点记录中选择，
不能在共享 source 上全局删记录，否则会影响 PT 节点或其他分析块。record 单位下
是否允许独立的选记录分组键，以及选择与 denominator 的关系，尚需明确；本文不
据此引入已批准字段。

## 4. format 值域与空节点

### 4.1 SAS 能提供什么

SAS MEANS 的 CLASS `PRELOADFMT` 配合 PROC `COMPLETETYPES`，可将已指定 format
中的未观察水平纳入输出。format 同时可以把 AVISITN 映射成访视标签。

PROC FREQ 的 `SPARSE` 用于把变量已有水平的零频组合纳入输出，不能据此假定会
预载 format 内所有从未观察的值。MEANS 与 FREQ 不应直接套用同一组选项。

来源：

- [SAS MEANS CLASS statement](https://support.sas.com/documentation/cdl/en/proc/61895/HTML/default/a000146731.htm)
- [SAS FREQ missing combinations](https://support.sas.com/documentation/cdl/en/procstat/63104/HTML/default/procstat_freq_sect016.htm)

### 4.2 对当前生成流程的影响

当前过程按内部 node_key 分析，而不是直接把 AVISITN 放在 CLASS 中。仅给源变量
绑定 format，能够影响其显示标签，但不会让一个从未出现的访视自动产生 node_key。
节点目录还参与 expected-cell skeleton、层级布局和排序，需在这些步骤之前存在。

合理的候选方向是：用 format 定义类别目录，实际 source records 仍独立参与分析，
再将实际计数或统计结果与完整节点目录关联。类别目录不是带假受试者的分析记录，
因此不必把 dummy observations 注入计数源。

需要确认：

- format 引用放在哪个 metadata 对象中，以及如何与 label_variable 配合；
- 节点按原始值还是格式化值分组；MEANS 的 PRELOADFMT 使用格式化值分组，可能合并
  原始值，不能无意改变当前 typed node identity；
- 是否只支持有限离散值，如何处理 ranges、OTHER、missing、multilabel；
- 子节点值域是否依赖父节点。不能把所有 SOC 与所有 PT 无条件作笛卡尔积；
- format 在调用方 SAS 环境中的定义和可用性，以及旧 bundle 的迁移。

本文不增加 format 字段或应用内 SAS catalog 读取功能。

## 5. 三处实际错配的具体含义

### 5.1 parent_level

metadata 可以填写第三层的 parent_level 为第一层，但当前生成器仍从第二层的
level records 继续分组。只改变 parent_level，SAS 源码不变。该字段目前没有驱动
实际层级输入与布局。若严重程度作为独立动态 level，分支输入、节点身份、深度和
遍历顺序都需要一致的父子契约；若使用固定分析 rows，则当前 SOC/PT 两层结构已
能表达需要的布局。表示方式尚待确认。

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
细则、迁移和 emitter 契约尚待确认，见 [统一分母契约](denominator-contract-design.md)。
本轮尚未实现新模型。

## 6. 零计数与零分母

| 情况 | 正确含义 |
| --- | --- |
| Header 列没有受试者 | membership join 后没有事件，实际 numerator=0 |
| 有受试者，但 SEX 全缺失；分母为 non_missing(SEX) | denominator=0，但 Missing row 的 numerator 可以非零 |
| 自定义分母谓词不匹配任何记录 | denominator=0，不能据此改写独立 row condition 的实际 numerator |

当前程序先计算 row counting events，通过 FREQ 和 expected-cell join 得到实际
numerator；本次只移除了 denominator=0 分支中覆盖 numerator 的赋值。pct 在分母
为零时不可估计，仍渲染为 NE。这不增加数据级验证，也不改变 population membership。
