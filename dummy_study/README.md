# Dummy study

一个自包含的示例研究，用于回归验证本项目的 shell → metadata → SAS 源码 → 统计量
整条链路。规划见 `plans/dummy-study.md`。

## 当前状态

| 阶段 | 内容 | 状态 |
| --- | --- | --- |
| P1 | 目录、数据、变量字典 | 完成 |
| P2 | 6 个 MD shell | 完成 |
| P3 | metadata bundle（schema_version 2） | 完成 |
| P4 | 生成并运行 SAS | 完成 |
| P5 | R 独立计算比对 | 完成 |
| P6 | 分页版式（`page_rows`、`Page x of Y`、页边空白行） | 完成 |

## 分页

分页是 **header 级**版式属性，不是表格或行的属性：一页能放多少行取决于纸张方向、
列宽、字号与单元格内边距，因此由 `metadata/headers.yaml` 的 `page_rows` 显式配置。

| 值 | 含义 |
| --- | --- |
| 正整数（默认 22） | 每页正文最多 22 个打印行，其中 20 行放数据、2 行是页首/页尾的强制空白行 |
| `0` | 不分页（整表连续输出），用于不需要版式的调用方 |

分页由 SAS 侧完成：按「块」（一个 chunk 或一个层级节点的连续行）累加高度，只有当下一个块
会超出容量时才开新页，因此块不会被从中间切开——唯一例外是**单块本身就高于一整页**（某
个 SOC 下挂了 30+ 个 PT），此时它填满当前页并在下一页继续。每页首尾各有一行空白行；续页
顶部若已经是块分隔空白行，则不再叠加第二行。页码由 `footnote1 j=r` 输出，右对齐、罗马体、10pt（与正文单元格一致）。

## 目录

```text
dummy_study/
  data/           3 个 ADaM 数据集（提交进仓库，见下）
  variables/      变量字典（脚本生成）+ descriptors.csv（SAS PROC CONTENTS 导出）
  shell/          一张表一个 MD shell（P2）
  metadata/       metadata 源码：manifest/populations/headers + tables/ + templates/（P3）
  tools/          descriptor 导出、变量字典、shell 校验、bundle 校验、SAS 运行脚本
  verify/         R 独立计算与比对（P5）
```

## 数据

| 数据集 | 观测 | 变量 | 来源 |
| --- | ---: | ---: | --- |
| `adsl.sas7bdat` | 254 | 49 | `study/sas_data/adsl.sas7bdat` |
| `adae.sas7bdat` | 1191 | 55 | `study/sas_data/adae.sas7bdat` |
| `adlbh.sas7bdat` | 24966 | 46 | `study/sas_data/adlbh.sas7bdat` |

**这是一次显式的约定例外**：`AGENTS.md` §4 要求不要把用户数据集复制进仓库。
这里只复制了本 dummy study 用到的 3 个集（共约 10.8 MB），来源是公开的 CDISC
pilot 研究数据（CDISCPILOT01），其余 9 个集仍只留在本地 `study/sas_data/`
（该目录被 `.gitignore` 的 `/study/` 规则忽略）。理由：没有数据就无法运行真实 SAS
验证，而这个示例的全部价值在于可重复执行。

提交的是 SAS 9.4 的 `sas7bdat` 二进制格式。生成的 `.sas` 源码不会进仓库——全局
`*.sas` 规则会把它们忽略，只有手写内容（shell、bundle、脚本）被跟踪。

## 变量字典

`variables/` 下的 `adsl.md`、`adae.md`、`adlbh.md` 由
`tools/build_variable_dictionary.py` 生成，逐变量给出：类型、长度、SAS 标签、
格式、非缺失数、不同值数，以及具体取值（不超过 12 个值时全列，否则给范围）。

标签与格式来自 `variables/descriptors.csv`，它由 `tools/export_descriptors.sas`
用 `PROC CONTENTS` 导出；取值分布由脚本直接读数据计算。把描述符作为已提交文件保留，
是为了在没有 SAS 的机器上也能重建字典。

重建字典（不需要 SAS）：

```powershell
python dummy_study/tools/build_variable_dictionary.py
```

数据刷新后重新导出描述符（需要 SAS）：

```powershell
& 'E:\sas\SASFoundation\9.4\sas.exe' -sysnowindow -sysin dummy_study/tools/export_descriptors.sas `
  -log dummy_study/tools/export_descriptors.log -print dummy_study/tools/export_descriptors.lst -nosplash
