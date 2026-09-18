#!/bin/bash
# 前台持续蹲守：watch.sh [间隔秒]（默认 60，下限 30——Apple 按出口 IP 限频）
DIR="$(cd "$(dirname "$0")" && pwd)"
INTERVAL=${1:-60}; [ "$INTERVAL" -lt 30 ] && INTERVAL=30
echo "=== apple-stock 蹲守开始：每 ${INTERVAL}s 一轮（Ctrl-C 停止）==="
trap 'echo; echo "=== 已停止 ==="; exit 0' INT TERM
while true; do
  "$DIR/check.sh" && echo "*** 有货！去买 ***"
  echo "--- 下一轮 ${INTERVAL}s 后 ---"
  sleep "$INTERVAL"
done
