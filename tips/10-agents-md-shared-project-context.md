# 08 · 让 Claude Code 和 agy 在同一目录协同：AGENTS.md 薄壳 + 单一真相源

> 场景：同一个项目目录，有时用 Claude Code 开工，有时额度用完了换 agy 接手当"司机"，或者派 agy 去干体力活（施工模式）。两边都得看得懂项目规则，又不想维护两份会写岔的文档。

## 痛点

Claude Code 认 `CLAUDE.md`，agy（Antigravity/Gemini 系）默认认 `AGENTS.md`（项目级）和 `GEMINI.md`（全局 + 项目级都会找）。如果项目里只有 `CLAUDE.md`，agy 在这个目录里等于**读不到任何项目规则**——所有边界、约定、禁止事项对它都是空气。

真实事故：2026-08-15，agy 在一个只有 `CLAUDE.md`、没有 `AGENTS.md` 的项目里执行 `book-to-skill`，因为看不到项目边界规则，机械套用了它自己全局规则里"skills 要放 dotfiles 才能跨机器同步"的条文，把整个上游工具仓库和生成的知识库都装进了 `~/dotfiles` 并且**自己 push 到了远端**，越权操作了项目之外的仓库。

## 方案：AGENTS.md 当薄壳，CLAUDE.md 当唯一真相源

不要把 `CLAUDE.md` 的内容复制一份到 `AGENTS.md`（两份内容迟早会写岔）。而是让 `AGENTS.md` 只做三件事：

1. 声明 `./CLAUDE.md` 是唯一真相源，指示 agy 完整读一遍
2. 列一份"忽略清单"——Claude Code 专属、agy 执行不了的机制（记忆系统、子代理、TaskCreate、statusLine 等），省得它自作聪明假装能做
3. 列一份"照做清单"——两边都要遵守的硬约束，**最重要的一条：生成的文件/skill 一律留在项目内，禁止碰 `~/dotfiles` 或任何全局目录**，除非用户明确要求跨机器共享

```markdown
# AGENTS.md — agy（Antigravity/Gemini）等施工方 CLI 在本项目的入口（薄壳）

> 单一真相源 = `./CLAUDE.md`（项目规则正本）。本文件不复制内容，只定角色和差异。

**第一步：完整读 `./CLAUDE.md`**，项目规则以它为准。同时遵守全局 `~/.claude/CLAUDE.md`（协作偏好等）。读到你执行不了的机制时按下表处理：

## 忽略清单（Claude Code 专属，你无法执行，跳过即可）

- Claude 的记忆系统、子代理（Agent/Task 委派）、会话内 TaskCreate 待办
- SessionStart hook 注入的专属上下文机制、`statusLine`
- Skill / slash 命令触发词——本项目 `.claude/skills/` 你不一定读得到，读不到就说没有，别假装调得到

## 照做清单（与 Claude 同一标准）

- **生成的文件 / skill 一律落在本项目内，禁止碰 `~/dotfiles` 或任何全局 skills 目录**，除非用户明确要求跨机器共享
- 花钱动作（LLM/搜索 API、云资源）执行前必须向用户确认
- 不确定直说不确定，不要猜

⚠ 非交互（`-p`/print）模式下默认没有工作区，读不到本文件——调用时必须带 `--add-dir <本项目绝对路径>`（另见 [04 · print 模式在新目录/worktree 里秒超时](04-worktree-untrusted-folder-print-timeout.md)）。
```

## 进阶：项目本身有"司机/施工方"双 AI 分工时

如果项目已经在用 driver-builder 模式（Claude 派 agy 去隔离 worktree 里干活，比如 `scripts/agy-do.sh <任务号>`），`AGENTS.md` 开头再加一段"模式判断"，让 agy 先分清自己是被脚本调起的施工方，还是用户直接开的交互司机——两种模式看的文件完全不同（施工模式只看任务卡，司机模式才读 `CLAUDE.md` 全文）：

```markdown
## 模式判断

- **施工模式**：被 `scripts/agy-do.sh` 调起、当前目录在 `.worktrees/<任务号>/` 里、prompt 让你按任务卡施工 → **只看任务卡本身**，本文件其余部分与你无关。
- **司机模式**：用户直接在项目根开你交互干活 → 按下面的规则来。
```

## 落地方式

- **无软链关系**：`AGENTS.md` 是独立维护的文件（内容极短，改动频率低），不建议用 symlink 全量指向 `CLAUDE.md`（那样等于把 `CLAUDE.md` 的所有 Claude 专属内容也塞给 agy，噪音大）。
- **如果嫌两份文件麻烦**：可以反过来，把 `GEMINI.md` symlink 到 `AGENTS.md`（`ln -s AGENTS.md GEMINI.md`），agy 无论认哪个名字都读到同一份薄壳内容。

---

*记录于 2026-08-15。起因：agy 越权把项目内容 push 进 `~/dotfiles` 的事故复盘。*
