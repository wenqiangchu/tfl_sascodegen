# Dummy Study 实施发现（P1–P3）

本文记录 `dummy_study/` 在 P1（数据与变量字典）、P2（shell）、P3（metadata bundle）
三个阶段中**通过实测发现的事实与缺陷**。规划与阶段状态见 `plans/dummy-study.md`；
本文只记「原本的假设错了什么、证据是什么、怎么处置的」，便于单独复查。

阅读顺序建议：先看 §1 汇总表，再看 §2 需要你确认的三项，最后按需查 §3–§5 明细。

---

## 1. 汇总表

| # | 阶段 | 类型 | 发现 | 处置 |
| ---: | --- | --- | --- | --- |
| 1 | P1 | 数据事实 | `DCSREAS` 有 **9** 个真实取值 + 空白，不是规划里写的 10 个 | 修正规划数字 |
| 2 | P1 | 工具缺陷 | SAS 空白字符值经 `astype(str)` 变成字面量 `nan`，被当成真实取值 | 先存缺失掩码再转换 |
| 3 | P1 | 工具缺陷 | 带 `DATE` 格式的列被 pandas 解码成 `datetime64`，输出成纳秒 | 按 dtype 分支渲染 ISO 日期 |
| 4 | P2 | 设计错误 | `ANL01FL='Y'` 会**排除 Baseline**（只标在 306 条基线后记录上） | 过滤条件改为只用 `PARAMCD='HGB'` |
| 5 | P2 | 设计错误 | 分级 shift 无法用 `BNRIND`/`ANRIND`：HGB 基线 247 条全是 `'N'` | 改用 `LBNRIND`（235/9/3） |
| 6 | P2 | 数据事实 | `ADLBH` 没有 `ANRLO`/`ANRHI`，无法自行推导分级 | 同上，只能依赖 `LBNRIND` |
| 7 | P2 | 数据事实 | 5 例有基线分级但无基线后分级；其中 1 例基线为 HIGH | 规则定为「沿用基线分级」 |
| 8 | P2 | 数据事实 | TEAE 子集的 PT 是 **230** 个，不是 242（242 是全部 `AEDECOD`） | 两处数量分别标注 |
| 9 | P2 | 设计错误 | `result_sort` 的字母序兜底在 **SOC 层从不触发**（23 节点无并列） | P5 改为检查 SOC 内部的 PT 顺序 |
| 10 | P2 | 数据事实 | PT 层 230 行中 **130 行**三键并列 | 同上，这是字母序的主战场 |
| 11 | P2 | 设计错误 | 静态行「At Least One TEAE」原计划用 `placement: above` | 改为独立的普通 chunk |
| 12 | P2 | 边界 | `LBNRIND` 另有 `ABNORMAL`（其他参数 427 条），HGB 无此取值 | shell 中显式记录为已知边界 |
| 13 | P2 | 自查发现 | 7 处 `char(N)` 长度是我凭印象写的，与 SAS 不符 | `check_shells.py` 抓出并全部修正 |
| 14 | P2 | 自查发现 | `AESEV` 分级计数我写成 923/219/49，实测 **770/378/43** | 修正 |
| 15 | P2 | 既有缺陷 | `test-shinytest2.R` 偶发失败（DT 未渲染就断言），5 次中 2 次失败 | 加 DOM 等待辅助，6/6 通过 |
| 16 | P3 | 模型约束 | level 必须给 `format`，**或** `order_variable` + `order_direction` | AE 层补 `order_variable` |
| 17 | P3 | 模型约束 | `node_role: analysis` 强制 `node_analysis_id`，且必须指向同层 `same_row` block；`label` 禁止该字段 | 按约束建模 |
| 18 | P3 | 模型约束 | `cell_format` 占位符必须**精确等于**该行 `statistics` 的 id 集合 | 连续表改成一行一个统计量行 |
| 19 | P3 | 模型约束 | 连续型行不允许 `condition`；分类行必须有 `condition` | 按约束建模 |
| 20 | P3 | **运行时陷阱** | population 表达式在 **header source** 上求值；`WORK.*` 作 header source 时缺少 `SAFFL` 会导致 SAS **编译期 ERROR** | 派生表一并物化 `SAFFL` |
| 21 | P3 | 结构验证 | `result_sort` 生成 `metric_1..3` + `label_sort` + `descending`，与 `[4,3,1,0]` 完全对应 | 静态通过，运行期待 P4 |
| 22 | P3 | 结构验证 | `format` 通过 `preloadfmt order=data` 实现「零计数也出行」 | 静态通过，运行期待 P4 |
| 23 | P3 | **能力边界** | shift 表的**逐列基线分母**（如 Placebo 的 82）在模型中不可表达 | 见 §2.1 |

---

## 2. 需要确认的三项

### 2.1 shift 表的百分比分母 —— 已确认可实现，无需决策

**P3 时我判断「逐列基线分母（如 Placebo 的 82）在模型里不可表达」，这个判断是错的。**
P4 用真实 SAS 跑出来，逐列分母是工作的：

| section | 行 | 基线 Normal 列 | 基线 Low 列 | 基线 High 列 | Overall 列 |
| --- | --- | --- | --- | --- | --- |
| Placebo | Normal | 69 (84.1%) | 0 (0.0%) | 0 (NE%) | 69 (81.2%) |
| Placebo | Low | 11 (13.4%) | 3 (100.0%) | 0 (NE%) | 14 (16.5%) |
| Placebo | High | 2 (2.4%) | 0 (0.0%) | 0 (NE%) | 2 (2.4%) |

- `69 (84.1%)` = 69/82，分母是该 section 内**基线为 Normal** 的受试者数，不是整组的 85；
- `3 (100.0%)` = 3/3，Low 列在 Placebo 组只有 3 人；
- `0 (NE%)` 表示分母为 0（Placebo 组没有基线 High 的受试者）——按约定「分母为 0 时保留
  实际 n，`pct` 不可估计」。这一格恰好验证了该边界。
- `Overall` 列是 69/85、14/85、2/85，三个百分比加起来 100%，行和等于该组基线人数。

结论：**shell 原本的设计（列头 N 用全人群 235/9/3/247，组内百分比用逐列基线人数）
可以原样实现**，不需要在 (a)/(b)/(c) 之间做选择。P3 的「能力边界」结论作废。

### 2.2 连续型表的行组织方式

`cell_format` 的占位符必须与该行 `statistics` 的 id 集合**完全相同**，所以无法
「一行内放 8 个统计量」。当前做法是每张连续表 5 行：

```
n
Mean (SD)
Median
Q1, Q3
Min, Max
```

这是标准 TFL 版式，但与 shell §3 里「统计量：n, mean, sd, median, q1, q3, min, max」
的一行清单读起来不同。**如果这不是你要的行结构，需要在 P4 之前改。**

### 2.3 完整节点探针从 `Week 28` 移到 `LIFE THREATENING`（**需要你复核**）

你先前确认「`Week 28` 探针保留」。P4 发现它**与访视排序不可兼得**，因此我把它迁走了。

原因（详见 §6.2）：level 一旦声明 `format`，emitter 就走 format 目录路径并忽略
`order_variable`。访视表因此只能二选一：

