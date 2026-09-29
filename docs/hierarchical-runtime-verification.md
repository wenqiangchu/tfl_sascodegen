# Hierarchical 行组装与合批性能验证

当前收尾测试见 [收尾记录](source-generation-closeout.md)。本文的 SAS 执行结果按
各阶段保留，均早于最终删除 CARDIMAGE 防御；不能将其视为最新源码的重新执行。

验证日期：2026-09-29。用户在完成源码修复后批准继续外部 SAS 验证与性能测量。
本次使用本机 Windows / SAS 9.4，以及仓库中手写的纯合成 WORK 数据；不读取研究
数据，不向应用增加 SAS 执行、结果读取或性能监测功能。下述初次性能测量未修改
生产代码；后续源码精简维护单独记录在文末。

## 行组装正确性

运行 `test/fixtures/sas/hierarchical_row_assembly/run_case.sas`，每个场景使用独立
SAS 进程，比较手工预期的行身份、顺序、标签、缩进、所有列值以及 spacer 位置。

| 场景 | Long cells | Wide rows | 含 spacer 的最终行数 | 结果 |
| --- | ---: | ---: | ---: | --- |
| basic | 12 | 4 | 4 | 通过 |
| sorted | 12 | 4 | 4 | 通过 |
| multilevel | 30 | 10 | 13 | 通过 |
| mixed | 27 | 9 | 11 | 通过 |
| empty | 0 | 0 | 0 | 通过 |

5 个进程均 exit=0，产生对应 `[FIXTURE] row assembly ... passed` 标记，无 SAS
ERROR。SAS 安装本身存在 SASHELP 串联库警告；empty 的两次 PROC COMPARE 另有
“未找到匹配观测”警告，该场景的独立 cell/assembly 行数检查也通过。

负向对照：仅在忽略目录中的 basic 生成源码副本中，将最终 SET 的
`(drop=row_sequence)` 移除，恢复旧行为。该副本生成 2 条宽表记录，并被新 fixture
以 `row_identity_or_column_collision` 拦截，exit=2。生产源码未回退。这证明新断言
能捕获原先“long cells 正确但最终丢行”的问题。

## 性能测量方法

- 使用 `build_benchmark.R` 生成共享/独立两条路径；独立路径使用既有 alternate
  emitter，不增加生产开关。两者除合批之外使用同一 metadata 和 synthetic inputs。
- 10,000 / 30,000 records，每 subject 两条记录，十个分组节点；2 / 4 个连续
  blocks，各输出一行 mean；三个 Header columns 为 Overall、半数 subjects、Empty。
  counting_unit 固定为 record，digits 固定为 1。
- 每种配置/路径执行三次，每次独立启动 SAS，交替先执行的路径，共 24 个样本。
  非专用空闲机器，没有控制 OS 文件缓存或其他系统负载。
- 时间为生成的 SAS 程序从 source preparation 到最终 table assembly 的执行耗时，
  **不是 R 生成源码的耗时**。排除 SAS 启动、synthetic 数据准备、保存对照结果和
  report 输出；以 SAS DATETIME 在该区间前后计时。
- 空间为执行结束时所有 `_TFL_*` WORK 数据表的 `dictionary.tables.filesize` 之和。
  **这是末态中间表文件大小，不是峰值 WORK、峰值内存或累计 I/O。** 同一配置三次
  运行的该指标一致。
- 每个配置最后一次 shared/independent 的完整 public statistic 表和最终宽表通过
  精确 PROC COMPARE（criterion=0），共八次比较通过。fixture 不把性能快慢作为测试门槛。

## 测量结果

时间为三次运行中位数，单位秒；空间单位 MiB（1,048,576 bytes）。

| Records | Blocks | 独立耗时 | 合批耗时 | 合批时间变化 | 独立空间 | 合批空间 |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 10,000 | 2 | 1.386 | 1.364 | -1.6% | 61.48 | 63.54 |
| 10,000 | 4 | 1.908 | 1.794 | -6.0% | 93.62 | 97.49 |
| 30,000 | 2 | 5.775 | 5.871 | +1.7% | 168.79 | 174.54 |
| 30,000 | 4 | 5.890 | 5.905 | +0.3% | 254.93 | 266.18 |

