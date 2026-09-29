# SAS 源码生成与编辑流程收尾

日期：2026-09-29。范围为已批准的 Report/QC 生成、Header orientation、hierarchical
统计/行组装修复、源码可读性维护，以及关联的编辑器回归修复。应用继续只生成 SAS
source text，不读取分析数据、不执行 SAS。

## 验证层次与覆盖

| 层次 | 当前证据及边界 |
| --- | --- |
| 用户验收 | 用户在本次会话明确表示已阅读生成代码并符合预期，随后报告已进行了端到端测试。未提供逐项操作日志，因此不替用户补写测试步骤、数据集或 SAS 运行结果。 |
| R core/application | YAML/ZIP 往返、draft、对象引用、Report/QC 生成、共享块边界和行组装 source regression。收尾补充保存修改 → 导出 ZIP → 新 workspace 导入 → 普通/层级 table 的 Report/QC 源码一致性测试。 |
| Shiny/Chrome | 运行仓库现有 shinytest2 测试，覆盖初始上传页、导入失败、无修改导航、dirty guard、编辑保存/放弃、Header orientation、source preview、Report/QC 和下载按钮状态。 |
| 下载适配器 | 单独核对文件名与写出源码内容；不将它说成浏览器真实下载响应的端到端字节比对。 |
| SAS runtime | 此前的 synthetic SAS 数值、schema、异常与行组装对照保留为历史证据。删除 CARDIMAGE 管理后的最终源码未重新执行 SAS；本次 R/browser 测试不弥补这一边界。 |

完整测试入口为 `Rscript test/run_tests.R`，不是只执行 emitter 的局部 filter。
最终完整执行退出码为 0：17 个测试文件、100 个测试、1,060 项通过断言；失败、
错误、跳过和测试 warning 均为 0。其中包含 16 个 Shiny/Chrome 测试，没有跳过
浏览器测试。运行环境为 R 4.4.0、testthat 3.3.2、Shiny 1.8.1.1、shinytest2 0.5.1、
Chromote 0.5.1。R 启动时仍有 locale 及 package build-version 提示，和测试框架的
warning 计数分别记录。日志及结果摘要保存在忽略目录 tmp，不提交运行产物。

## 文档核对

- README 使用已实现的应用说明；不再将当前测试说成依赖截图快照。
- 中英文用户指南统一为显式 character informat，而非并未实现的“显式设置记录
  长度”；说明生成器沿用调用方 CARDIMAGE 设置。
- 便携契约补齐现有 Header.orientation 必填字段、YAML 示例和编辑器说明，与
  已实现的模型及用户指南对齐；没有改变 metadata 行为。
- 保留 INPUT 按字段分行、Header/计数等有边界短规则一行的排版原则。
- P0-13 只共享 value/digits DATA step，所有原 block 表名和逐块 join/render 保留。
- `hierarchical-runtime-verification.md` 按历史阶段记录行数及 SAS 结果，本文件作为
  当前自动化验证的入口，不将历史运行结果误写为最终源码重新验证通过。
- shinytest2 的局部运行命令改用 `test_dir`，确保公共 helper 和 project_root 加载。

## 提交范围

当前 Report/QC、metadata orientation、emitter 与 UI 变更互相依赖，因此以一个
完整可运行状态提交相关 production、设计/用户文档、自动化测试和纯合成 fixtures。
现有 tracked demo ZIP 是 UI 测试所需的合成 metadata fixture，只有 YAML 条目，
不含分析数据。

不纳入本次提交：本地 `study/` 数据与运行输出、`ref/` 参考稿、根目录旧 UI 设计
草稿、SAS 生成文件、日志、临时快照，以及原已存在的两张旧截图删除。它们保持原
工作区状态；不会为追求 clean status 而删除或提交不相关内容。没有推送远端。
