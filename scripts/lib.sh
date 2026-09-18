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

apw_bark() { # $1=标题 $2=正文（失败自动重试一次并告警）
  [ -z "${BARK_URL:-}" ] && return 0
  local t b
  t=$(jq -rn --arg x "$1" '$x|@uri'); b=$(jq -rn --arg x "$2" '$x|@uri')
  curl -s --max-time 15 "$BARK_URL/$t/$b" -o /dev/null && return 0
  sleep 3
  curl -s --max-time 15 "$BARK_URL/$t/$b" -o /dev/null \
    || echo "[$(date '+%m-%d %H:%M:%S')] ⚠️ Bark 推送失败，检查 config.env BARK_URL"
}

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
