# CFIP 主槽同路径基线与自动晋升实现记录

## 目标

补齐现有自动链路的最后一段：在不恢复旧 `06:30` 任务、不停止或重启 PassWall、每周期最多修改一条 Cloudflare 记录的前提下，让 `auto/auto1/auto2` 能依据真实 PassWall 同路径数据稳定排序，并允许已进入 `auto3/auto4` 的长期合格候选晋升。

完整链路为：

`.110 Sidecar -> VM36 竞争候选隔离门控 -> auto3/auto4 -> 主槽同路径三日基线 -> auto/auto1/auto2 单记录晋升 -> Cloudflare`

## 实现范围

### Router Candidate Gate

`router-candidate-gate.sh` 新增：

- `primary-canary IP`：对指定 Cloudflare IPv4 使用现有隔离 Xray 路径做两轮真实下载，不要求该 IP 位于 Sidecar staging；
- `primary-qualify`：从独立主槽历史生成连续三日资格；
- 独立状态文件：
  - `router-primary-canary-history.tsv`
  - `router-primary-canary.latest.tsv`
  - `router-primary-baseline-qualified.tsv`
- 主槽最低门槛固定不得低于 `4.0 MB/s`；
- 测试前后继续校验生产 Xray PID、监听、PassWall UCI、runtime JSON 和临时 Xray 清理；不停止、不重启、不修改生产 PassWall。

### Sidecar Auto Sync

`sidecar-auto-sync.sh` 新增：

- 每个自然周期在候选 canary 之外，顺序测试三个当前主槽；
- 三个当前主槽均取得至少三个不同日期的同路径资格前，状态为 `awaiting_primary_baseline`，不写主槽 DNS；
- 新候选必须先存在于 `auto3/auto4`，并已有竞争资格；
- 候选三日最低速度必须不低于 `4.0 MB/s`，且至少比当前最弱主槽高 `25%`；
- 主槽和合格挑战者按三日最低速度、平均速度、通过天数排序；
- 竞争槽不一致时优先处理竞争槽；只有竞争槽已稳定后才处理主槽，因此一个周期仍只产生一条写入；
- `CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY` 允许严格的 `0|1`，默认仍为 `0`；
- 主槽计划和写入状态分别为 `primary_planned`、`primary_updated`；
- 继续复用现有 Cloudflare 并发内容检查、写后 GET、PassWall/HTTP 验收和单记录自动回滚。

## 测试结果

2026-07-31 在 `.140` 的 `/tmp` 隔离副本完成：

- `tests/test-router-candidate-gate.sh`：通过；
- `tests/test-sidecar-auto-sync-plan.sh`：通过；
- `sidecar/tests/run-tests.sh`：通过；
- `tests/run-all-regression-tests.sh`：通过；
- 全项目回归：通过。

专项测试覆盖：主槽三日资格、`4.0 MB/s` 硬下限、Cloudflare CIDR 拒绝、主槽排序、`25%` 改善要求、竞争槽前置、缺失基线故障安全、开关 `0|1` 校验和单条计划选择。

## 生产门控事实

2026-07-31 只读检查确认：

- VM36 的 `04:15` 自动同步完成，状态为 `awaiting_multiday_gate`；
- `CFIP_AUTO_SYNC_APPLY=1`，主槽开关仍为 `0`；
- 唯一 `04:15` cron 存在，旧 `06:30` cron 不存在；
- PassWall 一个有效 Xray 进程承载 `1070/1041/11400/15353`，四监听正常；
- VM36、`.110`、`.140` 的 Google/YouTube HTTP 均为 `204`；
- 项目锁均空闲，Sidecar 无 Xray JSON、瞬时容器或 `cfip-direct` 附着；
- Cloudflare 五记录只读 API 验证通过。

同日发现的 Sidecar `Result=exit-code` 来自 `2026-07-31 03:32 CST` 自然运行，错误为旧配置要求已退役的 `k12-reg`。三容器修复实际部署时间为 `2026-07-31 06:48 CST`，晚于该失败样本；当前脚本和真实配置均只要求 `sub2api`、`sub2api-postgres`、`sub2api-redis`。因此必须等待 `2026-08-01` 下一次自然运行形成修复后的新样本，不能把旧失败误判为修复后复发。

## 生产实施门槛

仅在下一次自然 Sidecar 满足以下条件后部署 VM36：

- `Result=success`、`ExecMainStatus=0`、`MainPID=0`；
- 新报告和新导出来自修复后的不同时间；
- 三个必要容器健康，锁空闲，无残留，HTTP 正常；
- VM36 `04:15` 同步正常，PassWall、DNS和 Cloudflare 内容未异常。

部署时先创建 `/root/openwrt-backup/cfip-primary-promotion-<时间>`，备份现有两个脚本、同步配置、crontab 和相关状态摘要；先在 VM36 `/tmp` 运行 Bash 语法及 BusyBox 计划测试，再原子替换脚本。首次验证保持主槽开关为 `0`，确认会得到 `awaiting_primary_baseline` 而不写 DNS；通过后才把主槽开关设为 `1`。由于真实三日基线尚不存在，启用开关本身不会立即更新主槽。

## 回滚

若部署、语法、计划测试、PassWall PID/监听、HTTP、DNS或 cron 校验失败：

1. 立即停止，不运行同步任务；
2. 从本机备份恢复 `router-candidate-gate.sh`、`sidecar-auto-sync.sh`、`sidecar-auto-sync.env` 和 crontab；
3. 不重启 PassWall，不改 DNS、路由、池或 Sidecar；
4. 复核 Xray PID与四监听、Google/YouTube和五记录三路 DNS；
5. 网络级最终回滚仍为关闭 VM36 后启动 VM33，两台不得同时占用 `.254`。
