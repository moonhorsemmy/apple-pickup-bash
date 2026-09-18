#!/bin/bash
# diff.sh —— 对比两次 sweep 快照：新增/消失的有货门店、SKU 门店数变化
# 用法: diff.sh <旧sweep.jsonl> <新sweep.jsonl>（不传参数则自动取最近两个）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
export LC_ALL=C

if [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  mapfile -t F 2>/dev/null || F=()
  if [ ${#F[@]} -eq 0 ]; then
    F=(); while IFS= read -r _f; do F+=("$_f"); done < <(ls -t "$VAR"/sweep-*.jsonl 2>/dev/null | head -2)
  fi
  if [ ${#F[@]} -lt 2 ]; then
    echo "用法: diff.sh <旧sweep.jsonl> <新sweep.jsonl>（var/sweep-*.jsonl；目前快照不足两个）"; exit 2
  fi
  OLD="${F[1]}"; NEW="${F[0]}"   # ls -t：最新的在前，次新的在后
else
  OLD="$1"; NEW="$2"
fi
[ -f "$OLD" ] && [ -f "$NEW" ] || { echo "文件不存在"; exit 2; }

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
# 展平为 "零件号\t门店号" 对（去重排序，供 comm）
flat() { jq -sr '.[] | .stores[] | .no as $no | .avail[] | "\(.part)\t\($no)"' "$1" | sort -u; }
flat "$OLD" > "$T/old"; flat "$NEW" > "$T/new"
# 标题映射（两份合并）
{ jq -sr '.[] | .stores[] | .avail[] | select((.title//"")!="") | "\(.part)\t\(.title)"' "$OLD"
  jq -sr '.[] | .stores[] | .avail[] | select((.title//"")!="") | "\(.part)\t\(.title)"' "$NEW"; } | sort -u > "$T/titles"

title_of() { grep -F "$(printf '%s\t' "$1")" "$T/titles" | head -1 | cut -f2; }
sname_of() { jq -r --arg no "$1" --arg loc "$LOCALE" '.[] | select(.locale==$loc) | .state[] as $s
  | $s.store[] | select(.id==$no) | "\($s.name) \(.name)"' "$DATA/stores.json" 2>/dev/null; }

echo "===== sweep 对比 ====="
echo "旧：$(basename "$OLD")（$(date -r "$OLD" '+%m-%d %H:%M' 2>/dev/null || echo '?')）"
echo "新：$(basename "$NEW")（$(date -r "$NEW" '+%m-%d %H:%M' 2>/dev/null || echo '?')）"

GAINED=$(comm -13 "$T/old" "$T/new"); LOST=$(comm -23 "$T/old" "$T/new")
echo "--- 🟢 新增有货：$(printf '%s' "$GAINED" | grep -c .) 项"
if [ -n "$GAINED" ]; then printf '%s\n' "$GAINED" | while IFS="$(printf '\t')" read -r p no; do
  echo "  $(title_of "$p") [$p] +$(sname_of "$no")($no)"; done; fi
echo "--- 🔴 消失（被买走/下架）：$(printf '%s' "$LOST" | grep -c .) 项"
if [ -n "$LOST" ]; then printf '%s\n' "$LOST" | while IFS="$(printf '\t')" read -r p no; do
  echo "  $(title_of "$p") [$p] -$(sname_of "$no")($no)"; done; fi

echo "--- SKU 有货门店数变化"
cat "$T/old" "$T/new" | cut -f1 | sort -u | while read -r p; do
  O=$(grep -c "^$(printf '%s\t' "$p")" "$T/old"); N=$(grep -c "^$(printf '%s\t' "$p")" "$T/new")
  [ "$O" = "$N" ] && continue
  D=$((N-O)); [ $D -gt 0 ] && SIGN="+$D" || SIGN="$D"
  echo "  $(title_of "$p") [$p]：$O → $N（$SIGN）"
done
