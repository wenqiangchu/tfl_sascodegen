# ADLBH 变量字典

数据文件：`dummy_study/data/adlbh.sas7bdat`　观测数：**24966**　变量数：**46**

由 `dummy_study/tools/build_variable_dictionary.py` 生成，请勿手工编辑。
标签/类型/长度/格式来自 `variables/descriptors.csv`（SAS `PROC CONTENTS`）；取值分布来自数据本身。

## 变量一览

| # | 变量 | 类型 | 长度 | 标签 | 格式 | 非缺失 | 不同值 | 取值 / 范围 |
| ---: | --- | --- | ---: | --- | --- | ---: | ---: | --- |
| 1 | STUDYID | char | 12 | Study Identifier |  | 24966 | 1 | `CDISCPILOT01` |
| 2 | SUBJID | char | 4 | Subject Identifier for the Study |  | 24966 | 254 | 共 254 个不同值，前 12 个：`1001`, `1002`, `1004`, `1006`, `1007`, `1008`, `1009`, `1010`, `1012`, `1015`, `1017`, `1018` |
| 3 | USUBJID | char | 11 | Unique Subject Identifier |  | 24966 | 254 | 共 254 个不同值，前 12 个：`01-701-1015`, `01-701-1023`, `01-701-1028`, `01-701-1033`, `01-701-1034`, `01-701-1047`, `01-701-1097`, `01-701-1111`, `01-701-1115`, `01-701-1118`, `01-701-1130`, `01-701-1133` |
| 4 | TRTP | char | 20 | Planned Treatment |  | 24966 | 3 | `Placebo`, `Xanomeline High Dose`, `Xanomeline Low Dose` |
| 5 | TRTPN | num | 8 | Planned Treatment (N) |  | 24966 | 3 | `0`, `54`, `81` |
| 6 | TRTA | char | 20 | Actual Treatment |  | 24966 | 3 | `Placebo`, `Xanomeline High Dose`, `Xanomeline Low Dose` |
| 7 | TRTAN | num | 8 | Actual Treatment (N) |  | 24966 | 3 | `0`, `54`, `81` |
| 8 | TRTSDT | num | 8 | Date of First Exposure to Treatment | DATE. | 24966 | 205 | 2022-07-10 – 2024-09-02 |
| 9 | TRTEDT | num | 8 | Date of Last Exposure to Treatment | DATE. | 24966 | 214 | 2022-08-29 – 2025-03-05 |
| 10 | AGE | num | 8 | Age |  | 24966 | 36 | 51 – 89 |
| 11 | AGEGR1 | char | 5 | Pooled Age Group 1 |  | 24966 | 3 | `65-80`, `<65`, `>80` |
| 12 | AGEGR1N | num | 8 | Pooled Age Group 1 (N) |  | 24966 | 3 | `1`, `2`, `3` |
| 13 | RACE | char | 32 | Race |  | 24966 | 3 | `AMERICAN INDIAN OR ALASKA NATIVE`, `BLACK OR AFRICAN AMERICAN`, `WHITE` |
| 14 | RACEN | num | 8 | Race (N) |  | 24966 | 3 | `1`, `2`, `6` |
| 15 | SEX | char | 1 | Sex |  | 24966 | 2 | `F`, `M` |
| 16 | COMP24FL | char | 1 | Completers of Week 24 Population Flag |  | 24966 | 2 | `N`, `Y` |
| 17 | DSRAEFL | char | 2 | Discontinued due to AE? |  | 6657 | 1 | `Y` |
| 18 | SAFFL | char | 1 | Safety Population Flag |  | 24966 | 1 | `Y` |
| 19 | AVISIT | char | 16 | Analysis Visit |  | 24411 | 11 | `Baseline`, `End of Treatment`, `Week 12`, `Week 16`, `Week 2`, `Week 20`, `Week 24`, `Week 26`, `Week 4`, `Week 6`, `Week 8` |
| 20 | AVISITN | num | 8 | Analysis Visit (N) |  | 24411 | 11 | `0`, `2`, `4`, `6`, `8`, `12`, `16`, `20`, `24`, `26`, `99` |
| 21 | ADY | num | 8 | Analysis Relative Day |  | 24966 | 208 | -101 – 213 |
| 22 | ADT | num | 8 | Analysis Date | DATE. | 24966 | 695 | 2022-06-30 – 2025-03-05 |
| 23 | VISIT | char | 16 | Visit Name |  | 24966 | 19 | 共 19 个不同值，前 12 个：`SCREENING 1`, `UNSCHEDULED 1.1`, `UNSCHEDULED 1.2`, `UNSCHEDULED 1.3`, `UNSCHEDULED 12.1`, `UNSCHEDULED 4.1`, `UNSCHEDULED 5.1`, `UNSCHEDULED 7.1`, `UNSCHEDULED 8.2`, `UNSCHEDULED 9.2`, `WEEK 12`, `WEEK 16` |
| 24 | VISITNUM | num | 8 | Visit Number |  | 24966 | 19 | 1 – 13 |
| 25 | PARAM | char | 48 | Parameter |  | 24966 | 17 | 共 17 个不同值，前 12 个：`Anisocytes`, `Basophils (GI/L)`, `Eosinophils (GI/L)`, `Ery. Mean Corpuscular HGB Concentration (mmol/L)`, `Ery. Mean Corpuscular Hemoglobin (fmol(Fe))`, `Ery. Mean Corpuscular Volume (fL)`, `Erythrocytes (TI/L)`, `Hematocrit`, `Hemoglobin (mmol/L)`, `Leukocytes (GI/L)`, `Lymphocytes (GI/L)`, `Macrocytes` |
| 26 | PARAMCD | char | 7 | Parameter Code |  | 24966 | 17 | 共 17 个不同值，前 12 个：`ANISO`, `BASO`, `EOS`, `HCT`, `HGB`, `LYM`, `MACROCY`, `MCH`, `MCHC`, `MCV`, `MICROCY`, `MONO` |
| 27 | PARAMN | num | 8 | Parameter (N) |  | 24966 | 17 | 1 – 17 |
| 28 | PARCAT1 | char | 3 | Parameter Category 1 |  | 24966 | 1 | `HEM` |
| 29 | AVAL | num | 8 | Analysis Value |  | 24966 | 1354 | 0 – 582 |
| 30 | BASE | num | 8 | Baseline Value |  | 23937 | 670 | 0 – 572 |
| 31 | CHG | num | 8 | Change from Baseline |  | 20955 | 1744 | -254 – 276 |
| 32 | A1LO | num | 8 | Analysis Range 1 Lower Limit |  | 20437 | 21 | 0.12 – 140 |
| 33 | A1HI | num | 8 | Analysis Range 1 Upper Limit |  | 24539 | 24 | 0.2 – 400 |
| 34 | R2A1LO | num | 8 | Ratio to Analysis Range 1 Lower Limit |  | 20437 | 1699 | 0 – 9.75 |
| 35 | R2A1HI | num | 8 | Ratio to Analysis Range 1 Upper Limit |  | 24539 | 1843 | 0 – 2.64912 |
| 36 | BR2A1LO | num | 8 | Base Ratio to Analysis Range 1 Lower Lim |  | 19848 | 764 | 0.731579 – 9.75 |
| 37 | BR2A1HI | num | 8 | Base Ratio to Analysis Range 1 Upper Lim |  | 23838 | 842 | 0 – 1.5614 |
| 38 | ANL01FL | char | 2 | Analysis Flag 01 |  | 3695 | 1 | `Y` |
| 39 | ALBTRVAL | num | 8 | Amount Threshold Range |  | 24539 | 1590 | 0.15 – 512 |
| 40 | ANRIND | char | 1 | Analysis Reference Range Indicator |  | 24966 | 3 | `H`, `L`, `N` |
| 41 | BNRIND | char | 2 | Baseline Reference Range Indicator |  | 23937 | 2 | `H`, `N` |
| 42 | ABLFL | char | 2 | Baseline Record Flag |  | 2982 | 1 | `Y` |
| 43 | AENTMTFL | char | 2 | Last value in treatment visit |  | 6190 | 1 | `Y` |
| 44 | LBSEQ | num | 8 | Sequence Number |  | 24966 | 361 | 3 – 380 |
| 45 | LBNRIND | char | 8 | Reference Range Indicator |  | 24966 | 4 | `ABNORMAL`, `HIGH`, `LOW`, `NORMAL` |
| 46 | LBSTRESN | num | 8 | Numeric Result/Finding in Standard Units |  | 24966 | 1354 | 0 – 582 |

## 说明

- 不同值不超过 12 个的变量直接列出全部取值；超过的给出范围。
- 带 `DATE*`/`YYMMDD*` 等日期格式的数值变量按 SAS 1960-01-01 纪元换算成 ISO 日期显示。
- 字符变量的前后空格已去除，与 SAS 侧 `strip()` 的口径一致。