| Records / Blocks | 独立耗时范围 | 合批耗时范围 |
| --- | --- | --- |
| 10,000 / 2 | 1.380–1.457 | 1.333–1.384 |
| 10,000 / 4 | 1.852–3.525 | 1.756–1.807 |
| 30,000 / 2 | 5.728–5.938 | 5.721–5.898 |
| 30,000 / 4 | 5.812–6.012 | 5.851–13.172 |

探索性 100,000 records / 2 blocks 的单次 shared 运行耗时约 63.3 秒。该规模没有
完成配对重复测量，随后停止并缩小为上述正式规模，因此不纳入比较，也不能据此推断
合批相对性能或增长复杂度。

当前样本没有显示稳定加速；两条路径时间接近，且个别运行有明显波动。合批末态中间
表空间稳定增加约 3.4%–4.4%。结果仅覆盖该 synthetic record-grain profile，不能
外推到 distinct_subject/distinct_key、更多层级、不同节点数或研究数据。

## 后续建议与复现

行组装正确性已完成这一组明确预期场景的闭环。用户随后明确优先减少代码量、提升
可读性，因此下一项改为检查生成源码的重复步骤，见下节。步骤级性能分析暂不作为
后续工作的前提；上述测量保留为精简前的历史证据，不因过程调用次数减少而宣称
总体更快，也不依据少量有波动的样本撤回已批准的合批实现。

复现命令和入口见
[fixture README](../test/fixtures/sas/hierarchical_row_assembly/README.md)。本地证据位于该
目录的忽略路径：`logs/{basic,sorted,multilevel,mixed,empty,pre_fix}.log`、
`logs/bench_<records>_<blocks>_<mode>_<repeat>.log`、`logs/benchmark_compare.log` 和
`generated/benchmark-results.json`。生成程序、SAS datasets 和日志不提交 Git；本文件
保留方法、数值与限制供审阅。

## 源码精简与可读性更新

本节记录首轮输入/结果拆分精简；后续 P0-13 的当前结果见文末。

