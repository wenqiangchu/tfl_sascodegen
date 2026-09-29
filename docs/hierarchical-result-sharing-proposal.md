# Hierarchical continuous blocks 结果处理精简：已批准边界

状态：**已确认并实施**（2026-09-29）。用户明确“确认，按这一小范围实施，不增加共享
中间表或宏封装”，并要求“不要为了缩减代码量而降低可读性”。本决定只共享统计值转换与精度解析的
DATA step；不将整套 expected-cell、join、statistic、render 流程合为一个 group
流水线。本决定作为 P0-13，仅细化 P0-11 的结果处理步骤与执行顺序；其他边界不变。

## 1. 数据对象与职责

以下对象均沿用已批准的 metadata/生成期/SAS WORK 契约。本实现不增加共享中间
数据集、不改为多 block PrimitiveBatchPlan，也不新增 YAML、workspace 或 UI 字段。

### 1.1 分组和输入输出描述

只消费 [P0-11](hierarchical-continuous-batching-proposal.md) 已有的相邻兼容 continuous
group。group 的全部字段及其职责为：

| 字段 | 职责 |
| --- | --- |
| `container_order` | 当前 container 的生成编号。 |
| `anchor_level_order` | 当前 level 的位置和共同 node scope。 |
| `compatibility` | 既有七项比较值：`primitive_type`、`source_contract`、`membership_source`、`nodes_dataset`、`counting_unit`、`distinct_key`、`primitive_definition`；判定规则不变。 |
| `members` | 按原 analysis_blocks 顺序保存的 members。 |
| `input_dataset` | 既有 shared MEANS input；本次共享转换不读取或修改它。 |
| `raw_dataset` | 既有 shared raw output；仍先按原规则拆回各 block raw。 |

member 的全部字段及其职责为：

| 字段 | 职责 |
| --- | --- |
| `block_order` | 原 analysis_blocks 位置，保持现有分组与执行顺序。 |
| `analysis_id` | 原 block ID，仍由现有 HSMAP 步骤映射到 hierarchical statistic。 |
| `primitive_plan` | 原单 block plan，拥有 row/result map、raw、precision、statistic、render 名称及局部 metadata 身份；不改为共享可变对象。 |
| `analysis_input_dataset` | 原规范化/counting-unit input；本次结果转换不读取或修改它。 |

共享转换只从每个原 plan 的 `batch_order` 确定 `_TFL_CJOIN_<nested>`，向
其 `statistic_dataset` 指定的 `_TFL_STAT_<nested>` 输出。现有 plan 的其他字段
仍由 preparation、expected-cell、join、render 和布局步骤按原职责消费。

### 1.2 转换输入 `_TFL_CJOIN_<nested>` 的完整字段

每个 block 仍独立创建 compact map、expected cells，并与自己的 raw 和 precision
关联。共享转换只读取已经完成关联、包含下列全部 29 列的 CJOIN，不读取分析数据。
下表按语义列示字段；SAS 实际列序受原 LENGTH/INPUT 和 SQL 投影影响，验收以现有
数据集 descriptor 为准，不按这张说明表重新排列。

| 字段 | SAS 类型 | 职责 |
| --- | --- | --- |
| `chunk_order` | numeric 8 | 原 nested plan 内位置，仍为 1，不表示 block 身份。 |
| `chunk_id` | character | 原 nested composite chunk ID。 |
| `row_order` | numeric 8 | block 内静态行顺序。 |
| `row_id` | character | 局部行 ID，不同 blocks 可以同名。 |
| `row_type` | character 16 | analysis 或 label。 |
| `label` | character | 原静态标签，不提前覆盖为动态标签。 |
| `indent_level` | numeric 8 | metadata 的局部缩进。 |
| `statistic_id` | character 16 | 所请求的统计量；label row 为空。 |
| `statistic_order` | numeric 8 | 当前行的 statistic 顺序。 |
| `digits_mode` | character 16 | none、absolute 或 relative。 |
| `digits_value` | numeric 8 | 绝对小数位或相对偏移。 |
| `use_header_n` | numeric 8 | 原公共 map 字段，continuous 不引入新的 Header N 逻辑。 |
| `cell_format` | character | 原样保留的字符模板。 |
| `header_column_id` | character | 当前 expected cell 的 Header 身份。 |
| `column_order` | numeric 8 | 当前 Header 位置。 |
| `node_key` | character | 当前节点身份。 |
| `group_path` | character | 当前节点路径。 |
| `node_label` | character | 当前动态节点标签，留给后续布局使用。 |
| `node_order_path` | character | 当前默认节点顺序路径。 |
| `hierarchy_level` | numeric 8 | 当前节点层级。 |
| `_n` | numeric 8 | 原 PROC MEANS 的非缺失数。 |
| `_mean` | numeric 8 | 原均值。 |
| `_sd` | numeric 8 | 原样本标准差。 |
| `_median` | numeric 8 | 原中位数。 |
| `_q1` | numeric 8 | 原第一四分位数。 |
| `_q3` | numeric 8 | 原第三四分位数。 |
| `_min` | numeric 8 | 原最小值。 |
| `_max` | numeric 8 | 原最大值。 |
| `base_digits` | numeric 8 | 当前 block/node 独立推导的基础精度，已由原 join 处理缺省。 |

