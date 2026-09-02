# 未决问题

本文只记录尚未获得用户批准的设计问题。这里的建议不是已批准的契约；
在确认后，应把结果分别写入设计决策或拒绝方案记录。

## 第 2 组：解析后的 metadata 对象

第 2 组中与 ref 重叠的字段语义已经按用户要求冻结，详见
`docs/design-decisions.md` 和 `docs/ref-alignment.md`。以下只保留实现层面尚未
冻结的项目：

1. YAML canonical profile 的数值序列化细节，以及实施阶段使用的 R YAML 包和版本。
2. SAS dataset reference 的具体语法和调用方绑定 convention。
3. 四类 emitter 的具体 SAS 语句、物理中间 dataset 命名和实现依赖；业务职责与
   logical-cell 字段契约已在第 7 组冻结。
4. SAS 中与 ref 结果等价的 percentile、base_digits、rounding、formatting 和
   `NE` 实现。
5. 传输/解析失败和生成前置引用失败的最小稳定错误包络。

## 本项目独立的后续确认

1. 外部 SAS dataset reference 的精确写法和调用方绑定 convention。
2. 四类 emitter 的具体 SAS PROC/步骤、中间对象命名和 source regression 实现；
   逻辑输出职责已确认。
3. `cell_format` 的 SAS 代码生成方式，以及 percentile、rounding、missing/NE 的
   最终实现细节。
4. 传输/解析错误与生成前置引用错误的最小稳定错误包络。

## 第 3 组：Session-owned Workspace 与 Draft

以下事项尚未获得用户确认：

1. dirty draft 存在时，导入新 bundle、切换 active table 和生成 SAS 是否拒绝操作、
   先提示用户，或允许操作并保留 draft。
2. revision 的具体字段、并发模型和 UI 展示细节。

已确认的 workspace、save、export 和删除语义见 `docs/design-decisions.md` 的第 3 组；
`custom_code.before`/`after` 语义见第 4 组；population/header membership 语义见第 5 组。
