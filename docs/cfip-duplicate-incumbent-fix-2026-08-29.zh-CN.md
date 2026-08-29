# CFIP 优选 IP 重复主槽失格修复与全链路复核（2026-08-29）

## 结论

本次发现并修复一个确定性的主槽去重边界缺陷：当重复主槽中的一个 incumbent 在当天真实 PassWall 复测低于 `4.0 MB/s` 时，旧逻辑会把整个重复修复计划安全放弃，即使已有满足主槽门槛、连续日期门控且速度高于当前有效弱主槽的替代候选。

修复后仍保持原有安全约束：不降低 `3.5 MB/s` 竞争门槛、不降低 `4.0 MB/s` 主槽门槛、不绕过连续三日门控、不改变 `25%` 正常晋升条件、不批量改写 Cloudflare，每个周期最多更新一条记录。

## 复现证据

- 2026-08-29 自然 Sidecar 周期成功，导出 3 个 observation 候选；Sidecar 报告为 5 行双轮 HTTP 200。
- VM36 04:35 自然同步成功，仅更新 `auto3`；当时 `auto=104.17.129.81`、`auto1=104.17.129.81` 仍重复。
- 同日主槽真实隔离复测中，`104.17.129.81` 的最低速度为 `3.99 MB/s`，因此当天状态为 `low`；`104.17.134.190` 最低 `4.25 MB/s` 并通过。
- 竞争资格中已有 `104.17.130.125` 最低 `4.14 MB/s`、`104.17.158.61` 最低 `4.11 MB/s`，均满足主槽最低门槛所需的历史资格条件。
- 这说明问题不是 Sidecar 无候选、DNS 污染或 Cloudflare 读取失败，而是重复 incumbent 失格时的计划构建逻辑过早退出。

## 实施的最小修复

修改 `sidecar-auto-sync.sh` 的 `build_primary_targets()`：

1. 先识别重复主槽，再分别判断每个当前主槽是否仍有有效主槽资格。
2. 对失格但重复的 incumbent 保留一个零速度占位，仅用于保留原槽并替换后续重复槽。
3. 计算替代候选的比较基准时忽略该失格 incumbent，只使用仍有效主槽的最低速度。
4. 替代项仍必须满足现有主槽门槛，并严格高于当前有效弱主槽；没有满足条件的候选时继续安全等待。
5. 增加回归场景，覆盖“重复 incumbent 当日失格但存在安全替代项”的情况。

## 测试与部署

- 本地 `bash -n`：通过。
- `tests/test-sidecar-auto-sync-plan.sh`：通过。
- `tests/run-all-regression-tests.sh`：通过。
- 部署前生产脚本哈希：`8cfccbfe8fb3b56e59834c3c479fb990146466aa4b5586f999e93eafb52a55b5`。
- 修复后生产脚本哈希：`814a757d9a1e57eb101d0aa168eb8b58896ffcdfd7fa3faae3e452fa42f31b7e`。
- root-only 回滚目录：`/root/openwrt-backup/cfip-duplicate-incumbent-fix-20260829-093137`。
- PassWall 重启：`0`；DNS 写入：`0`；Cloudflare 写入：`0`；cron 变化：`0`。

## 修复后完整只读复核

- `.110`：`cfip-sidecar.service` 为 `Result=success`、退出码 `0`、`MainPID=0`；timer active/enabled；报告 5 行、导出 3 行；Sidecar 锁空闲；无临时 Xray 配置、无瞬时 CFIP 容器、`cfip-direct` 无附着；`sub2api`、PostgreSQL、Redis 均 running/healthy；Ollama 无驻留模型。
- VM36：新脚本哈希匹配；唯一 04:35 cron 保持；旧 06:30 cron 不存在；四把项目锁空闲；一个 Xray 进程承载 `1070/1041/11400/15353`；Google/YouTube HTTP 204。
- DNS：`auto`、`auto1`、`auto2`、`auto3`、`auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致；Cloudflare 五条记录只读 GET 全部 HTTP 200。
- 当前主槽仍为 `auto=104.17.129.81`、`auto1=104.17.129.81`、`auto2=104.17.134.190`，因为修复部署发生在本次自然同步之后，未人工补写 Cloudflare；下一自然周期才是修复实际处理重复槽的验证点。

## 独立观察项

本次复核中 `.110` 宿主直连 Google/YouTube 请求超时，但 Sidecar 自然测速成功，且宿主、Sidecar、VM36 直连出口关系符合既有拓扑。该现象属于宿主直连路径的独立可达性问题，目前没有证据表明它影响 CFIP 代理测速或 VM36 生产代理，因此未修改 DNS、PassWall、路由、出口关系或 Sidecar 门控。若后续自然周期仍重复出现，应单独评估 `.110` 直连路径，不与本次主槽去重修复混合处理。

## 下一步

等待下一次自然 Sidecar 与 VM36 04:35 同步，观察新脚本是否按每周期一条记录规则将重复主槽拆分。不得手工改写 `auto`/`auto1`，不得补跑同步，不得降低门槛。若候选仍不满足严格比较条件，保持当前值是正确的故障安全结果。
