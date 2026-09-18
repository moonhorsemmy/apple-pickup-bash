#!/bin/bash
# 一次查同城全部门店（location 模式）：city.sh "省 市" [零件号...]
# 注意：nearby 半径大、跨城重叠；响应可能带邻市门店（按需取用，聚合要去重）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
LOC=${1:-}
if [ $# -gt 0 ]; then shift; fi
if [ $# -gt 0 ]; then PARTS=("$@"); fi
NOW=$(date "+%m-%d %H:%M:%S")
if [ -z "$LOC" ] || { [ ${#PARTS[@]} -eq 0 ] && [ -z "${FAMILY:-}" ]; }; then
  echo "用法: city.sh \"省 市\" [零件号...]（大陆必须「省 市」格式；catalog.sh cities 列全表）"; exit 2
fi

apw_warm
PARTS_Q=()
while IFS= read -r _l; do PARTS_Q+=("$_l"); done < <(apw_parts)
apw_query "loc:$LOC" "${PARTS_Q[@]}"

if [ "$APW_CODE" != "200" ] || ! printf '%s' "$APW_BODY" | jq empty 2>/dev/null; then
  echo "[$NOW] 未知(原因: HTTP $APW_CODE 或响应非 JSON) — 不能当无货"; exit 3
fi
N=$(printf '%s' "$APW_BODY" | jq -r '.body.stores | length')
if [ "$N" = "0" ]; then
  echo "[$NOW] 未知(原因: 该 location 返回 0 店——格式不对或被拒；换邻城 nearby 或逐店查) — 不能当无货"; exit 3
fi
echo "[$NOW] $LOC → $N 家店："
printf '%s' "$APW_BODY" | jq -c '.body.stores[] | {no:.storeNumber, name:.storeName,
  av:[.partsAvailability // {} | to_entries[] | select(.value.pickupDisplay=="available")
      | {part:.key, title:(.value.messageTypes.regular.storePickupProductTitle // "")}]}' \
| while IFS= read -r line; do
    NO=$(printf '%s' "$line" | jq -r '.no'); NAME=$(printf '%s' "$line" | jq -r '.name')
    CNT=$(printf '%s' "$line" | jq -r '.av | length')
    echo "-- $NAME($NO)：$CNT 个 SKU 有货"
    printf '%s' "$line" | jq -r '.av[] | "   \(.title)  [\(.part)]"'
    printf '%s' "$line" | jq -r '.av[] | .part' | while IFS= read -r p; do
      if [ "$(apw_state_get "$NO|$p")" != "available" ]; then
        apw_bark "📱有货了" "$NAME($NO) $p 可到店取货" "$(apw_buy_url "$p")"
        apw_state_set "$NO|$p" "available"
      fi
    done
  done
