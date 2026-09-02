# 未决问题

本文只记录尚未获得用户批准的设计问题。这里的建议不是已批准的契约；
在确认后，应把结果分别写入设计决策或拒绝方案记录。

## 第 2 组：解析后的 metadata 对象

第 2 组中与 ref 重叠的字段语义已经按用户要求冻结，详见
`docs/design-decisions.md` 和 `docs/ref-alignment.md`。以下只保留实现层面尚未
冻结的项目：

1. SAS dataset reference 的具体语法和调用方绑定 convention。
2. 四类 emitter 的具体 SAS 语句、物理中间 dataset 命名和实现依赖；业务职责与
   logical-cell 字段契约已在第 7 组冻结。
3. SAS 中与 ref 结果等价的 percentile、base_digits、rounding、formatting 和
   `NE` 实现。

## 本项目独立的后续确认

1. 外部 SAS dataset reference 的精确写法和调用方绑定 convention。
2. 四类 emitter 的具体 SAS PROC/步骤、中间对象命名和 source regression 实现；
   逻辑输出职责已确认。
3. `cell_format` 的 SAS 代码生成方式，以及 percentile、rounding、missing/NE 的
   最终实现细节。
4. emitter 具体实现的依赖锁定；不改变已确认的 strict single-document import
   profile 和 P0-1 的 parser/toolchain 选择。

Session-owned workspace、draft guard 和 revision 已在第 3 组及第 9 组确认；具体
Shiny 控件布局属于实施阶段，不再列为开放设计问题。
