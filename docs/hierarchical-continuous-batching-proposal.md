# Hierarchical continuous blocks 共用 PROC MEANS：已批准设计

状态：已确认（2026-09-29），按用户“按上述方案实施”的指示实施。

## 1. 问题与已批准范围

P0-10 已将同 anchor level 的 membership expansion 集中，但多个兼容 continuous
blocks 仍重复调用 PROC MEANS。本决定保留各 block 的 preparation、precision、
结果和布局责任，共享中间的连续统计过程。后续获批的
[P0-13](hierarchical-result-sharing-proposal.md) 只进一步共享 value/digits DATA step；
各 block 的关联、私有输出及渲染仍保持独立。

依据：[portable contract](../table-and-chunk-analysis-model.md) 第 9.4、13、14 节，
[已批准决定](design-decisions.md) P0-8、P0-10。

已批准的前置契约：

- 产品输出为 SAS source text；R/Shiny 不读取分析数据、不运行 SAS。
- `_TFL_HMERGE_<container>_<level>` 已按 level 共用，保留原始 `source_row`。
- `record` 按记录分析；`distinct_subject` 和 `distinct_key` 每个 node/header/unit
  允许至多一个非缺失记录，全部缺失保留一个 missing unit。两个非缺失记录即冲突，
  即使数值相等也不能折叠为合法 unit；现有错误及 `ABORT CANCEL` 语义继续适用。
- 每个 block 拥有独立 nested batch namespace、precision、statistic、render 和布局身份。
- 本文件与 P0-11 替代 P0-10 对符合本契约的 continuous blocks 不合并 procedure
  的限制；其余 P0-10 责任与对象生命周期继续适用。

本次确认合批范围、兼容条件、共享输入、raw output 拆分以及批内失败顺序。
YAML、workspace、UI 和统计量定义不需要新增设计。

## 2. 数据对象及字段

以下是生成期描述或生成 SAS 中的 WORK 对象，不进入 metadata bundle。

### 2.1 输入与所有权

输入为已解析的 container、其有序 `analysis_blocks`、Header catalog、已注册的
continuous definition，以及 P0-10 的 level/node/membership 数据集描述。
metadata 的所有字段沿用 portable contract，本次不新增或更改字段。

container 负责分组和 block 映射；continuous primitive 负责单 block 规范化、
counting-unit materialization、precision 和结果格式化。共享步骤只消费已准备好的
numeric analysis values，不能修改 `_TFL_HMERGE` 或 block 输入。

### 2.2 Continuous group 描述的全部字段

| 字段 | 类型与责任 |
| --- | --- |
| `container_order` | 当前程序中 container 的既有 batch 编号，隔离不同 container。 |
| `anchor_level_order` | container 内 1-based level 位置，确定唯一 node scope。 |
| `compatibility` | 下表的完整兼容描述，依据声明契约，不来自数据扫描。 |
| `members` | 非空、有序 member sequence，顺序等于原 analysis_blocks 顺序。 |
| `input_dataset` | 共享输入名称，固定为 `_TFL_HCIN_<container>_<first-block>`。 |
| `raw_dataset` | 共享输出名称，固定为 `_TFL_HCRAW_<container>_<first-block>`。 |

`<first-block>` 从首个 member 的 `block_order` 派生，沿用既有补零约定，不使用
用户 ID。新前缀与 block namespace 分离。单 member 沿用现有路径，不创建共享对象。

### 2.3 兼容描述的全部字段

| 字段 | 判定规则 |
| --- | --- |
| `primitive_type` | 仅 `continuous_summary`。 |
| `source_contract` | container 的完整 grain、subject_key、record_key、duplicate_policy 声明一致；同 container 内自然相同。 |
| `membership_source` | 相同 P0-10 expanded source 名称。 |
| `nodes_dataset` | 相同 node catalog 名称。 |
| `counting_unit` | record、distinct_subject 或 distinct_key 完全相同。 |
| `distinct_key` | distinct_key 模式下为原始字段 sequence，字段及顺序完全相同；其他模式 absent。不按大小写或集合等价推断兼容。 |
| `primitive_definition` | 使用同一已解析 continuous definition，包括 analysis、merge、render 和 batch contract；不混用统计实现。 |