| 配置 | 顺序 | 完整节点 |
| --- | --- | --- |
| `format: $TFLVISIT`（含 Week 28） | 字母序（`Week 12` 排在 `Week 2` 前）✗ | ✓ |
| `order_variable: AVISITN` | 协议顺序 ✓ | 无探针 |

TFL 表的访视必须按临床顺序，所以选了后者，并把探针迁到严重度的封闭取值域：
`TFLSEV` 增加 `4 = 'LIFE THREATENING'`（数据里没有这个取值）。P4 实测该行输出
`0 (0.0%)` 且没有被整行删除，完整性验证的强度与原设计相同。

**需要你确认**：接受这次迁移，还是希望保留 `Week 28` 而让访视按字母序输出。

### 2.4 `format` 会静默忽略 `order_variable`（已决策：模型层拒绝）

> **2026-11-07 更新：已决定并实施。** 见本节末尾「最终决策」。


`src/emitters/hierarchical.R:285`：

```r
if (!is.null(level$format)) return(hierarchical_formatted_level_source(plan, level_order))
```

`parse_level_value` 允许同时声明 `format` 与 `order_variable`（不报错），但 emitter 在
format 分支提前返回，`order_variable`/`order_direction` 被**静默丢弃**——生成的 SAS 里
连变量名都不出现。这比「拒绝该组合」更危险：用户写了排序规则，得到的却是另一种顺序，
且没有任何提示。

这是产品行为，不只影响 dummy study。可能的处置：

| 选项 | 说明 |
| --- | --- |
| (a) 模型层拒绝该组合 | 同时声明时报错，最直白；会破坏已有的 fixtures（若有） |
| (b) emitter 支持 format + order | 用 format 提供节点集合、用 order_variable 提供顺序；工作量最大但语义最好 |
| (c) 保持不变，只在文档写清 | 记录为「format 优先级最高」的已知语义 |

我没有替你做这个决定。

#### 最终决策（2026-11-07）

**选择 (a) 的收窄版：模型层拒绝 `format` + `label_variable` / `order_variable` /
`order_direction`。**

理由：

1. `format` 同时提供**节点值域、显示标签、节点顺序**三件事，而这三人字段各自只是其中
   一项的另一种写法，且只能表达数据中已存在的值，无法表达 format 新增的值。
2. 值域一旦扩大，`order_variable` 的取值空间就与节点不再一一对应，排序变量对新节点
   **无值可比** —— 所以"忽略它"不是缺陷，是逻辑必然。
3. `label_variable` 也不该保留：format 路径下它既不影响标签也不影响节点身份
   （`node_label` 与 `level_value` 都来自 `vvalue(variable)`），写了完全无效。
4. 先前的"允许保留但忽略"会静默丢弃用户写入，无告警、无结果差异提示。

**未采纳 (b) 支持组合**：实测发现 `format` 驱动时节点顺序来自 `order=data`，而
`NOTSORTED` 才是"按声明序"的必要条件（不带时是原始值序）。也就是说"用 format 定序"
本身已足够表达顺序诉求，再开 `order_variable` 后门会破坏 `format` 的清晰语义。
我没有替你做这个决定。

## 3. P1 明细：数据与变量字典

### 3.1 数据规模

| 数据集 | 观测 | 变量 | 大小 |
| --- | ---: | ---: | ---: |
| `adsl` | 254 | 49 | 1.3 MB |
| `adae` | 1191 | 55 | 1.7 MB |
| `adlbh` | 24966 | 46 | 7.9 MB |

三个集合计约 10.9 MB，是本仓库唯一的二进制数据例外（理由见 `dummy_study/README.md`）。

### 3.2 空白值变成 `nan`（发现 #2）

SAS 的空白字符值在 pandas 里是 `NaN`；直接 `astype(str)` 会变成**字符串 `"nan"`**，
于是被当成一个真实取值统计。后果：`DCSREAS` 显示 10 个取值（多一个 `nan`）、
`BNRIND` 显示 3 个（多一个 `nan`）。

处置：先记录 `isna()` 掩码，转字符串后再用掩码还原缺失。字典末尾的「另有 N 条空白」
说明也由掩码生成。

### 3.3 日期列变成纳秒（发现 #3）

带 `DATE` 格式的变量被 pandas 解码为 `datetime64[ns]`，再经 `pd.to_numeric`
变成纳秒整数（如 `1341792000000000000`）。处置：按 dtype 分支渲染 ISO 日期。

交叉验证：`TRTSDT` 渲染为 `2012-07-09 – 2014-09-02`，与 SAS `DATE9.` 的
`09JUL2012 – 02SEP2014` 一致。

### 3.4 描述符来源

环境没有 `pyreadstat`，无法直接读 SAS 标签与格式。改为用
`tools/export_descriptors.sas`（`PROC CONTENTS`）导出 `variables/descriptors.csv`
（150 行 = 49 + 55 + 46），把结果作为**已提交文件**保留，这样没有 SAS 的机器也能重建字典。

---

## 4. P2 明细：shell

### 4.1 `ANL01FL='Y'` 会排除 Baseline（发现 #4）

规划 §4.3 原本写 `filter: PARAMCD = 'HGB' and ANL01FL = 'Y'`。实测：`ANL01FL`
只标在 306 条**基线后**记录上，Baseline 行是空白的。加上这个过滤会让 Baseline
节点整行消失，且只剩 9 次访视。已改为只过滤 `PARAMCD='HGB'`。

### 4.2 shift 的分级来源（发现 #5、#6）

| 变量 | HGB 基线分布 | 能否用于 shift |
| --- | --- | --- |
| `BNRIND` / `ANRIND` | 247 条**全部**是 `'N'` | 否，三列退化成一列 |
| `LBNRIND` | 235 `NORMAL` / 9 `LOW` / 3 `HIGH` | 是 |
| `ANRLO`/`ANRHI` | **不存在** | 无法自算 |

### 4.3 无基线后分级的受试者（发现 #7）

247 例有基线分级；5 例没有基线后分级，其中 1 例（`01-703-1279`，Low Dose）基线为
HIGH。规则选「沿用基线分级」（`coalesce(W_RANK, BL_RANK)`），使每个 section 的三行
之和等于该组基线人数；若改为「归入未知」或「排除」，部分 section 会少人。

预期矩阵（行 = 基线后最差，列 = 基线）：

| Arm | 基线 N/L/H | N→ | L→ | H→ |
| --- | --- | --- | --- | --- |
| Placebo | 82/3/0 | 69/11/2 | 0/3/0 | 0/0/0 |
| High | 79/1/1 | 73/4/2 | 0/1/0 | 1/0/0 |
| Low | 74/5/2 | 69/5/0 | 0/5/0 | 1/0/1 |
| 全人群 | 235/9/3 | — | — | — |

### 4.4 字母序兜底的真实战场（发现 #9、#10）

`result_sort` 的排序键是 `metric_missing_k` 升序 → `descending metric_k` →
`label_sort` → `node_order_path`。

- **SOC 层 23 个节点三键互不相同**：字母序兜底一次都不会被触发。
- **PT 层 230 行中 130 行并列**：字母序在此大量生效。

