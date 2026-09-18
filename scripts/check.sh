#!/bin/bash
# 查一次指定门店（可临时覆盖：check.sh [门店号] [零件号...]）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
if [ $# -gt 0 ]; then STORE="$1"; shift; fi
if [ $# -gt 0 ]; then PARTS=("$@"); fi
NOW=$(date "+%m-%d %H:%M:%S")

if [ -z "${STORE:-}" ] || { [ ${#PARTS[@]} -eq 0 ] && [ -z "${FAMILY:-}" ]; }; then
  echo "[$NOW] 配置缺失：config.env 填 STORE+PARTS（或 FAMILY，需先 catalog.sh refresh）"; exit 2
fi

apw_warm
PARTS_Q=()
while IFS= read -r _l; do PARTS_Q+=("$_l"); done < <(apw_parts)
apw_query "$STORE" "${PARTS_Q[@]}"

if [ "$APW_CODE" != "200" ] || ! printf '%s' "$APW_BODY" | jq empty 2>/dev/null; then
  echo "[$NOW] 未知(原因: HTTP $APW_CODE 或响应非 JSON——被拦/限频/网络，停 10 分钟再查) — 不能当无货"
  exit 3
fi
N=$(printf '%s' "$APW_BODY" | jq -r '.body.stores | length')
if [ "$N" = "0" ]; then
  echo "[$NOW] 未知(原因: Apple 未返回门店——型号可能未开售/停售) — 不能当无货"
  exit 3
fi

ANY_IN=0
for p in "${PARTS_Q[@]}"; do
  DISPLAY=$(printf '%s' "$APW_BODY" | jq -r --arg p "$p" '.body.stores[0].partsAvailability[$p].pickupDisplay // empty')
  NAME=$(printf '%s' "$APW_BODY" | jq -r '.body.stores[0].storeName // "?"')
  ST=$(apw_classify "$DISPLAY")
  T=$(printf '%s' "$APW_BODY" | jq -r --arg p "$p" '.body.stores[0].partsAvailability[$p].messageTypes.regular.storePickupProductTitle // empty')
  [ -z "$T" ] && T="$p"   # Apple 没给机型名时退回零件号
  echo "[$NOW] $NAME($STORE) $T [$p] → $ST"
  if [ "$DISPLAY" = "available" ]; then
    ANY_IN=1
    if [ "$(apw_state_get "$STORE|$p")" != "available" ]; then
      apw_bark "📱有货了" "$NAME($STORE) $T 现在可到店取货" "$(apw_buy_url "$p")"
    fi
  fi
  apw_state_set "$STORE|$p" "$DISPLAY"
done
[ $ANY_IN -eq 1 ] && exit 0 || exit 1