container 和 level 必须相同，由 group 身份固定。`analysis_variable` 可以不同，
但都必须满足既有 numeric contract。应用不检查实际变量类型；typed keys 在各
block 的原始 typed 字段上完成 materialization，不进入共享分析表。

rows、请求的 statistics、digits、cell format、placement、result_sort 不属于
兼容 key，它们继续在各 block 的结果和布局阶段处理。

共享步骤使用内置 continuous emitter 的 preparation/MEANS/result 契约。
代码注册的替代 emitter 或声明不可合批的 definition 继续走独立 emitter 路径，
避免绕过其源码实现；本次不增加新的 emitter 插件阶段接口。

### 2.4 Group member 描述的全部字段

| 字段 | 类型与责任 |
| --- | --- |
| `block_order` | 原 container analysis_blocks 中的 1-based 位置；共享 SAS 表的 analysis_order 使用此值。 |
| `analysis_id` | 原 block id，供最终 hierarchical statistic 身份映射。 |
| `primitive_plan` | 现有单 block PrimitiveBatchPlan，保留 chunk、rows、result map、header/node 引用和全部既有 dataset 名称；只有一个 chunk，内部 chunk_order=1。 |
| `analysis_input_dataset` | 已 materialize 的 `_TFL_CUNIT_<nested>`；record 则为 `_TFL_CIN_<nested>`。显式声明共享步骤读取哪个对象。 |

primitive_plan 的 nested batch 编号沿用当前为各 block 预留的编号。不能因合批
压缩编号或移动后续 container 的 namespace。analysis_variable、precision/raw/
statistic/render 名称从该 plan 取得，不另存一份可变副本。

### 2.5 共享 SAS 输入的全部字段

| 字段 | 类型与含义 |
| --- | --- |
| `analysis_order` | SAS numeric 8，原 block 位置。 |
| `node_key` | 沿用当前 _TFL_NODE_LEN 的 character，动态节点身份。 |
| `column_order` | SAS numeric 8，展示 Header 列位置。 |
| `analysis_value` | SAS numeric 8，已按该 block counting unit 处理的值，允许 SAS missing。 |

每个 member 从自己的 analysis_input_dataset 投影四个字段，再按 member 顺序
append。此时才移除 unit keys 和 source_row；precision 仍读取各 block 的完整输入。
禁止 append 原始 source records，禁止通过字符串化 key 强行合并。

### 2.6 共享 raw output 与 block 输出

共享 raw output 的全部保留字段为 `analysis_order`、`node_key`、`column_order`、
`_n`、`_mean`、`_sd`、`_median`、`_q1`、`_q3`、`_min`、`_max`。
前三项组成唯一分析键，后八项是现有 continuous procedure 的 numeric 输出。
_TYPE_ 和 _FREQ_ 继续移除；percentile 和 sample SD 定义沿用既有契约。

按 analysis_order=block_order 拆入各 member 原有 `_TFL_CRAW_<nested>`，
移除 analysis_order，补回单 block 的 chunk_order=1。因此 block raw 完整字段仍为
chunk_order、node_key、column_order 及上述八个统计量。

之后沿用各 block 自己的 expected-cell map、precision、`_TFL_STAT_<nested>`、
`_TFL_REND_<nested>`。其输出字段沿用现有 primitive contract；container 再设置
chunk_id 和 analysis_id，原 row/header/statistic 身份不变。

## 3. 数据流、生命周期与失败行为

~~~text
shared level membership
  -> block A normalization / counting units / precision
  -> block B normalization / counting units / precision
  -> append narrow values with analysis_order
  -> one PROC MEANS by analysis_order, column_order, node_key
  -> split raw statistics to block A and block B
  -> each block's expected cells and raw/precision join
  -> shared value/digits conversion into private statistic outputs (P0-13)
  -> each block's render cells
  -> existing hierarchical result_sort and same_row/below assembly
~~~

1. 按原 analysis_blocks sequence 扫描；只合并相邻且完整兼容的 continuous
   blocks。遇到 categorical、不同 level 或其他不兼容 block 即结束当前组。
   因此 continuous A → categorical B → continuous C 暂时仍为三个独立步骤。
