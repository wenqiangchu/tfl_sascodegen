# Dummy study：shell、metadata 与独立验证

状态：**草案，待确认**（本篇是规划，不是已批准契约）。
位置决定：**`dummy_study/`（项目根目录下）**。数据决定：**拷贝并提交**所需数据集。


> P1–P3 的实测发现（原本的假设错在哪、证据、处置）已单独整理到
> `docs/dummy-study-findings.md`；本文只保留阶段状态与实施记录。

## 1. 目标

在项目根目录的 `dummy_study/` 下建立一个自包含的 dummy study，用于：

1. 以 MD 形式给出 6 张常见 TFL 的 shell，逐行/section 标明所用变量与该变量在真实数据中的取值；
2. 把这些 shell 落成可导入的 metadata bundle（schema_version 2）；
3. 用 `dummy_study/data/` 实际生成并运行 SAS；
4. 用 **R 独立计算**同样的单元格，与 SAS 结果逐格比对，证明生成的统计量正确。

第 4 步是本项目此前缺失的环节：现有 `study/validation_v2` 的独立 oracle 面向层级装配，
本 dummy study 的 oracle 面向**统计量定义**（n/mean/sd/median/q1/q3/min/max/pct）。

## 2. 数据

只拷贝 3 个 ADaM 数据集，共约 **10.8 MB**：

| 数据集 | 体积 | 用途 |
| --- | --- | --- |
| `adsl.sas7bdat` | 0.19 MB | 处置、基线特征、人群标志、Header 列与分母 |
| `adae.sas7bdat` | 0.75 MB | TEAE by SOC/PT |
| `adlbh.sas7bdat` | 9.88 MB | by-visit 层级连续、shift 表 |

来源 `study/sas_data/`（CDISC pilot，公开数据）。**这是对 AGENTS.md §4「不要把用户数据集
复制进 fixtures」的一次显式例外**，理由与代价都记在 `dummy_study/README.md`：
只拷 3 个集、约 10.8 MB、公开数据；其余 9 个集不进入仓库。

已实测的字段覆盖（用于选具体参数）：

- `ADSL`：254 例；`TRT01P`/`TRT01A` 3 组；`ITTFL` 全 Y、`SAFFL` 全 Y、`EFFFL` = N/Y；
  `AGE` 51–89；`AGEGR1` = `<65`/`65-80`/`>80`；`SEX` = F/M；`RACE` 3 值；
  `DURDIS` 2.2–183.1；`DURDSGR1` = `<12`/`>=12`；`EOSSTT` = COMPLETED/DISCONTINUED；
  `DCSREAS` 10 值（含空）。
- `ADAE`：1191 行；`TRTA` 3 组；`AEBODSYS` 23 个 SOC；`AEDECOD` 242 个 PT；
  `AESEV` = MILD/MODERATE/SEVERE；`TRTEMFL` = Y/空；`AESER`、`AEOUT`、`AESDTH`。
- `ADLBH`：24966 行；17 个 `PARAMCD`；`AVISIT` 11 个 + 空；`ANRIND` = H/L/N；
  `BNRIND` = H/N/空；`ABLFL`、`ANL01FL`。
  **选定 `PARAMCD='HGB'`**：254 例 × 11 次访视，`BNRIND` 覆盖 97.3%，
  基线 247 例、基线后 1759 条、可配对 240 例。

## 3. 目录结构

```text
dummy_study/
  README.md                     目的、数据来源与例外说明、如何跑
  data/                         adsl / adae / adlbh（提交）
  shell/                        一张表一个 md
    14.1.1-disposition.md
    14.1.2-baseline-characteristics.md
    14.3.2.1-hgb-by-visit.md
    14.2.3-hgb-shift.md
    14.3.1.2-teae-by-soc-pt.md
    14.3.1.4-teae-by-soc-pt-severity.md
  variables/                    adsl.md adae.md adlbh.md（脚本生成）
  metadata/                     bundle（schema_version 2）
    manifest.yaml populations.yaml headers.yaml
    tables/*.yaml  templates/*.yaml
  tools/
    build_variable_dictionary.py  从 data/ 生成 variables/*.md
    check_shell_cells.R           核对 shell §3 的条件变量是否存在于数据
  verify/
    compute_expected.R          R 独立计算 → expected/*.csv
    compare_with_sas.R          SAS 输出 vs expected 逐格比对
```

Git 行为（已用 `git check-ignore` 实测）：`.gitignore` 中的 `/study/` 只匹配仓库根下的
`study/`，`dummy_study/` 不受影响；`dummy_study/data/*.sas7bdat` 可正常跟踪，
而生成的 `*.sas` 仍被全局 `*.sas` 规则忽略——这正是期望行为（只有手写内容进仓库，
生成物不进）。

## 4. 表清单与 chunk 映射

人群（`populations.yaml`）：`randomized`（`'1'`，254 例）、`itt`（`ITTFL='Y'`）、
`safety`（`SAFFL='Y'`）、`efficacy`（`EFFFL='Y'`）。

Header（`headers.yaml`）：`planned_treatment`（`TRT01P`，3 列）、
`actual_treatment`（`TRT01A`，3 列）、`shift_hgb_baseline`（见 §4.4）。
列的 `condition` 在 header source 上逐例求值，因此**列可以是任意受试者级属性**。

### 4.1 14.1.1 Subject Disposition

- population `randomized`；header `planned_treatment`
- 单个 `categorical_summary_nonexclusive`，`source_data: study.adsl`，
  `counting_unit: distinct_subject`，`denominator {scope: header_population, unit: distinct_subject}`
- 行：

