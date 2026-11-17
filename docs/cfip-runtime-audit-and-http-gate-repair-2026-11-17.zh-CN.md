# CFIP 运行审计与 HTTP 门控修复报告

日期：2026-11-17（Asia/Shanghai）

## 结论

本次确认生产链路没有被破坏，发现并修复了一个会造成无谓回滚的门控问题：

- 2026-11-17 04:35 自然同步确实完成了候选门控并更新了
  `auto4.greentraceifm.top`，但更新后的 Google/YouTube HTTP 门控同时超时；
- 原脚本随后成功恢复更新前的五槽快照，历史状态为
  `failed_rolled_back`，不是 DNS 写坏；
- 部署器的前后 DNS 快照还把公共 `1.1.1.1` 的瞬时 `NO_ANSWER` 当成生产
  DNS 发生变化，导致一次安全部署在替换前被错误阻断；
- 已将 HTTP 门控改为有限三次重试，并将部署器的 DNS 不变性检查限定为
  VM36 本地 resolver 与 LAN 网关；公共 resolver 仍在部署后单独只读核验。

最终生产状态：**链路正常，修复已部署，历史重复槽保留等待自然周期安全收敛。**

## 生产证据

固定维护链路：

```text
本机 -> 192.168.1.140 OpenClaw -> VM36 192.168.1.254
```

### .110 Sidecar

- `cfip-sidecar.service` 最近自然结果：`success`
- timer：`active/enabled`
- 最新报告：存在，5 行
- 候选导出：存在，3 行
- Xray 残留：0
- 瞬时 CFIP 容器：0
- `sub2api`、`sub2api-postgres`、`sub2api-redis`：`healthy`
- `.110` 宿主直连 Google/YouTube：本次为 `000` 超时

最后一项是 `.110` 宿主直连出口限制，不能作为 VM36 代理链路故障证据。

### VM36

- 受保护密钥认证：通过
- Xray：1 个有效进程
- 监听：`1070`、`1041`、`11400`、`15353` 全部存在
- 项目锁：空闲
- 默认路径 Google/YouTube：HTTP `204`
- SOCKS 路径 Google/YouTube：HTTP `204`
- 唯一自动同步 cron：

```text
35 4 * * * timeout 1800 /root/cf-dns-speedup/sidecar-auto-sync.sh run >> /root/cf-dns-speedup/sidecar-auto-sync.log 2>&1
```

- 旧 `06:30` 任务：不存在
- `CFIP_AUTO_SYNC_APPLY=1`
- `CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY=1`

### DNS 与 Cloudflare

部署后连续三轮查询 `1.1.1.1` 均一致：

```text
auto   = 162.159.237.251
auto1  = 104.26.1.38
auto2  = 104.17.129.81
auto3  = 104.26.7.141
auto4  = 104.26.1.38
```

Cloudflare 五条记录只读 GET 均为 HTTP `200`，内容与上述生产记录一致。

当前 `auto1` 与 `auto4` 仍重复 `104.26.1.38`。本次没有手工修改 DNS；
2026-11-17 的 `auto4` 去重更新因 HTTP 门控失败而被安全回滚，等待下一次
自然周期重新按真实候选和单记录门控处理。

## 失败事件与根因

### 2026-11-17 自然周期

历史记录：

```text
status=failed_rolled_back
record=auto4.greentraceifm.top
stage=http_gate_after
rollback=verified_five_slot_snapshot
task_id=20261117T043500-28018
```

含义是：

1. Cloudflare 更新已经发生；
2. 更新后的双 HTTP 门控未通过；
3. 脚本恢复了更新前五槽快照；
4. 回滚后的五槽验证通过；
5. 因此任务失败，但生产状态恢复。

这不是 Cloudflare 内容损坏，也不是 PassWall 或 DNS 服务中断。

### 部署器问题

第一次修复部署在 HTTP 后验遇到瞬时超时，自动回滚。

第二次尝试没有替换生产脚本，原因是部署器比较部署前后完整 DNS 快照时，
`1.1.1.1` 的缓存状态出现瞬时差异。公共 resolver 的缓存变化不代表
VM36 或 LAN DNS 被修改，因此该比较条件过严。

## 已实施修复

### 1. 生产同步脚本

文件：`sidecar-auto-sync.sh`

- Google 和 YouTube HTTP 门控每轮最多执行 3 次；
- 每次失败记录两条最终 HTTP 状态；
- 瞬时失败后恢复会记录恢复轮次；
- 三轮仍失败时继续执行原有安全回滚；
- 不改变候选门槛、三日资格、主槽晋升、竞争槽规则或单记录限制。

部署后脚本 SHA256：

```text
d9b825afd2853f5fdaf5ea1ffe9d47c1a4261fcd2034bf42d1f6a2b5d54087c3
```

### 2. 部署器

文件：`tools/Deploy-CfipGlobalDedupe.ps1`

- 部署前后 DNS 不变性比较只使用 VM36 本地 resolver
  `127.0.0.1` 和 LAN 网关 `192.168.1.1`；
- 公共 DNS 不参与变更前后快照比较；
- 部署后仍单独执行三路 DNS 和 Cloudflare 只读核验；
- 保留原子替换、root-only 备份、锁、PassWall PID/监听、cron、报告和
  HTTP 后验；
- 任一生产后验失败仍自动恢复旧脚本。

生产 root-only 备份：

```text
/root/openwrt-backup/cfip-global-dedupe-20261117-214621
```

部署结果：

```text
PassWall 重启：0
DNS 修改：0
Cloudflare 写入：0
cron 修改：0
手动同步：0
```

## 测试

通过：

- `bash -n sidecar-auto-sync.sh`
- `tests/test-sidecar-auto-sync-plan.sh`
- `tests/run-all-regression-tests.sh`
- `sidecar/tests/run-tests.sh`
- PowerShell 部署脚本语法检查
- VM36 BusyBox 计划测试
- 部署后固定链路只读验收

测试覆盖了 HTTP 门控“首轮失败、次轮恢复”的路径。

Windows Git Bash 中真实 `flock` 竞争测试仍按既有规则跳过；VM36 生产锁
后验为空闲。

## 收口建议

本轮不再手工改写 `auto1` 或 `auto4`，也不补跑同步任务。等待下一次自然
`04:35` 周期，重点观察：

1. `auto4` 是否在候选通过真实门控后安全去重；
2. 更新后 HTTP 门控的有限重试是否吸收瞬时抖动；
3. 失败时是否继续准确记录 `failed_rolled_back` 或 `rollback_failed`；
4. 是否仍保持最多一条 Cloudflare 记录变更。

如果下一自然周期没有安全候选，保持重复现状仍是正确的故障安全行为。