2. 每组按 member 顺序完成 preparation。source_row 不重新编号；counting unit
   不跨 block 折叠。同一 subject 在不同 analysis variable 中的缺失状态互不影响。
   precision 仍按 block/node 求值，并跨重叠 Header 列消除重复 source row。
3. 共享 procedure 使用 NWAY NOPRINT，CLASS analysis_order column_order node_key，
   VAR analysis_value，生成既有八项 raw statistics。
4. 完成全部 raw 拆分后，按原 member 顺序准备各自 expected-cell 和 raw/precision
   join，再按 P0-13 共用 value/digits 转换，最后逐块 render。raw 缺少某个
   node/header 组合时，仍由该 block skeleton 补全。
5. result_sort 继续读取被引用 block 的独立 statistic dataset，无需从共享表按
   row ID 猜测 block；same_row、below 和子层级跟随规则保持原身份边界。
6. group input 在所有 member preparation 后创建，由共享 procedure 只读使用；
   group raw 只供拆分读取，block raw 必须在本组后处理之前完成。所有对象使用 SAS
   WORK 生命周期，不新增清理副作用，不写回 R workspace。

生成前置错误继续使用已有 envelope，不返回部分 source。SAS runtime 中任一 member
出现多个非缺失记录，继续由该 block 原 guard 输出同样字段和 unit keys 并执行
ABORT CANCEL。include_duplicate_check=FALSE 不关闭这种统计契约冲突处理。

**已确认的顺序影响：**共享 procedure 必须等待整组 preparation 成功。若后一个
block 中止，较早 block 的 precision 可能已存在，但该组的 PROC MEANS、statistic
和 render 尚未执行。旧路径可能已经完成较早 block；本方案不保证异常时部分 WORK
表或全部诊断的全局先后顺序相同。单项诊断内容、字段顺序、按 member 顺序首次遇到
的 unit 冲突及终止语义保持；较早 block 的 render 阶段诊断可能尚未产生。应用仍只
生成源码，不接管这些运行结果。

## 4. 方案选择与被拒绝的替代方案

| 方案 | 收益 | 代价及建议 |
| --- | --- | --- |
| 每个 block 全部独立 | 完全沿用 P0-10 | 仅作为单 block 或不兼容 block 的保留路径。 |
| 单 block preparation/结果处理，共享 PROC MEANS | 复用现有 counting-unit、precision、identity 和布局边界；K 次 procedure 减为 1 次 | 已采用；新增窄表 append 与 raw 拆分。 |
| 统一多 block primitive plan，共享 materialization 与结果处理 | 有机会进一步减少中间表和重复步骤 | 本轮未采用：需消除读取 plan$chunks[[1L]] 的假设并改造结果 identity。 |

相邻兼容块较易保留执行顺序；收集同 level 全部兼容块可以减少更多 procedure，
但会跨过其他 blocks，扩大诊断和中止顺序变化。首版采用相邻策略，
跨块重排留作单独设计，不能默认为已批准。

减少 procedure 数量不等于已证明运行更快。新增 WORK 读写可能抵消收益，
验收以分析等价和 procedure 数量为准，不承诺耗时或内存改善比例。

不采用跨 categorical、不兼容块、level 或 container 重排；不引入 YAML 合批开关。

## 5. 实施后的验收条件

以下条件由 focused source regression 与 synthetic SAS 对照 fixture 覆盖。

| 场景 | 验收点 |
| --- | --- |
| 同 level 相邻两个 continuous blocks，使用不同变量 | 一个 membership merge、一个 MEANS；两套统计值及 analysis/row identity 独立。 |
| 三个 compatible blocks | procedure 为 1；逐 member 映射，无重复或丢失 logical cells。 |
| counting unit 不同、distinct key 字段或顺序不同 | 分为不同组；typed key 不被统一转换。 |
| 不同 level、不同 container、被 categorical 隔开 | 不合并；categorical denominator、FREQ 和顺序保持。 |
| 三种 counting unit 各自的兼容组 | 每种模式分别覆盖两个 blocks，唯一非缺失值及全 missing unit 保持原语义。 |
| 后一个 block 冲突，含两个相等的非缺失记录 | 原 guard 中止，共享 MEANS 与后处理未执行；前一个 block 的合法值不能掩盖冲突。 |
| 不同变量精度、absolute/relative digits、重叠 Header 列 | base_digits 按 block/node 独立，precision 不交叉影响。 |
| 空 Header 列、节点中某变量全 missing、container 无节点 | 分别保持 expected-cell 补全和空节点集行为，n/NE 与独立分析一致。 |
| result_sort 引用第二个 block、合法的跨 block 同名局部 row ID | 排序只读取被引用 block 的 statistic，不混入第一个 block。 |
| same_row/below、父子层级、单 block fallback | 展示顺序和标签不变；单 block 延续当前源码路径。 |
| 多 container 和重复生成 | dataset 名称无碰撞；同一 snapshot 生成确定性 source。 |

