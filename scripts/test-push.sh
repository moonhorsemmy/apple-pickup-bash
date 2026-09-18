#!/bin/bash
# 推送链路自检：列出已配置通道，并向其发一条测试消息（手机收到=链路通）
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
echo "===== 推送通道配置检查 ====="
[ -n "${BARK_URL:-}" ]        && echo " ✓ Bark        $BARK_URL"
[ -n "${SERVERCHAN_KEY:-}" ]  && echo " ✓ Server酱    (微信推送, key=${SERVERCHAN_KEY:0:8}...)"
[ -n "${NTFY_TOPIC:-}" ]      && echo " ✓ ntfy        topic=$NTFY_TOPIC"
[ -n "${IMSG_ADDR:-}" ]       && echo " ✓ iMessage    $IMSG_ADDR"
[ -n "${FEISHU_WEBHOOK:-}" ]  && echo " ✓ 飞书 webhook"
CNT=0
for v in BARK_URL SERVERCHAN_KEY NTFY_TOPIC IMSG_ADDR FEISHU_WEBHOOK; do
  eval "val=\${$v:-}"; [ -n "$val" ] && CNT=$((CNT+1))
done
if [ $CNT -eq 0 ]; then
  echo " ✗ 未配置任何通道。config.env 里任配一个："
  echo "   Bark(专用App):      BARK_URL=https://api.day.app/你的Key"
  echo "   Server酱(微信):     SERVERCHAN_KEY=SCTxxxx  （sct.ftqq.com 微信扫码领取）"
  echo "   ntfy(零账号):       NTFY_TOPIC=自定义主题名  （ntfy App 订阅同名主题）"
  echo "   iMessage(零安装):   IMSG_ADDR=+86你的手机号  （Mac 信息 App 需登录同 Apple ID）"
  echo "   飞书群机器人:       FEISHU_WEBHOOK=https://open.feishu.cn/open-apis/bot/v2/hook/xxx"
  exit 2
fi
echo "===== 发送测试 ====="
apw_push "🔔 apple-pickup-bash 链路测试" "推送链路已打通。真实到货提醒长这样（含购买直达链接，点开试试）" "$(apw_buy_url MJT74CH/A)"
echo "手机上收到测试消息即链路完成；没收到检查对应通道配置。"
