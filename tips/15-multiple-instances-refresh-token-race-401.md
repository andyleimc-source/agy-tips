# 15 · 开太多 agy 实例会互相踢下线：OAuth token 刷新竞争导致 401

`Agent execution terminated due to error` 这句话没有任何信息量，看着像网络断了。我为它查了一整轮代理线路（成果见 tips/14），最后发现这次的直接原因跟网络无关：**同时开着的多个 agy 实例，在互相刷掉对方的登录状态。**

## 症状

agy 任务中途终止，只有一句：

```
Agent execution terminated due to error.
Error ID: 5346b817-...
```

那个 Error ID 是**服务端的**，本地日志里一次都搜不到，别指望靠它定位。真原因要去翻 `~/.gemini/antigravity-cli/log/cli-*.log`（agy 默认就在写，不用额外开 `--log-file`）：

```
E0828 16:07:00 errorreport.go:223] agent executor error: calling model:
  UNAUTHENTICATED (code 401): Request had invalid authentication credentials.
  Expected OAuth 2 access token, login cookie or other valid authentication credential.
```

401，不是超时，不是 connection refused。线路是通的，是**凭据**在请求发出的那一刻已经失效了。

## 根因：token 只有一份，刷新的却有很多个

登录态存在 `~/.gemini/antigravity-cli/antigravity-oauth-token`，**全局一份**。而每个跑着的 agy 实例都自带一个后台协程，按自己的节奏每小时刷一次这个 token。

日志里能直接看到两个不同实例各刷各的（前面那串数字是 goroutine id，不同实例不同）：

```
I0828 11:06:19  70  browser.go:259] token refreshed, new expiry=12:06:18
I0828 12:06:18  70  browser.go:259] token refreshed, new expiry=13:06:17
I0828 13:06:29  13  browser.go:259] token refreshed, new expiry=14:06:28
I0828 14:06:21  70  browser.go:259] token refreshed, new expiry=15:06:20
```

OAuth 刷新会让上一个 access token 作废。于是 A 刷完，B 手里那个就是废的，B 下一次调模型就吃 401——而这时候 B 可能正跑到任务一半。

出事时机器上有 **8 个 agy 实例活着，其中两个已经挂了 29 小时**，全是开完忘了关的。这个 401 在我几周的日志里只出现过 3 次，但这 3 次全部集中在实例最多的时候。

## 排查时踩的两个坑

**1. 别用 `grep -i antigravity` 数实例。** 进程名就叫 `agy`，这么 grep 会得到 0 个，然后你就会得出「没有实例在跑」的错误结论，接着放心去重启隧道。我就这么干了一次。正确姿势：

```sh
ps -Ao pid,etime,%cpu,command | grep '[.]local/bin/agy '
```

**2. Error ID 不在本地日志里。** 前面说过了，但值得再说一次——很容易在它上面浪费时间。

## 处理

写了个 `scripts/agy-ps`，列出所有活着的实例并标出闲置的（CPU 近似 0 且存活超 2 小时），`-k` 清掉：

```
$ agy-ps
PID      存活         CPU%   工作目录
13115    01-05:15:04    0.0    ~/coding/dailymd  ← 闲置
92683    04:33          72.5   ~/coding/dailymd
15381    07:25:59       0.0    ~/coding/mingzhi  ← 闲置
...
要清掉标了「闲置」的：agy-ps -k
```

⚠ 解析 `etime` 别偷懒数冒号：它有 `MM:SS` / `HH:MM:SS` / `D-HH:MM:SS` 三种格式，按冒号个数判断「超过 2 小时」会把 90 分钟（`01:30:00`，同样两个冒号）也算进去。老实换算成秒。

另外在 `scripts/agy-wrapper` 里加了个启动告警：实例数 ≥ 3 就喊一嗓子，把这个坑挡在发生之前。

## 结论

- **`Agent execution terminated due to error` 是个占位符，不是诊断。** 每次都去翻 `cli-*.log` 里的 `errorreport.go`，那里才有真话。
- **401 和网络问题在这句话下面长得一模一样**，但方向完全相反：一个查代理，一个查有几个实例在跑。先看日志再动手，能省一整轮排查。
- 共享单份凭据的 CLI，**多开就是竞争**。tmux 里开完就走、忘了关的会话，是这类问题最常见的来源。

## 涉及脚本改动

新增 `scripts/agy-ps`；`scripts/agy-wrapper` 增加并发实例启动告警。
