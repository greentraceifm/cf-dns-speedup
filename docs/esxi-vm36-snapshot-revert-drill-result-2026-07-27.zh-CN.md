# ESXi VM36 离线快照与 Revert 演练结果 - 2026-07-27

## 结论

`OpenWrt-25.12.1-stage`（VM36，`192.168.1.253`）离线快照与真实 Revert
演练通过。VM36 能在无需人工连接网卡的情况下冷启动，marker 经正常重启后保持，
真实 Revert 后 marker 消失，证明系统盘持久层已准确回到快照时状态。

生产 VM33 `Openwrt_Jump63`（`.254`）全程保持 Powered on。未停止、重启或修改
生产 PassWall、Xray、DNS、DHCP、nft、Sidecar、CFIP、路由、ESXi 主机或 datastore
配置。

## 实际过程

1. 完成 VM36 身份、存储、guest 和生产链路门控。
2. 第一次离线快照创建后发现 VM36 的 `ethernet0.startConnected=FALSE`，冷启动后
   `.253` 无法恢复。该故障发生在 marker 创建和 Revert 之前。
3. 用户仅对 VM36 启用“打开电源时连接”。只读验证确认 `.253`、原 IP/MAC 和
   PassWall disabled 状态恢复。
4. 原快照创建于网卡修复之前，经 IT 专家组三人一致批准和用户单独授权后，在
   VM36 Powered off 时删除且仅删除该旧快照。Snapshot Manager 随后为空，无
   consolidation 提示。
5. VM36 冷启动后无需手工连接网卡，120 秒门限内自动恢复 SSH。
6. VM36 正常关机后创建新的离线快照：

   `OpenWrt-25.12.1-stage-pre-marker-revert-drill-20260727-154536`

   快照不含内存、不 quiesce。Host Client 确认创建任务成功、快照唯一且无
   `Consolidation needed`。
7. VM36 启动后创建无秘密 marker：

   `/root/cfip-vm36-snapshot-revert-drill.marker`

   marker 属主为 root、权限 `0600`、大小 74 字节，只包含固定标识和创建时间。
   `sync` 后正常重启 VM36，marker 仍存在且格式匹配。
8. 生产门控再次通过后正常关闭 VM36，只对上述新快照执行一次真实 Revert。
9. Host Client 确认 Revert 任务成功。启动 VM36 后 `.253` SSH 自动恢复，marker
   不存在，证明回退有效。

## Revert 后验收

- VM36 IP：`192.168.1.253/24`；
- VM36 MAC：`00:0c:29:ec:33:dd`；
- 系统：ImmortalWrt `25.12.1`；
- Xray：`26.3.27`；
- PassWall UCI 为 `enabled=0`，init disabled；
- 无 Xray、HAProxy 或 sing-box 进程；
- `1070/1041/11400/15353` 无监听；
- DHCP ignore、DHCPv6 和 RA 保持禁用；NDP 未配置，前后状态一致；
- 无 `/tmp/etc/passwall`、PSW/passwall nft 残留；
- marker 不存在；
- 虚拟网卡自动连接并保持 `VM Network`；
- 新快照仍保留，Host Client 无 `Consolidation needed`；
- VM33/.254 始终 Powered on，无异常 task。

生产侧复核：

- `.254` 两个 Xray 进程正常；
- `1070/1041/11400/15353` 监听正常；
- PC、`.140` 和 `.254` 的 Google/YouTube 均为 HTTP 204；
- 无 CFIP/Sidecar 运行任务。

## 异常与处置说明

marker 首次验证脚本在写入和 `sync` 后因 VM36 不提供 `stat` 命令而停止。未重新
创建 marker；改用只读 `ls -ln`、`wc` 和固定行匹配完成验证。该工具差异未影响
marker、快照或 Revert 结果。

Host Client 的 snapshot/revert task ID 未采集，不作推测；任务成功状态由用户在
Host Client 中确认。

## 收口状态

- 演练结果：`VM36_SNAPSHOT_REVERT_DRILL=success`；
- 保留新快照，不删除、不合并、不 consolidate；
- 该快照是短期事务回退点，不替代既有冷备；
- 后续删除快照必须重新审核和授权；
- 本阶段不进入真实 PassWall 配置测试或生产迁移；
- 完整 PassWall 测试仍需独立最小方案、IT 专家审核和用户授权。
