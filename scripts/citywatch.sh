#!/bin/bash
# citywatch.sh —— 单次城市监控拍（供 launchd 定时调用，也可手动跑）
# 用法: citywatch.sh "北京 北京" MJTD4CH/A MJYC4CH/A ...
# 每次只跑一拍：查一次→比对状态→变有货推 Bark→退出。心跳由 launchd 负责。
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
LOC=${1:-}
if [ $# -gt 0 ]; then shift; fi
if [ $# -gt 0 ]; then PARTS=("$@"); fi
TS=$(date "+%m-%d %H:%M:%S")
if [ -z "$LOC" ] || [ ${#PARTS[@]} -eq 0 ]; then
  echo "[$TS] 用法: citywatch.sh \"省 市\" 零件号..."; exit 2
fi

# ---- 541 冷却自律：冷却期内直接跳过，不发请求 ----
if apw_in_cooldown; then
  echo "[$TS] 冷却中，本拍跳过（剩 ${APW_COOLDOWN_LEFT}s）"; exit 0
fi

apw_warm
apw_query "loc:$LOC" "${PARTS[@]}"
IS_JSON=0; printf '%s' "$APW_BODY" | jq empty 2>/dev/null && IS_JSON=1
# 541 / 200但非JSON（拦截页）= 被拦 → 进入 10 分钟冷却
if [ "$APW_CODE" = "541" ] || { [ "$APW_CODE" = "200" ] && [ $IS_JSON -eq 0 ]; }; then
  apw_enter_cooldown 600
  echo "[$TS] 被拦（HTTP $APW_CODE）→ 进入 600s 冷却，期间自动跳过"; exit 3
fi
if [ "$APW_CODE" != "200" ] || [ $IS_JSON -eq 0 ]; then
  echo "[$TS] 心跳：未知(HTTP $APW_CODE 或非JSON)——不当无货"; exit 3
fi
N=$(printf '%s' "$APW_BODY" | jq -r '.body.stores | length')
if [ "$N" = "0" ]; then
  echo "[$TS] 心跳：0 店（location 被拒，可稍后重试或换邻城）"; exit 3
fi

# ---- 逐拍结构化落盘（放货规律分析的数据底座） ----
PARTS_JSON=$(printf '%s\n' "${PARTS[@]}" | jq -R . | jq -sc .)
printf '%s' "$APW_BODY" | jq -c --argjson parts "$PARTS_JSON" --arg ts "$TS" --arg loc "$LOC" '
  {ts:$ts, loc:$loc, stores:[.body.stores[] | {no:.storeNumber, name:.storeName,
    parts:([(.partsAvailability // {}) | to_entries[] | select(.key as $k | any($parts[]; . == $k))
           | {(.key):(.value.pickupDisplay // "")}] | add // {})}]}' >> "$VAR/beats.jsonl"
# 节流：超 2 万行保留最近 1 万
if [ "$(wc -l < "$VAR/beats.jsonl" 2>/dev/null || echo 0)" -gt 20000 ]; then
  tail -n 10000 "$VAR/beats.jsonl" > "$VAR/beats.jsonl.t" && mv "$VAR/beats.jsonl.t" "$VAR/beats.jsonl"
fi

printf '%s' "$APW_BODY" | jq -c --argjson parts "$PARTS_JSON" \
  '.body.stores[] | {no:.storeNumber, name:.storeName,
     st:[(.partsAvailability // {}) | to_entries[] | select(.key as $k | any($parts[]; . == $k))
        | {key:.key, d:(.value.pickupDisplay // ""), t:(.value.messageTypes.regular.storePickupProductTitle // "?")}]}' \
| while IFS= read -r line; do
    NO=$(printf '%s' "$line" | jq -r '.no'); NAME=$(printf '%s' "$line" | jq -r '.name')
    printf '%s' "$line" | jq -c '.st[]' | while IFS= read -r st; do
      P=$(printf '%s' "$st" | jq -r '.key'); D=$(printf '%s' "$st" | jq -r '.d'); T=$(printf '%s' "$st" | jq -r '.t')
      KEY="$NO|$P"; OLD=$(apw_state_get "$KEY")
      if [ "$D" = "available" ] && [ "$OLD" != "available" ]; then
        echo "[$TS] 🎯 HIT $NAME($NO) $T [$P]"
        apw_bark "📱有货了" "$NAME($NO) $T 现在可到店取货"
      fi
      apw_state_set "$KEY" "$D"
    done
  done
echo "[$TS] 心跳：$LOC $N 店查完"
