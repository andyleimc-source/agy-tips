# 09 · 隧道搭好了还是间歇性报错？大概率是调用方绕开了 wrapper

跟 tips/06、08 配套的踩坑记录:出口隧道和 wrapper 都装对了,`agy-tunnel status`/`agy-tunnel ip` 也确认通道是通的,但某个 skill 或脚本跑起来还是偶发 `User location is not supported`。查了半天,问题不在隧道，在调用方自己绕开了 wrapper。

## 症状

- 手动在终端跑 `agy -p "..."` 一切正常(因为交互 shell 里 PATH 排序对,解析到的是 wrapper)
- 同一个 prompt 换成脚本/Claude Code 的 Bash 工具跑,时不时报地区错误
- 报错不是每次都出现，跟 tips/06 描述的"共享 IP 判定飘忽"症状一模一样，容易被误判成"隧道也不是百分百稳"

## 根因

装 wrapper 的方式是把它放在 `~/.local/overrides/agy`，靠 **PATH 顺序**排在真二进制 `~/.local/bin/agy` 前面。这个机制只在"按命令名 `agy` 走 PATH 解析"的调用方式下生效。

两类调用方式会跳过它，且不会报任何错——因为路径本身是存在的、可执行的，只是导流失效了：

1. **写死了二进制的绝对路径**：不管是某个 skill 文档里的示例命令、还是 Python 脚本里 `shutil.which("agy") or "/Users/andy/.local/bin/agy"` 这种写法——`shutil.which` 在某些非交互/非登录场景下 PATH 不含 overrides 目录，直接落到硬编码的 fallback，从此稳定绕开 wrapper。
2. **非交互 SSH / cron / launchd 等场景的 PATH 本来就不含 `~/.local/overrides`**（这个坑本身也是个已知陷阱，跟 mac-sync 那条"非交互 ssh PATH 不含 /opt/homebrew/bin"是同一类问题）。

第 1 类最隐蔽：代码逻辑看起来完全合理("先找 PATH 里的 agy，找不到再退回已知路径")，实际效果却是**优先级反了**——`shutil.which` 在 PATH 不含 overrides 时找到的可能压根不是 wrapper，最后兜底又落回裸二进制。

## 修法

调用方自己判断优先级，不要依赖 `shutil.which`/PATH 解析的默认顺序：**显式先探测 `~/.local/overrides/agy` 是否存在，存在就用它，不存在才退回其他方式**。

```python
from pathlib import Path
import shutil

_override = Path.home() / ".local" / "overrides" / "agy"
AGY_BIN = str(_override) if _override.exists() else (shutil.which("agy") or str(Path.home() / ".local" / "bin" / "agy"))
```

Shell 脚本同理：

```bash
if [ -x "$HOME/.local/overrides/agy" ]; then
  AGY_BIN="$HOME/.local/overrides/agy"
else
  AGY_BIN="$(command -v agy || echo "$HOME/.local/bin/agy")"
fi
```

## 排查清单

装了 tips/06 那套隧道之后，任何新写的调用 agy 的脚本/skill 文档，加进代码审查/验收清单里过一遍：

- [ ] 有没有硬编码 `~/.local/bin/agy`（裸二进制）当首选或兜底优先于 override？
- [ ] 有没有依赖 `shutil.which("agy")` / `command -v agy` 的默认返回值，却没显式测过 override 路径？
- [ ] 这段调用会不会跑在非交互 shell（cron、launchd、Claude Code 的 Bash 工具、SSH 非交互命令）里？这些场景的 PATH 未必含 `~/.local/overrides`。

## 教训来源

2026-08-15，一个批量生图 skill（文档里直接写死了裸二进制路径当"推荐用法"，理由是"避免 zsh 函数在非交互 shell 里报错"——这个理由本身没错，但选错了替代路径，绕过了 wrapper 而不是绕过 zsh 函数）间歇性生图失败，排查后发现同一个 prompt 换成 wrapper 路径立刻稳定成功。顺手排查了另外两个用 `shutil.which("agy") or "~/.local/bin/agy"` 写法的 Python 脚本，属于同一类风险，一并改掉。
