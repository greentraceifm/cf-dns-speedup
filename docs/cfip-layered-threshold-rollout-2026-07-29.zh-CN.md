# CFIP 分层门槛与竞争槽链路实施记录（2026-07-29）

## 结论

分层候选协议、三日真实 PassWall 门控和竞争槽规划已部署并完成一次全链路 dry-run。当前状态为 `awaiting_multiday_gate`，Cloudflare 五条记录未改变。

生产写开关仍为 `CFIP_AUTO_SYNC_APPLY=0`，稳定主槽晋升保持 `CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY=0`。启用竞争槽自动写入属于单独的 Cloudflare Action Gate，必须另行明确授权。

## 当前架构

- `.110`：唯一自动扫描和 Sidecar 代理验证执行面；每日自然 timer 约 03:33 运行。
- VM36 `.254`：PassWall、路由器端真实路径门控、三日历史、排序和 Cloudflare 竞争槽同步。
- `.140`：仅维护和验收跳板，不在日常自动链路中。
- VM37：已关机，保留注册和磁盘；不参与生产。
- VM33：继续关机保留最终网络回滚。

## 已部署规则

- Sidecar 最多导出 3 个候选。
- 观察底线固定为两轮 HTTP 200、完整下载且 `min >= 3.5 MB/s`。
- `3.5-6.49 MB/s` 标记为 `observation`，`>= 6.5 MB/s` 标记为 `excellent`。
- 门槛禁止低于 3.5 MB/s，不按候选数量动态降低。
- VM36 同时兼容 v1 和 v2 导出。
- 竞争候选必须通过 VM36 隔离 Xray 的真实 PassWall 路径，并连续 3 个不同日期通过。
- `auto3/auto4` 为竞争槽；未满三日不写入。
- 每周期最多更新一条记录。
- `auto/auto1/auto2` 自动晋升代码保持关闭。

## 本轮发现和修复

### 1. 路径守卫拓扑假设错误

旧守卫要求 `.110` 主机出口与 Sidecar 出口不同。实际出口矩阵证明：

- `.110` 主机与 Sidecar 都使用 ISP 直连出口；
- 两者均不同于 VM36 的 PassWall SOCKS 代理出口；
- Sidecar 旁路原本有效，不需要额外 nft 规则。

曾尝试恢复三条精确 nft `return` 规则，但 `path-check` 仍失败；规则计数证明 HTTPS 流量未经过预期链。三条规则随后全部删除，PassWall、dnsmasq、配置和 cron 均未改变。

最小修复为增加显式 `SIDECAR_HOST_EXIT_RELATION=same|different`：默认仍为 `different`，当前部署明确设为 `same`。修复后的真实 `path-check` 通过。

### 2. OpenWrt BusyBox 不支持小数 sleep

VM36 首次真实门控在测速前因 `sleep 0.5/0.2/0.1` 失败。三处等待改为兼容的 `sleep 1`，全项目回归通过。失败遗留的单个隔离临时目录已清理；没有遗留 Xray 进程或 19080 监听。

### 3. 部署辅助命令兼容性

VM36 没有 GNU `install` 命令。部署辅助流程改为同目录临时文件加 `cp/chown/chmod/mv`，不改变生产运行逻辑。

## 实际运行结果

### `.110` Sidecar

完整 observe 成功，`Result=success`、`ExecMainStatus=0`。报告包含 5 个候选，v2 导出 3 个观察候选：

| 候选 | Sidecar min MB/s | Sidecar avg MB/s | 层级 |
| --- | ---: | ---: | --- |
| 104.24.81.118 | 3.86 | 3.92 | observation |
| 104.21.0.246 | 3.68 | 3.70 | observation |
| 104.17.79.121 | 3.52 | 3.55 | observation |

没有候选达到 6.5 MB/s 优秀标志。

### VM36 真实 PassWall 门控

| 候选 | round1 MB/s | round2 MB/s | min MB/s | avg MB/s | 结果 |
| --- | ---: | ---: | ---: | ---: | --- |
| 104.24.81.118 | 2.96 | 4.11 | 2.96 | 3.54 | low |
| 104.21.0.246 | 4.14 | 2.75 | 2.75 | 3.44 | low |
| 104.17.79.121 | 4.25 | 3.93 | 3.93 | 4.09 | pass |

只有 `104.17.79.121` 通过首日 3.5 MB/s 门槛。系统正确输出 `awaiting_multiday_gate`，没有更新 DNS。

## 备份与回滚

- `.110`：`/var/backups/cfip-sidecar/layered-export-host-relation-20260729-132306`
- VM36 消费端：`/root/openwrt-backup/cfip-layered-consumer-20260729-211825`
- VM36 BusyBox 修复：`/root/openwrt-backup/cfip-busybox-sleep-20260729-221420`

项目级回滚可恢复上述脚本和配置备份，不需要重启 PassWall。网络级最终回滚仍为关闭 VM36 后启动 VM33，两台不得同时占用 `.254`。

## 验收结果

- 全项目回归、Sidecar 测试、v1/v2 协议测试、三日门控测试和单记录规划测试通过。
- PassWall 未停止、重启或切换；原有 Xray 和 1070/1041/11400/15353 监听正常。
- Sidecar 锁空闲，无 Xray JSON、瞬时容器或 `cfip-direct` 附着残留。
- Docker PID 和四个既有容器健康；Ollama idle。
- PC、`.110`、`.140`、VM36 的 Google/YouTube 均为 HTTP 204。
- `auto..auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三个 DNS 视图一致。
- Cloudflare API 已只读复核，五记录与实施前一致。

## 下一 Action Gate

现有 cron 为每日 04:15，晚于 `.110` 的自然 Sidecar 周期：

```text
15 4 * * * timeout 1800 /root/cf-dns-speedup/sidecar-auto-sync.sh run
```

下一步仅将 `CFIP_AUTO_SYNC_APPLY=0` 改为 `1`。该动作不会立即写 DNS；只有同一候选连续 3 个不同日期通过真实 PassWall 门控后，才允许每周期最多更新一条 `auto3/auto4`。主槽自动晋升继续保持关闭。
