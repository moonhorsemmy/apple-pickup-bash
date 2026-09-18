#!/bin/bash
# 更新到最新版（git clone 安装的用户；zip 下载的请改为 git clone）
# 用户配置（scripts/config.env）与运行数据（var/）不受影响
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/lib.sh"; apw_config
cd "$APW_DIR"
echo "当前版本：v${APW_VERSION:-?}"
if [ ! -d .git ]; then
  echo "本目录不是 git 仓库（可能是 zip 下载的）：请备好 scripts/config.env 后改用"
  echo "  git clone https://github.com/moonhorsemmy/apple-pickup-bash.git"
  exit 2
fi
if [ -n "${PROXY:-}" ]; then
  git -c "http.proxy=$PROXY" -c "https.proxy=$PROXY" pull --ff-only || exit 1
else
  git pull --ff-only || exit 1
fi
echo "更新完成（国内网络可先在 config.env 配 PROXY 加速）。"
echo "脚本若有更新，建议重跑 scripts/test-push.sh 确认推送链路仍通。"
