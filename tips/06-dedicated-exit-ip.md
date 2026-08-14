# 06 · 给 agy 单开一条专用出口线路，治好 "User location is not supported"

## 症状

用机场/共享代理跑 agy，跑着跑着报：

```
FAILED_PRECONDITION: User location is not supported for the API use
```

关键是它**不稳定**：同一个节点、同一个出口 IP，一轮对话里前几个请求正常返回，下一个就被拒，整轮被掐断。重开一轮可能又好了一会儿。

## 走过的弯路

- **换节点**——没用。实测换了 5 个日本节点，全部一样的间歇性失败。
- **怀疑是登录态过期**——不是。同一时刻浏览器登录正常，agy 交互模式也能起来。
- **怀疑是 agy 的 bug**——不是。同一条线路下的其他 Google 服务也会零星报同类错误。

## 真正的原因

机场节点是几百人共用的机房 IP 段。Google 的地理位置库对这类段的判定是**飘忽的**——同一个 IP 在不同请求里可能被判成不同区域，或者干脆判成"不支持的地区"。换节点无效，是因为一家机场的节点常常同属一个小机房段，在 Google 眼里是同一类东西。

独占、固定、有正经归属的自有服务器 IP，判定是稳定的。

## 方案

在一台自有海外服务器（我用的是腾讯云硅谷，任何 VPS 都行）上开一条 SSH 动态转发，做成本地 SOCKS5 代理，**只给 agy 用**，机器上其他一切照旧走原来的代理。

四个零件：

| 零件 | 干什么 |
|---|---|
| `scripts/agy-tunnel` | `ssh -N -D 127.0.0.1:7899` 开本地 SOCKS5；带 `up/down/status/ip` 四个子命令 |
| `scripts/agy-tunnel.plist.template` | launchd 服务，负责开机自启 + 掉线自动重连 |
| `scripts/agy-wrapper` | 装成 `~/.local/overrides/agy`，给 agy 注入 `https_proxy=socks5://127.0.0.1:7899`，然后 exec 真二进制 |
| shell PATH 配置 | 保证 `~/.local/overrides` 永远排在 PATH 第一，盖得住真二进制 |

**为什么不直接 `export https_proxy` 到 shell 里**：那会让这台机器上所有命令都走这条自有线路，一条小 VPS 带宽扛不住，也没必要。wrapper 的意义就是把这条线路精确地限定在 agy 一个进程上。

**通道挂了怎么办**：wrapper 会自动降级——先探 7899，不通就退回本机机场端口 7897，再不通就裸连。降级后 agy 还能用，只是又会偶发中断，所以定位问题时第一件事是 `agy-tunnel ip` 确认走的哪条。

## 安装

### 1. 服务器免密

**这是最容易卡住的一步**，隧道起不来九成是这里：

```bash
ssh-copy-id ubuntu@YOUR.SERVER.IP
# 验证（必须打印 ok，不能提示输密码）
ssh -o BatchMode=yes -o ConnectTimeout=10 ubuntu@YOUR.SERVER.IP 'echo ok'
```

`agy-tunnel` 用的是 `BatchMode=yes`，一旦需要交互输密码就直接失败，launchd 会陷入"起来→立刻退出→10 秒后再起"的循环，日志里全是这个。多台机器的话，**每台机器的公钥都要单独加一遍**。

### 2. 放脚本

```bash
mkdir -p ~/.local/bin ~/.local/overrides
cp scripts/agy-tunnel  ~/.local/bin/agy-tunnel
cp scripts/agy-wrapper ~/.local/overrides/agy
chmod +x ~/.local/bin/agy-tunnel ~/.local/overrides/agy
```

改 `~/.local/bin/agy-tunnel` 里的 `HOST=` 成你自己的服务器（或在 shell 里 `export AGY_TUNNEL_HOST=ubuntu@1.2.3.4`）。

真二进制留在 `~/.local/bin/agy`——wrapper 会先找 `agy-real`，找不到就用 `agy`，两种装法都兼容。

### 3. 装 launchd 服务（macOS）

```bash
sed "s|__AGY_TUNNEL__|$HOME/.local/bin/agy-tunnel|" \
  scripts/agy-tunnel.plist.template > ~/Library/LaunchAgents/local.agy-tunnel.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/local.agy-tunnel.plist
launchctl kickstart -k gui/$(id -u)/local.agy-tunnel
```

