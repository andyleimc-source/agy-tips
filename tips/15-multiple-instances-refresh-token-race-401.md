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

写了个 `scripts/agy-ps`，列出所有活着的实例、标出没人用的，`-k` 清掉：

```
$ agy-ps
PID     存活       最后说话   工作目录        状态
13115   01-05:38:24  08-27 13:36   ~/coding/dailymd   闲置 ← 可杀 · ok 落盘进度
92683   27:53        08-28 16:44   ~/coding/dailymd   在用 · ok 收工
26658   25:09        从未输入      ~/coding/dailymd   在用
15381   07:49:19     08-28 09:18   ~/coding/mingzhi   闲置 ← 可杀 · 然后用 2 和 3 分别合成
68742   06:34:39     08-28 16:08   ~/coding/dailymd   在用 · 继续
```

⚠ **「闲不闲」不能看进程存活时长，也不能看 CPU。** 我第一版就是这么写的（CPU≈0 且存活 > 2 小时），一跑就当场误判：一个开了 6.5 小时、45 分钟前还在对话的会话被标成僵尸，而一个刚开 25 分钟、还没来得及说第一句话的被算成在用。三个直觉都是错的：

- 存活久 ≠ 没在用；
- CPU≈0 ≠ 没在用——agy 等你打字的时候就是 0%；
- **日志还在写 ≠ 有人在用**——后台刷 token 和配额的心跳一直在写日志，这个最有迷惑性。

唯一靠得住的判据是**最后一次人类输入**：用 `lsof` 定位每个实例自己的 `cli-*.log`，取最后一条 `HandleUserInput` 的时间戳，从那里算多久没动静。顺带把最后那句话打出来，一眼就能认出是哪个会话——比 PID 有用得多。

（日志时间戳形如 `I0828 16:47:31`，只有月日时分秒、没有年份，换算时要自己补当前年份。）

另外在 `scripts/agy-wrapper` 里加了个启动告警：实例数 ≥ 3 就喊一嗓子，把这个坑挡在发生之前。

## 结论

- **`Agent execution terminated due to error` 是个占位符，不是诊断。** 每次都去翻 `cli-*.log` 里的 `errorreport.go`，那里才有真话。
- **401 和网络问题在这句话下面长得一模一样**，但方向完全相反：一个查代理，一个查有几个实例在跑。先看日志再动手，能省一整轮排查。
- 共享单份凭据的 CLI，**多开就是竞争**。tmux 里开完就走、忘了关的会话，是这类问题最常见的来源。

## 涉及脚本改动

新增 `scripts/agy-ps`；`scripts/agy-wrapper` 增加并发实例启动告警。
