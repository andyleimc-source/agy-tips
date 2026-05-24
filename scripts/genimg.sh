#!/usr/bin/env bash
# 用法: ./genimg.sh "提示词" [输出路径]
# 默认输出到 ~/Desktop/<时间戳>.png
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "用法: $0 \"提示词\" [输出路径]" >&2
  exit 1
fi

prompt="$1"
out="${2:-$HOME/Desktop/$(date +%s).png}"

agy -p "${prompt}，保存到 ${out}" --dangerously-skip-permissions
echo "→ ${out}"