这些 CJOIN 的列类型、顺序和字符长度相容，依据是同一内置 continuous contract、
同一生成程序的 `_TFL_ID_LEN` / `_TFL_LABEL_LEN` / `_TFL_CELL_LEN`，以及同一
node/Header catalog。不得用隐式截断、字符串化或统一精度来强行适配不兼容输入。

### 1.3 转换输出与临时状态

`_TFL_STAT_<nested>` 保留输入的全部 29 列，并按原顺序增加：

| 字段 | SAS 类型 | 职责 |
| --- | --- | --- |
| `value` | numeric 8 | 按 statistic_id 选择的未舍入值，n 缺失补零。 |
| `estimable` | numeric 8 | 当前 statistic 的可估计标记。 |
| `resolved_digits` | numeric 8 | 当前 statistic 的最终精度；n 和 label row 不适用。 |

每个私有 statistic 仍是原来的 32 列。实际物理表保留了 map/raw/precision 字段，
不能只按公共逻辑对象的七个字段重新裁剪。

每个输入增加一个 SAS `IN=` 临时标志。其名称由原 nested batch 编号派生，表示
“当前记录来自哪张 CJOIN”，只决定显式 OUTPUT 的目标。标志不写入任何结果表，
不加入共享 `analysis_order`，不重编 chunk_order，也不以 row_id、label 或字符串
chunk_id 推断归属。它是本 DATA step 的临时状态，不能成为后继步骤的依赖。

### 1.4 保留的对象、所有权与生命周期

| 原对象 | 后续责任 |
| --- | --- |
| 各 block 的 input、counting-unit、precision、raw | 按原流程独立创建；本次不修改其内容或计算方式。 |
| `_TFL_KEY_MAP_<nested>` / `_TFL_KEY_<nested>` | 每块独立生成 inline metadata 和 expected cells，保留现有名称、所有字段与特殊字符规则。 |
| `_TFL_CJOIN_<nested>` | 每块独立完成自己的 raw/precision join；供共享转换只读使用。 |
| `_TFL_STAT_<nested>` | 在共享转换中分别创建，保留原字段、类型、长度、列顺序和记录归属。 |
| `_TFL_RSTAT_<nested>` / `_TFL_REND_<nested>` | 按原 block 顺序独立排序和渲染；不改变 BY key、cell_text 累积、输出字段。 |
| `_TFL_HSMAP_*` 和所有层级布局/assembly 对象 | 继续从各 block 原有结果读取；result_sort、same_row/below、最终行号及 spacer 均按原实现。 |

不增加、删除或重命名以上 WORK 对象，不主动清理它们，不覆盖其他 group。各 block
仍是私有结果的逻辑所有者，group 只负责安排同一转换步骤的多个输入和输出。共享
转换不得修改 CJOIN。SAS WORK 负责生命周期回收，不向 R workspace 写回结果。

## 2. 实施前的重复量与阅读成本

R 已经复用 expected-cell、statistic 和 render 函数，但生成 SAS 时会为每个 block
重复输出。仅继续提取 R helper，不会减少 SAS 重复。

设计评估时在 R 内存中读取生产生成器和 `hierarchical_row_assembly/metadata.R` 的纯合成
定义，按现有两/四个 continuous blocks 示例测量。每块一行 mean、三个 Header
columns；未重建磁盘生成文件、未执行 SAS。