| 行标签 | 缩进 | `condition` | 统计量 |
| --- | --- | --- | --- |
| Randomized | 0 | `1` | 仅 `n`（`cell_format: '{n}'`） |
| Intent-to-Treat | 0 | `ITTFL = 'Y'` | n, pct |
| Safety | 0 | `SAFFL = 'Y'` | n, pct |
| Efficacy | 0 | `EFFFL = 'Y'` | n, pct |
| Completed | 0 | `EOSSTT = 'COMPLETED'` | n, pct |
| Discontinued | 0 | `EOSSTT = 'DISCONTINUED'` | n, pct |
| Adverse Event | 1 | `DCSREAS = 'Adverse Event'` | n, pct |
| Death | 1 | `DCSREAS = 'Death'` | n, pct |
| Lack of Efficacy | 1 | `DCSREAS = 'Lack of Efficacy'` | n, pct |
| Lost to Follow-up | 1 | `DCSREAS = 'Lost to Follow-up'` | n, pct |
| Physician Decision | 1 | `DCSREAS = 'Physician Decision'` | n, pct |
| Protocol Violation | 1 | `DCSREAS = 'Protocol Violation'` | n, pct |
| Sponsor Decision | 1 | `DCSREAS = 'Sponsor Decision'` | n, pct |
| Withdrew Consent | 1 | `DCSREAS = 'Withdrew Consent'` | n, pct |
| I/E Not Met | 1 | `DCSREAS = 'I/E Not Met'` | n, pct |

10 个 `DCSREAS` 取值全部列出，且含空值者不被任何行计数——这一条要写进 shell 脚注并由
R 侧断言「各行之和 + 未分类 = 254」。

### 4.2 14.1.2 Demographics and Baseline Characteristics

- population `itt`；header `planned_treatment`
- 7 个 chunk：3 个连续 + 4 个分类

| chunk | 类型 | 变量 / 条件 | 统计量 |
| --- | --- | --- | --- |
| age | `continuous_summary` | `AGE` | n, mean, sd, median, q1, q3, min, max |
| bmi | `continuous_summary` | `BMIBL` | 同上 |
| durdis | `continuous_summary` | `DURDIS` | 同上 |
| agegr | `categorical_summary_exclusive` | `AGEGR1` ∈ {`<65`,`65-80`,`>80`} | n, pct |
| sex | `categorical_summary_exclusive` | `SEX` ∈ {F, M} | n, pct |
| race | `categorical_summary_exclusive` | `RACE` 3 值全列 | n, pct |
| durdsgr | `categorical_summary_exclusive` | `DURDSGR1` ∈ {`<12`,`>=12`} | n, pct |

用 `categorical_summary_exclusive` 而非 nonexclusive，是因为这几组取值互斥，
重叠时应触发告警——这正好验证 exclusive 的重叠检测。

### 4.3 14.3.2.1 Hemoglobin by Visit（层级连续，**format 驱动**）

- population `safety`；header `actual_treatment`
- `hierarchical_summary`，`source_data: study.adlbh`，`filter: PARAMCD = 'HGB'`
  ——**不能加 `ANL01FL = 'Y'`**：本数据的 `ANL01FL` 只标在 306 条基线后记录上，
  Baseline 行为空；加上这个过滤会让 Baseline 节点整行消失（这是初稿的错误）。
- level 1：`variable: PARAM`，`node_role: label`，`missing_policy: exclude`（单节点）
- level 2：`variable: AVISIT`，`format: $TFLVISIT`，`node_role: label`，`missing_policy: exclude`
- `analysis_blocks`：`anchor_level` = level 2，`placement: below`，
  `type: continuous_summary`，`counting_unit: record`，`analysis_variable: AVAL`
- 统计量：n, mean, sd, median, q1, q3, min, max

`custom_code.before` 定义：

```sas
proc format;
  value $TFLVISIT
    'Baseline'         = 'Baseline'
    'Week 2'           = 'Week 2'
    ... 按临床顺序到 'Week 26'
    'End of Treatment' = 'End of Treatment';
run;
```

**这张表是 format 功能的核心验证点**：`AVISIT` 是字符串，按字母序会把 `Week 12` 排在
`Week 2` 之前；只有通过 format 才能同时得到**正确临床顺序**和**完整节点集合**
（即使某次访视在数据中完全缺失也会出行）。shell 里要写明这一点，并在 R 侧断言
「输出中 12 个访视节点按临床顺序出现，且缺失访视的统计量为空而不是行被省略」。

> 实测：HGB 共 2052 条记录，12 个 `AVISIT` 取值中 11 个有数据（Baseline 247、Week 2 243、
> Week 4 221、Week 6 200、Week 8 187、Week 12 166、Week 16 147、Week 20 126、
> Week 24 113、Week 26 109、End of Treatment 247），另有 46 条 `AVISIT` 为空的记录被
> `missing_policy: exclude` 排除；`AVAL` 无缺失。
>
> 「完整节点」需要数据里不存在的节点才能验证。**P4 修订**：原本计划用 `$TFLVISIT`
> 声明 `Week 28` 做探针，但实测发现 `format` 一旦声明就会接管整个 level 的节点构造
> 并忽略 `order_variable`，访视只能按字母序排列。两者不可兼得，所以访视层改用
> `order_variable: AVISITN` 保证临床顺序，探针迁到 14.3.1.4 的 `TFLSEV`
> （`4 = 'LIFE THREATENING'`）。详见 `docs/dummy-study-findings.md` §2.3、§6.2。

### 4.4 14.2.3 Hemoglobin Shift（基线 → 基线后最差）

**布局（按你的决定）**：列 = 基线等级，行 = 基线后最差等级，每个治疗组一个 section。

- population `safety`
- `custom_code.before` 做两件事：
  1. 物化 `WORK.SHIFT_HGB`（每例一行）：`USUBJID`、`TRTA`、`LBNRIND_BL`（`ABLFL='Y'`
     记录的 `LBNRIND`）、`ANRIND_WORST`（基线后按 `NORMAL < LOW < HIGH` 取最大等级；
     没有基线后分级时沿用基线分级，使每个 section 的行和等于该组基线人数）
  2. 定义分级名（`NORMAL`/`LOW`/`HIGH`）供显示与顺序使用
- **分级来源是 `LBNRIND`，不是 `BNRIND`/`ANRIND`**：HGB 的 `BNRIND`/`ANRIND` 在全部
  247 条基线记录上都是 `'N'`，按它做 3 列 shift 会退化成一列；`LBNRIND` 的基线分布是
  235 `NORMAL` / 9 `LOW` / 3 `HIGH`。`ADLBH` 没有 `ANRLO`/`ANRHI`，无法自算分级。
