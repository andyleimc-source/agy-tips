# 04 · print 模式在新目录/worktree 里秒超时:是「文件夹未信任」,不是认证挂了

> 版本:agy(macOS,2026-07-14 实测)。与 [02 · print 模式认证失效](02-print-mode-auth-bug.md) **是两回事**,别混。

## 现象

同一份已登录、平时能跑的 agy,换到一个**新目录**(尤其是 `git worktree`、临时目录、刚 clone 的仓库)里跑 `agy -p`,**秒 timeout、零输出**:

```
$ cd /path/to/repo/.worktrees/some-branch
$ agy --dangerously-skip-permissions --print-timeout 45m -p "干活"
Error: timeout waiting for response
```

交互模式在同一目录下会**弹一个「授权/信任这个文件夹」的框**;print 模式弹不出这个框 → 直接卡死超时。

## 和 tip 02 怎么区分(关键)

| | tip 02(认证失效) | 本条(文件夹未信任) |
|---|---|---|
| 交互模式弹什么 | Google OAuth 登录 URL | 「授权/信任此文件夹」 |
| 换个**已授权**目录跑 | 照样超时 | **正常返回** ← 决定性判据 |
| 根因 | OAuth token 不落盘 | 目录不在信任列表 |
| 能否本地修 | 1.0.3 上不能,等官方 | **能,见下** |

**一句话判据**:把同一条 `agy -p` 拿到一个**以前授权过的老目录**里跑——能返回就是本条(文件夹问题),还超时才是 tip 02(认证问题)。

## 根因

agy CLI 的信任文件夹列表在:

```
~/.gemini/antigravity-cli/settings.json  →  "trustedWorkspaces": [ ... ]
```

**是精确路径匹配,不认父目录前缀。** 即使 `/Users/you` 和 `/Users/you/repo` 都在列表里,它们的**子目录**(如 `/Users/you/repo/.worktrees/foo`)仍算未信任、仍会弹授权框。这就是为什么:

- 主仓库授权过 ≠ 它的 git worktree 授权过(worktree 是不同的绝对路径);
- 每开一个新 worktree / 临时目录,都得单独进一次信任列表。

`--dangerously-skip-permissions` 只跳**工具权限**,**不跳文件夹信任**——两套独立机制,别指望它兜底。

## 修复:起 agy 前把目标目录幂等塞进 trustedWorkspaces

手动一次性:

```bash
agy 在某目录能交互授权就先授权一次;或直接改配置。
```

自动化(脚本/CI/worktree 流水线里,起 agy 前先跑这段,幂等):

```bash
TARGET_DIR="$(pwd)"                                   # 或你要让 agy 干活的绝对路径
AGY_SETTINGS="$HOME/.gemini/antigravity-cli/settings.json"
if [ -f "$AGY_SETTINGS" ]; then
  python3 - "$AGY_SETTINGS" "$TARGET_DIR" <<'PY'
import json, sys
path, wt = sys.argv[1], sys.argv[2]
d = json.load(open(path))
tw = d.setdefault("trustedWorkspaces", [])
if wt not in tw:
    tw.append(wt)
    json.dump(d, open(path, "w"), indent=2, ensure_ascii=False)
    print("trusted:", wt)
PY
fi
# 之后再 agy --dangerously-skip-permissions -p "..." 就不会弹授权框了
```

要点:
- **写绝对路径**(agy 匹配的是 cwd 的绝对路径,不是相对路径)。
- **幂等**:已存在就不重复加。
- 改的是用户级配置文件,和被信任的仓库无关,不会污染仓库 git。

## 验证

在一个**从没授权过**的新目录里:

```bash
mkdir -p /tmp/agy-trust-test && cd /tmp/agy-trust-test
# 先跑上面那段把 /tmp/agy-trust-test 加进 trustedWorkspaces
agy --dangerously-skip-permissions --print-timeout 60s -p "只回复两个字:通过"
```

- 返回「通过」= 信任生效、修好了。
- 仍 `timeout waiting for response` = 要么路径没写对(检查 settings.json 里那条是不是这个目录的绝对路径),要么其实是 tip 02 的认证问题(拿老目录复测确认)。

---

*记录于 2026-07-14。起因:[sage] 的 agy 施工流水线 `agy-do.sh` 每张任务卡在独立 git worktree 里起 `agy -p`,首次进新 worktree 全部秒超时零施工;一度误判成 OAuth 失效(tip 02),实为 worktree 是新绝对路径、不在 trustedWorkspaces。根治=施工脚本起 agy 前把 worktree 路径自动加进信任列表。*