R 回归覆盖分组、生成源结构、结果拆分及既有 report/compare 生成。若另行执行 SAS
runtime 验证，使用 synthetic fixtures，对照独立运行的 blocks 比较 N、mean、SD、
分位数、min/max 及 logical cells；生成源、日志和结果沿用 Git 忽略规则。
不得把只通过源码检查写成 SAS 数值验证通过。

## 6. 实施与验证

已实施的边界：

1. 单 block preparation、precision、结果关联及渲染，共享 PROC MEANS；P0-13
   另共享 value/digits 转换，保持原 block namespace。
2. 首版只合并同 container、同 level、顺序相邻且上述完整契约兼容的 continuous blocks。
3. 采用 analysis_order 窄输入与显式 raw 拆分，接受第 3 节说明的批内中止顺序影响。

`src/emitters/continuous.R` 将准备、MEANS、结果关联和数值转换拆为可复用步骤；
`src/emitters/hierarchical.R` 负责相邻分组、共享分析/转换及原 block 输出映射。
metadata、workspace、UI 和生成请求契约不变。

验证入口：`test/testthat/test-z-hierarchical-emitter.R` 和
[SAS 对照 fixture](../test/fixtures/sas/hierarchical_continuous_batching/README.md)。
2026-09-29 使用 SAS 9.4 执行 record、distinct_subject、typed distinct_key、空 source、
全 missing 五个成功场景，全部 raw statistics、precision、hierarchical statistic 和
render 输出与独立 block 执行一致；两个第二 block 冲突场景均按预期 ABORT CANCEL。
没有以这些小样本断言生产规模的性能收益。

## 7. 源码精简维护（2026-09-29）

用户在 session `01a0e906-683a-7581-b7a1-589ba0116fb7` 明确：优化的主要目的
是减少代码量、提升可读性，没有运行速度提升也可以接受。后续以生成的完整 SAS
行数、重复 DATA/PROC 步骤和人工阅读路径评估收益；分析结果和失败语义仍是前提。
R 端函数复用或 PROC MEANS 次数减少，不能单独证明生成程序更简洁。

本次在既有契约内精简两处重复步骤，不扩展合批范围：

1. 单个 nested continuous chunk 的规范化步骤同时创建其 chunk input
   `_TFL_CIN_<nested>_001` 和 batch input `_TFL_CIN_<nested>`。两张表的字段、
   记录顺序、typed keys 和 source_row 完全相同，省去随后原样复制的 DATA step。
   两个既有名称和 WORK 对象均保留；counting-unit guard、precision 和后续消费
   顺序不变。普通 top-level batch 以及多 chunk input 的拼接路径保持原责任。
2. 共享 `_TFL_HCRAW_*` 通过一个 DATA step 按 analysis_order 显式 OUTPUT 到
   各 block 原有 `_TFL_CRAW_*`。统一恢复 chunk_order=1 并移除 analysis_order；
   每条 raw record 只写入所属 block。空输入仍创建所有零行输出，所有输出完成后
   才开始 expected-cell/statistic/render。组内每个 block 位置仍使用原 sequence
   编号，包括从第 2 个 block 开始的组。

未采用宏包装整段重复代码或压缩多条语句来降低物理行数，也未改变独立 precision、
expected-cell、statistic、render 或布局的所有权。用户随后单独确认 P0-13，仅共用
无跨记录累积的 value/digits 转换；其完整边界见
[已批准结果转换设计](hierarchical-result-sharing-proposal.md)。初次精简的测量与验证见
[源码精简记录](hierarchical-runtime-verification.md#源码精简与可读性更新)。
