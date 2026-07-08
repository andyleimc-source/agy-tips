# agy-tips

记录 [Google Antigravity CLI](https://antigravity.google)（命令 `agy`）的使用技巧、自动化脚本、踩坑笔记。

目标：把订阅额度（AI Pro / Ultra）压榨到极致，能自动化的事别再手点。

## 目录

- [01 · 用订阅额度自动生成图片](tips/01-image-gen-with-subscription.md)
- [02 · `agy -p`（print 模式）认证失效:交互能用、自动化全超时](tips/02-print-mode-auth-bug.md) ⚠ 1.0.3 已知 bug
- [03 · 让 agy 别再每步都问：默认自动批准所有工具权限](tips/03-auto-approve-all-permissions.md)

## 脚本

- [`scripts/genimg.sh`](scripts/genimg.sh) — 一行命令出图

## 适用环境

- macOS / Linux（zsh / bash）
- 已安装 Antigravity 桌面 app 或 CLI（`agy --version` 能跑）
- 已 OAuth 登录订阅账号（不是 API key）

## 贡献

欢迎 PR。新增技巧放 `tips/NN-标题.md`，并在本 README 加一行索引。
