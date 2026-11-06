# ADAE 变量字典

数据文件：`dummy_study/data/adae.sas7bdat`　观测数：**1191**　变量数：**55**

由 `dummy_study/tools/build_variable_dictionary.py` 生成，请勿手工编辑。
标签/类型/长度/格式来自 `variables/descriptors.csv`（SAS `PROC CONTENTS`）；取值分布来自数据本身。

## 变量一览

| # | 变量 | 类型 | 长度 | 标签 | 格式 | 非缺失 | 不同值 | 取值 / 范围 |
| ---: | --- | --- | ---: | --- | --- | ---: | ---: | --- |
| 1 | STUDYID | char | 12 | Study Identifier |  | 1191 | 1 | `CDISCPILOT01` |
| 2 | SITEID | char | 3 | Study Site Identifier |  | 1191 | 17 | 共 17 个不同值，前 12 个：`701`, `702`, `703`, `704`, `705`, `706`, `707`, `708`, `709`, `710`, `711`, `713` |
| 3 | USUBJID | char | 11 | Unique Subject Identifier |  | 1191 | 225 | 共 225 个不同值，前 12 个：`01-701-1015`, `01-701-1023`, `01-701-1028`, `01-701-1034`, `01-701-1047`, `01-701-1097`, `01-701-1111`, `01-701-1115`, `01-701-1118`, `01-701-1130`, `01-701-1133`, `01-701-1146` |
| 4 | TRTA | char | 20 | Actual Treatment |  | 1191 | 3 | `Placebo`, `Xanomeline High Dose`, `Xanomeline Low Dose` |
| 5 | TRTAN | num | 8 | Actual Treatment (N) |  | 1191 | 3 | `0`, `54`, `81` |
| 6 | AGE | num | 8 | Age |  | 1191 | 35 | 51 – 89 |
| 7 | AGEGR1 | char | 5 | Pooled Age Group 1 |  | 1191 | 3 | `65-80`, `<65`, `>80` |
| 8 | AGEGR1N | num | 8 | Pooled Age Group 1 (N) |  | 1191 | 3 | `1`, `2`, `3` |
| 9 | RACE | char | 32 | Race |  | 1191 | 3 | `AMERICAN INDIAN OR ALASKA NATIVE`, `BLACK OR AFRICAN AMERICAN`, `WHITE` |
| 10 | RACEN | num | 8 | Race (N) |  | 1191 | 3 | `1`, `2`, `6` |
| 11 | SEX | char | 1 | Sex |  | 1191 | 2 | `F`, `M` |
| 12 | SAFFL | char | 1 | Safety Population Flag |  | 1191 | 1 | `Y` |
| 13 | TRTSDT | num | 8 | Date of First Exposure to Treatment | DATE. | 1191 | 187 | 2012-07-09 – 2014-09-02 |
| 14 | TRTEDT | num | 8 | Date of Last Exposure to Treatment | DATE. | 1191 | 193 | 2012-08-28 – 2015-03-05 |
| 15 | ASTDT | num | 8 | Analysis Start Date | DATE. | 1180 | 427 | 1994-04-01 – 2014-11-03 |
| 16 | ASTDTF | char | 1 | Analysis Start Date Imputation Flag |  | 15 | 1 | `D` |
| 17 | ASTDY | num | 8 | Analysis Start Relative Day |  | 1180 | 178 | -6970 – 194 |
| 18 | AENDT | num | 8 | Analysis End Date | DATE. | 718 | 280 | 2012-08-03 – 2014-10-31 |
| 19 | AENDY | num | 8 | Analysis End Relative Day |  | 718 | 145 | -2 – 211 |
| 20 | ADURN | num | 8 | Analysis Duration (N) |  | 714 | 75 | 1 – 444 |
| 21 | ADURU | char | 3 | Analysis Duration Units |  | 714 | 1 | `DAY` |
| 22 | AETERM | char | 46 | Reported Term for the Adverse Event |  | 1191 | 242 | 共 242 个不同值，前 12 个：`ABDOMINAL DISCOMFORT`, `ABDOMINAL PAIN`, `ACROCHORDON EXCISION`, `ACTINIC KERATOSIS`, `AGITATION`, `ALCOHOL USE`, `ALLERGIC GRANULOMATOUS ANGIITIS`, `ALOPECIA`, `AMNESIA`, `ANXIETY`, `APPLICATION SITE BLEEDING`, `APPLICATION SITE DERMATITIS` |
| 23 | AELLT | char | 46 | Lowest Level Term |  | 1191 | 326 | 共 326 个不同值，前 12 个：`ABDOMINAL CRAMPS`, `ABDOMINAL DISCOMFORT`, `ABDOMINAL PAIN`, `ABRASION NOS`, `ABRASIONS`, `ACTINIC KERATOSIS`, `AGITATION`, `ALCOHOL USE`, `ALK PHOS RAISED`, `ALLERGIC GRANULOMATOSIS`, `ALLERGY`, `ANKLE EDEMA` |
| 24 | AELLTCD | num | 8 | Lowest Level Term Code |  | 0 | 0 | （全部缺失） |
| 25 | AEDECOD | char | 46 | Dictionary-Derived Term |  | 1191 | 242 | 共 242 个不同值，前 12 个：`ABDOMINAL DISCOMFORT`, `ABDOMINAL PAIN`, `ACROCHORDON EXCISION`, `ACTINIC KERATOSIS`, `AGITATION`, `ALCOHOL USE`, `ALLERGIC GRANULOMATOUS ANGIITIS`, `ALOPECIA`, `AMNESIA`, `ANXIETY`, `APPLICATION SITE BLEEDING`, `APPLICATION SITE DERMATITIS` |
| 26 | AEPTCD | num | 8 | Preferred Term Code |  | 0 | 0 | （全部缺失） |
| 27 | AEHLT | char | 8 | High Level Term |  | 1191 | 242 | 共 242 个不同值，前 12 个：`HLT_0003`, `HLT_0005`, `HLT_0008`, `HLT_0012`, `HLT_0013`, `HLT_0016`, `HLT_0018`, `HLT_0019`, `HLT_0020`, `HLT_0025`, `HLT_0026`, `HLT_0027` |
| 28 | AEHLTCD | num | 8 | High Level Term Code |  | 0 | 0 | （全部缺失） |
| 29 | AEHLGT | char | 9 | High Level Group Term |  | 1191 | 242 | 共 242 个不同值，前 12 个：`HLGT_0004`, `HLGT_0005`, `HLGT_0007`, `HLGT_0008`, `HLGT_0011`, `HLGT_0012`, `HLGT_0013`, `HLGT_0015`, `HLGT_0017`, `HLGT_0020`, `HLGT_0030`, `HLGT_0032` |
| 30 | AEHLGTCD | num | 8 | High Level Group Term Code |  | 0 | 0 | （全部缺失） |
| 31 | AEBODSYS | char | 67 | Body System or Organ Class |  | 1191 | 23 | 共 23 个不同值，前 12 个：`CARDIAC DISORDERS`, `CONGENITAL, FAMILIAL AND GENETIC DISORDERS`, `EAR AND LABYRINTH DISORDERS`, `EYE DISORDERS`, `GASTROINTESTINAL DISORDERS`, `GENERAL DISORDERS AND ADMINISTRATION SITE CONDITIONS`, `HEPATOBILIARY DISORDERS`, `IMMUNE SYSTEM DISORDERS`, `INFECTIONS AND INFESTATIONS`, `INJURY, POISONING AND PROCEDURAL COMPLICATIONS`, `INVESTIGATIONS`, `METABOLISM AND NUTRITION DISORDERS` |
| 32 | AESOC | char | 67 | Primary System Organ Class |  | 1191 | 23 | 共 23 个不同值，前 12 个：`CARDIAC DISORDERS`, `CONGENITAL, FAMILIAL AND GENETIC DISORDERS`, `EAR AND LABYRINTH DISORDERS`, `EYE DISORDERS`, `GASTROINTESTINAL DISORDERS`, `GENERAL DISORDERS AND ADMINISTRATION SITE CONDITIONS`, `HEPATOBILIARY DISORDERS`, `IMMUNE SYSTEM DISORDERS`, `INFECTIONS AND INFESTATIONS`, `INJURY, POISONING AND PROCEDURAL COMPLICATIONS`, `INVESTIGATIONS`, `METABOLISM AND NUTRITION DISORDERS` |
| 33 | AESOCCD | num | 8 | Primary System Organ Class Code |  | 0 | 0 | （全部缺失） |
| 34 | AESEV | char | 8 | Severity/Intensity |  | 1191 | 3 | `MILD`, `MODERATE`, `SEVERE` |
| 35 | AESER | char | 1 | Serious Event |  | 1191 | 2 | `N`, `Y` |
| 36 | AESCAN | char | 1 | Involves Cancer |  | 1191 | 2 | `N`, `Y` |
| 37 | AESCONG | char | 1 | Congenital Anomaly or Birth Defect |  | 1191 | 1 | `N` |
| 38 | AESDISAB | char | 1 | Persist or Signif Disability/Incapacity |  | 1191 | 2 | `N`, `Y` |
| 39 | AESDTH | char | 1 | Results in Death |  | 1191 | 2 | `N`, `Y` |
| 40 | AESHOSP | char | 1 | Requires or Prolongs Hospitalization |  | 1191 | 2 | `N`, `Y` |
| 41 | AESLIFE | char | 1 | Is Life Threatening |  | 1191 | 2 | `N`, `Y` |
| 42 | AESOD | char | 1 | Occurred with Overdose |  | 1191 | 1 | `N` |
| 43 | AEREL | char | 8 | Causality |  | 1187 | 4 | `NONE`, `POSSIBLE`, `PROBABLE`, `REMOTE` |
| 44 | AEACN | char | 1 | Action Taken with Study Treatment |  | 0 | 0 | （全部缺失） |
| 45 | AEOUT | char | 26 | Outcome of Adverse Event |  | 1191 | 3 | `FATAL`, `NOT RECOVERED/NOT RESOLVED`, `RECOVERED/RESOLVED` |
| 46 | AESEQ | num | 8 | Sequence Number |  | 1191 | 23 | 1 – 23 |
| 47 | TRTEMFL | char | 1 | Treatment Emergent Analysis Flag |  | 1126 | 1 | `Y` |
| 48 | AOCCFL | char | 1 | 1st Occurrence within Subject Flag |  | 218 | 1 | `Y` |
| 49 | AOCCSFL | char | 1 | 1st Occurrence of SOC Flag |  | 550 | 1 | `Y` |
| 50 | AOCCPFL | char | 1 | 1st Occurrence of Preferred Term Flag |  | 781 | 1 | `Y` |
| 51 | AOCC02FL | char | 1 | 1st Occurrence 02 Flag for Serious |  | 3 | 1 | `Y` |
| 52 | AOCC03FL | char | 1 | 1st Occurrence 03 Flag for Serious SOC |  | 3 | 1 | `Y` |
| 53 | AOCC04FL | char | 1 | 1st Occurrence 04 Flag for Serious PT |  | 3 | 1 | `Y` |
| 54 | CQ01NAM | char | 19 | Customized Query 01 Name |  | 493 | 1 | `DERMATOLOGIC EVENTS` |
| 55 | AOCC01FL | char | 1 | 1st Occurrence 01 Flag for CQ01 |  | 152 | 1 | `Y` |

## 说明

- 不同值不超过 12 个的变量直接列出全部取值；超过的给出范围。
- 带 `DATE*`/`YYMMDD*` 等日期格式的数值变量按 SAS 1960-01-01 纪元换算成 ISO 日期显示。
- 字符变量的前后空格已去除，与 SAS 侧 `strip()` 的口径一致。