| 实施前处理段 | 每 block 行数 | 2 blocks | 4 blocks | 已采用边界 |
| --- | ---: | ---: | ---: | --- |
| compact map + expected-cell expansion | 24 | 48 | 96 | 保持逐 block，便于查看每块的行定义。 |
| raw/precision join | 11 | 22 | 44 | 保持逐 block，关联对象和精度来源直接可见。 |
| statistic value / digits DATA step | 22 | 44 | 88 | 仅这一段共享。 |
| statistic sort + render | 28 | 56 | 112 | 保持逐 block，避免让分流编号进入渲染 BY key。 |
| 合计 | 85 | 170 | 340 | 不把整段重复量当作应删除的代码。 |

计数包括现有操作注释及一条 inline metadata record，不含 preparation、MEANS、
raw 拆分、HSMAP 和布局。本方案共享的是无跨记录累积的转换逻辑：对每条输入
独立计算 value、estimable、resolved_digits。重复的 map/join/render 保留了清楚的
block 边界，因此不以消除全部重复为目标。

## 3. 已批准的数据流与 SAS 形态

仅对 **P0-11 已有且至少两个 members 的 continuous group** 使用共同转换。
不同 rows、statistics、digits、cell_format 可共组，因为它们已经成为每条 CJOIN
记录的字段；不跨 categorical、非相邻 blocks、level 或 container，也不接管替代
注册 emitter。单 block 和其他原有路径保持。

```text
each block: existing preparation / precision
  -> existing shared MEANS and private raw outputs
  -> block A map / expected cells / raw-precision join
  -> block B map / expected cells / raw-precision join
  -> one value/digits DATA step, writing private STAT A and STAT B
  -> block A sort / render / HSMAP
  -> block B sort / render / HSMAP
  -> existing result_sort and hierarchical layout
```

以下为两个 blocks 的生成形态；输入与输出名称随原 nested batch 编号变化：

```sas
/* Apply the same statistic conversion to each block's prepared results. */
data _TFL_STAT_002 _TFL_STAT_003;
  set _TFL_CJOIN_002(in=_tfl_result_002)
      _TFL_CJOIN_003(in=_tfl_result_003);
  select (statistic_id);
    when ('n') value = coalesce(_n, 0);
    when ('mean') value = _mean;
    when ('sd') value = _sd;
    when ('median') value = _median;
    when ('q1') value = _q1;
    when ('q3') value = _q3;
    when ('min') value = _min;
    when ('max') value = _max;
    otherwise value = .;
  end;
  estimable = not missing(value);
  resolved_digits = .;
  if digits_mode = 'absolute' then resolved_digits = digits_value;
  else if digits_mode = 'relative' then resolved_digits = coalesce(base_digits, 0) + digits_value;
  if resolved_digits < 0 and not missing(resolved_digits) then do;
    putlog 'ERROR: [USER] Relative digits resolved to a negative value.';
    estimable = 0; resolved_digits = .;
  end;
  if _tfl_result_002 then output _TFL_STAT_002;
  if _tfl_result_003 then output _TFL_STAT_003;
run;
```

输入列表和 OUTPUT 使用相同的 nested 编号，按原 member 顺序出现。没有新共享表、
中间编号映射表、宏定义/调用跳转，也不压缩已有业务语句。每条记录的来源和去向
可以在这个 DATA step 内直接核对。不同 block 的同名 row ID 不会合并，数据也
不会在 block 间聚合、去重或共享 base_digits。

按上面相同排版，两个旧 DATA steps 共 44 行，共享片段为 26 行（含新增注释）。
完整源码规模见第 7 节。输出 DATA 声明超过 80 字符时分行列出名字，不以行数增加
为失败，也不通过宏或缩写隐藏输出名。

## 4. 创建顺序与失败边界

counting-unit guard、precision、共享 MEANS 和 raw 拆分保持原顺序。因此
continuous_unit_multiple_values 的诊断、首次冲突和 ABORT CANCEL 不受此共享
转换影响，duplicate-check 选项也不改变它。

结果阶段从逐块完成全部步骤，变为先准备本组所有 CJOIN，再一次转换，最后逐块
render/HSMAP。用户已接受这项顺序变化：较早 block 的 STAT/render 不再先于较晚
block 的 CJOIN 创建；任意 SAS 编译/执行错误时，部分 WORK 表的产生时机及系统
日志交错可能不同。最终正常输出的身份、字段、统计值、字符 cells 和展示顺序
须相同。SET 按 member 顺序串接输入并保留各 CJOIN 的记录顺序，不重新排序。

