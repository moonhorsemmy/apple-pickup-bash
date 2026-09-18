# apple-pickup-bash

**苹果直营店到店取货库存监控与到货提醒 —— 零依赖 bash 版**（macOS / Linux，bash + curl + jq）。

盯住你想买的 iPhone / iPad / Mac / Apple Watch：选好门店和型号，一有货就推送提醒（Bark / 微信 Server酱 / ntfy / iMessage / 飞书 任一通道）。
也是一份可直接装进 AI agent 的 skill（`SKILL.md`）。

> 一句话纪律：**只提醒，不下单**。加购、结账、付款由你自己在 Apple 官网完成。

## 它能做什么

| 能力 | 命令 | 说明 |
|---|---|---|
| 查一次某门店 | `scripts/check.sh R359 MJT74CH/A` | 三态输出：有货 / 无货 / 未知（**失败绝不当无货**） |
| 查全城门店 | `scripts/city.sh "上海 上海"` | 一次请求返回同城+周边门店 |
| 全国扫描排行 | `scripts/sweep.sh iphone-18-pro` | 26 个城市查询覆盖全部 46 店，输出"哪个版本货最多" |
| 快照对比 | `scripts/diff.sh` | 两次 sweep 之间：新增/消失门店、SKU 门店数变化 |
| 常驻监控 | `scripts/citywatch.sh` + launchd/systemd | 60s 一拍，变有货推 Bark，自动 541 冷却 |
| 门店/型号查询 | `scripts/catalog.sh stores 上海` / `parts "18 Pro 512"` | 离线目录（自带快照） |

## 30 秒上手

```bash
git clone https://github.com/moonhorsemmy/apple-pickup-bash.git && cd apple-pickup-bash
cp scripts/config.example.env scripts/config.env   # 按需改门店/型号/Bark
scripts/catalog.sh stores 北京                       # 查门店编号
scripts/check.sh R388 MJT74CH/A                      # 查一次
```

依赖：bash、curl、jq（macOS：`brew install jq`）。

## 配置推送（不配则只记日志，不会推手机）

```bash
cp scripts/config.example.env scripts/config.env   # 编辑，任配一个通道：
#   Bark(专用App) / Server酱(微信) / ntfy(零账号) / iMessage(零安装) / 飞书
scripts/test-push.sh                               # 发一条测试，手机收到=链路通
```

到货提醒自带官网购买页直达链接（按零件号生成，Bark/ntfy 点通知直接跳转，其余通道链接可点）：

```
📱有货了 — 天津大悦城(R637) iPhone 18 Pro 512GB 银色 现在可到店取货
https://www.apple.com.cn/shop/buy-iphone/iphone-18-pro?product=MJTD4CH/A
```

**监控语义（v2.2）**：

- **实际有货才通知**：检测到状态翻转后，等 5 秒对该店单独复核一次，确认仍有货才推送；转瞬即逝的只记日志，不打扰你
- **确认有货即停止追踪**：推送后写入 `var/STOP`，后续每拍直接跳过——目标是买到一台，不是永久蹲守
- **恢复监控**：`scripts/resume.sh`（清 STOP 与状态基线；若恢复时恰好有货，下一拍会重新确认并推送）

## 常驻监控

**macOS（launchd）**——把下面存成 `~/Library/LaunchAgents/com.$USER.apple-pickup-bash.plist`（脚本路径按实际改），`launchctl bootstrap gui/$(id -u) <plist路径>` 启动：

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.$USER.apple-pickup-bash</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>/path/to/apple-pickup-bash/scripts/citywatch.sh</string>
    <string>北京 北京</string>
    <string>MJTD4CH/A</string>
  </array>
  <key>StartInterval</key><integer>60</integer>
  <key>RunAtLoad</key><true/>
</dict></plist>
```

**Linux（systemd timer）**：`systemd-run --on-unit-inactive=60s --timer-property=Restart=always ...` 或写标准 service+timer 单元调用 `citywatch.sh`。

监控数据自动落盘 `var/beats.jsonl`（时间×门店×状态），放货规律分析一条 jq：

```bash
jq -r '.stores[] | select(.parts["MJTD4CH/A"]=="available") | "\(.ts) \(.name)"' var/beats.jsonl
```

## 三条红线（本工具的自我约束）

1. **只提醒，不下单**：到通知为止，绝无自动加购/结账。
2. **不做反检测**：不上多出口轮换/多账户；单进程、克制频率。
3. **限频自律**：Apple 按出口 IP 限频（连续约 30 次触发 HTTP 541，拦截 10–15 分钟）。默认间隔 ≥30s（扫描 ≥4s/城）；被 541 自动进入 600s 冷却、期内零请求。
   批量抢购牟利只会让这条路对所有人失效——请克制使用。

## 作为 agent skill 使用

本仓库即一份 skill：把目录放进你的 skills 目录（如 `~/.agents/skills/`），agent 读 `SKILL.md` 即知用法与纪律。兼容 macOS 自带 bash 3.2。

## 更新

```bash
scripts/update.sh        # git pull 到最新版（尊重 config 的 PROXY 设置）
```

克隆安装的用户跑 update.sh 即可；zip 下载的建议改用 git clone。用户配置（config.env）与运行数据（var/）不会被更新覆盖。目录快照超过 14 天会自动提醒 refresh。


- 接口知识与工程纪律致敬 [ENCHIGO/apple-pickup-watcher](https://github.com/ENCHIGO/apple-pickup-watcher)（GPL-3.0，其上游为 hteen/apple-store-helper）；本项目未复制其代码，详见 `NOTICE`
- [GPL-3.0-or-later](LICENSE)
- 推送依赖 [Bark](https://github.com/Finb/Bark)（可选）

## 免责声明

本项目与 Apple Inc. 无关联。接口为官网非公开零售接口，随时可能变化或失效（本工具对未知响应一律报"未知"而非"无货"）。查询结果仅供参考，最终库存以 Apple 官网为准；使用本工具造成的一切后果由使用者自行承担。
