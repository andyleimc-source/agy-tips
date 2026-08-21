# agy-tips

记录 [Google Antigravity CLI](https://antigravity.google)（命令 `agy`）的使用技巧、自动化脚本、踩坑笔记。

目标：把订阅额度（AI Pro / Ultra）压榨到极致，能自动化的事别再手点。

## 目录

- [01 · 用订阅额度自动生成图片](tips/01-image-gen-with-subscription.md)
- [02 · `agy -p`（print 模式）认证失效:交互能用、自动化全超时](tips/02-print-mode-auth-bug.md) ⚠ 1.0.3 已知 bug
- [03 · 让 agy 别再每步都问：默认自动批准所有工具权限](tips/03-auto-approve-all-permissions.md)
- [04 · print 模式在新目录/worktree 里秒超时：文件夹未信任（非认证问题）](tips/04-worktree-untrusted-folder-print-timeout.md)
- [05 · 施工模式：Claude Code 写卡 + agy 施工 + Claude 验收](tips/05-claude-drives-agy-construction-mode.md)
- [06 · 给 agy 单开一条专用出口线路，治好 "User location is not supported"](tips/06-dedicated-exit-ip.md)
- [07 · 终端 Markdown 渲染与排版避坑：为什么会看到 #### 与最佳排版姿势](tips/07-terminal-markdown-rendering.md)
- [08 · 专用出口 IP 也不一定稳：Google 判的是 ASN 归属，不是「独不独占」](tips/08-exit-ip-asn-not-just-dedicated.md)
- [09 · 隧道搭好了还是间歇性报错？大概率是调用方绕开了 wrapper](tips/09-callers-must-use-the-wrapper-not-the-binary.md)
- [10 · 让 Claude Code 和 agy 在同一目录协同：AGENTS.md 薄壳 + 单一真相源](tips/10-agents-md-shared-project-context.md)
- [11 · 自定义状态栏：一眼看到机型、执行模式、上下文余量和额度](tips/11-custom-statusline.md)
- [12 · 汉化 /resume 英文会话标题：包装层退出时自动异步回写 SQLite](tips/12-auto-translate-resume-titles.md)

## 脚本

- [`scripts/genimg.sh`](scripts/genimg.sh) — 一行命令出图
- [`scripts/agy-do`](scripts/agy-do) — 按任务卡派 agy 施工（worktree 隔离 + 逃逸检测 + 验收摘要，`--async` 后台跑）
- [`scripts/agy-runs`](scripts/agy-runs) — 列出后台施工：在跑 / 待验收 / 失败，见 tip 05
- [`scripts/agy-tunnel`](scripts/agy-tunnel) — 自有服务器 SOCKS5 出口（up/down/status/ip）
- [`scripts/agy-wrapper`](scripts/agy-wrapper) — 只给 agy 注入这条出口的代理外壳，通道断了自动降级；会话退出自动异步汉化标题
- [`scripts/agy-title-zh`](scripts/agy-title-zh) — 扫描并汉化 SQLite 会话标题，见 tip 12
- [`scripts/agy-tunnel.plist.template`](scripts/agy-tunnel.plist.template) — launchd 常驻（开机自启 + 掉线重连）
- [`scripts/statusline.sh`](scripts/statusline.sh) — 状态栏脚本，见 tip 11

## 适用环境

- macOS / Linux（zsh / bash）
- 已安装 Antigravity 桌面 app 或 CLI（`agy --version` 能跑）
- 已 OAuth 登录订阅账号（不是 API key）

## 贡献

欢迎 PR。新增技巧放 `tips/NN-标题.md`，并在本 README 加一行索引。