所以「字母序验证」必须落在某个 SOC **内部**的 PT 顺序上，只看 SOC 层等于没验。

### 4.5 自查抓到的两处凭空数字（发现 #13、#14）

`tools/check_shells.py` 第一次运行就报出 7 处长度错误：

| 变量 | 我写的 | 实际 |
| --- | --- | --- |
| `EOSSTT` | char(11) | char(12) |
| `DURDSGR1` | char(3) | char(4) |
| `ABLFL` | char(1) | char(2) |
| `ANL01FL` | char(1) | char(2) |
| `LBNRIND` | char(12) | char(8) |
| `PARAM` | char(38) | char(48) |
| `ABLFL`（另一处） | char(1) | char(2) |

另有 `AESEV` 分级计数：我写 923/219/49，实测全 1191 行是
`MILD` 770 / `MODERATE` 378 / `SEVERE` 43（TEAE 子集 731/354/41）。

这两类错误的共同点：**凭印象写数字**。所以 P2 之后所有统计量都改为「先跑数据，
再写文档」，并由 `check_shells.py` 与 `test-dummy-study-*.R` 双向守护。

### 4.6 既有测试缺陷（发现 #15）

`test-shinytest2.R` 有 5 次单独运行中 2 次失败，失败行号每次不同
（70/99、26/61、89）。根因：DT 在浏览器里渲染表格体之前，`wait_for_idle()` 已经返回，
断言读到空 `<tbody>`。这不是本 dummy study 引入的，与唯一被修改的已跟踪文件
`.gitignore` 无关。

处置：新增 `wait_for_rows()` / `wait_for_text()` 两个「等 DOM 状态」的辅助函数，
用在 `select_list_row()`、`import_demo()` 与列表内容断言处。修复后连续 6 次运行全通过。

---

## 5. P3 明细：metadata bundle

### 5.1 四条模型约束（发现 #16–#19）

```yaml
# 1) 每个 level 要么给 format，要么给 order_variable + order_direction
- id: 'visit'
  variable: 'AVISIT'
  format: '$TFLVISIT'          # 这条分支不需要 order_variable

- id: 'soc'
  variable: 'AEBODSYS'
  order_variable: 'AEBODSYS'   # 显示顺序其实由 result_sort 决定，
  order_direction: 'asc'       # 但模型仍强制要求这两个字段

# 2) node_role: analysis 必须带 node_analysis_id，且指向同层 same_row block
- id: 'soc'
  node_role: 'analysis'
  node_analysis_id: 'soc_subjects'   # label 角色给这个字段会报错

# 3) cell_format 占位符集合 == 该行 statistics 的 id 集合
statistics: [n, mean, sd]  →  cell_format: '{n} {mean} ({sd})'

# 4) 连续型行禁止 condition；分类行必须有 condition
```

### 5.2 population 在 header source 上求值（发现 #20）

这是 P3 最有价值的一条，且是**运行期**错误，静态校验抓不到。

`shift_header` 的 `source_data` 是 `WORK.SHIFT_HGB`（用派生表做 header 源，正是
`plans/dummy-study.md` §8 要验证的假设 ③）。生成的代码是：

```sas
/* Select the table population. */
data _TFL_POP_001 _TFL_HSUBJ_001(keep=USUBJID);
  set WORK.SHIFT_HGB;
  output _TFL_HSUBJ_001;
  if not (SAFFL = 'Y') then delete;
  output _TFL_POP_001;
run;
```

`WORK.SHIFT_HGB` 最初只有 `USUBJID / TRTA / LBNRIND_BL / ANRIND_WORST`，
没有 `SAFFL` → SAS 会在**编译期**报「变量 SAFFL 没有找到」。

处置：在 `custom_code.before` 里把 `SAFFL` 一并物化。**一般规则**：任何用 `WORK.*`
作 header source 的表，派生表必须带上 population 表达式引用到的全部变量。

### 5.3 `result_sort` 与 `format` 的静态验证（发现 #21、#22）

`t_14_3_1_2_teae` 生成：

```sas
create table _TFL_HORDER_002_001 as
select n.*, … metric_1, metric_missing_1, metric_2, metric_missing_2,
        metric_3, metric_missing_3, upcase(n.node_label) as label_sort, …

proc sort data=_TFL_HORDER_002_001;
  by parent_node_key metric_missing_1 descending metric_1
     metric_missing_2 descending metric_2
     metric_missing_3 descending metric_3 label_sort node_order_path;
```

`column_order: [4, 3, 1, 0]` 正好产出 3 个 metric + `label_sort`，与设计一致。

`t_14_3_2_1_hgb_by_visit` 生成 `put(AVISIT, $TFLVISIT.)` 与
`format AVISIT $TFLVISIT.;`；`t_14_3_1_4_teae_severity` 生成
`class parent_node_key SEV_RANK / preloadfmt order=data missing;` ——
`preloadfmt` 正是「零计数也出行」的 SAS 机制，`order=data` 取 format 声明顺序
（SEVERE → MODERATE → MILD）。

**两条都只是静态通过**，SAS 真实行为待 P4。

---

## 6. P4 明细：真实 SAS 运行

### 6.1 运行方式与结果

`dummy_study/tools/run_sas.R` 为每张表生成一个包装程序：绑定 `study` 库 → `%include`
生成程序（不改一行）→ 把 `_TFL_WIDE_001` / `_TFL_ASM_001` 落盘到
`generated/sasout/` → 用 `%put` 把行数写进日志。调用方式沿用项目已有的外部运行
harness：`-sysin <program> -log <log> -print <lst> -nosplash -noterminal`，相对文件名 +
`cwd` 为运行目录。

| 表 | exit | ERROR | 告警 | 未分类告警 | 行数 | RTF |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| `t_14_1_1_disposition` | 0 | 0 | 2 | 0 | 15 | 20 KB |
| `t_14_1_2_baseline` | 0 | 0 | 2 | 0 | 25 | 37 KB |
| `t_14_2_3_hgb_shift` | 0 | 0 | 2 | 0 | 9 | 16 KB |
| `t_14_3_1_2_teae` | 0 | 0 | 779 | 0 | 254 | 332 KB |
| `t_14_3_1_4_teae_severity` | 0 | 0 | 329 | 0 | 367 | 523 KB |
| `t_14_3_2_1_hgb_by_visit` | 0 | 0 | 2 | 0 | 67 | 77 KB |

告警分类（`run_sas.R` 内置，未分类即判定失败）：

- `environment_missing_library_entries`（每程序 2 条）：站点安装缺少 SASHELP 条目，
  与本程序无关；该告警是两条记录，第二行不含库名，靠中文续行文本识别。
- `source_duplicate_diagnostic_records_preserved`（AE 表 777 / 327 条）：AE 源天然
  「一例多条记录」，`distinct_subject` 的重复键 guard 只报告不聚合。与既有验证里的
  `audit_logs.py` 分类同名同义。
- 其余一律 `unclassified` 并让运行失败——避免用「总数」把真问题藏起来。

### 6.2 四个运行期缺陷