- header `shift_hgb_baseline`：`source_data: WORK.SHIFT_HGB`，列

| 列 id | 标签 | `condition` |
| --- | --- | --- |
| bl_normal | Normal | `LBNRIND_BL = 'NORMAL'` |
| bl_low | Low | `LBNRIND_BL = 'LOW'` |
| bl_high | High | `LBNRIND_BL = 'HIGH'` |
| overall | Overall | `1` |

列 N（全人群）：235 / 9 / 3 / 247。各 section 的组内基线人数：Placebo 82/3/0、
Low 74/5/2、High 79/1/1；Placebo 的 High 列整列为 0，正好验证「列不随数据增删」。

- 3 个 chunk（每个治疗组一个 section），`categorical_summary_nonexclusive`，
  `source_data: WORK.SHIFT_HGB`：
  - filter：`TRTA = 'Placebo'` / `TRTA = 'Xanomeline Low Dose'` / `... High Dose`
  - rows：3 行，`condition` 分别为 `ANRIND_WORST = 'NORMAL'` / `'LOW'` / `'HIGH'`
  - 统计量 n, pct

**挂起项（见 §7-1）**：Header 的 N 行来自 header source，
是「全人群各基线等级人数」；而每个 section 是单个治疗组。于是
N 与 % 的口径可能不一致。

### 4.5 14.3.1.2 TEAE by SOC and PT

- population `safety`；header `actual_treatment`
- `hierarchical_summary`，`source_data: study.adae`，`filter: SAFFL = 'Y' and TRTEMFL = 'Y'`
- level 1：`AEBODSYS`（`node_role: analysis`，计数与标签同一行）；level 2：`AEDECOD`
- 两个 `analysis_blocks`，都是 `categorical_summary_nonexclusive`、
  `counting_unit: distinct_subject`：
  - `soc_subjects`：`anchor_level: soc`，`placement: same_row`，行 `all`（`condition: '1'`，仅 `n`）
  - `pt_subjects`：`anchor_level: pt`，`placement: same_row`，行 `all`（同上）
- 静态行 `At Least One TEAE` 用**独立的普通 chunk**（排在层级 chunk 之前），
  而不是层级容器里的 `placement: above`：后者在现有夹具里没有可复用的验证实例。
- 实测：TEAE 受试者 Placebo 65 / Low 77 / High 76（共 218）；TEAE 子集含 23 个 SOC、
  230 个 PT（整批 `adae` 的 242 个 AEDECOD 里有 12 个不是治疗期事件）。

**排序（已确认支持）**。`levels[].result_sort` 就是按统计量排序的字段，语义与要求逐项对应：

```yaml
# level soc（PT 同理，换成 pt_subjects）
result_sort:
  metric:
    analysis_id: 'soc_subjects'   # 与 analysis_blocks 的 id 一致
    row_id: 'all'
    statistic_id: 'n'
  column_order: [4, 3, 1, 0]      # 最后一列 → 倒数第二列 → 第一列 → 字母序兜底
  direction: 'desc'
```

实现语义（`src/emitters/hierarchical.R` 的 `hierarchical_display_order_source`）：

- `column_order` 里每个正数一列一个 metric join，排序键依次为
  `metric_missing_k`（升序，让缺失值永远排后）→ `[descending] metric_k`；
- `0` 是哨兵值：追加 `upcase(node_label)` 升序，即**按标签字母序兜底**，
  且只能出现一次、必须在末尾（解析器强制）；
- `direction` 对**所有**列只有一个值——你的需求是全部降序，刚好契合；
- 排序在 `by parent_node_key ...` 下进行，所以 PT 是“在每个 SOC 内部”排序；
- 最终仍有 tie 时按 `node_order_path`（节点发现顺序）。

实测并列情况：**SOC 层 23 个节点三键互不相同**（字母序兜底不会触发）；
**PT 层 230 行中有 130 行并列**（字母序兜底大量生效）。所以验证字母序必须检查
某个 SOC 内部的 PT 顺序，只看 SOC 层是验不到的。

这样 4 列（Placebo / Low / High / Overall）对应 `[4, 3, 1, 0]`。

**需实测的风险（本 dummy study 的验证目标之一）**：“祖先节点自带计数”依赖
`node_role: analysis` + `node_analysis_id` + `placement: same_row` 这一组合
（`hierarchical.R:662-663` 的门控）。现有已验证夹具 14.3.1.2 与 14.3.1.4
**都只用了 `node_role: label`**，从未跑过这条路径。若同层只能挂一个 `same_row` block
或它不能与深层节点共存，退路是把 SOC 计数改为独立的 `placement: below` block，
并让 `result_sort.metric.analysis_id` 指向它。P4 运行时必须先验证这一点。

### 4.6 14.3.1.4 TEAE by SOC, PT and Severity

三层层级（`AESEV` 最大严重度 → SOC → PT），`custom_code.before` 取每例最大严重度后计数。
比现有 14.3.1.4（三层：`AESEV_MAX_ORDER` → SOC → PT）多一层嵌套，用于验证更深的层级装配。

## 5. MD shell 模板

每个 `shell/*.md` 固定 6 节，使「每行用什么变量、变量有哪些取值」可核对：

