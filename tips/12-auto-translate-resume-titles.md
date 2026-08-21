# 12 · 汉化 /resume 英文会话标题：包装层退出时自动异步回写 SQLite

即使全流程使用中文与 agy 对话，敲 `/resume` 时弹出的历史会话列表依然全是一长串英文标题（如 `Partner Meeting Calendar Update`、`Dida Data Synchronization`），在终端选择和模糊搜索时极不直观。

## 根因

agy 底层在每个会话首轮交互后，会调用后台的总结服务（`GetCascadeConversationTitle`）生成会话标题。该 Prompt 在 Google 后端写死，强制输出 3-5 词的英文首字母大写（Title Case）短语，客户端未暴露任何语言偏好配置项。

## 发现与突破口

agy 的历史会话索引统一存储在本地 SQLite 数据库中：
- 文件路径：`~/.gemini/antigravity-cli/conversation_summaries.db`
- 数据表：`conversation_summaries`
- 关键字段：`preview`（即 `/resume` 交互列表中展示的标题和模糊搜索匹配项）

只要把 SQLite 里的 `preview` 字段更新为中文，`/resume` 就会立刻渲染为纯中文标题，且支持直接输入中文拼音/文字搜索。

## 解决方案

整套自动化由两部分构成：

### 1. 轻量汉化脚本（`scripts/agy-title-zh`）

扫描 `conversation_summaries.db`，提取所有未汉化的英文 `preview`，通过公共翻译接口毫秒级批量翻译成精简中文并写回数据库：

```bash
# 手动全量汉化一次历史记录
agy-title-zh -v
```

### 2. 包装层挂载退出钩子（`scripts/agy-wrapper`）

在 `agy-wrapper` 退出时，后台异步触发汉化脚本，零等待、不阻塞终端：

```bash
# ~/.local/overrides/agy (agy-wrapper) 末尾
set -- ${ADD_DIR:+--add-dir "$ADD_DIR"} "$@"
case " $* " in
  *" --dangerously-skip-permissions "*) "$REAL" "$@" ;;
  *) "$REAL" --dangerously-skip-permissions "$@" ;;
esac
RC=$?

# 会话退出后后台异步汉化会话标题，不阻塞终端
( which agy-title-zh >/dev/null 2>&1 && agy-title-zh >/dev/null 2>&1 & )

exit $RC
```

## 效果对比

| 原生英文标题 | 自动汉化后 |
|---|---|
| `Partner Meeting Calendar Update` | `合作伙伴会议日历更新` |
| `Dida Data Synchronization` | `嘀嗒数据同步` |
| `Ghostty AGY Font Color Issue` | `Ghostty AGY 字体颜色问题` |
| `Conference Sponsorship Invoice Processing` | `会议赞助发票处理` |
| `PingCAP Wxcli Task Review` | `PingCAP Wxcli 任务回顾` |