| # | 现象 | 根因 | 处置 |
| ---: | --- | --- | --- |
| P4-1 | 访视按字母序输出 | 声明 `format` 后 emitter 走目录路径，忽略 `order_variable`（`hierarchical.R:285`） | 访视层改用 `AVISITN`，去掉 format |
| P4-2 | 严重度输出 MILD → MODERATE → SEVERE | 数值 format 按**未格式化值升序**建节点；rank 1=MILD 时最严重的排最后 | `SEV_ORDER` 改成显示序 1=SEVERE，归约用 `min()` |
| P4-3 | 我在 P3 断言「逐列分母不可实现」 | 误判 emitter 的分母推导 | 作废，见 §2.1 |
| P4-4 | shell 14.3.1.4 的预期计数是错量 | 写的是「受试者级最大严重度」（50/42/46），实际输出是「每 PT 取最大」的节点数 | 见 §6.3 |

### 6.3 「按 PT 取最大」与「按受试者取最大」不是一回事

shell 原先写的 level-1 预期（SEVERE 3/7/4、MODERATE 12/28/26、MILD 50/42/46）是
**受试者级最大严重度**，合计 65/77/76 = TEAE 人数。但三层层级是「严重度 → SOC → PT」，
严重度是**每个 PT 内部**取最大，于是同一受试者可以出现在多个严重度下。

实测节点计数：

| 严重程度 | Placebo | Low | High | Overall |
| --- | ---: | ---: | ---: | ---: |
| SEVERE | 5 | 16 | 8 | 29 |
| MODERATE | 25 | 49 | 51 | 125 |
| MILD | 58 | 55 | 64 | 177 |
| LIFE THREATENING | 0 | 0 | 0 | 0 |

四行之和 331 > Safety 人群 254 —— 这不是错误，而是「按 PT 取最大」的必然结果。
两个数各自自洽：331 是节点人次，254 是人群。已把 shell 的预期表改成实测值并加了说明。

### 6.4 与独立计算的一致性

| 表 | SAS 行数 | 独立计算（pandas） |
| --- | ---: | --- |
| TEAE | 254 | 1 + 23 SOC + 230 PT = 254 |
| severity | 367 | 1 + 253 PT = 254 |
| severity（加探针） | 367 | 3 + 53 (sev,soc) + 310 (sev,soc,pt) + 1 探针 = 367 |
| HGB by visit | 67 | 1 + 11 × 6 = 67 |
| disposition | 15 | 4 + 2 + 9 = 15 |
| shift | 9 | 3 section × 3 行 |

SOC 顺序也已核对：GENERAL 108 → SKIN 99 → NERVOUS 53 → GI 51 → CARDIAC 40 →
INFECTIONS 38，与 `result_sort` 的三键降序 + 字母序兜底一致。

正式的逐格比对属于 P5（R 独立实现 + 只断言 n/mean/sd/min/max 与 n/pct，
分位数只报告不判定）。

## 6.5 P5 复核发现的 section 标题行缺陷

用户复核 14.1.2 时指出：每个 section 只有统计量行，没有 section 标题行。
核查后确认属实，且同类问题出现在 6 张表中的 2 张。

**缺陷**：14.1.2 的 7 个 chunk、14.2.3 的 3 个 chunk 都直接以统计量行开头，
没有首行标题。14.2.3 尤其严重——三组 `Normal / Low / High` 连续打印而臂名只存在于
chunk 结构里，报表读者无法判断某一行属于哪个治疗组。

**根因**：metadata 的 `label` 行类型一直可用（`categorical.R:70` 对非 `analysis`
行跳过计数，行列骨架照常输出），但初版 bundle 只写 `analysis` 行，而 shell 里其实
已经声明了这些标题行：

- 14.1.2 §3 行 1–3（`Age (years)` / `Body mass index` / `Duration of disease`）
  与行 4、8、11、15（`Age group, n (%)` 等）；
- 14.2.3 §3 明确写了「每个治疗组一个 section」。

**修复**：给 7 + 3 个 chunk 各加一条 leading `type: 'label'` 行。实测确认
`label` 行渲染为 `row_role = 'label'`、各列空白。行数随之 15 → 32（14.1.2）、
9 → 12（14.2.3），6 个程序仍全部 `exit=0 / errors=0`。

**其余 4 张表核验通过**，它们本来就带 section 头，只是机制不同：

| 表 | section 头机制 |
| --- | --- |
| 14.1.1 | 无 section 行；各行自带语义（`Randomized` / `Completed` …），原因行已缩进 1 |
| 14.3.2.1 | `dynamic` 层级节点 `Hemoglobin (mmol/L)` + 各 visit |
| 14.3.1.2 | 静态行 `At Least One TEAE` + `dynamic` SOC 节点 |
| 14.3.1.4 | `dynamic` 三级节点（严重程度 → SOC → PT） |

**为何此前没有测试抓到**：`check_shells.py` 只校验 `DOMAIN.VARIABLE` 存在性、
`char(N)` 长度、`nan` 字面量与 6 段结构；P5 的 5520 个断言只覆盖有数值的单元格。
**section 标题行没有数字，任何数值比对都不会发现它消失。**

**新增双侧 guard**：

1. `check_shells.py` 第 5 项检查——shell §3 声明的 `label` 行数必须等于模板
   `type: 'label'` 行数；
2. `test-dummy-study-shells.R` 同一条不变量的 R 版本，纳入常规套件。

两者都用「删掉一条标题行」验证过会失败（`7 → 6`、`3 → 2`）。

**代价**：`label` 行不带 `condition`、不参与计数，因此不影响既有 5520 个断言；
P5 比对回归后仍为 5520 全一致。

## 6.6 缩进层级修正（14.1.2 / 14.2.3）

用户复核 14.1.2 时进一步指出统计量部分的缩进仍不对。核实后确认：补了 section 标题行
之后，**32 行全部是 `indent_level = 0`**，标题行与它管辖的统计量行左对齐，
视觉上仍是一个平铺列表，读不出「标题—归属行」关系。14.2.3 同样问题（12 行全 0）。

**机制**：缩进由 `src/generator/report_source.R:208` 的
`compute label` → `style=[pretext="^R/RTF'\li<n>"]` 实现，`n = indent_level * 200` twips。
模型早已支持 `indent_level`（`model.R:494-502`，`min_value = 0`），14.1.1 的
DCSREAS 明细行就用 1 级缩进。

**修复**：14.1.2 的 25 个 `analysis` 行、14.2.3 的 9 个 `analysis` 行全部补
`indent_level: 1`；`label` 行保持 0。RTF 实测出现且仅出现 `\li0` 与 `\li200` 两种取值，
确认缩进落到了渲染层。

**新增 guard**：`test-dummy-study-shells.R` 增加一条不变量——模板里 `type: 'label'`
行不得带 `indent_level: 1`，而 `type: 'analysis'` 行必须带。已用「删掉 `age_n` 的
`indent_level`」验证会失败。

**教训**：section 结构与缩进都是「没有数字」的契约，P5 的 5520 个数值断言全部无法覆盖。
这类版式不变量必须由结构检查守护，不能指望数值比对。

## 6.7 shinytest2 `wait_for_idle` 抛错（非本阶段引入）