```

脚本会在描述符行数与数据列数不一致时直接失败，避免字典与数据脱节。

### 已修正的两个陷阱

1. SAS 的空白字符值经 `astype(str)` 会变成字面量 `nan`，被当成一个真实取值统计。
   脚本先记录缺失掩码再转换，末尾的说明行也据此生成。
2. 带 `DATE` 格式的变量会被 pandas 解码成 `datetime64`，再经 `pd.to_numeric` 变成
   纳秒整数。脚本按 dtype 分支直接渲染 ISO 日期；`TRTSDT` 的结果
   `2012-07-09 – 2014-09-02` 与 SAS `DATE9.` 的 `09JUL2012 – 02SEP2014` 一致。

这两条由 `test/testthat/test-dummy-study-dictionary.R` 守护，回退会立即失败。

## Shell 与 metadata

`shell/` 是给人读的规格：一张表一个 MD 文件，固定 6 节（Identity / Columns / Rows /
Variable dictionary / Chunk plan / Open points），写明每行每 section 用哪个变量、
取哪些值、预期计数是多少。

`metadata/` 是给程序读的同一份规格：`manifest.yaml` + `populations.yaml` +
`headers.yaml` + `tables/` + `templates/`。它由 `tools/check_metadata.R` 校验，
用生产 codec 解析、生产模型验证，再把 6 张表各生成两次比对确定性。

```powershell
# 只校验，不写文件
Rscript dummy_study/tools/check_metadata.R

# 校验并写出 generated/metadata.zip 与 6 个 .sas
Rscript dummy_study/tools/check_metadata.R --write
```

`shell/` 与 `metadata/` 的一致性有两条守卫：`tools/check_shells.py` 核对 shell 里
引用的变量是否都在数据里、`char(N)` 是否与 SAS 长度一致；
`test/testthat/test-dummy-study-metadata.R` 保证 bundle 在常规 R 套件里始终可加载。

### 三条来自实际建模的注意事项

1. **population 表达式在 header source 上求值**。若 `header.source_data` 指向
   `WORK.*` 派生表，该表必须带上 population 表达式用到的全部变量（例如 `SAFFL`），
   否则 SAS 编译期直接报「变量没有找到」。
2. **每个 level 要么给 `format`，要么同时给 `order_variable` + `order_direction`**。
   AE 的 SOC/PT 层显示顺序由 `result_sort` 决定，但模型仍要求声明排序变量。
3. **`cell_format` 的占位符必须与该行 `statistics` 的 id 集合完全相同**，
   所以连续型表按「一行一个统计量行」组织（n / Mean (SD) / Median / Q1, Q3 / Min, Max）。

### 在真实 SAS 中运行

```powershell
# 全部 6 张表
Rscript dummy_study/tools/run_sas.R

# 只跑一张
Rscript dummy_study/tools/run_sas.R --table t_14_1_1_disposition
```

每个程序会被包进一个包装程序：绑定 `study` 库 → `%include` 生成程序（不改一行）→
把 `_TFL_WIDE_001` / `_TFL_ASM_001` 落盘到 `generated/sasout/` → 用 `%put` 把行数
写进日志。日志分类器只放行两类已知告警（站点 SASHELP 缺失、AE 源 `duplicate_key`
诊断），**未分类告警直接判失败**，避免用总数掩盖真问题。

P4 首轮 6/6 通过（exit=0、0 ERROR），但也暴露了 4 个静态检查抓不到的运行期缺陷，
详见 `docs/dummy-study-findings.md` §6。其中最容易被忽略的一条是：**level 一旦声明
`format`，emitter 就会忽略 `order_variable`**，所以「用 format 排顺序」是错的，
排序必须交给 `order_variable`。

### 独立验证（不依赖 SAS 生成的数字）

```powershell
Rscript dummy_study/verify/compute_expected.R   # 从原始数据重算每一格
Rscript dummy_study/verify/compare_with_sas.R   # 与 SAS 产物逐格比对
```

第一条用 `haven` 读 `data/`，按第一性原理重算（不复用 metadata、emitter 或生成的
SAS），长表写出 `generated/expected/expected.csv`。第二条把 SAS 报表明细解析成
`(路径, 列, 统计量)` 后 join。

当前结果：**5520 个断言单元格全部一致**。分位数（`median`/`q1`/`q3`）只记录不判定，
因为 `PROC MEANS` 默认 `PCTLDEF=5` 与 R 的分位数算法不同；它们在
`generated/comparison.csv` 的 `reported_only` 列里可见。
