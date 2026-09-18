#!/bin/bash
# apple-stock 公共库（bash 3.2 兼容）
APW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VAR="$APW_DIR/var"; DATA="$VAR/data"; mkdir -p "$VAR" "$DATA"
# 首次运行：若有捆绑快照（data/*.json）则复制进工作目录，开箱即用
if [ ! -f "$DATA/stores.json" ] && [ -f "$APW_DIR/data/stores.json" ]; then
  cp "$APW_DIR/data/"*.json "$DATA/" 2>/dev/null
fi
JAR="$VAR/cookies.txt"
UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"

apw_config() {
  if [ -f "$APW_DIR/scripts/config.env" ]; then
    . "$APW_DIR/scripts/config.env"
  elif [ -f "$APW_DIR/scripts/config.example.env" ]; then
    . "$APW_DIR/scripts/config.example.env"
    [ "${APW_QUIET:-0}" = 0 ] && echo "（未找到 config.env，使用示例配置；cp config.example.env config.env 后可自定义）" >&2
  else
    echo "缺少配置：cp scripts/config.example.env scripts/config.env" >&2; exit 2
  fi
}
apw_warm() {
  [ -f "$JAR" ] && [ -n "$(find "$JAR" -mmin -60 2>/dev/null)" ] && return 0
  curl -s -c "$JAR" -A "$UA" --max-time 20 "$BUY_PAGE" -o /dev/null
}

# apw_query <R359 | loc:省 市> <零件号...> → 设 APW_CODE / APW_BODY
apw_query() {
  local scope="$1"; shift
  local args=(-s -G -b "$JAR" -A "$UA" -H "Accept: application/json" -H "Referer: $BUY_PAGE"
    --data-urlencode "pl=true" --data-urlencode "mts.0=regular" --max-time 30 -w "\n%{http_code}")
  case "$scope" in
    loc:*) args+=(--data-urlencode "location=${scope#loc:}");;
    *)     args+=(--data-urlencode "store=$scope");;
  esac
  local i=0 p resp
  for p in "$@"; do args+=(--data-urlencode "parts.$i=$p"); i=$((i+1)); done
  resp=$(curl "${args[@]}" "$BASE_URL/shop/retail/pickup-message") || { APW_CODE=000; APW_BODY=""; return; }
  APW_CODE=$(printf '%s' "$resp" | tail -n1)
  APW_BODY=$(printf '%s' "$resp" | sed '$d')
}

# 三态：available→有货；unavailable/ineligible→无货；其余（含空）→未知+原因
apw_classify() { # $1=display 原值
  case "$1" in
    available)              echo "有货";;
    unavailable|ineligible) echo "无货";;
    "")                     echo "未知(原因: 响应里查不到该零件号——抄错/未发售/该店不卖)";;
    *)                      echo "未知(原因: pickupDisplay=$1 接口可能已变)";;
  esac
}

# 零件号 → 官网购买页直达链接（族页面 + product 预选参数，浏览器打开即选中该配置）
apw_buy_url() { # $1=零件号
  local fam cat
  fam=$(jq -r --arg p "$1" '.[] | select([.data.products[]? | select((.partNumber // .part) == $p)] | length > 0) | .family // empty' "$DATA/products_$LOCALE.json" 2>/dev/null | head -1)
  cat=$(jq -r --arg p "$1" '.[] | select([.data.products[]? | select((.partNumber // .part) == $p)] | length > 0) | .category // empty' "$DATA/products_$LOCALE.json" 2>/dev/null | head -1)
  if [ -z "$fam" ] || [ -z "$cat" ]; then echo "$BASE_URL/shop"; return; fi
  echo "$BASE_URL/shop/buy-${cat}/${fam}?product=$1"
}