```markdown
# 14.3.2.1 Hemoglobin by Visit

## 1. Identity
| 项 | 值 |
| 表号 | 14.3.2.1 |
| 标题 | Hemoglobin by Visit |
| 人群 | Safety（SAFFL = 'Y'） |
| 来源 | ADLBH（PARAMCD = 'HGB'） |
| 表号/文件 | shell/14.3.2.1-hgb-by-visit.md |

## 2. Columns
| 列 | 标签 | 来源 | condition | N 规则 |

## 3. Rows
| # | 行标签 | 缩进 | chunk id | condition (SAS) | 使用的变量 | 统计量 |
|---|---|---|---|---|---|---|

## 4. Variable dictionary（本表用到的变量）
| 数据集.变量 | 标签 | 类型 | 实测取值 / 范围 | 本表角色 |
| ADLBH.AVISIT | Visit | char | Baseline, Week 2 … Week 26, End of Treatment | 层级 level 2 节点 |

## 5. Chunk plan
```yaml
（可直接粘贴进 templates/*.yaml 的片段）
```

## 6. Open points / 脚注
```

第 4 节的取值必须与 `variables/*.md`（脚本实测生成）一致；
`tools/check_shell_cells.R` 检查第 3 节里出现的每个变量名确实存在于对应数据集，
避免 shell 与数据脱节。

## 6. 独立验证（R 计算）

不复用 SAS 的任何中间结果，全部从 `dummy_study/data/` 原始数据集重算：

1. `verify/compute_expected.R`：用 `haven::read_sas` 读入 3 个数据集，
   用 `dplyr` 按 shell §3 的定义逐表算出长表
   `(table, chunk_id, row_id, column_id, statistic, value)`，写入 `expected/*.csv`。
   - **R 侧只断言非分位数统计量**：对齐 `n`/`mean`/`sd`/`min`/`max` 与分类的
     `n`/`pct`；`median`/`q1`/`q3` 因 SAS `PCTLDEF` 与 R `quantile(type=)` 的定义差异，
     只输出到比对报告供人工看，**不计入 assert**，不会让比对失败。
     （若你只想忽略 `q1`/`q3` 而仍校验 `median`，改一行即可。）
   - 百分比分母按 shell §2 的 N 规则独立计算。
2. 生成并运行 SAS，把装配后的表落成永久数据集（`custom_code.after` 中
   `data study_out.asm_14_3_2_1; set _TFL_ASM_001; run;`）。
3. `verify/compare_with_sas.R`：读入该数据集与 `expected/*.csv`，逐格比对；
   数值容差 `1e-9` 绝对、计数/字符串精确；输出与现有 `runtime_v2` 一致的
   JSON 断言文件，非零退出码表示失败。

这样验证的是**统计量定义是否正确**，而不是「SAS 跑通了没有」。

## 7. 已确认决定与遗留项

1. **shift 表的 N 口径 — 已确认 (a)**。Header 的 N 行是全人群（235/9/3/247），
   百分比用**组内**基线人数作分母（Placebo 82/3/0 等），每个 section 的行和等于该组基线人数。
   否决的替代：(b) 拆成 3 张表；(c) 三列都用全人群分母（会让 Placebo 的 High 列显示
   `0/3`，而该组实际没有基线 High 的受试者）。
2. **AE 排序 — 已确认支持，无需新代码**。用 `levels[].result_sort`：
   `column_order: [4, 3, 1, 0]` + `direction: desc`，`0` 即标签字母序兜底（见 §4.5）。
   唯一需要实测的是“祖先节点自带计数”的 `same_row` 路径。
3. **第 6 张表 — 包含**（14.3.1.4 三层 severity）。
4. **分位数 — 比对时忽略** `median`/`q1`/`q3`；其余统计量与分类百分比必须对上（见 §6）。
5. **完整节点探针 — 已由 `Week 28` 迁到 `TFLSEV 4='LIFE THREATENING'`（待你复核）**。
   理由见 §4.3 的 P4 修订与 `docs/dummy-study-findings.md` §2.3：`format` 与
   `order_variable` 互斥，访视必须按临床顺序，探针因此迁到封闭取值域。
6. **`format` + `order_variable` 同时声明被静默忽略 — 产品级问题，未决**。
   `src/emitters/hierarchical.R:285` 在 format 分支提前返回。可选处置：模型层拒绝该组合、
   emitter 改为两者兼容、或只写进文档。未替你决定，见 findings §2.4。

## 8. 待验证的结构假设

以下三点在设计上支持、没有在现有夹具中真实跑过，属于本 dummy study 的验证目标。
**P4 已全部用真实 SAS 验证通过**：

1. `node_role: analysis` + `node_analysis_id` + `placement: same_row` 能否让 SOC 行带计数；
   → **成立**。TEAE 表输出 1 + 23 SOC + 230 PT = 254 行，SOC 行自带 `n (%)`。
2. `result_sort` 在**两层**都有 metric 时是否各自独立生效（SOC 按自身频数、PT 在 SOC 内排序）；
   → **成立**。SOC 顺序 GENERAL 108 → SKIN 99 → NERVOUS 53 → GI 51 → CARDIAC 40 →
   INFECTIONS 38，与三键降序 + 字母序兜底一致；PT 在其所属 SOC 内排序。
3. `header.source_data` 指向 `custom_code.before` 物化的 `WORK.SHIFT_HGB` 是否可行；
   → **成立，但有一个前提**：population 表达式在 **header source** 上求值，派生表必须带上
   表达式引用到的全部变量（`SAFFL`），否则 SAS 编译期报「变量没有找到」。已修正。
   （现有夹具的 header 都指向永久库数据集）。

## 9. 阶段与验收

| 阶段 | 产出 | 验收 |
| --- | --- | --- |
| P1 | `data/`、`tools/build_variable_dictionary.py`、`variables/*.md` | 字典由脚本生成；重跑输出一致；每个数据集的变量数与实测一致（49/55/46） |
| P2 | 6 个 `shell/*.md` | 每表 6 节齐全；`tools/check_shells.py` 通过；行/section 的变量都在字典里 |
| P3 | `metadata/`（schema_version 2） | `tools/check_metadata.R` 零错误；6 张表各生成两次一致 |
| P4 | 生成的 `.sas` 与运行日志 | 0 ERROR；日志审核无未分类告警；表头 N 与 shell 一致 |
| P5 | `expected/*.csv`、比对 JSON | 非分位数统计量与分类百分比全部一致（`median`/`q1`/`q3` 仅报告）；故意改一个条件能让比对失败（证明断言有效） |

### P1 实施记录（已完成）

- 数据：`adsl` / `adae` / `adlbh` 三个集共 10.9 MB，已拷入 `dummy_study/data/`。
- 描述符：`tools/export_descriptors.sas` 用 `PROC CONTENTS` 导出 150 行到
  `variables/descriptors.csv`（提交，便于无 SAS 环境重建字典）。
- 字典：`tools/build_variable_dictionary.py` 生成 `variables/{adsl,adae,adlbh}.md`，
  行数 49/55/46 与数据列数一致；连续两次运行输出逐字节相同。
- 两个实现陷阱已修并由测试守住：空白字符值不得变成字面量 `nan`；带 `DATE` 格式的
  变量不得泄漏为纳秒整数。`TRTSDT` 渲染为 `2012-07-09 – 2014-09-02`，与 SAS
  `DATE9.` 的 `09JUL2012 – 02SEP2014` 交叉核对一致。
- `.gitignore` 新增 `!dummy_study/tools/*.sas`（手写工具需跟踪）与
  `dummy_study/generated/`（生成程序不进仓库）。
- 测试：`test/testthat/test-dummy-study-dictionary.R` 共 17 项断言；注入字面量 `nan`
  后立即失败，恢复后通过。`Rscript test/run_tests.R` 退出 0。

### P2 实施记录（已完成）

产出 6 个 `shell/*.md`，每个 6 节齐全：
`14.1.1-disposition`、`14.1.2-baseline-characteristics`、`14.3.2.1-hgb-by-visit`、
`14.2.3-hgb-shift`、`14.3.1.2-teae-by-soc-pt`、`14.3.1.4-teae-by-soc-pt-severity`。

写 shell 过程中实测推翻了四处规划假设，已回写到上面的 §4.3、§4.4、§4.5：

1. **`ANL01FL='Y'` 会把 Baseline 排除**：HGB 的 `ANL01FL` 只标在 306 条基线后记录上，
   初稿的过滤条件会让 Baseline 节点整行消失，且只剩 9 次访视。已改为只过滤 `PARAMCD`。
2. **shift 表不能用 `BNRIND`/`ANRIND`**：HGB 全部 247 条基线记录的这两个变量都是 `'N'`，
   三列会退化成一列。改用 `LBNRIND`（基线 235 `NORMAL` / 9 `LOW` / 3 `HIGH`）。
   另外 5 例无基线后分级，规则定为「沿用基线分级」，使每 section 行和等于该组基线人数。
3. **静态行 `At Least One TEAE` 用独立普通 chunk**，不依赖未验证的 `placement: above`。
4. **`result_sort` 的字母序兜底在 SOC 层不会触发**（23 个 SOC 三键互不相同），
   但在 **PT 层大量生效（130 / 230 行并列）**；验证字母序必须看 SOC 内部的 PT 顺序。

新增 `tools/check_shells.py`，核对：六节结构、每个 `DOMAIN.VARIABLE` 是否存在、
`char(N)` 声明是否与 SAS 长度一致、是否混入字面量 `nan`。首次运行拓出 **7 处长度错误**
（`EOSSTT` 12 非 11、`DURDSGR1` 4 非 3、`ABLFL`/`ANL01FL` 2 非 1、`LBNRIND` 8 非 12、
`PARAM` 48 非 38），全部按描述符修正；现 37 条变量声明全部一致。

另一个被实测拓出的错误：14.3.1.4 的 `AESEV` 分级计数初稿写成 923/219/49，实测为
全 1191 行 `MILD` 770 / `MODERATE` 378 / `SEVERE` 43（TEAE 子集 731/354/41），已修正。

### P3 实施记录（已完成）

`dummy_study/metadata/` 下 14 个 YAML：`manifest.yaml`（schema_version 2）、
`populations.yaml`（4 个）、`headers.yaml`（3 个）、`tables/`（6 个）、`templates/`（6 个）。
`tools/check_metadata.R` 用生产 codec + 生产模型做校验：解析 → `parse_bundle_value` →
canonical archive 往返一致 → 6 张表各生成两次并比对 → `--write` 才落 `generated/metadata.zip`
与 6 个 `.sas`。默认运行 8.3 秒，零错误。

**模型层的硬约束**（不实测就会写错的四处）：

1. 每个 level 必须声明 `format`，**或者**同时声明 `order_variable` + `order_direction`。
   AE 的 SOC/PT 层没有 format，所以虽然显示顺序由 `result_sort` 决定，仍必须给
   `order_variable`（这里用变量自身，`asc`），否则模型直接拒绝。
2. `node_role: analysis` 强制要求 `node_analysis_id`，且它指向的 block 必须
   `placement: same_row` 并锚定在该 level；`node_role: label` 则禁止该字段。
3. `cell_format` 的占位符集合必须**精确等于**该行 `statistics` 的 id 集合。
   所以连续型表按「每行一个统计量行」组织（n / Mean (SD) / Median / Q1, Q3 / Min, Max），
   而不是一行塞 8 个统计量。
4. 连续型行**不允许** `condition`；分类行**必须**有 `condition`。

**§8 三个结构假设的静态验证结果**（生成源码已确认，运行期待 P4）：

| 假设 | 结果 |
| --- | --- |
| ① `node_role: analysis` + `node_analysis_id` + `placement: same_row` | **生成通过**，SOC/PT 行带计数的代码已产出；运行期未验 |
| ② 两层 `result_sort` 独立生效 | **生成通过**：`_TFL_HORDER_002_001` 产出 `metric_1..3` + `label_sort`，`proc sort by parent_node_key metric_missing_1 descending metric_1 … label_sort node_order_path`，与设计的 `[4,3,1,0]` 完全对应 |
| ③ `header.source_data` 指向 `WORK.*` | **生成通过**，但发现一个运行时陷阱（见下） |

**新发现（P3 最有价值的一条）**：population 表达式是在 **header source** 上求值的，
不是原始 ADSL。`shift_header` 指向 `WORK.SHIFT_HGB`，而该派生表最初只有
`USUBJID/TRTA/LBNRIND_BL/ANRIND_WORST`，生成的代码是
`set WORK.SHIFT_HGB; if not (SAFFL = 'Y') then delete;` —— SAS 会在编译期报
「变量 SAFFL 没有找到」。已在 `custom_code.before` 里把 `SAFFL` 一并物化，并在注释中
说明原因。**任何用 `WORK.*` 作 header source 的表都必须让派生表带上 population 表达式
用到的所有变量。**

**副作用确认**：`format` 确实驱动完整节点。visit 层生成
`if 0 then set _TFL_HSRC_001; if 0 then _tfl_fmt_value = put(AVISIT, $TFLVISIT.);` 与
`format AVISIT $TFLVISIT.;`；severity 层生成 `class parent_node_key SEV_RANK / preloadfmt
order=data missing;`，`preloadfmt` 正是「零计数也出行」的 SAS 机制，`order=data` 取
format 声明顺序（SEVERE → MODERATE → MILD）。

**新增永久 guard**：`test/testthat/test-dummy-study-metadata.R`（85 断言）在常规套件里
完成解析 + 模型校验 + 引用解析 + 最小表端到端生成；注入 `missing_policy: 'drop'`
后立即失败，恢复后通过。

### P4 实施记录（已完成）

`tools/run_sas.R` 生成包装程序（`libname study` → `%include` 生成程序 → 把
`_TFL_WIDE_001` / `_TFL_ASM_001` 落盘 → `%put` 行数进日志），调用方式沿用项目已有
外部 harness（`-sysin/-log/-print/-nosplash/-noterminal`，相对文件名 + cwd）。

**6/6 全部 exit=0、0 ERROR、0 未分类告警**；行数 15 / 25 / 9 / 254 / 367 / 67，与
独立 pandas 计算逐项一致。日志分类器把两类已知告警（站点 SASHELP 缺失、AE 源
`duplicate_key` 诊断）与真正的异常分开，未分类即判失败。

**四个运行期缺陷**（静态校验与单元测试都抓不到，只有真跑才暴露）：

1. **声明 `format` 会静默忽略 `order_variable`**（`src/emitters/hierarchical.R:285`
   提前返回）。访视因此按字母序（`Week 12` 排在 `Week 2` 前）。已改用
   `order_variable: AVISITN`，输出 Baseline → Week 2 → … → End of Treatment。
2. **数值 format 按未格式化值升序建节点**：rank 1=MILD …3=SEVERE 时，输出是
   MILD → MODERATE → SEVERE。已把 `SEV_ORDER` 定义成显示序（1=SEVERE），归约用 `min()`。
3. **P3 的「逐列分母不可实现」结论是错的**：shift 实测 `69 (84.1%)` = 69/82，
   零分母渲染 `NE`。shell 原设计可原样实现，该「能力边界」作废。
4. **shell 14.3.1.4 的预期计数是错量**：原写的 3/12/50 是「受试者级最大严重度」，
   实际输出是「每 PT 取最大」的节点数 29/125/177（合计 331 > 人群 254，属正常）。

**完整节点探针已从 `Week 28` 迁到 `TFLSEV 4='LIFE THREATENING'`**（因为 1 与 2 的
互斥性）。这是对已确认决定的修订，待你复核。

**新增永久 guard**：`test/testthat/test-dummy-study-metadata.R` 追加 4 条不变量
（访视层禁用 format + 必须有 AVISITN、探针节点存在、`SEV_ORDER` 显示序、
`WORK.*` header 派生表必须带 population 变量），防止 P4 的修复被回退。

### P5 实施记录（已完成）

用 R（`haven`）独立重算每一格，再与 SAS 产物逐格 join 比对。两个脚本：

- `verify/compute_expected.R`：从原始 `adsl`/`adae`/`adlbh` 按第一性原理重算，
  长表输出 `generated/expected/expected.csv`；
- `verify/compare_with_sas.R`：把 SAS 报表行解析成 `(path, column, stat)` 后再 join，
  输出 `generated/comparison.csv`。

**结果：5520 个断言单元格全部一致**，6 张表零 `mismatched`、零 `missing`、零 `extra`。

| 表 | 期望格 | 对齐 | 断言 | 双侧不可估计 |
| --- | ---: | ---: | ---: | ---: |
| disposition | 120 | 120 | 120 | 0 |
| baseline | 176 | 176 | 140 | 0 |
| hgb_shift | 72 | 72 | 72 | 3 |
| teae | 2032 | 2032 | 2032 | 0 |
| teae_severity | 2936 | 2936 | 2936 | 0 |
| hgb_by_visit | 352 | 352 | 220 | 0 |

**写入脚本的四个判断**（都是踩过之后才定下的）：

1. **按展示精度比对，不按 1e-6。** 渲染值已四舍五入，`6.4542400` 对 `"6.45"`
   比全精度是在测浮点格式而不是统计量。小数位从单元格文本**反读**，一张代码路径
   同时覆盖计数（0/1 位）与连续型（逐表 2 位）。
2. **用 SAS 的 ROUND 语义。** 基础 `round()` 是「五成双」，SAS 是「五入」。
   `42.65` 按 1 位：R 得 42.6、SAS 得 42.7 —— 这一格曾真实失败，改为
   `floor(abs(x)*10^d + 0.5)/10^d` 后通过。
3. **节点全集按「全人群」建，再逐列零填充。** SAS 输出会把某臂没有的 PT 打印成
   `0 (0.0%)` 而不是删除，若按列内出现值建节点表，会误报 690/1072 个 `extra`。
4. **`same_row` 节点带计数，不是统计行。** 靠 `row_role == 'dynamic'` / `hierarchy_level > 0`
   区分；按「数值为空即节点」判断会把 SOC/PT 的计数整体丢掉。

**为何分位数不断言**：`PROC MEANS` 默认 `PCTLDEF = 5`，R 有 9 种分位数算法。
脚本仍计算并记录 `median`/`q1`/`q3`（`asserted = FALSE`），差异会出现在
`comparison.csv` 的 `reported_only` 里，但不作为通过条件。

**新增永久 guard**：`test-dummy-study-metadata.R` 追加一条，断言两个验证脚本存在、
可解析，且保留了「分位数不断言」与「按显示精度 + SAS 取整规则比对」这两个契约。

### P5 复核修正（section 标题行）

用户复核 14.1.2 指出每个 section 缺标题行。核实后确认 14.1.2（7 处）与
14.2.3（3 处）缺失，其余 4 张表通过。已补 `type: 'label'` 行并新增双侧 guard
（`check_shells.py` 第 5 项 + `test-dummy-study-shells.R`）；详见
`docs/dummy-study-findings.md` §6.5。P5 比对回归后仍 5520 格全一致。

**遗留待决**：14.1.1 是否需要 `Analysis Populations` / `Study Disposition` 之类的
分组标题行——当前 shell 未声明，各行语义自足。

### P5 复核修正二（缩进层级）

用户复核指出 14.1.2 统计量缩进仍不对。核实：补标题行后 32 行全为 `indent_level = 0`，
与标题行左对齐。已给 14.1.2 的 25 个 `analysis` 行、14.2.3 的 9 个补
`indent_level: 1`（`label` 行保持 0），RTF 实测 `\li0` / `\li200` 两档。
新增结构 guard；详见 `docs/dummy-study-findings.md` §6.6。

**教训**：section 结构与缩进都无数字，P5 数值断言无法覆盖，必须由结构检查守护。

### P5 复核修正三（列宽溢出 / RTF 分栏）

用户指出部分行「溢出到下面、不与 stub 同栏」。实测确认是 ODS 的**水平分栏**：表头
`	rhdr` 出现两种 `cellx` 布局，第 3/4 列被推到后续页且 stub 只在首栏。
连带使页数近乎翻倍（14.3.1.2 25→14 页，14.3.1.4 40→21 页）。

根因：`report_page_layout()` 只留 1.5pt 边框余量，而 ODS 的分栏判定用含内边距/边框的
实际网格宽度。二分探针测得临界点 6.40in / 可用 6.50in，**需要 ≈0.1in 余量**。
已引入 `fit_reserve = 0.25in` 并加契约测试（`printable - grid ≥ fit_reserve`）。

**推翻的假设**：`width=` 字符宽度提示不是原因——带/不带 `width=` 的产物字节完全相同。

**新增能力**：用 Word COM `ComputeStatistics(2)` 实测页数（14–23 行/页），作为分页
策略的唯一可靠容量依据。详见 `docs/dummy-study-findings.md` §6.8 / §6.9。

**更正**：`model.R:952-956` 并不限制「一个 level 一个 block」；14.3.1.4 重构为
解释 2 属于纯 metadata 改动（见 §6.10）。

### 布局修正一（列宽溢出 + 空行规则）

用户复核发现两个版面缺陷，均已修复：

1. **列宽溢出导致 RTF 水平分栏**（`docs/dummy-study-findings.md` §6.8）：ODS 在内容网格
   超出可用宽度时把表拆成多栏，后续栏打印在后续页且 stub 只在首栏，页数近乎翻倍。
   根因是 `report_page_layout()` 只留 1.5pt 余量；二分探针测得需 ≈0.1in，已引入
   `fit_reserve = 0.25in` 并加契约测试。14.3.1.2 页数 25→14、14.3.1.4 40→21。

2. **空行规则语义错误**（§6.11）：原「深度变化即插空行」把 SOC 与其 PT 切断。
   改为「块边界」判定——新 chunk、顶层节点、或 below 行块结束。14.3.1.2 空行 46→23，
   14.3.2.1 1→10（后者原本只是巧合）。`gap_before` 作为产物列保留但不进 RTF。

**待办**：14.3.1.4 重构为解释 2（SOC/PT 下各有 below 严重程度行）；分页（`page_rows`
可配、SAS 侧 retain 累积、Page x of Y、每页首尾空行）。

### 布局修正二（14.3.1.4 重构为解释 2）

用户指出原 shell 结构有误：应为 by SOC by PT，SOC 与 PT **各自**带一组严重程度行。
已重构：`levels` 降为 `soc`→`pt`，严重程度改为两个 `below` block，删除 `sev` level
与 `TFLSEV`。模型无需改动（一个 level 可同时挂 `same_row` 与 `below`）。

**发现并修掉一个口径错误**：SOC 层严重程度行原按每 SOC/PT 的 `SEV_ORDER` 计数，
导致三行重叠（MILD 70 vs 应为 54）。已派生 `SOC_SEV_ORDER`（跨 SOC 的 PT 取 min）。
另一陷阱：自引用 `CREATE TABLE` 会触发递归引用 WARNING，已改为经 `AE_PTSEV` 中转。

结果：输出 1012 行、252 个空行、55 页、P5 断言 8096 格全一致。
详见 `docs/dummy-study-findings.md` §6.12。

**代价**：dummy study 6 张表不再有任何 level 级 `format` 用法，
该功能改由 `test/fixtures/sas/runtime_v2/run_formats.py` 覆盖。

### 布局修正三（分页：`page_rows` / `Page x of Y` / 页边空白行）

需求（已确认）：

1. `page_rows` 作为 **header 级**配置，默认 22，`0` 表示不分页；
2. 分页在 **SAS 侧**完成（不引入 R 侧后处理）；
3. 每页正文首尾各一行空白；
4. `Page x of Y` 页脚；
5. 块不得跨页切开。

实现：`src/generator/report_source.R` 新增 `page_break_source()`（按块累加高度、生成
`page_group`）与 `page_padding_source()`（插入页首/页尾垫行）；`rtf_report_source()`
改为读 `_TFL_PAGED_001`，加 `define page_group / order noprint`、
`break after page_group / page` 和 `footnote "Page ^{thispage} of ^{lastpage}"`。
`compare_source()` 仍比对 `_TFL_ASM_001`，分页是版式而非数据。

三个实测结论（详见 `docs/dummy-study-findings.md` §6.13）：

- **容量要按打印行计**。只数数据行会让「20 数据行 + 4 空行」的块溢出，因为空行也占行；
  标题行由 ODS 每页重复，不占预算。
- **块高于一整页时必须允许切开**。14.3.1.2 最大 SOC 挂 34 个 PT（单块 35 行 > 20 容量），
  任何页都放不下；加了「仅超页块可切」后 6 张表全部 `pages == groups`。
- **页首垫行不叠加**。块分隔空行属于它后面的块，因此续页页首天然是空行；只在页首
  非空行时补垫，页尾每页补垫。

另外踩到 SAS 数据步三个坑（`set obs=0` 放在首个 `set` 会终止 step、`call missing(of _all_)`
会清掉保存变量、多对多 join 让 1012 行涨到 6381 行），均已记入 §6.13。

结果：**90 页**（1/2/1/16/64/6），每页 ≤ 22 打印行且首尾各一空行，P5 断言 10680 格
仍全一致。`compare_with_sas.R` 新增 `check_pagination()`，把「不超容量 + 页首尾均有垫行」
变成可失败的断言（已注入故障验证其会失败）。

## 10. format 驱动层级（14.3.1.5）

### 10.1 目标

把 `levels[].format` 这条路径变成被真正执行、被真正断言的路径。此前 6 张表虽然覆盖了
`format`（14.3.2.1 的 `visit` 层用数值型 format），但从未覆盖两个组合：

1. **首层用字符型 format**；
2. **父层和子层都用 format**（完整的格式化值组合）。

新增第 7 张表 **14.3.1.5 Serious TEAE by SOC and PT**，并明确标注它**不是临床报表需求**，
只为验证 format 的零频节点行为。数据事实：`AESER = 'Y'` 只有 3 行 / 3 例受试者，
落在 1 个 SOC、2 个 PT 上。

### 10.2 形状

两个 level 都声明 `format`（方案 A）：

| level | 变量 | format | 值域 |
| --- | --- | --- | --- |
| `soc` | `AEBODSYS` | `$tflssoc` | TEAE 子集的全部 23 个 SOC |
| `pt` | `AEDECOD` | `$tflspt` | 2 个有严重事件的 PT |

结果 **69 行 = 23 SOC + 46 PT**，其中 **66 行是零频**（22 个零频 SOC + 44 个零频 PT）。
44 这个数字是「父层 format × 子层 format」的必然结果：每个 SOC 下都长出完整子值域。

两个 format 都在本表 `custom_code.before` 里定义，**且都带 `(NOTSORTED)`**。

### 10.3 模型收紧：format 与三个字段互斥

`parse_level_value()` 现在拒绝 `format` 与 `label_variable` / `order_variable` /
`order_direction` 同时出现。理由：format 同时给出**值域 + 标签 + 顺序**，那三个字段
各自只能表达其中一项，且只能表达数据里已存在的值，无法表达 format 新增的节点；
先前"允许保留但生成时忽略"等于静默丢弃用户写入。

### 10.4 `NOTSORTED` 是调用方的责任

`PROC FORMAT` 默认按 `START` 排序丢弃声明顺序，`PRELOADFMT ORDER=DATA` 于是退回原始值
顺序。应用不读 format catalog，无法判断也不需要判断，因此：**不检查、不告警、只记录**。

实测结果（`\qr`-free 探针，format 声明为 `2='ZULU' 3='ALPHA' 1='MIKE'`）：

| 选项 | 输出顺序 |
| --- | --- |
| `order=data`，无 `NOTSORTED` | 原始值序 MIKE, ZULU, ALPHA |
| `order=data`，有 `(NOTSORTED)` | 声明序 ZULU, ALPHA, MIKE |
| `order=internal` / `order=freq` | 原始值序 |
| `order=formatted` | 按标签字母序 |

`NOTSORTED` 的结果与数据到达顺序无关，且能在 `CNTLOUT` → `CNTLIN` 往返中存活
（不带时声明序被丢弃）。这些都写进 `docs/design-decisions.md` 与用户契约。

### 10.5 两个被这次新增抓出来的缺陷

1. **首层字符 format 会撞型别**。catalog 种子行的 `call missing(AEBODSYS)` 在 `SET`
   之前把变量建成数值型，随后 `format AEBODSYS $fmt.` 报「已定义为字符型和数值型」。
   修法：`call missing` 之前显式 `length <var> $<label_len>;`。
2. **P5 值比对看不见顺序**。去掉 `NOTSORTED` 后顺序明显改变（首行从 Nervous 变 Cardiac），
   而按 `(路径, 列, 统计量)` 的 join 依然全 ok。修法：`compute_expected.R` 额外产出
   `node_order.csv`（format 声明序推出的行序），`compare_with_sas.R` 的
   `check_node_order()` 逐行比对，不一致即失败。

另加 `check_format_nodes()`：断言 23 父 / 22 零频、46 子 / 44 零频、3 行非零，
把「零频节点必须被打印而不是被丢弃」变成可失败的断言（缺席的节点没有单元格可与之
不一致，值比对天生看不见）。

### 10.6 结果

| 表 | 页 | 行 | 最大/页 |
| --- | ---: | ---: | ---: |
| 14.3.1.5 | 5 | 97 | 21 |

7 张表合计 **97 页**，每页在容量内且首尾有垫行；P5 **11232** 个断言单元格全部一致。

### 10.7 分页边界修正（P1-4）

审阅指出页分配对「超页块」的两处边界缺陷，均已修复：

1. **溢出一行**：超页块的首行原本不检查容量，于是前一个超页块恰好填满一页后，下一块
   的首行会挤进同一页，使正文达到 `usable + 1`。现在**所有行**（含块首行）都执行
   `_rows_on_page + 1 > usable` 检查。
2. **分隔行落在页尾**：超页块开始时若当前页只剩 1 行，它的首行（分隔行）会成为该页最后
   一行，加页尾垫行后连续两个空行。现在超页块首行额外要求剩余空间 ≥ 2 行（分隔行 + 至少
   一个内容行），否则直接换页。

修复后页数 95 → **97**（14.3.1.2 从 16 页变 18 页）：那条守卫让 4 个超页块中的一部分
提前换页，不再挤进剩余空间不足的页。`largest_page` 仍 ≤ 22。

`compare_with_sas.R` 的 `check_pagination()` 新增 `stranded_separator`（页尾连续两个
空行即判违规）。
