# 体验课完课率看板

**每次部署必须先归档，禁止覆盖或删除历史快照。** 使用 [部署流程](DEPLOYMENT.md) 中的脚本。

所有时间维度数据统一使用 `python3 refresh_dashboard.py` 一键刷新；新增看板模块必须同时接入这条链路，不依赖人工下载原始数据。详见 [数据刷新说明](DATA_REFRESH.md)。

[历史版本目录](https://shenludidi-eng.github.io/trial-lesson-completion/archive/) 保存发布前和发布后的独立页面。

Dino English 体验课 L1–L4 完课率看板。可按 UTC 时间窗、人群国家、年龄、英文能力筛选，并对照上一相同周期。

2026-10-26 展示更新：新增土耳其（Türkiye）国家筛选和核心国家对照。土耳其只统计 2026-10-16 00:00:00 UTC 起的进课；10/19–10/25 为第一周，不显示上期数值及涨跌幅。从 10/26–11/01 这一周起，在对照窗也落入首周及以后的情况下恢复对比。其他国家保持原有对比规则。麦克风权限事件未加入漏斗；本次未重新取数。

国家覆盖核验：体验课完课率与漏斗、体验课课后练习、正式课课后练习、Dino 助手使用，以及分日、年龄、英文能力、设备、开口和首句回复统计均纳入土耳其。V1/V2 国家画像改用统一国家列表，确保土耳其不因样本少而被归入“其他”。历史录音反馈中已有土耳其筛选及 3 条分析样本；该区仍使用自身历史样本和独立筛选，不代表本周新增录音数。本次不刷新录音分析。

打开 GitHub Pages 即可查看，无需安装依赖。右上角可切换中文 / English，默认中文。

https://shenludidi-eng.github.io/trial-lesson-completion/

页顶可切换「体验课完课率」「体验课课后练习完成情况」「正式课课后练习完成情况」「体验课课中 Dino 助手使用情况」和「全部练习题表现」。课后练习不并进完课率，单独统计。正式课页只看 L1–L4 正式课，不含 732 / 1615 / 734 / 733 / 1661 / 1616。一课通常有词句 / 口语 / 听力三练，分别看进入占比和完成率；完课且三练都完成同时看占开课、占完课。进入某练=开启该练任务 / 解锁该练任务（9/21 后完课每课各解锁 1 个）。进入任意一个是三类进入的并集，不低于任一单练进入。课后练习漏斗可切整体 / 三类；整体末步是完成任一课后练习，三类只看开始了→完成了。1.8.0 自 2026-09-21 起计入可练分母。

数据覆盖 2026-08-01 00:00:00 至 2026-10-26 02:12:59 UTC。测试账号继续排除。完课只看 `trigger + type=trial + result=complete`。默认快捷窗口是近 7 个完整 UTC 日（现为 10/19–10/25）。L1–L4 的 Template 触达漏斗按 V1 / V2 分 Level Tab；V1 导入拆成「引出课程视频 / 播放课程视频 / 引出词汇教学视频」，V2 导入拆成「欢迎学生+课程介绍 / 播放课程视频 / 引出词汇教学视频」。L1 的 V1 已下架，漏斗默认只展示 V2，右侧「展示V1」可展开对照，展开后 V1 在左、V2 在右。导入三步按 lead-in 内 pre-video / video / post-video 计。欢迎/引出课程视频看进入 pre-video；播放课程视频看完成 video；引出词汇教学视频看完成 post-video，或已经开始单词教学视频。不占用后面的「单词教学视频」「教词 1 / 单词教学」。L1 的教词 1/2/3 分别显示为 apple / bread / juice。L2 V2 的教词/泡泡/选词/口测 1/2/3 分别显示为 cow / cat / horse，口测与 L1 一样写成口语测评。导入三步标签完整展示，不再缩略。「版本对比 · V1 vs V2」不在顶部 Tab，默认折叠，标题右侧点展开。年龄 × 级别 × 完课率矩阵紧挨在分日完课率上面。分日 × 国家段在沙特右侧是日本。核心国家是马来/越南/韩国/沙特/日本，只写完课率、占比和是否低于本级别，不再写「把整体往下拉」。版本对比保留三个完课率数字；L2–L4 下面是 V1 / V2 进入用户的年龄、英文能力、国家、设备系统占比，L1 不展示画像。年龄 × 英文能力在 9/14 后窗口先看单岁交叉，下面再看历史年龄段。矩阵行 3–12、14、15 岁（不含 13 岁）、列 L1–L4，完课率大于等于 50% 标绿，小于等于 30% 标红。

上一版备份（数据同样至 2026-10-06 02:13:15 UTC，V1 导入前两步仍按进入 pre-video / 完成 pre-video）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-06-0213-v1-pre-same.html

更早一版（数据同样至 2026-10-06 02:13:15 UTC，导入三步仍共用同一个 lead-in 触达）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-06-0213-leadin-same.html

更早一版（数据同样至 2026-10-06 02:13:15 UTC，L1 漏斗仍默认并列 V1 / V2）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-06-0213-leadin3.html

更早一版（数据同样至 2026-10-06 02:13:15 UTC，导入仍是单步，矩阵 ≥50% 标绿）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-06-0213-ge50.html

更早一版（数据同样至 2026-10-06 02:13:15 UTC，矩阵仍是大于 50% 才标绿）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-06-0213.html

更早一版（数据至 2026-10-01 17:48:40 UTC）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-01-1748-live.html

更早一版（数据同样至 2026-10-01 17:48:40 UTC，焦点国家分析仍带「把整体往下拉」）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-01-1748.html

更早一版（数据至 2026-10-01 17:13:33 UTC，布局已是折叠版本对比 + 年龄×级别在分日上面）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-01-1713-collapse.html

更早一版（数据同样至 2026-10-01 17:13:33 UTC，版本对比仍在顶部 Tab、年龄×级别矩阵还在核心年龄段后面）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-10-01-1713.html

更早一版（数据至 2026-09-30 11:14:22 UTC）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-30-1114-labels.html

更早一版（数据同样至 2026-09-30 11:14:22 UTC，尚无年龄×级别矩阵）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-30-1114.html

更早一版（数据至 2026-09-29 12:13:21 UTC）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-29-1213.html

更早一版（数据至 2026-09-29 02:13:57 UTC，年龄 × 英文能力已拆单岁/历史段）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-29-0213-age-ability.html

更早一版（数据同样至 2026-09-29 02:13:57 UTC，年龄 × 英文能力仍是一段表）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-29-0213-l1-hide-profile.html

更早一版（数据同样至 2026-09-29 02:13:57 UTC，L1 也展示画像）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-29-0213-l1-profile.html

更早一版（数据同样至 2026-09-29 02:13:57 UTC，版本对比仍是完课率柱+表）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-29-0213-version-tabs.html

更早一版（数据同样至 2026-09-29 02:13:57 UTC，默认窗口仍是 9/14 至今）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-29-0213.html

更早一版（数据至 2026-09-28 02:10:40 UTC，漏斗仅 L1 分版本）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-28-0210-l1-funnel.html

更早一版（数据同样至 2026-09-28 02:10:40 UTC，仍带 wrap-up 勾选框）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-28-0210.html

更早一版（数据至 2026-09-27 05:10:54 UTC）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-27-0510.html

更早一版（数据至 2026-09-24 10:11:35 UTC）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-24-1011.html

更早一版（数据至 2026-09-24 03:13:03 UTC）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-24-0313.html

更早一版（数据至 2026-09-23 03:47:28 UTC，已排除这三个测试账号）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-23-test-filter.html

更早一版（仍含这三个测试环境账号的 12 节课）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-23-before-test-filter.html

更早一版（分析文案已更新，核心年龄柱改为绿色之前）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-23-analysis.html

更早一版（2026-09-23 数据已刷新，分析文案与升降用词更新前）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-23-data.html

更早一版（2026-09-23 数据刷新前，含漏斗平均耗时 / 沙特对照）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-23.html

再早一版（2026-09-22 凌晨，含漏斗、不含平均耗时 / 沙特对照）：

https://shenludidi-eng.github.io/trial-lesson-completion/archive/2026-09-22.html

最近一次数据重算：2026-10-30 09:24 UTC。体验课 22,086 节，事件截止 2026-10-30 09:13:53 UTC；正式课 4,081 节，事件截止 2026-10-30 08:53:23 UTC；练习分析截止 2026-10-30 UTC。