2026-09-29，依据用户在 session `01a0e906-683a-7581-b7a1-589ba0116fb7` 的目标
澄清继续维护。移除单 nested continuous chunk 的原样输入复制步骤，改为一次创建
两个既有输入；共享 raw 拆分改为一次读取、按 block 显式 OUTPUT。对象契约见
[设计维护记录](hierarchical-continuous-batching-proposal.md#7-源码精简维护2026-09-29)。

测量使用同一 `build_benchmark.R` 的 synthetic metadata：一层、两个或四个连续
blocks、每块一行 mean、三个 Header columns。计数区间为程序开头到最终 table
assembly，排除末尾 RTF report；行数包含注释和空行。DATA/PROC 数为该 fixture
生成源码中以 `data ` / `proc ` 开头的行数，不表示运行耗时或通用 SAS parser。

| Blocks | 精简前合批行数 | 精简后合批行数 | 减少行数 | 合批 DATA steps 前 → 后 | 精简后独立路径行数 |
| ---: | ---: | ---: | ---: | --- | ---: |
| 2 | 556 | 545 | 11 | 37 → 34 | 532 |
| 4 | 866 | 839 | 27 | 57 → 50 | 832 |

本次分别减少约 2.0% 和 3.1% 的完整源码行数。两条路径都受益于移除输入复制；
精简前独立路径分别为 540 / 848 行。当时合批程序仍比独立路径多 13 / 7 行，
不能据此宣称合批整体比独立路径更短。PROC 数没有变化，合批为 22 / 34，独立为
23 / 37。本次未重新运行性能基准，不将前述历史耗时用作本次改动后的性能结论。

源码回归覆盖两、三、四个 blocks、非首位开始的组、多个 containers、三种
counting units、单 block fallback、排序和最终行组装。外部 SAS fixture 新增四个
blocks 的对照，检查全部 raw statistics、precision、最终 statistic/render 和
绝对行数。独立结果保存后删除本 fixture WORK 中的 `_TFL_*` 表，再运行共享路径，
防止残留结果掩盖漏写输出。手算行组装 fixture 继续核对完整宽表与 spacer。

本次验证结果：7 组相关 R/source 回归全部通过（source generator、report source、
FDA source structure、continuous、categorical、hierarchical 与 row assembly）。
SAS 9.4 的 6 个 shared/independent 成功场景（record、four、subject、key、empty、
missing）及 5 个手算行组装场景均 exit=0，并产生预期通过标记，无 SAS ERROR。
subject_conflict、key_conflict 均在第二个 block 按预期 exit=2，保留
continuous_unit_multiple_values，未执行共享 MEANS 或失败兜底。
环境原有的 R locale/package-version 和 SASHELP/空输入 COMPARE 警告仍存在；
没有把这些合成场景外推为任意分析数据的正确性保证。

仅重建并打印当前源码规模：

```text
Rscript test/fixtures/sas/hierarchical_row_assembly/build_benchmark.R
```

该命令只生成 SAS source，不执行 SAS 或性能基准。外部验证日志使用两个 fixture
目录的忽略路径 `logs/readability_<case>.log`；原性能日志和 JSON 保留。

用户随后确认只共享 statistic 转换，保留逐块 expected-cell、join 和 render，
详见下节。没有扩展 categorical 合批或新增用户配置。

## P0-13：仅共享 statistic 转换的验证

2026-09-29，按用户确认完成
[P0-13 的小范围实现](hierarchical-result-sharing-proposal.md)。共享 DATA step 直接
读取各 block 的 CJOIN，以 IN 标志写入各自 STAT；原 KEY_MAP、KEY、CJOIN、STAT、
RSTAT、REND 及 schema 均保留，没有共享结果中间表或 SAS 宏。所有输入/输出名在
同一段源码中明确列出，长输出列表分行，不压缩计算和错误处理语句。

### 完整源码规模

与上一轮相同的 metadata、计数区间和口径，实施前已保存源码作对照：

| Blocks | 改前合批行数 | 改后合批行数 | 减少 | DATA steps 前 → 后 | 独立路径行数 |
| ---: | ---: | ---: | ---: | --- | ---: |
| 2 | 545 | 527 | 18（3.3%） | 34 → 33 | 532 |
| 4 | 839 | 781 | 58（6.9%） | 50 → 47 | 832 |

PROC 数仍为合批 22 / 34、独立 23 / 37。独立路径源码字节未变。当前两个示例中
合批源码分别比独立路径短 5 / 51 行；不是所有 metadata 的普遍比例。没有重复
性能基准，也不将行数或 DATA step 数减少解释为运行加速。

### 验证结果

- 7 组相关 R/source 回归全部通过；新增断言锁定 2/3/4 blocks 的一次转换、所有
  CJOIN 先于转换、逐块 render、非首位组和多 container 的输入输出对应。
- 使用修改前保存的 emitter，与当前版本生成相同 fixture：单 block、不兼容组、
  普通 continuous、替代注册 emitter 四条路径的完整源码逐字节相同。
- SAS 9.4 的 record、four、varied、subject、key、empty、missing 七个对照场景
  均 exit=0、通过全部断言且无 SAS ERROR。除原 raw/precision/最终结果外，还逐块
  比较 STAT 全部 32 列及 REND；六类保留的结果表对照列名、顺序、类型、长度、
  format、informat 和 label，IN 标志未泄漏。
- varied 场景包含第二个 block 的 label row、相反 statistic 顺序、不同 cell
  格式、额外 n-only row 和长标签；固定为 8 条宽表行，验证没有跨记录状态遗留。
- negative 场景两条路径均完成，分别记录 12 条原始负精度 ERROR，mean 为 NE，
  n 与其他有效 statistic 正常；schema、统计和字符结果仍一致。本机进程 exit=0，
  末尾有 SAS 的错误页汇总；不能将该场景称为“没有 ERROR”。
- subject_conflict/key_conflict 仍在第二块的 counting-unit guard 按预期 exit=2，
  不执行共享 MEANS 或转换。
- basic、sorted、multilevel、mixed、empty 五个手算行组装场景均 exit=0、无 SAS
  ERROR，行身份、顺序、值和 spacer 通过原独立预期。

SASHELP/空输入 COMPARE、R locale/package-version 的环境警告仍存在；本次证据
限于这些 synthetic fixtures。负精度的诊断次数由实际日志核对，block 顺序由
源码的 SET 顺序锁定；相同诊断文本未用于推断各条日志的 block 身份。

复现构建使用原两个 fixture builder；SAS 命令及 negative 的判定规则见
[fixture README](../test/fixtures/sas/hierarchical_continuous_batching/README.md)。本次
日志在各 fixture 的忽略目录 `logs/conversion_<case>.log`，生成程序、日志和本地
修改前快照不提交 Git。常规 R/source 测试未增加 SAS 运行依赖。

### 生成源码可读性复核

2026-09-29，继续只读检查当前生成的 `benchmark_2_shared.sas` 及层级布局 emitter。
本轮未修改生产代码、未重新生成 SAS、未重跑运行期测试。

| 阅读任务 | 当前源码的追踪方式 | 审阅结论 |
| --- | --- | --- |
| 找到某个 block 的统计输入 | 同一 nested 后缀串起 KEY_MAP、KEY、CRAW、CPREC 和 CJOIN；SQL 明确列出本块 raw/precision 来源。 | 保留逐块关联，来源直接可见。 |
| 确认共享转换没有混入其他 block | 同一个 DATA step 明列 CJOIN 输入、IN 标志与对应 STAT 输出，编号一一对应。 | 当前共享范围可读；不需要查额外映射表或宏定义。 |
| 理解字符 cell 的形成 | 各 block 的 STAT → RSTAT → REND 单独保留，BY key、cell_text 累积和输出条件位于同一段。 | 这些重复说明了有状态的处理边界，值得保留。 |
| 理解同一节点的展示行 | 后续 HSMAP/HMAP 明确设置 analysis_id，并区分 same_row 与 below 的标签、缩进和 order_key。 | 不建议仅为消除相似语句再合并布局步骤。 |

剩余明显的阅读负担是 compact map 的 INPUT 语句较长，阅读字段与 informat 时需要
横向滚动。后续若继续改善，应优先考虑只改变换行和缩进的排版维护，并保持 inline
data records、字段顺序和 informat 原文不变；这会增加物理行数，不应视为退步。
该次审阅尚未实施排版调整；用户继续后完成的维护如下。

### INPUT 分行排版维护

2026-09-29，将 compact map 的 INPUT 改为每个字段/informat 单独一行。示例中
该语句最长行由 298 字符降至 34 字符，字段顺序和宏分隔点保持原样，便于逐项阅读。
没有调整共享范围、统计公式或数据对象，也没有新增 SAS 宏。

相关七组 R/source 回归通过；原有排版断言已适配换行。29 份重新生成的程序与
修改前逐一对照：仅规范化 INPUT 内的空白后，完整程序文本一致。INPUT 的 token
顺序、所有 inline records 和其余代码没有变化。本轮未重新运行 SAS，前述数值和
运行期验证属于 P0-13 实施时的记录。

每份 compact map 的 INPUT 从 1 行变为 15 行。当前两块/四块示例的合批程序分别
为 555 / 837 行，独立路径为 560 / 888 行；DATA/PROC 数保持原值。这里接受为
可读性增加的行数，不能将它解释为计算步骤增加或统计行为变化。

### 移除 CARDIMAGE 防御与短规则合行

2026-09-29，按用户明确要求删除四条 CARDIMAGE 保存/切换/恢复/清理语句，生成
源码直接沿用调用方 SAS 会话设置。此前自动保护长 DATALINES 记录的行为不再存在，
本次没有换成全局 OPTIONS 或其他防御。

按“一条规则一行”整理 Header column 的 IF/赋值/OUTPUT、categorical 分子和分母
事件、chunk catalog 的赋值/OUTPUT，以及层级标签的 Header 列输出。不同规则仍
分行；原 INPUT 字段分行保留，嵌套判断、错误处理及渲染累积逻辑保持展开。

相关七组 R/source 回归通过，Header 重叠规则继续使用独立 IF；新增/更新断言覆盖
分类事件的具名和隐式 OUTPUT。29 份重新生成的程序逐一对照：扣除上述四条语句
后，保留字符串/注释的 SAS token 序列一致，所有 inline data records 完全一致，
其余差异仅为排版。生产源码中已无 CARDIMAGE 处理。本轮未重跑 SAS，前面的运行
期对照仍是移除该选项管理之前的历史验证。

当前两块/四块示例分别为合批 535 / 809 行、独立 540 / 860 行；DATA/PROC 数不变。
