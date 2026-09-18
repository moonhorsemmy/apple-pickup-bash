---
name: apple-pickup-bash
description: 查询 Apple 直营店到店取货库存并蹲守到货（国行 iPhone/iPad/Mac/Watch）。当用户问"某门店有没有货/帮我盯现货/到货了提醒我/查库存/哪个版本货最多/全国哪里有货"时使用。自带三态纪律与限频保护，绝不自动下单。
---

# Apple 到货蹲守（apple-pickup-bash）v2

自搓极简版：bash + curl + jq 直查 Apple 官网 `/shop/retail/pickup-message`（老接口 `/shop/fulfillment-messages` 已被 541 拦死，勿用）。v2 新增：目录缓存、同城一次查、全国扫描排行。接口口径与工程纪律致敬开源 [ENCHIGO/apple-pickup-watcher](https://github.com/ENCHIGO/apple-pickup-watcher)（GPL-3.0，本项目未抄其代码）。兼容 macOS 自带 bash 3.2。

## 脚本一览

```bash
S=<本仓库目录>/scripts

$S/catalog.sh refresh            # 拉/更新门店+零件号快照到 var/data/（走代理，缺了会自动拉）
$S/catalog.sh stores 上海         # 查门店号（省 城市 店名）
$S/catalog.sh parts "18 Pro 512"  # 查零件号（也可传家族名如 iphone-18-pro 全展开）
$S/catalog.sh cities           # 家族清单；cities = 全国「省 市」清单（城市查询必须用这个格式）
$S/city.sh "北京 北京" MJY64CH/A     # 同城查询示例（18 Pro Max）
```

**⚠️ 城市查询格式（最高频的坑）**：location 必须是「**省 市**」两段式（`"上海 上海"`、`"江苏 苏州"`、`"北京 北京"`、`"广东 深圳"`）。只写城市名（`location=北京`）会被 Apple 拒绝——响应 HTTP 200 但 `body.errorMessage="请输入有效的省/市名称或邮政编码"`、门店列表为空。**这属于查询格式错误，不是无货**。全表见 `$S/catalog.sh cities`。

$S/check.sh                      # 查一次 config.env 里的 STORE×PARTS
$S/check.sh R388 MJTD4CH/A       # 临时覆盖门店/零件号
$S/city.sh "上海 上海"            # 同城一次查全部门店（nearby 模式）
$S/sweep.sh iphone-18-pro        # 全国扫描+排行（可逗号分隔多家族；SWEEP_LIMIT=3 截断测试）
$S/watch.sh 60                   # 前台蹲守（默认 60s，下限 30；拍视频就拍这个窗口）
$S/citywatch.sh "北京 北京" MJTD4CH/A   # 单拍城市监控（给 launchd 用，也可手动）
$S/diff.sh                        # 对比两次 sweep 快照（新增/消失/门店数变化；不传参自动取最近两个）
$S/update.sh                      # 更新到最新版（git pull，尊重 PROXY）
```

**监控数据底座**：`var/beats.jsonl`——citywatch 每拍追加一行结构化数据（时间×门店×零件状态），放货规律分析就是一条 jq，例如查某零件的全部出现历史：
```bash
jq -r '.stores[] | select(.parts["MJTD4CH/A"]=="available") | "\(.ts) \(.name)"' var/beats.jsonl
```

**常驻监控用 launchd（系统级，重启/登出都在）**——已安装 `com.$USER.apple-pickup-bash`（京津 9 店盯 512G 银，60s 一拍）：

```bash
# 管理：
launchctl print gui/$(id -u)/com.$USER.apple-pickup-bash   # 状态
launchctl bootout gui/$(id -u)/com.$USER.apple-pickup-bash # 停止
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.$USER.apple-pickup-bash.plist  # 启动
# 改盯法：编辑 ~/Library/LaunchAgents/com.$USER.apple-pickup-bash.plist 的 ProgramArguments（地点/零件号），bootout+bootstrap 生效
# 日志：var/launchd-out.log（心跳与 🎯 HIT 行）、var/launchd-err.log

配置在 `scripts/config.env`：STORE / PARTS 数组 / FAMILY（填家族名则自动展开全系零件号）/ BARK_URL / SWEEP_PACE。状态 `var/state.txt`（键 `店号|零件号`，变有货才推 Bark）、扫描明细 `var/sweep-*.jsonl`。

## 本轮实战沉淀的接口事实（2026-09-18 首销日验证）

1. **接口只有"有/无"，没有数量**。"哪个版本货最多"= 有货门店数（sweep.sh 的口径）。
2. **大陆 location 必须写「省 市」**（"上海 上海""江苏 苏州"），只写城市名返回 0 店；「北京 北京」偶发 0 店，可用邻城（如天津）的 nearby 覆盖——**nearby 半径很大、跨城重叠**，聚合必须按 storeNumber 去重。
3. **成功信封+空门店列表** = 型号未开售/停售/当前不可购买（Duo 10 月发售期查它就是这样），不是无货也不是出错。**实测案例（2026-09-18 首销日）：18 Pro Max 全国 0 店有货——单独查任何店的 Pro Max 零件，Apple 正常返回门店+该零件 `unavailable`（这是真无货）；但若返回空门店列表，则是"未铺货"信号，别当查询故障**。
4. **限频实测**：Apple 按出口 IP 计，连续约 30 次请求触发 HTTP 541（拦 10–15 分钟）；26 城×4s 间隔的全国扫描实测不触发。被 541 → 停 10 分钟，勿并发绕过。
5. 全国 ≈26 个「省 市」location 查询即可覆盖全部 46 店（邻城重叠互相补齐）。
6. **Windows 用户**：本工具脚本依赖 bash+jq（Git Bash 可跑）；若无此环境，agent 可按本文件的接口口径直接用 curl/PowerShell 复刻查询——但「省 市」格式、三态纪律、限频自律必须原样遵守。

## 铁律（agent 必须遵守，违反=害用户错过货）

1. **间隔 ≥30 秒**（sweep 类 ≥4s/城）。被 541 → **自动进入 600s 冷却**（citywatch 内置：冷却期内跳过查询不发请求，过期自动清除；541 与"200 但非 JSON"都算被拦）。
2. **三态纪律**：available=有货；unavailable/ineligible=无货；失败/541/非 JSON/字段不认识/**空门店**=未知。**失败绝不能说成无货**，未知必须带原因。
3. **只提醒，不下单**：到"通知你"为止，加购/结账/付款用户自己在官网完成。
4. **单进程**：同时只跑一个 watch/sweep；Apple Watch 表壳要连带表带零件号（companionPart，目录里有）。
5. 仅供个人查询使用。
6. **实际有货才通知**：翻转后 sleep 5 单店复核，确认 available 才推送；**确认即写 var/STOP 停止追踪**（resume.sh 恢复并重置基线）。

## 维护备忘（改脚本前必读，都是踩过的坑）

- macOS /bin/bash = 3.2：**没有 mapfile、没有 declare -A**；数组用 `while read` 逐行追加。
- **`jq -n` 会忽略 stdin**（null 输入）——要解析管道输入时绝不加 -n；@uri 编码场景才用 -n。
- **jq `as` 绑定不改变上下文**：`.state[] as $s | select($s.name|...)` 必须显式 `$s.`，写 `.name` 测到的是父对象的 null。
- 聚合输出记得 `jq -r`，否则带引号和转义符。
- curl 参数数组展开（`"${Q[@]}"`）+ `--data-urlencode` 处理中文/斜杠。
- 目录 json 是**异构 schema**：iPhone/iPad/Mac 用 `partNumber+dimensionCapacity+dimensionColor`，Apple Watch 用 `part+dimensions{}`——过滤时全部 `// ""` 兜底，否则 `test(null)` 崩。
- **常驻监控绝不用 `nohup 循环 &`**：挂在工具调用临时 shell 下的进程会被运行时回收（实测存活 26 分钟后被杀，nohup 挡不住进程组回收）。心跳交给 launchd（`StartInterval` 拉起短命单拍脚本 `citywatch.sh`），进程每次只活 2 秒，不存在被回收问题。

## 给 agent 的调用姿势

- "查一下某店"→ `check.sh 店号 零件号`；"北京/成都有没有"→ `city.sh "省 市"`（先 `catalog.sh cities` 对格式）；"全国哪个版本货最多"→ `sweep.sh 家族名`（2 分钟，26 请求）。
- "帮我盯着"→ 改 config.env → `watch.sh` 后台跑（告知 job/停止方式）→ 输出"有货"即报用户并推 Bark。
- 报告必须带：观察时间（首销日库存分钟级变动）、三态结论、未知的原因；不承诺持续监控（除非 watch 在跑）。
