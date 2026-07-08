# 03 · 让 agy 别再每步都问：默认自动批准所有工具权限

> 环境：agy（Antigravity CLI），macOS 实测 2026-07-08。

## 痛点

跑 agy 时它老停下来问你确认，最烦的是这种：

```
Accept this file edit?
> 1. Yes, accept this change
  2. No, reject this change
```

改一堆文件时每个都要按一下 Yes，自动化/施工场景直接被打断。

## 一次性开：命令行 flag

agy 自带一个全局 flag（`agy --help` 可见）：

```
--dangerously-skip-permissions   Auto-approve all tool permission requests without prompting
```

单次会话直接带上即可，不再弹任何权限确认：

```bash
agy --dangerously-skip-permissions -i "帮我重构这个模块"
```

> 相关但更弱的：`--mode accept-edits` 只自动批准**文件编辑**，命令执行等仍会问。要全部放行用 `--dangerously-skip-permissions`。

## 永久开：包一层 wrapper 默认注入

不想每次手打 flag，就用一个 wrapper 脚本把 `agy` 换成「永远带这个 flag」的版本。把 wrapper 放在 PATH 里比真正的 `agy` 更靠前（比如 `~/.local/overrides/agy`，真二进制留作 `~/.local/bin/agy-real`）：

```sh
#!/bin/sh
# agy wrapper：默认自动批准所有工具权限,别每步都停下来问
# 已手动带该 flag 时不重复注入;子命令(models/update/plugin…)也能安全带
case " $* " in
  *" --dangerously-skip-permissions "*)
    exec "$HOME/.local/bin/agy-real" "$@" ;;
  *)
    exec "$HOME/.local/bin/agy-real" --dangerously-skip-permissions "$@" ;;
esac
```

要点：

- **flag 放在参数最前**（子命令之前）。agy 把它当全局 flag，`agy models` / `agy update` 这类子命令也能安全容忍，不会报错。
- **带去重**：你手动再传 `--dangerously-skip-permissions` 也不会重复注入。
- 交互模式、`agy -p` print 模式、以及任何调 `agy` 的施工脚本，**全都自动生效**（因为都走这个 wrapper）。

装好后验证 flag 已默认带上：

```bash
agy models        # 正常列出模型 = wrapper 生效且没打断子命令
```

## 为什么没有「配置文件里开一下」

agy 目前没有明文的全局权限配置文件——权限是存在**每个会话的 protobuf**（`~/.gemini/antigravity-cli/implicit/*.pb`）里的，逐会话记忆，没有一个总开关 json 可改。所以「永久放行」只能靠上面的 flag / wrapper 这条路。

## 风险提示

flag 名字里的 `dangerously` 不是吓唬人：**它会放行 agy 的一切操作**，包括改文件、跑命令、删东西，全部不再问你。

- 适合：你信任当前工作区、在隔离的 worktree / 沙盒里跑、或就是要无人值守自动化。
- 想再加一层保险：叠加 `--sandbox`（终端受限沙盒运行），或只在特定项目目录用 wrapper、其他地方仍用原始 `agy`。

---

*记录于 2026-07-08。起因：施工时 agy 反复弹「Accept this file edit?」打断流程。*
