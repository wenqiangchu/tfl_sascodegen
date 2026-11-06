# ADSL 变量字典

数据文件：`dummy_study/data/adsl.sas7bdat`　观测数：**254**　变量数：**49**

由 `dummy_study/tools/build_variable_dictionary.py` 生成，请勿手工编辑。
标签/类型/长度/格式来自 `variables/descriptors.csv`（SAS `PROC CONTENTS`）；取值分布来自数据本身。

## 变量一览

| # | 变量 | 类型 | 长度 | 标签 | 格式 | 非缺失 | 不同值 | 取值 / 范围 |
| ---: | --- | --- | ---: | --- | --- | ---: | ---: | --- |
| 1 | STUDYID | char | 12 | Study Identifier |  | 254 | 1 | `CDISCPILOT01` |
| 2 | USUBJID | char | 11 | Unique Subject Identifier |  | 254 | 254 | 共 254 个不同值，前 12 个：`01-701-1015`, `01-701-1023`, `01-701-1028`, `01-701-1033`, `01-701-1034`, `01-701-1047`, `01-701-1097`, `01-701-1111`, `01-701-1115`, `01-701-1118`, `01-701-1130`, `01-701-1133` |
| 3 | SUBJID | char | 4 | Subject Identifier for the Study |  | 254 | 254 | 共 254 个不同值，前 12 个：`1001`, `1002`, `1004`, `1006`, `1007`, `1008`, `1009`, `1010`, `1012`, `1015`, `1017`, `1018` |
| 4 | SITEID | char | 3 | Study Site Identifier |  | 254 | 17 | 共 17 个不同值，前 12 个：`701`, `702`, `703`, `704`, `705`, `706`, `707`, `708`, `709`, `710`, `711`, `713` |
| 5 | SITEGR1 | char | 3 | Pooled Site Group 1 |  | 254 | 11 | `701`, `703`, `704`, `705`, `708`, `709`, `710`, `713`, `716`, `718`, `900` |
| 6 | ARM | char | 20 | Description of Planned Arm |  | 254 | 3 | `Placebo`, `Xanomeline High Dose`, `Xanomeline Low Dose` |
| 7 | TRT01P | char | 20 | Planned Treatment for Period 01 |  | 254 | 3 | `Placebo`, `Xanomeline High Dose`, `Xanomeline Low Dose` |
| 8 | TRT01PN | num | 8 | Planned Treatment for Period 01 (N) |  | 254 | 3 | `0`, `54`, `81` |
| 9 | TRT01A | char | 20 | Actual Treatment for Period 01 |  | 254 | 3 | `Placebo`, `Xanomeline High Dose`, `Xanomeline Low Dose` |
| 10 | TRT01AN | num | 8 | Actual Treatment for Period 01 (N) |  | 254 | 3 | `0`, `54`, `81` |
| 11 | TRTSDT | num | 8 | Date of First Exposure to Treatment | DATE. | 254 | 205 | 2012-07-09 – 2014-09-02 |
| 12 | TRTEDT | num | 8 | Date of Last Exposure to Treatment | DATE. | 254 | 214 | 2012-08-28 – 2015-03-05 |
| 13 | TRTDURD | num | 8 | Total Treatment Duration (Days) |  | 254 | 117 | 1 – 212 |
| 14 | AVGDD | num | 8 | Avg Daily Dose (as planned) |  | 254 | 48 | 0 – 78.6 |
| 15 | CUMDOSE | num | 8 | Cumulative Dose (as planned) |  | 254 | 118 | 0 – 15417 |
| 16 | AGE | num | 8 | Age |  | 254 | 36 | 51 – 89 |
| 17 | AGEGR1 | char | 5 | Pooled Age Group 1 |  | 254 | 3 | `65-80`, `<65`, `>80` |
| 18 | AGEGR1N | num | 8 | Pooled Age Group 1 (N) |  | 254 | 3 | `1`, `2`, `3` |
| 19 | AGEU | char | 5 | Age Units |  | 254 | 1 | `YEARS` |
| 20 | RACE | char | 32 | Race |  | 254 | 3 | `AMERICAN INDIAN OR ALASKA NATIVE`, `BLACK OR AFRICAN AMERICAN`, `WHITE` |
| 21 | RACEN | num | 8 | Race (N) |  | 254 | 3 | `1`, `2`, `6` |
| 22 | SEX | char | 1 | Sex |  | 254 | 2 | `F`, `M` |
| 23 | ETHNIC | char | 22 | Ethnicity |  | 254 | 2 | `HISPANIC OR LATINO`, `NOT HISPANIC OR LATINO` |
| 24 | SAFFL | char | 1 | Safety Population Flag |  | 254 | 1 | `Y` |
| 25 | ITTFL | char | 1 | Intent-To-Treat Population Flag |  | 254 | 1 | `Y` |
| 26 | EFFFL | char | 1 | Efficacy Population Flag |  | 254 | 2 | `N`, `Y` |
| 27 | COMP8FL | char | 1 | Completers of Week 8 Population Flag |  | 254 | 2 | `N`, `Y` |
| 28 | COMP16FL | char | 1 | Completers of Week 16 Population Flag |  | 254 | 2 | `N`, `Y` |
| 29 | COMP24FL | char | 1 | Completers of Week 24 Population Flag |  | 254 | 2 | `N`, `Y` |
| 30 | DISCONFL | char | 1 | Did the Subject Discontinue the Study? |  | 144 | 1 | `Y` |
| 31 | DSRAEFL | char | 1 | Discontinued due to AE? |  | 92 | 1 | `Y` |
| 32 | DTHFL | char | 1 | Subject Died? |  | 3 | 1 | `Y` |
| 33 | BMIBL | num | 8 | Baseline BMI (kg/m^2) |  | 253 | 122 | 13.7 – 40.1 |
| 34 | BMIBLGR1 | char | 6 | Pooled Baseline BMI Group 1 |  | 254 | 3 | `25-<30`, `<25`, `>=30` |
| 35 | HEIGHTBL | num | 8 | Baseline Height (cm) |  | 254 | 52 | 135.9 – 195.6 |
| 36 | WEIGHTBL | num | 8 | Baseline Weight (kg) |  | 253 | 116 | 34 – 108 |
| 37 | EDUCLVL | num | 8 | Years of Education |  | 254 | 19 | 3 – 24 |
| 38 | DISONSDT | num | 8 | Date of Onset of Disease | DATE. | 254 | 241 | 1998-06-13 – 2013-09-16 |
| 39 | DURDIS | num | 8 | Duration of Disease (Months) |  | 254 | 205 | 2.2 – 183.1 |
| 40 | DURDSGR1 | char | 4 | Pooled Disease Duration Group 1 |  | 254 | 2 | `<12`, `>=12` |
| 41 | VISIT1DT | num | 8 | Date of Visit 1 | DATE. | 254 | 207 | 2012-07-06 – 2014-08-29 |
| 42 | RFSTDTC | char | 20 | Subject Reference Start Date/Time |  | 254 | 205 | 共 205 个不同值，前 12 个：`2012-07-09`, `2012-07-20`, `2012-07-22`, `2012-07-29`, `2012-07-31`, `2012-08-05`, `2012-08-30`, `2012-09-02`, `2012-09-07`, `2012-09-08`, `2012-09-12`, `2012-09-15` |
| 43 | RFENDTC | char | 20 | Subject Reference End Date/Time |  | 254 | 211 | 共 211 个不同值，前 12 个：`2012-09-01`, `2012-09-02`, `2012-09-17`, `2012-09-29`, `2012-10-23`, `2012-11-06`, `2012-12-02`, `2012-12-06`, `2012-12-19`, `2012-12-24`, `2013-01-12`, `2013-01-14` |
| 44 | VISNUMEN | num | 8 | End of Trt Visit (Vis 12 or Early Term.) |  | 254 | 9 | `4`, `5`, `6`, `7`, `8`, `9`, `10`, `11`, `12` |
| 45 | RFENDT | num | 8 | Date of Discontinuation/Completion | DATE. | 254 | 211 | 2012-09-01 – 2015-03-05 |
| 46 | DCDECOD | char | 27 | Standardized Disposition Term |  | 254 | 9 | `ADVERSE EVENT`, `COMPLETED`, `DEATH`, `LACK OF EFFICACY`, `LOST TO FOLLOW-UP`, `PHYSICIAN DECISION`, `PROTOCOL VIOLATION`, `STUDY TERMINATED BY SPONSOR`, `WITHDRAWAL BY SUBJECT` |
| 47 | EOSSTT | char | 12 | End of Study Status |  | 254 | 2 | `COMPLETED`, `DISCONTINUED` |
| 48 | DCSREAS | char | 18 | Reason for Discontinuation from Study |  | 144 | 9 | `Adverse Event`, `Death`, `I/E Not Met`, `Lack of Efficacy`, `Lost to Follow-up`, `Physician Decision`, `Protocol Violation`, `Sponsor Decision`, `Withdrew Consent` |
| 49 | MMSETOT | num | 8 | MMSE Total |  | 254 | 15 | 10 – 24 |

## 说明

- 不同值不超过 12 个的变量直接列出全部取值；超过的给出范围。
- 带 `DATE*`/`YYMMDD*` 等日期格式的数值变量按 SAS 1960-01-01 纪元换算成 ISO 日期显示。
- 字符变量的前后空格已去除，与 SAS 侧 `strip()` 的口径一致。
