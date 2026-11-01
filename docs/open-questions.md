# 未决问题

## P-2a：统一 denominator 契约的来源细则与迁移（已关闭）

已关闭。模型与实施决定分别来自 session `01a182b8-5fd8-7271-bc73-8ed5ddafc291`
和 `01a19004-a9fc-73b2-987d-498188be499d`。统一分母 parser、canonical YAML、UI、
primitive/nested emitter 与 v2 transport 已更新。Header source 条件顺序、scope/unit
宿主限制、分母键独立性及不自动迁移均按批准契约实施。详见
[统一分母实施决定](design-decisions.md#统一分母实施规则)和
[契约](denominator-contract-design.md)。

## P-2b：SOC/PT 最高严重程度与记录选择

用户需要 SOC 内和每个 PT 内分别统计受试者最高严重程度。现有 custom_code.before
可以派生 SOC_MAX_SEV/PT_MAX_SEV，再由各分析 block 的 row condition 和
distinct_subject 计数；若要通过 metadata 指定带 asc/desc 的排序键并自动保留
首条，则需记录选择契约。计数身份和排序优先级不能混为同一个 NODUPKEY 键。

待确认：字段表示、与 counting_unit 的关系、选择时机、并列排序与缺失值处理。

## P-2c：parent_level 的实际作用

当前生成器按 levels sequence 建立线性链，parent_level 不驱动实际输入和布局。
用户的 SOC/PT 严重程度表可用两层动态节点和各层的固定严重程度 rows 表达；如果
严重程度也需要作为动态 level 分支，必须明确父子输入、节点身份、深度和遍历规则。
表示方式未确认前，不把任意 parent_level 引用继续解释成已支持的分支能力。

## P-2d：format 节点目录

用户希望自定义 format 同时定义可能的节点值和显示标签。需要明确 metadata 引用、
与 label_variable 的关系、原始值与格式化值的分组语义，以及父节点相关的值域。
MEANS PRELOADFMT/COMPLETETYPES 和 FREQ SPARSE 的能力不同，不能共用一套假定。
当前分析基于内部 node_key，完整节点目录还需进入 expected-cell 与布局流程。

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
