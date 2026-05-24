# 01 · 用订阅额度自动生成图片

**场景**：想在自己的代码/脚本里调 Nano Banana 生成图片，又不想付 API key 的钱——直接复用已经买的 AI Pro / Ultra 订阅额度。

## 为什么不用 SDK

官方 `google-antigravity` Python SDK 只支持 `GEMINI_API_KEY`，等于按量付费。**SDK 这条路省不了钱。**

要走订阅，只能用 CLI（`agy`），因为 CLI 支持 OAuth 登录。

## 一行命令

```bash
agy -p "生成一张 1024x1024 的小狗照片，背景蓝色渐变，保存到 ~/Desktop/dog.png" \
    --dangerously-skip-permissions
```

关键 flag：

| flag | 作用 |
|------|------|
| `-p` / `--print` / `--prompt` | 非交互模式，跑完就退出 |
| `--dangerously-skip-permissions` | **必须加**。否则 agent 调写文件/图像工具时会卡在权限确认，非交互模式没人按 y |

## 前置检查

```bash
# 1) 确认登录的是订阅账号（OAuth），不是 API key
agy plugin list

# 2) 图像生成插件装了没（默认可能没带 Nano Banana）
agy plugin list | grep -iE "image|banana|nano"
```

如果第 2 步空的，去 Antigravity 桌面 app 的 plugin marketplace 找 Nano Banana 装上，CLI 会共享配置。

## 封装成可复用脚本

见 [`scripts/genimg.sh`](../scripts/genimg.sh)：

```bash
./scripts/genimg.sh "提示词" ./out/x.png
```

业务代码里直接 shell out 调用，Node/Python 都行：

```js
// Node
const { execSync } = require('child_process');
execSync(`~/scripts/genimg.sh "${prompt}" "${outPath}"`);
```

```python
# Python
import subprocess
subprocess.run(["~/scripts/genimg.sh", prompt, out_path], check=True, shell=False)
```

## 坑

- **配额不是无限**。Nano Banana Pro 图像有独立日配额，2026 年 2 月收紧过。Ultra $200/月 也别指望刷无限张。
- **CI/服务器**跑要先在本地 OAuth 登录一次，把 `~/.antigravity/`（或对应凭证目录）同步过去；token 过期得手动 refresh。
- `--dangerously-skip-permissions` 名字虽然吓人，但非交互模式下不加根本跑不动。生产环境注意提示词来源可信。
