# 未决问题

本文只记录尚未获得用户批准的设计问题。这里的建议不是已批准的契约；
在确认后，应把结果分别写入设计决策或拒绝方案记录。

## 第 2 组：解析后的 metadata 对象

以下项目已根据 ref 形成对齐建议，但尚未在本项目中单独冻结：

1. 内存对象采用带 S3 类标记的普通 R list、R6 对象，还是无类型 raw list；建议
   采用普通 R list 加类型标记，保持值语义。
2. schema version 1 是否采用 strict unknown fields；ref 建议拒绝未声明字段，
   新能力通过 schema version 或 registry 扩展。
3. 缺失或重复 ID、discriminator-specific 必填字段和引用字段的导入边界；建议
   结构无法表示时导入失败，未解析的跨对象引用延迟到生成前置阶段。
4. hierarchical chunk 是否省略顶层 `rows`；ref 建议只在 analysis block 中保存
   rows。
5. 可选字段是保持缺省还是物化默认值；建议保持缺省，只有已经定义语义的字段在
   生成时解释默认值。
6. header columns 的顺序；ref 以 `display_order` 为权威并在 canonical YAML 中
   规范化 sequence，本项目需确认是否采用该规则。
7. 未注册 chunk type 是否在导入时拒绝；ref 建议由 ChunkRegistry 严格拒绝，且
   不允许 YAML 注入函数。
8. hierarchical `result_sort` 是否采用 ref 的结构化字段：`metric`、整数
   `column_order` 和 `direction`，其中 `0` 表示末尾 label。
9. denominator、row、level、analysis block 的 discriminator-specific 字段是否
   在导入时做结构检查；建议做结构检查，不做数据或 SAS 语义检查。
10. YAML canonical profile 的数值序列化细节，以及实施阶段使用的 R YAML 包和版本。

以下内容已由用户在本轮明确要求沿用，不再作为未决项：continuous `digits` 的
绝对/`+n`/`-n` 相对精度、ref 的 `base_digits` 解析边界和负 resolved digits 失败。

## 本项目独立的后续确认

1. 外部 SAS dataset reference 的精确写法和调用方绑定 convention。
2. population expression 的 source scope、SAS expression dialect 和缺失值语义。
3. 四类 chunk 的 SAS emitter、PROC/步骤选择、中间和最终逻辑输出 schema。
4. `cell_format` 的 SAS 代码生成方式，以及 percentile、rounding、missing/NE 的
   最终实现细节。
5. `custom_code.before`/`after` 的 SAS 插入点、共享作用域和允许改变的对象。
6. 传输/解析错误与生成前置引用错误的最小稳定错误包络。