# 推送：向所有已配置通道发（任配一个即可；都没配则告警提示）
# 通道：BARK_URL / SERVERCHAN_KEY（微信）/ NTFY_TOPIC / IMSG_ADDR（iMessage，零安装）/ FEISHU_WEBHOOK
# $3 可选=购买页链接：Bark 点通知跳转 / ntfy Click 跳转 / 其余附在正文里（可点开）
apw_push() { # $1=标题 $2=正文 [$3=链接]
  local sent=0 t b msg u uenc
  u="${3:-}"
  if [ -n "${BARK_URL:-}" ]; then
    t=$(jq -rn --arg x "$1" '$x|@uri'); b=$(jq -rn --arg x "$2" '$x|@uri')
    uenc=""; [ -n "$u" ] && uenc=$(jq -rn --arg x "$u" '$x|@uri')
    curl -s --max-time 15 "$BARK_URL/$t/$b?group=apple-pickup${uenc:+&url=$uenc}" -o /dev/null && sent=1
  fi
  if [ -n "${SERVERCHAN_KEY:-}" ]; then
    [ -n "$u" ] && b="$2

[点此直达购买页]($u)" || b="$2"
    curl -s --max-time 15 -X POST "https://sctapi.ftqq.com/${SERVERCHAN_KEY}.send" \
      --data-urlencode "title=$1" --data-urlencode "desp=$b" -o /dev/null && sent=1
  fi
  if [ -n "${NTFY_TOPIC:-}" ]; then
    if [ -n "$u" ]; then
      curl -s --max-time 15 -H "Title: $1" -H "Tags: bell" -H "Click: $u" -d "$2" "https://ntfy.sh/${NTFY_TOPIC}" -o /dev/null && sent=1
    else
      curl -s --max-time 15 -H "Title: $1" -H "Tags: bell" -d "$2" "https://ntfy.sh/${NTFY_TOPIC}" -o /dev/null && sent=1
    fi
  fi
  if [ -n "${IMSG_ADDR:-}" ]; then
    msg=$(printf '%s — %s%s' "$1" "$2" "${u:+

$u}" | tr -d '"' | tr -d '\\')
    osascript -e "tell application \"Messages\" to send \"$msg\" to buddy \"$IMSG_ADDR\"" >/dev/null 2>&1 && sent=1
  fi
  if [ -n "${FEISHU_WEBHOOK:-}" ]; then
    msg=$(printf '%s — %s%s' "$1" "$2" "${u:+
$u}" | jq -Rs .)
    curl -s --max-time 15 -X POST "$FEISHU_WEBHOOK" -H 'Content-Type: application/json' \
      -d "{\"msg_type\":\"text\",\"content\":{\"text\":$msg}}" -o /dev/null && sent=1
  fi
  if [ $sent -eq 0 ]; then
    echo "[$(date '+%m-%d %H:%M:%S')] ⚠️ 无可用推送通道：在 config.env 配 BARK_URL / SERVERCHAN_KEY / NTFY_TOPIC / IMSG_ADDR / FEISHU_WEBHOOK 任一，并跑 scripts/test-push.sh 验证"
    return 1
  fi
  return 0
}
apw_bark() { apw_push "$@"; }  # 兼容旧名

# state.txt 键值（键可含 "店号|零件号"），变有货才推
apw_state_get() { grep "^$1=" "$VAR/state.txt" 2>/dev/null | tail -n1 | cut -d= -f2-; }
apw_state_set() {
  local tmp="$VAR/state.txt.new"
  { grep -v "^$1=" "$VAR/state.txt" 2>/dev/null; echo "$1=$2"; } > "$tmp" && mv "$tmp" "$VAR/state.txt"
}

# 零件号来源：PARTS 数组或 FAMILY（需 catalog.sh refresh 过的缓存）
apw_parts() {
  if [ -n "${FAMILY:-}" ]; then
    jq -r --arg f "$FAMILY" '.[] | select(.family==$f) | .data.products[].partNumber' "$DATA/products_$LOCALE.json"
  else
    printf '%s\n' "${PARTS[@]}"
  fi
}

# ---- 541 冷却自律：被拦后写标记，冷却期内自动跳过查询 ----
apw_cooldown_file() { echo "$VAR/cooldown.until"; }
apw_in_cooldown() {
  local f until now
  f=$(apw_cooldown_file)
  [ -f "$f" ] || return 1
  until=$(cat "$f" 2>/dev/null); now=$(date +%s)
  case "$until" in ''|*[!0-9]*) rm -f "$f"; return 1;; esac
  if [ "$now" -ge "$until" ]; then rm -f "$f"; return 1; fi
  APW_COOLDOWN_LEFT=$((until - now))
  return 0
}
apw_enter_cooldown() { # $1=秒，默认 600
  echo $(( $(date +%s) + ${1:-600} )) > "$(apw_cooldown_file)"
}

# 复核：对单店单零件独立再查一次（不碰 apw_query 的全局变量）
# 返回 pickupDisplay 原值；查询失败/非JSON/查不到返回空字符串
apw_verify() { # $1=店号 $2=零件号
  local resp code body
  resp=$(curl -s -G -b "$JAR" -A "$UA" -H "Accept: application/json" -H "Referer: $BUY_PAGE" \
    --data-urlencode "pl=true" --data-urlencode "mts.0=regular" --data-urlencode "store=$1" \
    --data-urlencode "parts.0=$2" --max-time 20 -w "\n%{http_code}" "$BASE_URL/shop/retail/pickup-message") || { echo ""; return; }
  code=$(printf '%s' "$resp" | tail -n1); body=$(printf '%s' "$resp" | sed '$d')
  [ "$code" = "200" ] || { echo ""; return; }
  printf '%s' "$body" | jq -r --arg p "$2" '.body.stores[0].partsAvailability[$p].pickupDisplay // empty' 2>/dev/null
}
