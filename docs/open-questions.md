# 未决问题

本文只记录尚未获得用户批准的设计问题。这里的建议不是已批准的契约；
在确认后，应把结果分别写入设计决策或拒绝方案记录。

## 第 2 组：解析后的 metadata 对象

第 2 组中与 ref 重叠的字段语义已经按用户要求冻结，详见
`docs/design-decisions.md` 和 `docs/ref-alignment.md`。以下只保留实现层面尚未
冻结的项目：

1. 四类 emitter 的具体 SAS DATA/PROC 语句、物理列类型和实现依赖；P0-5 的兼容 batch
   分组策略、P0-6 的专用规范化输入字段和 P0-7 的公共 statistic/render 字段及
   `_TFL_` 命名边界已冻结。
2. warning 文本的具体字段顺序和每类 emitter 的 source regression fixture。

## 本项目独立的后续确认

1. 四类 emitter 的具体 SAS 步骤、raw/render 物理对象转换、兼容 batch 的规范化实现
   和 source regression；连续统计使用 `PROC MEANS` 默认 percentile，分类计数使用
   `PROC FREQ`。
2. `cell_format`、公共 long-form 结果的 SAS 列类型，以及运行期 missing/NE/warning
   边界测试。
3. emitter 具体实现的依赖锁定；不改变已确认的 strict single-document import
   profile 和 P0-1 的 parser/toolchain 选择。

source_data 的非空字符串边界、宏变量原样保留、关键操作注释和不输出 provenance
的策略已在 P0-3 确认。Session-owned workspace、draft guard 和 revision 已在第 3
组及第 9 组确认；具体 Shiny 控件布局属于实施阶段，不再列为开放设计问题。
