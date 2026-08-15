# 09 · 自定义状态栏：一眼看到机型、执行模式、上下文余量和额度

> 环境：agy（Antigravity CLI）`settings.json` 支持 `statusLine`，macOS/Linux 实测 2026-08-15。

## 效果

三行信息，不用敲命令就能看清当前会话状态：

```
mkp · Desktop/myread
3.7 Flash · exec med skip · ctx 95% · 5h 93% ~02:44 · 7d 92%
出兵决策全员态度梳理
```

- 第一行：机器名 · 当前目录（有 git 分支/worktree 时会带出来，颜色区分）
- 第二行：模型简称 · 执行模式(exec/plan/accept) + 推理强度(low/med/high) + 沙箱状态 · 上下文剩余百分比 · 5 小时额度余量与恢复时间 · 7 天额度余量
- 第三行：当前会话在干什么（一句话，跟 Claude Code 的状态栏标题联动，同一个会话在两边看到的是同一句话）

## 配置方式

`~/.gemini/antigravity-cli/settings.json` 里加：

```json
{
  "statusLine": {
    "type": "command",
    "command": "/path/to/statusline.sh"
  }
}
```

agy 会把当前会话的 JSON 状态（`model`、`context_window`、`quota`、`mode`、`workspace` 等字段）通过 stdin 喂给这个脚本，脚本只管拼字符串输出到 stdout。

## 脚本要点

完整脚本见 [`scripts/statusline.sh`](../scripts/statusline.sh)，核心逻辑：

1. **模型简称**：`jq -r '.model.display_name'` 拿到 `"Gemini 3.7 Flash (Medium)"`，用 `sed` 剥掉厂商前缀和括号备注，只留 `3.7 Flash`。
2. **上下文余量**：`.context_window.remaining_percentage`，四舍五入成整数百分比。
3. **额度**：`.quota["gemini-5h"]` / `.quota["gemini-weekly"]`（`remaining_fraction` + `reset_in_seconds`），换算成"还剩多少 % · 几点恢复"；同时兼容 Claude Code 风格的 `.rate_limits.five_hour` 字段，两边共用一份脚本逻辑更省事。
4. **执行模式**：`.mode` 映射成 `exec`/`plan`/`accept` 三态；`.model.effort` 拿推理强度；`.sandbox.enabled` 判断是否沙箱。
5. **会话标题**：读 `~/.claude/session-title/<session_id>` 的第一行——这是 Claude Code 那边按会话维护的一句话任务标题（见配套 CLAUDE.md 规则："每轮识别当前核心事项，写入这个文件"）。agy 和 Claude Code 共用同一份文件，**同一个项目目录来回切换司机，状态栏标题不会丢**。
6. **中日韩字符宽度**：标题截断用了个 `cw`（char width）函数按 Unicode 区间判断全角/半角，避免中文标题被从字中间切断。

## 为什么这么设计

- **不重复造轮子**：字段名同时兼容 agy 原生的 `quota.gemini-*` 和 Claude Code 风格的 `rate_limits.*`，同一份脚本两边都能用（如果你也在 Claude Code 里配了类似的 statusline）。
- **裸 shell，不装依赖**：只用 `jq`（唯一外部依赖，`brew install jq`）+ POSIX shell 内置命令，跨机器同步不用担心环境缺东西。
- **颜色用 ANSI 转义手写**，不依赖终端能力探测——朴素但兼容性最好。

---

*记录于 2026-08-15。*
