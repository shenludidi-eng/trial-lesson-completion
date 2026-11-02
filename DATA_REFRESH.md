# 看板一键数据刷新

在本目录执行：

```bash
python3 refresh_dashboard.py
```

这一个命令会：

1. 调用原有的 BigQuery 取数链路，更新体验课完课、引导、课后练习、Dino 助手、学生回合、首次回答、正式课课后练习和设备系统数据。
2. 更新“全部练习题表现”的课中、课后、国家、Level、年龄和能力日粒度数据。
3. 从 `student_class.lesson_version` 更新 L1 V3 / V4 对比数据，覆盖看板全部历史日期。
4. 将香港与澳门的不同原始写法统一合并为「港澳」，并与泰国一起更新到筛选、核心国家对比、画像、分时/分日和练习题国家分析；同样覆盖全部历史日期。
5. 检查查询量、CSV 字段、日期范围和 HTML 必需模块；只有全部通过后才覆盖本地看板文件。
6. 保留 `.refresh-runs/<UTC时间>/manifest.json` 供核对，但不会自动提交、push 或部署。

L1 版本与开课通过 `class_id` 关联，覆盖看板从 `2026-08-01 00:00:00 UTC` 起的全部历史日期。原看板的结构版本 V2 在生产环境实际是 V3，
因此全部改名为 V3；`lesson_version=4` 的课堂从 V3 中拆出为 V4。新课堂如果 ODS
尚未同步，会暂按原直接导入结构留在 V3；下次运行同一条命令会自动将已同步的 V4 拆出。

技术同学可在 Archery 用 `student_class` 表核查，例如
`SELECT * FROM student_class WHERE lesson_id = 732 AND lesson_version IN (3, 4)`。
本地一键刷新读取 BigQuery ODS 中的同名 `student_class` 副本并执行相同字段口径，
这样不需要人工从 Archery 下载再导入。

## 常用命令

```bash
# 刷新全部时间数据
python3 refresh_dashboard.py

# 上次原看板刷新中断后继续
python3 refresh_dashboard.py --resume

# 只快速更新练习分析和 L1 V3/V4
python3 refresh_dashboard.py --exercise-only

# 不查库，只检查当前产物
python3 refresh_dashboard.py --validate-only
```

## 数据口径

- 截止日默认是脚本运行时的 UTC 当日；看板最终显示查询结果中真实的最大日期，不会把脚本运行时间冒充为数据时间。
- 国家口径在每次刷新后自动归一：香港和澳门（含 `Hong Kong` / `HK` / `Macau` / `Macao` 等常见写法）合并为「港澳」；泰国纳入核心国家。该规则同时作用于所有历史课堂和练习题国家数据。
- 客观题使用“通关所需作答次数”，核心指标是一次通过率、第 2/3/4+ 次通过分布、平均次数及 P50/P90，不使用 `result` 事件正答率。
- Archery 中的题型名单/模板映射属于非时间维表，当前保留已核对的快照；看板上会随时间变动的指标都由 BigQuery 在这个命令中重算。只有课程模板配置变更时，才需要另行更新 Archery 快照。

## 首次使用

如果提示未配置数据库登录，先在原维护工作区运行一次 `登录数据库.command`，用有 BigQuery 权限的账号登录。之后日常只需要上面的一个刷新命令。

## 新需求接入规则

以后新增的看板模块如果包含时间维度，必须同时接入 `refresh_dashboard.py`：

1. 生产 SQL 放在仓库中，日期使用参数，不硬编码截止日。
2. 仅产出看板需要的聚合数据，不依赖人工下载原始明细。
3. 加入查询量保护、字段校验、日期不回退校验和失败回滚。
4. `python3 refresh_dashboard.py` 必须继续能够一次更新旧模块和所有新模块。
