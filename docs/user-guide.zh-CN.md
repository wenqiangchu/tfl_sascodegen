# SAS Code Generator 用户指南

## 应用简介

本应用用于导入 YAML metadata ZIP bundle、编辑描述性分析 metadata，并生成 SAS
source text。应用只生成代码，不读取、验证或执行 SAS 分析数据集。

## 启动应用

在 Windows 上双击 `start_app.bat`。脚本会自动选择可用的本地端口并尝试在 Chrome
中打开应用。也可以在项目目录中运行 `shiny::runApp('.')`。

首次打开时需要点击 `Upload metadata` 并选择 metadata ZIP。也可以先下载
`Download demo package`，使用其中的示例 bundle 进行体验。

## ZIP 文件结构

bundle 是一个 ZIP 文件，包含：

```text
manifest.yaml
populations.yaml
headers.yaml
tables/<table-id>.yaml
templates/<template-id>.yaml
```

每个 table 和 template 都是独立的 YAML 文件，便于在不同研究之间复制和复用。
`manifest.yaml` 当前用于声明 schema version。

## Metadata 编辑

- 左侧列表显示当前类型的 metadata 对象；点击对象后，右侧显示详细内容。
- 点击 `New` 后输入对象 ID，再编辑新建的草稿。
- 点击对应的 `Save` 按钮提交修改。
- `Discard changes` 恢复到最近一次保存的版本；如果对象尚未保存，则直接移除该新对象。
- 在存在未保存修改时切换对象或 dashboard，会出现 `Discard changes` 和 `Cancel`。
- 删除已有对象时，系统会根据需要进行确认和引用检查。

## Population 和 Header

Population 的表达式使用 SAS 语法保存。Header 的 columns 和 spanning headers 在同一个
DT 中编辑。DT 中显示 spanning label，保存时根据连续 label 区间生成 canonical span ID
并写回 YAML。

## Table 和 Template

Table 用于关联 population、header 和 template，并保存 custom code。Template 由多个独立
chunk card 组成。

Rows 和 statistics 使用同一个 DT：DT 中一行对应 RTF 中的一行；statistics 和 digits
使用空格分隔，例如：

```text
statistics: n mean sd
digits:     0 1 1
```

Hierarchical chunk 还包含多层 levels 和 analysis blocks，可以编辑 parent level、分析
类型和结构化 denominator。

## 生成 SAS

进入 `Generate SAS`，选择 table 后点击 `Generate SAS`。生成的 SAS source 可以在页面中
预览，也可以下载为 `.sas` 文件。

应用会原样保留 `source_data`、filter、condition、denominator expression 和 custom code。
这些内容不会在 R 或 Shiny 中执行，实际语法和数据集是否存在由调用方负责。

`Download metadata` 下载最近一次保存的 metadata，不会隐式保存当前未保存修改。
`Download demo package` 与当前 workspace 无关。

## 测试

在项目根目录运行：

```text
Rscript test/run_tests.R
```

测试覆盖 YAML/ZIP round-trip、source generation、workspace draft 行为以及 shinytest2
交互流程。
