# 02 · `agy -p`（print 模式）认证失效:交互能用、自动化全超时

> 版本:**agy 1.0.3**(macOS,2026-05-31 实测)。后续版本若修复,以实际为准。

## 现象

交互模式 `agy` 一切正常,但所有**非交互调用**都卡死、最后超时:

```
$ agy --dangerously-skip-permissions -p "一句话:国内有哪些零代码平台?"
Authentication required. Please visit the URL to log in:
  https://accounts.google.com/o/oauth2/auth?...&client_id=1071006060591-...
Waiting for authentication (timeout 30s)...
Error: authentication timed out.
```

影响面 = **所有走 print 模式的东西**:
- `agy -p` / `agy --print` 直接调用
- `agy-mcp`(`mcp__agy__ask` / `search` 等工具底层就是 `agy -p`)→ 600s 超时
- 任何 subprocess 封装(脚本、自动化、本项目 geo-radar 接 agy 平台)

## 根因

**print 模式和交互模式的 OAuth 凭证是隔离的。交互登录拿到的有效 token 不写回 print 模式读的 `~/.gemini/oauth_creds.json`。**

证据链:

```bash
# 1) 凭证文件停在很久以前、access_token 早已过期、交互登录后也不更新
ls -la ~/.gemini/oauth_creds.json          # mtime 停在登录那天,之后再登录也不变
python3 -c "import json,datetime as t; d=json.load(open('$HOME/.gemini/oauth_creds.json')); \
print('过期:', t.datetime.fromtimestamp(d['expiry_date']/1000))"   # 显示早已过期

# 2) 交互进程认证其实是有效的(在正常调 Google API)
ps aux | grep 'agy --dangerously' | grep -v grep      # 找到交互进程 PID
tail ~/.gemini/antigravity-cli/log/cli-*.log          # 看到 daily-cloudcode-pa.googleapis.com 正常请求
```

交互进程启动时用 `refresh_token` 在**内存里**刷新了 access_token、能正常工作,但**没落盘**到 `oauth_creds.json`。print 模式每次新起进程,只能读到那份过期凭证 → 触发全新 OAuth → 非交互环境无法完成 → 超时。

## 排查过的、**没用**的

- ❌ **杀进程**:清掉挂起的交互进程 + 所有 agy-mcp 僵尸,再跑 `agy -p` —— 照样弹 OAuth。
- ❌ **`agy update`**:已是最新 1.0.3,无更新。
- ❌ **重新交互登录**:登录成功(新交互进程在跑、认证有效),但 `oauth_creds.json` 的 mtime / `expiry_date` **纹丝不动** —— 实锤凭证不互通。
- ❌ **手动刷新 token**:用 `oauth_creds.json` 里的 `refresh_token` 向 `https://oauth2.googleapis.com/token` 刷新,Google 返回 `client_secret is missing`(client_secret 嵌在 Antigravity app 内,外部拿不到)。

## 现状对策

**没有干净的本地修复**(在 1.0.3 上):

- 自动化 / MCP / 任何 `agy -p` 调用 —— **暂时用不了**,只能等官方修。
- 真要在脚本里用 Gemini:绕开 agy,走 **Gemini 官方 API**(`generativelanguage.googleapis.com`,OpenAI 兼容)—— 但那是 **API key 按 token 计费**,不再是订阅额度,失去了用 agy 的意义。

## 验证是否已修复

新版装好后,直接:

```bash
agy --dangerously-skip-permissions --print-timeout 60s -p "say hi"
```

- 能正常返回 = 修好了。
- 仍弹 `Authentication required` + 超时 = 同一个 bug 还在,继续等。

---

*记录于 2026-05-31。起因:[money/geo-radar] 想把 agy(Gemini)接成 GEO 监测的一个采集平台,卡在 print 模式认证上。*