Linux 上换成 systemd user unit，`Restart=always` 即可。

### 4. PATH 排第一（zsh）

追加到 `~/.zshrc` **末尾**：

```zsh
# agy 专用出口：~/.local/overrides 必须排 PATH 第一，才能用 wrapper 盖住真二进制。
# 前面各处（pyenv / nvm / Antigravity 自己的安装脚本）都会 prepend PATH，
# 所以再挂个 precmd hook，每次提示符前把它顶回最前面。
export PATH="$HOME/.local/overrides:$PATH"
if [[ -o interactive ]]; then
  autoload -U add-zsh-hook 2>/dev/null
  _agy_overrides_path() { path=("$HOME/.local/overrides" ${path:#$HOME/.local/overrides}) }
  add-zsh-hook precmd _agy_overrides_path 2>/dev/null
fi
```

那个 precmd hook 不是多余的。Antigravity 的安装脚本自己会往 `~/.zshrc` 里加一行 prepend PATH，位置还不固定；只写一行 export 的话，哪天它插到你后面，wrapper 就静默失效了——agy 照样能跑，只是又开始间歇性报错，很难联想到是 PATH 顺序的问题。

## 验收清单

装完逐条过一遍，任何一条不对就别往下走：

```bash
# 1. 隧道在，且出口 IP 是你自己的服务器
agy-tunnel status          # → ✓ 通道在(127.0.0.1:7899)
agy-tunnel ip              # → 必须是你服务器的 IP，不是机场的

# 2. launchd 服务活着
launchctl print gui/$(id -u)/local.agy-tunnel | head -20   # → state = running

# 3. PATH 生效，agy 解析到 wrapper 而不是真二进制
zsh -lic 'echo ${path[1]}; whence -p agy'
# → /Users/你/.local/overrides
# → /Users/你/.local/overrides/agy

# 4. 真二进制还在（约 170MB，别不小心被 wrapper 覆盖了）
ls -la ~/.local/bin/agy ~/.local/bin/agy-real 2>&1

# 5. SOCKS5 代理本身通
curl -s --max-time 10 --proxy socks5h://127.0.0.1:7899 https://api.ipify.org
```

**怎么验证 wrapper 真的注入了环境变量**：别直接跑 agy 去试——它的登录令牌在系统钥匙串里，非交互终端跑不起来，你会误判成 wrapper 坏了。改成拿个桩程序替掉 exec 目标：

```bash
printf '#!/bin/sh\necho "ARGS: $*"\nenv | grep -i proxy | sort\n' > /tmp/stub.sh
chmod +x /tmp/stub.sh
sed "s|^REAL=.*|REAL=/tmp/stub.sh|; s|^\[ -x \"\$REAL\" \].*||" ~/.local/overrides/agy > /tmp/wt.sh
chmod +x /tmp/wt.sh && /tmp/wt.sh chat
```

应该打印出 8 个 proxy 变量，值都是 `socks5://127.0.0.1:7899`（不是 7897——是 7897 就说明隧道没通，wrapper 降级了）。

## 排障

| 现象 | 查这里 |
|---|---|
| `agy-tunnel status` 说通道不在 | `/tmp/agy-tunnel.log`。九成是 SSH 免密没配好，先手动跑上面那条 `BatchMode=yes` 的验证命令 |
| `agy-tunnel ip` 返回机场的 IP | 隧道没起，wrapper 降级了。同上 |
| launchd 服务反复重启 | 同样是 SSH 失败。`ThrottleInterval` 让它 10 秒一轮，日志会刷屏 |
| `whence -p agy` 指向 `~/.local/bin/agy` | PATH 里 overrides 没排第一，检查 `.zshrc` 末尾那段是不是被后面的 prepend 顶掉了 |
| 装了以后 agy 起不来 | 确认没把 wrapper 覆盖到 `~/.local/bin/agy`（真二进制约 170MB，几 KB 就是覆盖错了）。wrapper 里有自指防护会报错拦住 |

## 适用范围

不只 agy。任何"必须走干净固定出口、又不想全局改代理"的 CLI 都能套这套：改 wrapper 里的 `REAL` 指向和软链名字即可。