完整套件复跑时 `test-shinytest2.R:234` 以
`An error occurred while waiting for Shiny to be stable` 失败。根因：`wait_for_idle()`
在 Shiny 未稳定时是**抛错**，而非返回假值，所以此前只包住 DT 渲染等待的
`try(..., silent = TRUE)` 无法拦截它，一次瞬时抖动会随机带走一条测试。

**修复**：新增 `wait_for_stable()` 助手——首次 `wait_for_idle` 失败后以更长窗口重试一次，
仍失败才放弃；调用方的 DOM 等待（`wait_for_rows` / `wait_for_text`）与断言仍是真正的判据。
全文件 57 处 `wait_for_idle` 调用统一改走该助手。连跑 3 次 0 失败。

## 6.8 列宽溢出（RTF 分栏）—— 报告的严重缺陷

用户指出「有些行溢出到下面，Word 里不和 stub 在一起」。实测确认这是一个比外观更严重的问题。

**现象**：RTF 被 ODS 拆成**水平分栏（panels）**。表头的 `	rhdr` 段出现两种不同的 `cellx` 布局：

```
portrait:  [5153, 7239, 9325]        -> 3 格（stub + 2 列）
           [4638, 9266]              -> 2 格（stub + 1 列）
landscape: [10759, 12926]            -> 2 格
           [4295, 8580, 12865]       -> 3 格
```

即第三、四列被推到**后续页**，而**stub 列只出现在第一栏**。所以「行溢出到下面且不和 stub 在一起」是分栏的直接后果。

**连带影响**：分栏让页数几乎翻倍。

| 表 | 修复前页数 | 修复后 |
| --- | ---: | ---: |
| 14.1.1 | 2 | **1** |
| 14.1.2 | 3 | **2** |
| 14.3.1.2 | 25 | **14** |
| 14.3.1.4 | 40 | **21** |
| 14.3.2.1 | 6 | **3** |

（Word 16.0.19127 `ComputeStatistics(2)` 实测。）

**根因**：`report_page_layout()` 只预留了 **1.5pt**（0.0208in）给边框：

```
stub_width = 纸张宽 − 2×1in − 0.0208 − Σ列宽
```

但 ODS 的分栏判定用的是**含单元格内边距和边框的实际网格宽度**，这个网格比「声明列宽之和」宽。1.5pt 远不够。用 `probe_width3.sas` 做的二分探针确认：

| stub | 每列 | 网格合计 | 结果 |
| --- | --- | --- | --- |
| 2.479in | 1.00in | 6.479in | **分 2 栏** |
| 2.400in | 1.00in | 6.400in | 1 栏 ✓ |
| 2.000in | 1.10in | 6.400in | 1 栏 ✓ |
| 1.200in | 1.30in | 6.400in | 1 栏 ✓ |

临界点在 **6.40in**（可用宽度 6.5in − 0.1in）。所以需要的余量是 **≈0.1in**，而非 0.02in。

**修复**：引入显式 `fit_reserve = 0.25in`（取实测阈值的 2.5 倍安全边界）：

```r
stub_width = 纸张宽 − 2×1in − fit_reserve − 2×边框 − Σ列宽
```

修复后 6 张表全部 `distinct_layouts = 1`（单一网格、5 列齐全），`	rhdr` 段从 4 降到 2。

**顺带推翻一个假设**：`width=` 字符宽度提示**不是**原因。探针 `v_a`（带 `width=40`）、`v_b`（完全去掉 `width=`）、`v_c`（`width` 与 cellwidth 匹配）三者产物**字节完全相同**（均 5706 字节，分栏一致）。所以 `report_source.R` 里的 `width=40` / `width=16` 对版面没有影响，可以保留也可以清理，但不要误以为改它能解决溢出。

## 6.9 Word COM 页数测量能力

`test/fixtures/sas/runtime_v2/study/render_rtf.py` 已用 `win32com` 打开 Word 并 `ExportAsFixedFormat` 导出 PDF。本阶段补了 `ComputeStatistics(2)` 直接拿页数的能力，用于：

1. 证明分栏导致页数翻倍；
2. 为分页策略提供**真实物理容量**数据 —— 这是决定「一页放多少行」的唯一可靠依据。

实测容量（修复分栏后）：

| 表 | 数据行 | 页数 | 行/页 |
| --- | ---: | ---: | ---: |
| 14.1.1 | 15 | 1 | 15.0 |
| 14.1.2 | 38 | 2 | 19.0 |
| 14.2.3 | 14 | 1 | 14.0 |
| 14.3.1.2 | 300 | 14 | 21.4 |
| 14.3.1.4 | 476 | 21 | 22.7 |
| 14.3.2.1 | 68 | 3 | 22.7 |

**≈21–23 数据行/页**是当前版式下的稳定容量。这个数字是分页策略的输入，不是可以靠算术推出的（取决于字号 `fs20`、内边距 `clpadt=60`、行距 `sb/sa=60`、表头高度）。

## 6.10 更正：`placement` 与「一个 level 一个 block」的约束

此前分析 14.3.1.4 重构时我说「一个 level 只能有一个 `same_row` block，需要放开 `model.R:952-956` 约束」。**这个说法不准确，更正如下。**

`model.R:952-956` 的实际校验是：**当 level 声明了 `node_analysis_id` 时**，该 block 必须是 `same_row` 且锚定在该 level。它**没有**限制一个 level 只能有一个 block——`analysis_blocks` 是独立列表，可以给同一 level 再加 `placement: below` 的 block。

emitter 侧也已支持（`hierarchical.R:454-460`）：

```r
if (same_row) c(
  "  label = node_label; row_role = 'dynamic';",
  paste0("  indent_level = ", level_order - 1L, ";"),
  "  order_key = cats(display_order_path, 'A');"     # A = 同行，排在子节点前
) else c(
  "  row_role = 'static';",
  paste0("  indent_level = ", level_order, " + indent_level;"),
  "  order_key = cats(display_order_path, 'B', ...);" # B = below
)
```

`order_key` 的 `A` / `B` 前缀配合 `hierarchical.R:693` 的注释「Order current node and below static rows before dynamic children」，**正是为「节点计数行 → below 行 → 子节点」这个顺序设计的**。

**为何 `below` 而非 `before`**：SAS `proc report` 的 `compute before <var>` 作用于**分组变量的首行之前**；而我们要表达的语义是「SOC 这个节点的计数行之后、它的 PT 子节点之前」。用 `same_row` 承载计数、再用 `below` 承载严重程度汇总，等于把「之前」表达成「上一个节点之后」，不需要 `before`。实测也已确认 `compute before/after` + `line` 在 ODS RTF 下**不产生任何表格行**，所以 `before` 这条路本来也不通。

**结论**：14.3.1.4 重构为解释 2 不需要改模型约束，只需要在模板里给 `soc` 和 `pt` 各加一个 `placement: below` 的 `analysis_block`。这是纯 metadata 改动。

## 6.11 空行规则重写：从「深度变化」到「块边界」

用户指出「不是所有层级嵌套都该插空行」，并给出判定原则：**按 level 嵌套 + label/analysis
行决定**。核实后确认原规则是错的，且错在语义层。

