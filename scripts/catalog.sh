#!/bin/bash
# 目录工具：门店号/零件号/家族/全国城市清单（缓存优先，缺了自动拉）
# 用法: catalog.sh refresh | stores <城市词> | parts <词|家族名> | families | cities
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
SRC=https://raw.githubusercontent.com/ENCHIGO/apple-pickup-watcher/main/crates/apw-core/data

refresh() {
  if [ -n "${PROXY:-}" ]; then export https_proxy="$PROXY" http_proxy="$PROXY"; fi
  if curl -sL --max-time 90 -o "$DATA/stores.json" "$SRC/stores.json" \
     && curl -sL --max-time 90 -o "$DATA/products_$LOCALE.json" "$SRC/products_$LOCALE.json"; then
    echo "目录已缓存到 $DATA（$(date '+%m-%d %H:%M')）"
  else
    echo "快照拉取失败：国内网络请在 config.env 配 PROXY（如 http://127.0.0.1:7897）"
    return 1
  fi
}
[ -f "$DATA/stores.json" ] || refresh >/dev/null

# 快照过期提醒（≥14 天提示 refresh/update）
if [ -f "$DATA/stores.json" ]; then
  MOD=$(stat -f %m "$DATA/stores.json" 2>/dev/null || stat -c %Y "$DATA/stores.json" 2>/dev/null || echo 0)
  AGE=$(( ( $(date +%s) - MOD ) / 86400 ))
  [ $AGE -ge 14 ] && echo "提示：目录快照已 ${AGE} 天，新型号/门店可能缺失——scripts/catalog.sh refresh 或 scripts/update.sh" >&2
fi

CMD=${1:-}

  refresh) refresh;;
  stores)
    jq -r --arg kw "${2:-}" --arg loc "$LOCALE" '.[] | select(.locale==$loc) | .state[] as $s
      | select($s.name|test($kw;"i")) | $s.store[] | "\(.id)\t\($s.name) \(.address.city)\t\(.name)"' "$DATA/stores.json";;
  parts)
    jq -r --arg kw "${2:-}" '.[] | select(((.family//"")|test($kw;"i")) or ((.data.products//[])|any(((.partNumber//"")+" "+(.dimensionCapacity//"")+" "+(.dimensionColor//""))|test($kw;"i"))))
      | .family as $f | .data.products[] | select(type=="object")
      | "\(.partNumber // .part // "-")\t\($f)\t\(.dimensionCapacity // (.dimensions // {} | to_entries | map(.value) | join("/")) // "-")\t\(.dimensionColor // "-")\t\(.companionPart // "")"' "$DATA/products_$LOCALE.json";;
  families)
    jq -r '.[] | "\(.category)\t\(.family)"' "$DATA/products_$LOCALE.json";;
  cities)
    jq -r --arg loc "$LOCALE" '.[] | select(.locale==$loc) | .state[] as $s
      | $s.store[].address.city | select(. != "") | "\($s.name) \(.)"' "$DATA/stores.json" | sort -u;;
  *) echo "用法: catalog.sh refresh | stores <城市词> | parts <词|家族名> | families | cities";;
esac
