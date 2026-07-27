# ESXi VM36 离线快照与回退演练方案 v2 - 2026-07-27

## 1. 审批范围

本阶段只处理 ESXi `192.168.1.238` 上的 staging 虚拟机 VM36
`OpenWrt-25.12.1-stage`（`192.168.1.253`）：

1. 建立一个不含内存的离线快照；
2. 用无秘密 marker 验证 guest 持久层；
3. 对 VM36 执行一次真实 `Revert`；
4. 验证 VM36 回到快照前状态并保留快照。

本阶段不读取或传输 `.254` 的 PassWall 配置，不修改 nft、DHCP、DNS、
PassWall、Xray、订阅或生产配置，不启动 staging PassWall。VM33
`Openwrt_Jump63` 和 `.254` 全程只读。

即使本演练成功，也不得自动进入完整 PassWall 测试。

## 2. 控制面与秘密边界

- ESXi 只通过 LAN 内 `https://192.168.1.238` Host Client 操作。
- 当前 Codex SSH 公钥不能登录 `.238`；不得从截图、文档、聊天或命令行
  复用 ESXi root 密码。
- `.253` 只使用现有独立 SSH 密钥访问。guest IP 只能通过 `.253` SSH
  核对；VMware Tools 未运行，不能依赖 Host Client 显示 guest IP。
- `.254` 只能经 `.140` 的既有受保护通道做只读健康检查；禁止写命令、
  init/service、包管理、nft 和 UCI 修改。
- marker 内容不含秘密；但 VM36 快照包含系统盘、密码散列和 SSH 主机材料。
  `datastore1` 属于受访问控制的秘密存储边界，不得导出或复制本次快照链。

Host Client 会话不可用、对象身份不明确或需要重新输入凭据时停止，由用户
恢复安全登录后再继续。

## 3. 不可突破的边界

- 只能操作 VM36；不得关闭、重启、快照、Revert 或修改 VM33。
- 不删除、合并或 consolidate 任何快照。
- 不修改 VM36/VM33 的 VMX、VMDK、网卡、MAC、port group、CPU、内存、
  固件、虚拟硬件版本或自动启动设置。
- 不修改 datastore、VMFS、vSwitch、物理网卡或 ESXi 主机配置。
- 不启动 PassWall，不导入真实节点配置，不运行 CFIP/Sidecar 任务。
- 任一门控失败立即停止；不得在同一窗口修复后重试。

## 4. 运行前硬门控

### 4.1 VM36 与存储身份

在 Host Client 中确认：

- 名称 `OpenWrt-25.12.1-stage`，inventory ID 为 VM36；
- VMware MAC `00:0c:29:ec:33:dd`，port group 为 `VM Network`；
- VMX/VMDK 位于 `datastore1/OpenWrt-25.12.1-stage-20260726/`；
- 系统盘为 `OpenWrt-25.12.1-stage-thin.vmdk`，容量 4 GiB；
- 磁盘不是 `Independent` 模式；
- VM36 没有快照、没有 `Consolidation needed`、没有进行中的 task；
- datastore 可用空间不少于 10 GiB；
- VM33 `Openwrt_Jump63` 保持 Powered on 且没有 task。

路径、磁盘、snapshot chain、consolidation 状态或 VMID 任一不一致时停止。

### 4.2 `.253` guest 基线

通过 `.253` SSH 只读确认：

- `192.168.1.253/24`、MAC `00:0c:29:ec:33:dd`；
- ImmortalWrt `25.12.1`、Xray `26.3.27`；
- PassWall 配置 `enabled=0`、init disabled；
- Xray、HAProxy 及代理辅助进程为 0；
- `1070/1041/11400/15353` 无监听；
- DHCPv4、DHCPv6、RA、NDP 均 disabled，`67/68/547` 无监听；
- `/tmp/etc/passwall`、PassWall 锁和 `PSW/PSW_*` 规则无残留；
- `/root/cfip-vm36-snapshot-revert-drill.marker` 不存在；
- 网卡 Connected，仍连接 `VM Network`。

本方案不跨关机保存配置、nft、route 或 rule 摘要。Revert 后重新执行同一组
显式检查，避免摘要存储和易变字段造成误判。

### 4.3 `.254` 生产基线

只读确认：

- 两个 Xray 进程；
- `1070/1041/11400/15353` 全部监听；
- Google 和 YouTube 均为 HTTP 204；
- 无 CFIP/PassWall 更新任务或锁；
- VM33 没有 power、snapshot、reconfigure 或 storage task。

任一生产检查异常时不关闭 VM36，不创建快照。

## 5. 创建 VM36 离线快照

1. 记录开始时间，生成唯一名称：

   ```text
   OpenWrt-25.12.1-stage-pre-marker-revert-drill-YYYYMMDD-HHMMSS
   ```

