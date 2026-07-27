# ESXi VM36 快照回退演练最小修订 - 2026-07-27
## 0. 权威优先级与一次性例外

本修订仅针对本次已确认的 `startConnected` 缺陷处置，并优先覆盖：

- v2 主文档第 3 节“不得删除快照”的对应条款；
- v2 主文档第 4.1 节“VM36 没有快照”的运行前条件；
- 最终审批页“本次不包含快照删除”的对应条款。

覆盖范围只限在 VM36 Powered off 时删除且仅删除快照
`OpenWrt-25.12.1-stage-pre-marker-revert-drill-20260727-123600` 一次。
该快照删除成功并重新建立正确快照后，上述禁止删除、合并和 consolidate 的规则
立即恢复完整效力。所有其他 v2 主文档及最终审批页条款继续有效。

## 1. 修订原因

第一次离线快照创建后，VM36 启动时 `.253` 未恢复。只读检查确认 VM36 的
`ethernet0.startConnected` 为 `FALSE`，Host Client 中“打开电源时连接”未勾选。
用户随后仅对 VM36 勾选并保存该选项，`.253` SSH、IP
`192.168.1.253/24` 和 MAC `00:0c:29:ec:33:dd` 已恢复。

当前快照创建于网卡修复之前。真实 Revert 可能恢复快照时的虚拟设备连接状态，
因此该快照不得用于后续 marker/Revert 验证。当前 marker 不存在，VM36 PassWall
仍禁用且无代理进程；VM33/.254 的两个 Xray、目标监听和 Google/YouTube HTTP 204
均正常。

## 2. 唯一授权范围

本修订只允许处理 VM36 `OpenWrt-25.12.1-stage`：

1. 通过 `.253` SSH 正常关闭 VM36；
2. 在 VM36 Powered off 且 VM33 Powered on 时，删除且仅删除快照
   `OpenWrt-25.12.1-stage-pre-marker-revert-drill-20260727-123600`；
3. 等待删除/合并任务成功，确认无 `Consolidation needed`；
4. 启动 VM36，验证网卡无需手工连接即可恢复 `.253` SSH；
5. 正常关闭 VM36，创建一个新的不含内存、不 quiesce 的离线快照；
6. 按原权威方案继续无秘密 marker、正常重启、一次真实 Revert 和验收；
7. Revert 后异常时仍适用最终审批页限定的 VM36 单次 `Power off` 终态。

不允许再次修改 VM36 的 MAC、port group、网卡类型、CPU、内存、磁盘、固件或
其他 VMX 项。不得操作 VM33/.254，不得启停 PassWall，不得修改 DNS、DHCP、nft、
Sidecar、CFIP、ESXi 主机或 datastore 配置。

## 3. 删除旧快照的硬门控

必须同时满足：

- VM36 已通过 guest 正常关机并显示 Powered off；
- VM33 `Openwrt_Jump63` 显示 Powered on 且无 task；
- Snapshot Manager 中只有上述一个旧快照；
- 旧快照名称、创建时间和 VM36 身份完全匹配；
- 无进行中 task，无 `Consolidation needed`，datastore 空间正常；
- `.254` 两个 Xray、`1070/1041/11400/15353` 和 HTTP 204 均正常。

任一不符立即停止，不删除、不 Revert、不重试。

## 4. 旧快照处置

1. 在 Snapshot Manager 仅选择上述旧快照；
2. 执行一次 `Delete`，不得使用 `Delete All`、`Revert`、`Consolidate` 或 Clone；
3. 等待任务明确成功；任务失败时保持 VM36 Powered off，不重试、不修复快照链；
4. 成功后确认 Snapshot Manager 为空、无 consolidation 提示，VM33 状态未变；
5. 不把快照删除当作备份删除：现有 VM33 冷备和其他备份均不在本次范围。

## 5. 网卡冷启动验证

旧快照删除成功后只启动一次 VM36。不得在 Host Client 手工点击“连接网卡”。
在 120 秒内必须自动恢复 `.253` SSH，并显式确认原 IP、MAC、`VM Network`、
PassWall disabled、无代理进程和无 marker。失败时停止，保持实际状态，不创建新快照。

## 6. 重建快照并继续原演练

冷启动验证通过后：

1. 通过 SSH 正常关闭 VM36；
2. 创建唯一的新离线快照，名称使用新的时间戳；
3. Snapshot memory 和 quiesce 均不选择；
4. 确认 task 成功、唯一 delta 和无 consolidation 提示；
5. 再按原 v2 方案执行 marker 持久性重启、一次 Revert 和完整验收。

本修订只关闭已发现的 `startConnected` 缺陷，不扩大为 PassWall 测试、生产迁移或
通用事务脚本。
