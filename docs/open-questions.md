# 未决问题

当前没有待用户确认的设计问题。P0-1 至 P0-8 已冻结 YAML、workspace、批处理、
long-form result、四类 emitter 的 SAS 微契约、warning 顺序和 source regression
边界；Shiny active editor、dirty draft 和 New/ID 对话框语义已冻结，详见
`docs/active-editor-state-and-id-design.md` 与 `docs/design-decisions.md`。

后续仍有实现任务，但它们不是开放设计选择：按 P0-1 的 R/YAML 依赖基线实现 P1-P8
阶段、编写 synthetic tests，并在不执行 SAS 的前提下比较生成 source。
