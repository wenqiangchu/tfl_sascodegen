# 未决问题

## P-2a：统一 denominator 契约的来源细则与迁移（已关闭）

已关闭。模型与实施决定分别来自 session `01a182b8-5fd8-7271-bc73-8ed5ddafc291`
和 `01a19004-a9fc-73b2-987d-498188be499d`。统一分母 parser、canonical YAML、UI、
primitive/nested emitter 与 v2 transport 已更新。Header source 条件顺序、scope/unit
宿主限制、分母键独立性及不自动迁移均按批准契约实施。详见
[统一分母实施决定](design-decisions.md#统一分母实施规则)和
[契约](denominator-contract-design.md)。

## P-2b：SOC/PT 最高严重程度与记录选择（已关闭）

已确认不新增 `record_selection`、排序字段或新的 counting unit 字段。当前配置本身
不能声明“按 AESEVN 降序、并列按 AESEQ 升序后取第一条”；`filter` 只筛选记录，
`distinct_key` 只定义身份，`order_variable` 只排列动态节点，`result_sort` 只排列
输出结果。

实现通过 `custom_code.before` 或调用方预先准备的 ADaM source 完成。推荐在共享的
hierarchical source 中保留原始事件，并派生 `SOC_MAX_SEV` 与 `PT_MAX_SEV`：

- `SOC_MAX_SEV` 按 `USUBJID + SOC` 计算；
- `PT_MAX_SEV` 按 `USUBJID + SOC + PT` 计算；
- SOC analysis block 的 row condition 使用 `SOC_MAX_SEV`；
- PT analysis block 的 row condition 使用 `PT_MAX_SEV`；
- counting unit 继续使用 `distinct_subject`。

若业务必须物理保留第一条记录，则在 `custom_code.before` 中分别按 SOC 和 PT 的
分组键排序并使用 `FIRST.` 生成两个派生源；不能对共享 source 全局只保留一条，
否则会改变另一层的分析范围。严重程度并列规则、缺失值规则和分析前过滤条件由
调用方的 SAS preparation 明确，应用不读取或执行这些代码。

## P-2c：保留线性 hierarchical 结构（已关闭）

用户决定保留当前线性层级，不在本轮扩展通用树形分支。当前 levels sequence 定义
一条 level 链；每个父节点在运行时仍可产生多个由数据决定的同层子节点。例如
`SOC -> PT` 会在每个 SOC 节点下生成多个 PT 节点，这种一对多数据分组不需要树形
分支能力。

真正的树形分支是一个父 level 下存在不同的动态子 level，例如 `SOC -> PT` 同时
`SOC -> Severity`。它适用于两个或更多由数据决定的不同维度需要作为 sibling paths
展示、且各自拥有独立节点值域、source 范围、排序或分析 block 的场景。它不是多个
固定分析 rows，也不是一个 level 下有多个实际数据值。

未来若确有该类需求，树形 level graph 是可选的扩展方向；届时需要一起重构 metadata
父子契约、节点身份、父节点范围、排序遍历、anchor analysis 和行布局。该改造横跨
parser、UI、hierarchical emitter 与 render，属于较大重构。本轮不继续展开该方向的
方案讨论。当前 `parent_level` 的值不改变生成器按 levels sequence 处理的行为。

## P-2d：format 节点目录（核心设计已决定，边界待定义）

用户确认动态 level 可以引用调用方提供的 SAS format。format 必须已经在调用方的
format catalog 中定义，或由 `custom_code.before` 定义；应用不读取 catalog，也不
检查 format 是否存在、原始变量类型是否匹配或格式化结果是否为字符型。这些是调用方
的约定。指定 format 后，动态节点使用 format 产生的字符型格式化值同时作为节点身份、
节点值和显示标签；此时不使用 `label_variable`。未指定 format 时，才使用
`label_variable`（或其缺省变量）作为显示标签；原始变量可以是 numeric 或 character。

用户还确认 format 定义的是完整节点值域，而不是仅为实际观测值提供标签。动态节点
即使没有观测也要显示，频数为 0。一个 level 指定 format 后，其 format 值域应在每个
父节点下展开；父节点没有观测时，只有在父 level 自己的 format 值域将该父节点纳入时，
该父节点才存在。父 level 和子 level 都有 format 时，语义上允许完整的格式化值组合。

SAS 机制上，`PROC MEANS`/`PROC SUMMARY` 的 `CLASS ... / PRELOADFMT` 配合
`COMPLETETYPES` 可以预载 format 值域并产生零频组合；`PROC FREQ` 没有 `CLASS`
语句，`TABLES` 的 `SPARSE` 不能替代 format 值域预载。用户确认分类频数统一使用
`PROC MEANS`，不再使用 FREQ 结果再与完整骨架 merge 的路径。每个进入某个分类计数
输入的记录先设置 `flag=1`，再以 `N(flag)` 计数；不符合该 row condition 或分母条件
的记录在进入对应计数输入前排除，而不是设置为 0 后计数。

已决定：在 `levels[]` 增加可选字符串字段 `format`，保存不带末尾句点的 SAS format
名称；字符型 format 使用 `$` 前缀。emitter 负责补句点并生成 FORMAT 绑定。字段不
保存 catalog 路径，应用不解析或检查 format 的存在性和类型匹配。指定 format 时，
`order_variable` 不参与节点排序；节点顺序按 format 的存储顺序生成，SAS format 需要
声明顺序时由调用方使用 `NOTSORTED`，`result_sort` 仍可覆盖最终展示顺序。未指定
format 时沿用现有 `label_variable`、`order_variable` 和 `order_direction` 规则。

当前版本边界：format 只负责提供完整节点列表和原始值到显示值的映射。ranges、
`OTHER`、特殊 missing 和 multilabel format 暂不增加专门语义；需要这些效果时，调用方
必须在分析前自行准备数据或 format 结果。

## 其他

上述讨论记录与已确认修复见 [分析契约讨论记录](analysis-contract-review.md)。
[Hierarchical continuous 结果转换共享](hierarchical-result-sharing-proposal.md)
已按用户确认实施为 P0-13：只共享 value/digits DATA step，保留所有中间表和逐块
expected-cell、join、render、HSMAP，不增加共享中间表或宏封装。用户已接受本组
CJOIN 全部完成后统一转换的顺序变化；负相对精度明确保持现有 ERROR + NE，
不终止当前提交。可读性优先于行数。

既有已批准事项：Hierarchical 相邻兼容 continuous blocks 的
[共享 PROC MEANS 设计](hierarchical-continuous-batching-proposal.md) 已于 2026-09-29
确认并实施，合批范围、结果映射及批内中止顺序见 P0-11。

后续批准的 hierarchical 最终行身份与组装修复见 P0-12。明确预期的 synthetic
fixture 已补充，5 个场景的外部 SAS 运行期核验已通过；性能测量记录见
`docs/hierarchical-runtime-verification.md`。这些验证不增加应用内 SAS 执行功能。

既有批准范围：P0-1 至 P0-8 已冻结 YAML、workspace、批处理、
long-form result、四类 emitter 的 SAS 微契约、warning 顺序和 source regression
边界；Shiny active editor、dirty draft 和 New/ID 对话框语义已冻结，详见
`docs/active-editor-state-and-id-design.md` 与 `docs/design-decisions.md`。

既有实现任务继续按 P0-1 的 R/YAML 依赖基线实现 P1-P8
阶段、编写 synthetic tests，并在不执行 SAS 的前提下比较生成 source。
