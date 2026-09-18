#!/bin/bash
# 到货停止后重新开始监控：清 STOP 标记 + 重置状态基线 + 清冷却
# 说明：重置后若目标当前就有货，下一拍会立即复核并再次推送（这是预期行为）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
rm -f "$VAR/STOP" "$VAR/state.txt" "$VAR/cooldown.until"
echo "已恢复监控：STOP/状态/冷却已清空，下一拍重新开始（若当前有货会再次推送）"