**原规则**（`report_source.R:131-132`）：

```
gap_before = chunk_order 变化
          OR (hierarchy_level > 0 AND previous_level > 0 AND hierarchy_level ≠ previous_level)
```

即「层级深度一变就插空行」。后果：SOC 与它自己的 PT 之间被插入空行，**把父子关系切断**，
与用户观察一致（14.3.1.2 有 46 个空行、14.3.1.4 有 109 个）。

**新规则**：

```
gap_before = chunk_order 变化                      # 新 chunk
          OR hierarchy_level = 1                    # 顶层节点
          OR (previous_role = 'static' AND row_role = 'dynamic')  # below 行块结束
```

插入位置为**该行之前**，因此 `previous_role` 是查看上一行的角色。三个判据的语义：

| 判据 | 含义 | 例子 |
| --- | --- | --- |
| `chunk_order` 变化 | 新 chunk 开始 | 14.1.2 的 7 个特性之间、14.2.3 的 3 个治疗组之间 |
| `hierarchy_level = 1` | 顶层节点开始 | 14.3.1.2 的 23 个 SOC 之间 |
| 上一个 static → 当前 dynamic | 某节点的 below 行结束、下一个节点开始 | 14.3.1.4 的严重程度行结束后接下一个 PT |

**关键设计点**：只认「static 之后紧跟 dynamic」，不是在每个 static 行前都插。因为一个节点
的 below 行是**连续一段**，只有这段结束、下一个节点开始时才需要分隔。这条把「PT 之间是否
插空行」变成**数据驱动**——PT 下没有 below 行（14.3.1.2）就不插，有 below 行（14.3.1.4）就插，
无需为每张表写特例。

**改动生效后的空行数**：

| 表 | 原 | 新 | 说明 |
| --- | ---: | ---: | --- |
| 14.1.1 | 0 | 0 | 单 chunk、无层级 |
| 14.1.2 | 6 | 6 | chunk 之间 |
| 14.2.3 | 2 | 2 | chunk 之间 |
| 14.3.1.2 | 46 | **23** | SOC 之间；SOC↔PT 不再插 |
| 14.3.1.4 | 109 | **3** | 待重构为解释 2 后会变多 |
| 14.3.2.1 | 1 | **10** | 每个 visit 块之间 |

**14.3.2.1 从 1 涨到 10** 是正确的：该表是 `PARAM → visit → 统计量`，统计量行是
`static`（below），所以每个 visit 的统计量结束后、下一个 visit 前插入 —— 13 个 visit 得到
12 个候选，减去首行 1 个、再算上块边界，实际 10 个。原规则的 1 个空行是纯属巧合
（只在 `hierarchy_level` 1→2 变化处触发）。

**`gap_before` 已进入产物**：作为 `_TFL_ASM_001` 的一列保留（`keep report_order gap_before ...`），
但 `proc report` 不引用它，**不出现在 RTF 里**。这样空行规则可以被直接断言，
而不是像以前那样只能数 `row_role='spacer'` 的个数反推。

**新增/更新 guard**：
1. `test-dummy-study-metadata.R` 新增一条，断言新判据存在、旧判据 `previous_level` 已消失；
2. `test-report-source.R` / `test-shinytest2.R` / `test-z-hierarchical-emitter.R`
   三处原本 pin 住旧表达式的断言同步更新为 pin 新表达式。

## 6.12 14.3.1.4 重构为「SOC/PT 各带严重程度」（解释 2）

用户指出原 shell 的结构是错的：本表应当是 **by SOC by PT**，**SOC 下面有严重程度、
PT 下面也有严重程度**。原实现是「严重程度 → SOC → PT」三层，严重程度在最外层，
与需求相反。已按解释 2 重构。

### 新结构

```text
SOC 计数行                            ind 0
  SEVERE / MODERATE / MILD            ind 1   ← below block
                                      ← 空行
  PT 计数行                           ind 1
    SEVERE / MODERATE / MILD          ind 2   ← below block
                                      ← 空行
  下一个 PT ...
```

`levels` 降为两级（`soc` → `pt`），严重程度改为**两个 `below` analysis_block**：
`soc_severity`（锚定 `soc`）与 `pt_severity`（锚定 `pt`）。`TFLSEV` format 与
原 `sev` level 一并删除 —— 严重程度不再是层级，而是 below 行的 condition。

**模型无需改动**：核实后确认 `model.R:952-956` 只要求 `node_analysis_id` 指向的 block
是 `same_row`，并未限制一个 level 只能有一个 block。emitter 早已支持
（`hierarchical.R:454-460`，`same_row` 用排序前缀 `A`、`below` 用 `B`）。

### 发现并修掉的口径错误

重构后 P5 立刻报出 **64 个不符**，全部在 SOC 层的严重程度行：期望 MILD 54、
SAS 输出 70。根因是严重程度行错误地按 `SEV_ORDER` 计数。

`AE_MAXSEV` 的粒度是 `USUBJID × SOC × PT`，`SEV_ORDER` 是**该组合**的最差严重度。
用它给 SOC 层计数，等于「受试者在 SOC 下**任一** PT 达到该严重度就计入」——三行会重叠。
以最大 SOC（108 人）为例：

| 口径 | SEVERE | MODERATE | MILD | 合计 |
| --- | ---: | ---: | ---: | ---: |
| 任一 PT 达到 | 7 | 47 | **70** | 124 ✗ 超过 108 |
| **最差严重度** | 7 | 47 | **54** | 108 ✓ |

**用户确认两层都用「最差严重度」**（行内可相加）。修法：`custom_code.before` 派生
**两个**归约变量 —— `SEV_ORDER`（SOC/PT 最差，PT 层用）与 `SOC_SEV_ORDER`
（跨该 SOC 的 PT 再取 `min`，SOC 层用）。

**PT 层无此歧义**：`AE_MAXSEV` 已是一行一个 SOC/PT 组合，`SEV_ORDER` 就是该组合的
最差严重度，三行必然相加等于 PT 计数行的 n。

### 另一个 SAS 陷阱

第一版实现写成自引用：

```sas
create table WORK.AE_MAXSEV as select a.*, b.SOC_SEV_ORDER
  from WORK.AE_MAXSEV as a inner join (...) ...
```

触发 `WARNING: 该 CREATE TABLE 语句递归引用目标表。可能产生数据完整性问题。`
运行器把未分类 WARNING 视为失败（`0/1 programs clean`）。修法：先建
`WORK.AE_PTSEV`，再 join 回自身生成 `WORK.AE_MAXSEV`。

### 结果

| 项 | 原（SEV→SOC→PT） | 新（SOC/PT + below） |
| --- | ---: | ---: |
| 输出行数 | 476 | **1012** |
| 空行数 | 109（旧规则）/ 3 | **252** |
| 页数 | 21 | **55** |
| P5 断言格 | 2936 | **8096** |

行数构成：23 SOC + 23×3 SOC 严重度 + 230 PT + 230×3 PT 严重度 = 1012。
空行构成：22 个 SOC 边界 + 230 个 PT 边界 = 252，**每个空行都精确落在
`static` 段结束与下一个 `dynamic` 之间**（已用脚本全面校验）。

