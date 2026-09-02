# Ref 对齐审查

审查范围：`ref/阶段01-元数据结构与存储.md`、`ref/阶段02-Chunk扩展模型与注册机制.md`、
`ref/阶段03-最小Metadata核验器.md`、`ref/阶段04-Metadata驱动的R代码生成与执行.md`、
`ref/阶段05-Metadata编辑服务与Shiny Dashboard.md`、`ref/阶段06-Chunk扩展与层级分析.md`。

结论先分为三类：可直接沿用的是字段和业务语义；需要改写的是 R 语言实现；明确不能
沿用的是 ref 的磁盘、执行和报表边界。当前项目的 `AGENTS.md` 与便携契约优先于 ref
中与项目范围冲突的内容。

## 可沿用的字段含义与分析语义

| 领域 | ref 中可复用的决定 | 本项目处理 |
|---|---|---|
| 集合与顺序 | 对象是有序 sequence；位置 ID 是由 sequence 产生的编辑身份 | 沿用；不把位置 ID 当跨版本数据库主键 |
| Population | `id`、`label`、`expression`；表达式是 opaque source text | 沿用字段和不执行边界；表达式改为 SAS dialect |
| Header | `id`、`source_data`、`spanning_headers`、`columns`；column 有 condition、display_order、width、alignment 和 spanner 引用 | 沿用字段含义；`source_data` 表示外部 SAS 数据集引用，不是 R dataset binding |
| Table 引用 | `population_id`、`header_id`、`template_id` 是引用而非内联对象 | 沿用；当前项目继续排除 ref 的展示/报告字段 |
| Template/Chunk/Row | `body.chunks` 有序；chunk 公共字段、类型专属字段、row 的 label/analysis、statistics、cell_format | 沿用；未知 type 不静默解释 |
| Position ID | chunk、row、level、analysis block 使用位置 ID，插入/删除/移动后重编号并同步引用 | 沿用；动态 group value/runtime row ID 不写回 YAML |
| Filter/merge | source filter 先于 merge；不修改原始 source；subject-level 首期每个 `USUBJID` 至多一条 | 沿用为 SAS 生成器的逻辑顺序 |
| Continuous | n/mean/sd/median/q1/q3/min/max；sample SD；R quantile type 2 的等价分位数；n=0/n=1 与非有限值边界 | 沿用业务结果语义；PROC/DATA step 实现另行确认 |
| Precision | base digits 来自实际分析 subjects；15 位有效数字规范化；绝对和 `+n`/`-n` 相对 digits；负 resolved digits 失败 | 已确认沿用；SAS emitter 必须实现等价结果 |
| Formatting | half-away-from-zero、固定小数位、尾随零、负零归一化、字段级 `NE` | 沿用显示语义；SAS PUT/ROUND/格式化实现另行确认 |
| Categorical | `header_population`、`non_missing`、`custom` denominator；n/pct；pct 为 0–100；百分号由 cell format 提供；nonexclusive 允许 row overlap | 沿用；表达式由 SAS source 直接生成 |
| Registry | `ChunkTypeDefinition` 声明 required/optional fields、row/data/merge/analysis/render contract；用户 YAML 不能注入函数 | 沿用职责分离；registry binding 不进入 bundle |
| Hierarchical | ordered levels + analysis blocks；source grain/key；order variable/direction；missing policy；same_row/below；显式 denominator scope；static analyses 在 dynamic children 前 | 沿用字段和输出顺序语义；不生成 RTF |
| Hierarchical sorting | `result_sort.metric`、`column_order`、`direction`；0 为 label 且只能末尾；比较 raw value，NA/NE 在有效值后 | 沿用并冻结为结构化字段，不再使用 opaque mapping |
| Runtime result | `ChunkStatisticValue` 保留 chunk/row/header/statistic identity、raw value、estimable、resolved_digits；render 再形成 cell text | 沿用为 SAS generator 内部逻辑对象，是否落盘仍禁止 |

## 需要从 R 改写为 SAS 的内容

1. 所有 population/header/filter/denominator/row condition 从 R expression 改为
   SAS expression；平台保存原文、生成器拼接原文，不执行或翻译表达式。
2. ref 的 R data frame、`dplyr`、R quantile、R round 和 `reporter` package 只是实现
   例子，不能成为 SAS 契约。SAS PROC、DATA step、percentile definition、PUT/format
   和缺失显示需要在 emitter contract 中指定等价行为。
3. ref 的直接 R binding、`.tfl_*` 临时对象、`init.R`、`tfl_runtime.R`、Rscript 和
   RTF artifact 不进入当前产品；SAS source 的 section 和中间 dataset 名称需要
   另行定义。
4. ref 的 R parse validator 不可直接沿用。当前项目只要求 bundle parser 的结构
   错误和生成前置引用错误；是否增加 SAS source 静态检查需另行批准。

## 明确不能沿用的 ref 边界

- `study.yaml` 作为多文件 study 入口、`metadata/` 固定目录、roots、datasets
  清单和绝对/相对物理路径：当前项目使用单文件 bundle、session 内存 workspace，
  不保存 study root、dataset 文件路径或 artifact path。
- `orientation`、`titles`、`footnotes`、page header/footer、RTF reporter profile：
  当前 TableSpec 不包含这些字段，也不生成报表文件。
- R program/manifest、Rscript 执行、runtime snapshot、stdout/stderr、run history
  和 artifact replace policy：当前唯一必需产物是 SAS source text。
- ref 的数据文件存在性、R expression parse、变量类型、USUBJID 实际唯一性等
  运行/数据校验：当前平台不读取或验证 SAS 数据。

## Ref 中仍需本项目确认的事项

以下不是“自动继承”的决定，因为它们依赖 SAS 实现或当前产品边界：

1. 外部 SAS dataset reference 的精确语法和调用方绑定约定。
2. population expression 是否始终在 header.source_data 上求值，以及 SAS missing
   value、日期/时间和字符比较 dialect。
3. 四类 chunk 的具体 PROC/DATA step、显式中间 dataset schema、最终 logical cell
   schema 和 hierarchical record-to-subject 广播实现。
4. SAS percentile definition 是否采用与 ref R type 2 结果等价的方法，以及
   `base_digits` 在 SAS numeric/format 信息不可得时的取值来源。
5. `custom_code.before`/`after` 在 SAS source 中的精确插入点、共享作用域和允许
   改变的对象。
6. 传输/解析错误和生成前置引用错误的最小稳定错误包络。
7. YAML parser 的 R 包和版本；实现阶段通过依赖锁定确认，不改变 canonical profile。
