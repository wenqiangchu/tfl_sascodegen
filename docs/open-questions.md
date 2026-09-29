# 未决问题

当前没有待确认问题。
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