### 代价与遗留

**`format` 功能在 dummy study 里失去了覆盖。** 原 `TFLSEV` 是本 fixture 中唯一使用
level 级 `format` 的地方（14.3.2.1 已在 P4 移除 `$TFLVISIT`），重构后 6 张表**再无
任何 level 声明 `format`**。`format` 仍有专门覆盖（`test/fixtures/sas/runtime_v2/run_formats.py`，
13 个用例 + 永久 guard），所以不是无覆盖，但 dummy study 这条端到端链路不再经过它。
若要恢复，需要另找一张表用 `format` 驱动层级。

## 6.13 分页：容量必须按「打印行」计，且块不能跨页

### 为什么容量不能用 22

先前把 `page_rows` 默认值定为 22，理由是 Word 测得每页 21–23 行。但第一次跑出来是
**1012 行 / 101 页**（约 10 行一页），而不是 51 页。用 `ComputeStatistics(2)` 逐表测量
真实容量后发现两件事：

1. **每页还有重复的列标题行**（`	rhdr`）。14.1.1 每页 17 行总行、其中 2 行是标题，
   净数据行只有 15 行；14.3.1.4 是 1 行标题（多级标题），净数据行 20.8 行。
2. **空行也占打印行**。最初的容量累加写成 `where row_role ne 'spacer'`，只数数据行，
   于是 20 行数据 + 4 行空行的块被算成「20 行」，装进容量里，实际打印 24 行 → 溢出。
   改成数全部打印行后，`page_rows: 18` 才第一次得到「页数 = 组数」。

结论：`page_rows` 是**打印行**预算，空行要计入；标题行由 ODS 每页重复，不占预算
（它是表格头，不是 body 行）。

### 块不能被切开，除非块高于一整页

按块累加时，14.3.1.2 始终比组数多 2–3 页。原因不是算法错，而是数据形状：
最大的 SOC 挂了 34 个 PT，**单块 35 行**，比 20 行的容量还高，任何页都放不下。
这是物理约束，不是缺陷。实现上区分两种情况：

- 块 ≤ 容量：整块要么并入当前页，要么开新页，绝不切开；
- 块 > 容量：填满当前页后在下页继续（`_rows_on_page + 1 > usable` 时换页）。

加了这个例外后 6 张表全部 `pages == groups`（1/2/1/16/64/6 页），零分裂。

### 页首/页尾空白行：续页已有时不叠加

强制每页首尾各一行空白。实现时发现一个既成事实：**每个块都以一个空行开头**（块分隔
行），所以第 2 页起的页首天然就是空行；而块分隔行属于它**后面**的块，永远不会落在页尾。
因此正确的实现是：

- 页首：只有「该页第一行不是 spacer」时才补一行（`needs_top = row_role ne 'spacer'`）；
- 页尾：每页都补一行。

这样每页首尾恰好一行空白，不会出现连续两个空行。

### 页脚：`footnote style=[...]` 会被当字面文字输出

想让「Page x of Y」右对齐且与正文同字体，第一版写成
`footnote style=[fontstyle=roman textalign=right] "Page ..."`。结果 RTF 里出现的是
**这段属性文本本身**（`{style=[fontstyle=roman ...] Page ...}`），属性完全没生效。

正确写法有两条约束：

- **对齐用 `j=r`**，不是 `textalign=right`。`j=` 是 `FOOTNOTE` 语句自己的参数；
- **字体/字号要用行内 `^S={...}`**，并与 `footnote1 j=r` 放在同一条语句里。

实测最终形态：

```sas
footnote1 j=r "^S={fontstyle=roman fontweight=light fontsize=10pt}"
  "Page ^{thispage} of ^{lastpage}";
```

RTF 里体现为 `\\pard\\plain\\intbl\\sb10\\sa10\\qr\\f1\\fs20\\cf1{\\b0\\i0...`，
即 `\\qr`（右对齐）、`\\b0\\i0`（非粗非斜）、`\\fs20`（10pt）。
`\\fs20` 是刻意与正文一致：正文数据格也是 `\\fs20`（10pt），
表头是 `\\fs22`，标题是 `\\fs26`。

### SAS 数据步的三个坑

1. **`set <数据集>(obs=0)` 放在第一个 `set` 会终止整个 data step**。想借空数据集拿到
   变量结构时，必须写成 `if 0 then set ...;` 再 `set 驱动数据集;`，否则第二个 `set`
   一行都读不到（表现为 `_TFL_PADTOP_001` 有 0 个观测）。
2. **`call missing(of _all_)` 会连自己保存的临时变量一起清掉**。用它造「全空的一行」时，
   先存到 `_saved_*` 的页号和序号会同时被抹成缺失，输出行就全成了缺失值。改用
   `if 0 then set` 取结构、再直接赋值即可。
3. **多对多 join 会让行数爆炸**。把每块行数 join 回明细时，如果右侧表是「每块一行」而
   左侧是「每行一行」，且 `block_id` 有重复，SAS 会做笛卡尔积（1012 行变成 6381 行）。
   改成先 `create table` 把 `_block_size` 列并进明细，再单遍数据步累加，行数才稳定。

## 6.14 format 驱动的层级：一个真实的 emitter 缺陷 + 顺序无法被值比对覆盖

14.3.1.5（Serious TEAE by SOC and PT）是专门为验证 `format` 层级加的第 7 张表。它当场
暴露了两个问题。

### 缺陷：首层用字符型 format 时 SAS 报「已定义为字符型和数值型」

`src/emitters/hierarchical.R` 的 catalog 种子行是：

```sas
if _n_ = 1 then do;
  call missing(AEBODSYS);   /* 此处 AEBODSYS 尚未被 SET 定义 */
  flag = .; output;
end;
set _TFL_HNODE_001(keep=AEBODSYS);
```

**SAS 在 `call missing` 时就按缺失值把变量建成数值型**，随后 `format AEBODSYS $tflssoc.`
就撞上型别冲突：

```
ERROR: 变量 AEBODSYS 已定义为字符型和数值型。
ERROR 48-59: 输出格式 TFLSSOC 没有找到或无法加载。
```

之前 6 张表全躲过了，因为它们的首层分别是 `TRT01A`、`PARAMCD`（字符但**不带** format）、
`AEBODSYS`（无 format）和数值型 `AVISITN`——**没有任何一张是「首层 + 字符型 format」**，
所以这个组合从未被执行。修法是在 `call missing` 之前显式声明：

```sas
length AEBODSYS $&_TFL_HLABEL_LEN_001;
```

`&_TFL_HLABEL_LEN_001` 是 emitter 已算好的标签长度宏变量，复用即可，不需要新长度契约。
`test-z-hierarchical-emitter.R` 已加断言：`length SOC $` 必须出现在 `call missing(SOC);`
之前。

### 缺陷：值比对天生看不见「顺序」，format 定序等于没验

补上类型声明后 69 行全部算对，`compare_with_sas.R` 报 ok。但把它改成
`value $tflssoc`（去掉 `NOTSORTED`）——顺序明显从 `Nervous` 开头变成 `Cardiac` 开头——
**比对依然全部 ok**。

