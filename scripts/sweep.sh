#!/bin/bash
# 全国扫描：哪个版本货最多（接口无数值库存，"货最多"=有货门店数）
# 用法: sweep.sh [家族名，默认 iphone-18-pro，逗号分隔可多个]；SWEEP_LIMIT=N 截断测试
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
FAM="${1:-iphone-18-pro}"
PACE="${SWEEP_PACE:-4}"
OUT="$VAR/sweep-$(date +%Y%m%d-%H%M).jsonl"

PARTS_Q=()
while IFS= read -r _p; do PARTS_Q+=("$_p"); done < <(
  echo "$FAM" | tr ',' '\n' | while IFS= read -r f; do
    jq -r --arg f "$f" '.[] | select(.family==$f) | .data.products[].partNumber' "$DATA/products_$LOCALE.json"
  done)
[ ${#PARTS_Q[@]} -eq 0 ] && { echo "家族 $FAM 查不到零件号（先 catalog.sh refresh）"; exit 2; }
CITIES=()
while IFS= read -r _c; do CITIES+=("$_c"); done < <("$DIR/catalog.sh" cities)
echo "=== 全国扫描：${#CITIES[@]} 城 × ${#PARTS_Q[@]} 零件号，间隔 ${PACE}s（$(date '+%H:%M:%S') 起）==="

apw_warm
> "$OUT"; UNK=0; CONSEC=0; DONE_C=0
for LOC in "${CITIES[@]}"; do
  if [ -n "${SWEEP_LIMIT:-}" ] && [ "$DONE_C" -ge "$SWEEP_LIMIT" ]; then break; fi
  apw_query "loc:$LOC" "${PARTS_Q[@]}"
  if [ "$APW_CODE" != "200" ] || ! printf '%s' "$APW_BODY" | jq empty 2>/dev/null; then
    echo "$LOC → HTTP$APW_CODE 未知（可能被拦）"; UNK=$((UNK+1)); CONSEC=$((CONSEC+1))
    if [ $CONSEC -ge 2 ]; then echo "!! 连续异常，疑似 541 限频——中止，10 分钟后再扫"; break; fi
    sleep 30; continue
  fi
  CONSEC=0; DONE_C=$((DONE_C+1))
  N=$(printf '%s' "$APW_BODY" | jq -r '.body.stores | length')
  AV=$(printf '%s' "$APW_BODY" | jq -r '[.body.stores[] | .partsAvailability // {} | to_entries[] | select(.value.pickupDisplay=="available")] | length')
  echo "$LOC → 店$N 有货项$AV"
  if [ "$N" != "0" ]; then
    printf '%s' "$APW_BODY" | jq -c --arg loc "$LOC" '{loc:$loc, stores:[.body.stores[] | {no:.storeNumber, name:.storeName, avail:[.partsAvailability // {} | to_entries[] | select(.value.pickupDisplay=="available") | {part:.key, title:(.value.messageTypes.regular.storePickupProductTitle // "")}]}]}' >> "$OUT"
  fi
  sleep "$PACE"
done

echo ""; echo "===== SKU 有货门店数排行（全国去重后） ====="
jq -sr '[.[] | .stores[] | .no as $no | .avail[] | {no: $no, part: .part, title: .title}]
  | group_by(.part) | map({title: (.[0].title // "?"), part: .[0].part, stores: (map(.no) | unique | length)})
  | sort_by(-.stores) | .[] | "\(.stores) 店\t\(.title)  [\(.part)]"' "$OUT"
echo ""; echo "===== 门店货架 top10（城市=目录映射） ====="
jq -sr '[.[] | .stores[] | .no as $no | .avail[] | {no: $no}]
  | group_by(.no) | map({no: .[0].no, n: length}) | unique_by(.no) | sort_by(-.n) | .[0:10] | .[] | "\(.no)\t\(.n)"' "$OUT" \
| while IFS="$(printf '\t')" read -r no n; do
    INFO=$(jq -r --arg no "$no" --arg loc "$LOCALE" '.[] | select(.locale==$loc) | .state[] as $s
      | $s.store[] | select(.id==$no) | "\($s.name) \(.address.city) \(.name)"' "$DATA/stores.json" 2>/dev/null)
    echo "$no（$INFO）→ $n 个 SKU"
  done
echo ""; echo "明细：$OUT ｜ 未知城市 $UNK ｜ 覆盖城市 $DONE_C"
