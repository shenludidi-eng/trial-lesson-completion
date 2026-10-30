# 数据刷新与历史版本

每次发布必须保留发布前和发布后两份独立 HTML 快照。主链接显示最新版，历史页面保留当时的数据与计算逻辑。

1. 获取远端 `main` 最新版本，再执行 `python3 refresh_dashboard.py` 统一刷新原看板与练习分析的所有时间数据。延用当前看板口径：独立课堂、窗口内任意一次进课、排除测试账号、体验课完课取 `trigger + type=trial + result=complete`。刷新课后练习、开口轮次、首轮回复、Dino 助手、设备、正式课及全部练习题模块。
2. 记录数据源实际最新事件时间。页面上的数据截止时间不能直接用脚本执行时间代替。
3. 用下列脚本准备发布；时间参数传入本次元数据中的实际 UTC 截止时间：

```sh
python3 tools/prepare_deployment.py \
  --source /absolute/path/to/体验课完课率看板.html \
  --data-end 'YYYY-MM-DD HH:MM:SS' \
  --formal-data-end 'YYYY-MM-DD HH:MM:SS'
```

脚本会新增带 UTC 微秒时间和 SHA-256 前缀的 `before`、`release` 快照及 JSON 发布记录。使用排他创建，遇到同名文件就失败，不覆盖。`archive/index.html` 是可更新的历史目录，其他历史 HTML 不得修改、删除或复用文件名。

4. 检查页面四个标签、筛选、关键数字和历史链接，确认已有快照无变化。只提交 `index.html`、新增快照、发布记录、历史目录及必要的文档/工具；不要提交凭证、原始数据、用户 ID 或对话文本。
5. 提交并正常推送 `main`，禁止强制推送。远端有新提交时，先同步并重新基于最新首页创建快照。
6. 等待 GitHub Pages 成功，确认部署提交与刚推送提交一致，并核验线上首页及历史快照内容。

历史入口：https://shenludidi-eng.github.io/trial-lesson-completion/archive/

生产刷新入口已统一为仓库根目录的 `refresh_dashboard.py`。新模块不得建立人工下载步骤；必须将参数化 SQL、聚合产物、校验和回滚同时接入该命令。