2. 通过 `.253` SSH 正常关机，在 Host Client 等待 VM36 进入 Powered off。
3. 90 秒内没有关机时立即停止：不执行 `Power off`，不创建快照，VM36 保持
   实际原状态；由于尚未发生 ESXi 写操作，不宣称其已关机。
4. VM36 确认 Powered off 后，再次确认 VM33 仍 Powered on，当前选中对象
   确为 VM36。
5. 为 VM36 创建快照：
   - Snapshot memory：不选；
   - Quiesce guest file system：不选；
   - 描述注明“VM36 staging marker revert drill；不得用于 VM33”。
6. 等待 task 成功，记录 task ID、开始/结束时间和 datastore 前后可用空间。
7. 在 Snapshot Manager 确认快照只属于 VM36；在 Datastore Browser 中确认
   VM36 目录出现与该快照对应的唯一 `-000001.vmdk` descriptor/delta，且
   VM36 当前磁盘 backing 指向该 delta。
8. 确认没有 `Consolidation needed`，VM33 无 task 或状态变化。
9. 启动 VM36，等待 `.253` SSH 恢复，再执行 guest 与生产基线。

快照创建 task 已开始后发生失败时，保持 VM36 Powered off，不重试、不修复
snapshot chain。

## 6. 持久 marker 与 Revert 演练

### 6.1 验证 marker 位于持久层

1. 在 `.253` 创建：

   ```text
   /root/cfip-vm36-snapshot-revert-drill.marker
   ```

2. 文件仅包含固定字符串和时间，owner root、权限 `0600`，不含密码、token、
   节点、订阅、UUID 或配置摘要。
3. 执行 `sync`，正常重启 VM36；不使用 Revert。
4. 等待 `.253` SSH 恢复，确认 marker 仍存在且内容匹配。
5. marker 重启后消失、VM36 未正常恢复或 `.254` 异常时停止；不执行 Revert，
   记录 VM36 实际状态。

该重启证明 marker 位于 VM36 持久 overlay/VMDK，而不是随重启消失的临时层。

### 6.2 关闭并 Revert

1. 再次确认 `.254` 生产基线正常。
2. 正常关闭 VM36，等待 Powered off。90 秒超时时停止，不自动 Power off，
   记录 VM36 实际状态，不执行 Revert。
3. VM36 确认 Powered off 后，在 Snapshot Manager 核对 VM36、快照唯一名称、
   创建时间和对应 delta。
4. 选择刚创建的快照并执行 `Revert`。禁止 `Delete`、`Delete All`、
   `Consolidate`、`Clone` 或 VM33 的任何操作。
5. Revert task 失败时保持 VM36 Powered off，不重试。
6. Revert task 明确成功后启动 VM36，等待 `.253` SSH 恢复。

### 6.3 回退验收

必须同时满足：

- marker 不存在；
- `.253` IP、MAC、系统版本、Xray 版本匹配；
- PassWall 仍 `enabled=0`、init disabled；
- 无代理进程、目标监听、锁、`/tmp/etc/passwall` 或 `PSW/PSW_*` 残留；
- DHCPv4、DHCPv6、RA、NDP 仍 disabled；
- 虚拟网卡 Connected，仍连接 `VM Network`；
- VM36 快照仍存在，没有 consolidation 提示；
- VM33/.254 的 Xray、监听、HTTP 和 task 状态始终正常。

全部通过才能记录 `VM36_SNAPSHOT_REVERT_DRILL=success`。

## 7. 分阶段失败终态

- **快照创建前关机失败**：不执行任何 ESXi 写操作；VM36 保持实际原状态。
- **快照创建 task 开始后失败**：VM36 保持 Powered off；不重试、不修复链。
- **marker 持久性重启失败**：不执行 Revert；记录 VM36 实际状态，结束窗口。
- **Revert 前关机失败**：不执行 Revert；记录 VM36 实际状态，结束窗口。
- **Revert task 开始后失败**：VM36 保持 Powered off；不重试。
- **Revert 后验收失败**：停止继续变更；若 VM36 已运行但状态异常，只关闭
  VM36 的动作也需重新核对身份并获得单独授权。

所有失败状态下，VM33/.254 继续生产运行。不得为恢复 staging 修改 VM33、
网络、datastore 或 snapshot chain。

## 8. 成功后的收口

- 保留 VM36 快照；不删除、不合并、不 consolidate。
- 快照是短期事务回退点，不替代现有冷备份。
- 删除快照或 consolidate 必须另行审核授权。
- 记录实际快照名称、VM36 身份、snapshot/revert task ID、时间、datastore
  空间和前后健康结论；不记录凭据、配置摘要或磁盘内容。
- 只有本阶段成功后，才能开始设计完整 PassWall 测试的最小实现；该实现
  必须单独提交 IT 专家组审核并由用户再次授权。