原因是值比对的主键是 `(路径, 列, 统计量)`：

```r
key = paste(path, column_id, stat, sep = "
")
```

顺序错了，主键集合不变，每一格的值也都没变，所以 join 依然全中。也就是说：

> **format 驱动的表，其"顺序"这一半行为在 P5 里完全没有被验证。**

修法有两段：

- `compute_expected.R` 额外写 `generated/expected/node_order.csv`，内容是**从 format
  声明顺序推出的行序**（23 SOC × (1 + 2 PT) = 69 行）；
- `compare_with_sas.R` 新增 `check_node_order()`：按 `report_order` 重建报告路径序列，
  与 `node_order.csv` 逐行 `identical()`。不一致就打印第一个差异位置并
  `quit(status = 1L)`。

**已验证该守卫会失败**：删掉 `(notsorted)` 后

```
node order (format-driven tables)
t_14_3_1_5_serious_teae        69 rows  PROBLEM
  first difference at row 1: expected Nervous system disorders, got Cardiac disorders
node order contract violated: the format declaration order was not kept
```

进程退出码 1；恢复后回到 `ok`、退出码 0。

### 后续修正（P1-5）：`check_format_nodes()` 原本无法检出「零频节点被丢弃」

第一版的通过判据是 `children %% parents == 0 && children > 0 && parents > 0`。这个式子
**无法区分完整值域和被截断的值域**：

| 情形 | parents | children | `children %% parents == 0` |
| --- | ---: | ---: | --- |
| 完整（23 SOC × 2 PT） | 23 | 46 | TRUE |
| 22 个 SOC 被丢弃 | 1 | 2 | **TRUE** |
| 只剩 1 个父、44 个子 | 1 | 44 | **TRUE** |

真正兜住这种情况的其实是 `check_node_order()`（逐行比对 69 行路径），而
`check_format_nodes()` 只是把 23/22/46/44/3 打印出来、并未断言。参数 `sas_vars` 也从未使用。

修正为方案 A：`compute_expected.R` 额外写出 `generated/expected/node_shape.csv`，内容是
**从 format 声明顺序推出**的 `parents / zero_parents / children / zero_children / non_zero`
（14.3.1.5 为 23 / 22 / 46 / 44 / 3）；`check_format_nodes()` 逐项 `identical()`，不再做
整除判断，未使用的参数已删除。

同时把「format 表必须登记」从约定变成强制：脚本直接读 bundle，找出所有含 format level 的
表，若某表不在 `node_shape.csv` 里就打印表名并 `quit(status = 1L)`。此前新增一张 format
表却忘了登记，会让整条零频契约静默失效。

**故障注入验证**（三次，均确认退出码）：

| 注入 | 退出码 | 谁报的 |
| --- | ---: | --- |
| `$tflssoc` 只留 `NERVOUS SYSTEM DISORDERS` | 1 | 单元格比对（`missing_in_sas`） |
| `node_shape.csv` 改成 1/0/2/0/1 | 1 | `check_format_nodes` 单独报出 |
| `node_shape.csv` 删掉该表 | 1 | 「format-driven table missing」守卫 |

### 教训

1. **fixture 的目的是覆盖组合，不是覆盖代码行。** 7 张表里 6 张都"有 format 或字符变量"，
   但只有 14.3.1.5 同时具备「首层 + 字符 format」，缺陷就只在那里现形。要刻意去找
   未被覆盖的**字段组合**，而不是看行覆盖率。
2. **按主键 join 的比对只能验值，不能验序。** 凡是"顺序本身是契约"的输出（format 定序、
   `result_sort`、`NOTSORTED`），都必须另有一条按序列比对的断言。

## 6.15 首层字符 format 的种子行不能按标签长度声明变量

14.3.1.5 修复「`call missing` 隐式建数值型」时，第一版用的是

```sas
length AEBODSYS $&_TFL_HLABEL_LEN_001;
```

这修好了型别，但引入了截断风险：`_TFL_HLABEL_LEN_<batch>` 是**格式化后标签**的长度
（`vlength(put(var, fmt.))`，且有 `max(256, ...)` 下限），不是原变量的长度。当 format
把长值缩写成短标签时，种子步的变量长度小于源变量，`SET` 读入的值被截断。

**SAS 探针实测**（原值 259 字节，format 标签 `'LBL'`，均不带 `NOTSORTED` 之外的特殊设置）：

| 种子写法 | 读入长度 | `put(SOC, $sh.)` |
| --- | ---: | --- |
| `length SOC $256;`（按标签长度） | **256（截断）** | `NER` —— **完全未命中任何 format 条目** |
| `if 0 then set src(keep=SOC);`（继承源） | 258 | `LBL` —— 正确 |

注意后果比"key 对不上"更严重：截断后的值查不到 format 条目，`PUT` 直接返回截断前缀，
于是**节点标题变成 `NER` 而不是 `Nerv`**，节点值域也随之分裂（同时出现 `Nerv`/`NER`
两类节点）。同时 SAS 打出 `WARNING: 输入数据集为变量"xxx"指定了多个长度。这会造成数据截断。`

因此改为在 `call missing` 之前用 `if 0 then set <input>(keep=<variable>);` 继承类型与长度：
`if 0` 永不执行、不会触发 EOF，且对字符和数值都正确，不需要 `startsWith(format, "$")`
分支。（`$` 前缀本就不是"文档约定"，而是 SAS 规则：字符 format 必须以 `$` 开头。）

**为什么 14.3.1.5 没触发**：`AEBODSYS` 长 67 字节，而标签长度下限是 256，67 < 256 所以
不会被截断。要复现必须让原值超过 256 字节。

**为什么没有留下 SAS 运行期夹具**：SAS 对 format 的 START 值有 262 字节上限（实测：更长
的 START 会导致引号字符串解析失败/查找失常），而标签长度下限是 256，两者之间只有 6 字节
窗口，且在该窗口内 `PROC MEANS / PRELOADFMT` 仍会把超长值当作未匹配。构造一个既不依赖
SAS 未文档化边界、又能稳定表达"截断"的夹具成本高于收益，因此改为：单元测试断言种子行
使用 `if 0 then set` 且不再出现按标签长度的 `length`，缺陷证据由本节的上表记录。

## 7. 证据位置

| 内容 | 位置 |
| --- | --- |
| 阶段规划与实施记录 | `plans/dummy-study.md` §4、§7、§8、§9 |
| 数据事实（生成物） | `dummy_study/variables/{adsl,adae,adlbh}.md` |
| shell 规格 | `dummy_study/shell/*.md`（7 个） |
| shell 校验输出 | `python dummy_study/tools/check_shells.py`（7 shells / 150 descriptors） |
| metadata 源码 | `dummy_study/metadata/`（17 个 YAML） |
| bundle 校验输出 | `Rscript dummy_study/tools/check_metadata.R`（8.3 秒，零错误） |
| 生成源码（不提交） | `dummy_study/generated/sas/*.sas`（7 个，372–1296 行） |
| 守卫测试 | `test/testthat/test-dummy-study-{dictionary,shells,metadata}.R` |
