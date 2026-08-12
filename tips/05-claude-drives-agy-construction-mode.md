# 05 · 施工模式：Claude Code 写卡 + agy 施工 + Claude 验收

**问题**：Claude Code 直接写实现是 token 大户，一个中等功能几万 token 起步。而 agy 走 OAuth 吃 Google AI Pro/Ultra **订阅额度**，写代码这件事对它是"包月不额外计费"的。

**做法**：把角色拆开——

| 谁 | 干什么 |
|---|---|
| Claude（司机） | 写任务卡、审 diff、跑验证、合并、写返工要求 |
| agy（施工） | 严格照卡实现 + 自检 + commit |

Claude 自己上手的只剩：几行小修、架构判断、tricky 逻辑、写卡本身、验收。

起子脚本：[`scripts/agy-do`](../scripts/agy-do)，用法 `agy-do <任务卡文件> [--here]`。

## 四个真踩过坑才有的设计

**1. worktree 隔离 + 逃逸检测。** agy 有把 worktree 里的 `.git` 指针文件解析回主仓、直接往主分支提交的前科。脚本在施工前后各拍一次快照（主分支 HEAD + 主仓脏文件列表），事后比对报警。**只报警不自动回滚**——并行会话可能同时在推进主分支，自动 revert 比逃逸本身更危险。

**2. 开工前把工作目录写进 `trustedWorkspaces`。** agy 的信任是精确路径匹配、不认父目录前缀，所以主仓被信任不代表新建的 worktree 被信任。未信任的目录在 print 模式下弹不出信任框 → 秒超时零输出，很容易被误判成 OAuth 失效（详见 [04](04-worktree-untrusted-folder-print-timeout.md)）。`--dangerously-skip-permissions` 只跳工具权限，不跳文件夹信任。

**3. `--here` 逃生口。** Tauri / Xcode / 大 node_modules 这类项目，新建 worktree 意味着重新装依赖、重新全量编译，比省下来的 token 更亏。`--here` 原地干，代价是没有隔离，所以脚本强制要求开工时工作区干净——否则事后分不清哪些改动是 agy 写的。

**4. 参数顺序：`--print-timeout` 必须放在 `-p` 前面。** `-p/--print` 会把紧跟其后的 token 当成 prompt 值吃掉。

## 施工指令里值得写死的几条

- **工作区钉死**：写清唯一允许读写的绝对路径，要求开工先 `pwd` 自证，发现自己在工作区外就零写操作、写回执后停。
- **卡里的前提自己复核**：卡写「这个函数只被 X 调用」，agy 不会去 grep 验证，照卡删就可能打断活路径。要求它施工前自己核一遍。
- **断言归零靠删除，不许靠改名**：验收条件写成"grep 某符号零命中"时，agy 会把活生产函数改个名来让它归零。
- **有歧义写回执别猜**：约定在任务卡末尾追加 `## agy 回执`，脚本事后 grep 这个标题提醒司机。
- **禁区文件清单**：progress / plan / decision / handoff 这类流水文档一律别碰，否则会被顺手写进施工 commit。

## commit 署名

用 `GIT_AUTHOR_NAME=agy GIT_AUTHOR_EMAIL=agy@antigravity` 硬标记，别指望它记得自己署名。之后 `git log --author=agy` 一查就知道哪些代码是施工方写的、该重点审哪些。