当前 `statistic_digits_source` 对负相对精度执行 ERROR + estimable=0 + missing
resolved_digits，继续后续步骤，最后该 statistic 显示 NE；没有 ABORT CANCEL。
P0-13 已澄清早期文档中的 failure 表述，明确它不等同于终止当前提交。
本次保留实际行为与每条受影响 statistic 的诊断，不去重同文消息、不增加新的
中止策略。若要改成停止执行，应单独确认统计失败契约，不能混入本次源码精简。

源代码生成前置失败仍使用原 envelope，不返回部分 source。空 CJOIN 或整组零行
时，所有目标 STAT 必须正常创建为零行表，保留 schema，不能沿用旧同名数据集。

## 5. 方案比较与未采用项

| 方案 | 对阅读路径的影响 | 结论 |
| --- | --- | --- |
| 保持全部独立 | 每块可以从 map 一直顺序读到 render；重复的转换代码也最多 | 合理基线；若共享使排错更困难，应保留它。 |
| **仅共享 value/digits DATA step** | 保留所有原表名与逐块 join/render，只在一个位置列出来源和输出 | **已采用**。 |
| expected-cell、join、statistic、render 全部共享 | 需要额外 group 表、analysis_order 关联与渲染分组键、私有结果拆分；跟踪一个 block 的路径更长 | 本轮不推荐，减少行数不足以抵消阅读成本。 |
| 用生成 SAS 宏包装重复结果步骤 | 可保留运行顺序，但阅读需要在宏定义与调用之间跳转，并新增宏生命周期规则 | 本轮不推荐；不为行数指标引入这一层。 |

不采用：将整段统计计算压成单行、隐藏统计计算、用 chunk_order 冒充 block 身份、按 row ID/label
推断输出、统一各 block 的精度、将 analysis 与 render 合并、扩展到 categorical，
或增加用户配置。R 内部抽取 helper 只在职责更清楚时使用，不作为 SAS 精简成果。

## 6. 验收标准

可读性为约束：保留现有计算主体和英文步骤注释；输入/输出按相同 block 编号和
顺序明确列出；不增加共享 WORK 表、render BY 维度或生成 SAS 宏。不能为了通过
行数指标而压缩复杂逻辑或隐藏失败处理。用户后续确认的 Header 等短规则合行，
以及 CARDIMAGE 防御移除，见 `design-decisions.md` 的后续维护决定。

正确性和契约回归应覆盖：

- 两、三、四个 members、从非首位 block 开始的组、多个 containers；相同 snapshot
  的生成确定性，以及单 block、不兼容块、替代 emitter 的原路径。
- 不同 rows/statistics/digits/formats、相同局部 row ID、label row、n 和多个统计量
  组成的 cell；逐块输入和输出对应正确。
- 三种 counting unit、重叠/空 Header、全 missing、空节点集；两个 unit 冲突保持
  原行为。多个 blocks 各自出现负相对精度时，消息数量及 block 顺序保持。
- STAT 的全部 32 列，包括原 raw/metadata 辅助列，以及类型、长度、字段顺序与原
  路径一致；IN 标志不泄漏，value/resolved_digits 不从上一条记录遗留。
- 原 KEY_MAP、KEY、CJOIN、RSTAT、REND 名称继续可用。对照前清除 fixture 的生成
  表，防止旧输出掩盖未创建的新表。
- result_sort 指向第二个 block、same_row/below、多层级、混排 chunks 和 spacer
  继续通过手算 expected-row fixture；不只比较两个实现彼此相同。
- Report/QC 仍只生成 source；R 测试不执行 SAS。沿既有授权另行执行 synthetic SAS
  fixture 时，分别报告 source regression 和运行验证。
- 完整生成 SAS 行数、步骤数和阅读路径一起评估；不将示意片段行数当作实际成果，
  不以运行加速作为本次目标。

## 7. 实施与验证

已实施全部获批边界。continuous emitter 将原有统计 join 与逐记录 value/digits
转换拆开复用；hierarchical emitter 仅在现有兼容组内安排共享转换。单块及不兼容
路径仍由原 emitter 处理，没有新增配置、WORK 表或 SAS 宏。

数值转换实施时，在同一源码规模 fixture 上，2 blocks 从 545 行降至 527 行，4 blocks 从 839 行
降至 781 行；保留原注释和逐块 key/join/render。相关 R 回归、SAS schema/value
对照、负精度继续执行及手算行组装验证均通过，详见
[运行与源码验证记录](hierarchical-runtime-verification.md#p0-13仅共享-statistic-转换的验证)。
后续 INPUT 分行仅改善排版，因此当前行数高于该阶段数值；最新规模和对照见同一
验证记录末尾的排版维护说明。
