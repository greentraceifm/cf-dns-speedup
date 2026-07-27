# ESXi VM36 离线快照与回退演练 - 最终审批页

## 权威方案

本阶段的权威实施方案由以下文件和本页修订组成：

- 主文档：`esxi-vm36-offline-snapshot-revert-drill-v2-2026-07-27.zh-CN.md`
- 本页的“失败终态修订”优先于主文档第 7 节的对应条款。

以下文件是已被 IT 工程专家组拒绝的历史草稿，不得执行：

- `passwall-stage-full-test-implementation-plan-2026-07-27.zh-CN.md`
- `esxi-vm36-offline-snapshot-revert-drill-2026-07-27.zh-CN.md`

## 失败终态修订

将主文档第 7 节的“Revert 后验收失败”条款替换为：

> **Revert 后验收失败或 `.253` SSH 未恢复**：停止其他变更，重新核对
> VM36 的名称、VMID、MAC、VMX/VMDK 路径和 Host Client 当前选中对象。
> 先尝试正常关闭 VM36；SSH 不可用或 90 秒内未关机时，允许通过 Host
> Client 仅对 VM36执行一次 `Power off`。该失败处置包含在本阶段授权内；
> 不得操作 VM33。

VM36 关机后保持 Powered off，保存 task/event 和无秘密验收结果，结束窗口，
不再次 Revert、不修复 snapshot chain。VM33/.254 必须继续生产运行。

## 审批范围

本次待用户授权的动作仅包括：

1. VM36 身份、存储、guest 和 VM33/.254 只读门控；
2. VM36 正常关机；
3. 创建一个不含内存、不 quiesce 的 VM36 离线快照；
4. 启动 VM36，创建无秘密 marker，正常重启并确认 marker 持久；
5. 再次正常关闭 VM36，对刚创建的快照执行一次 Revert；
6. 启动 VM36 并完成前后健康验收；
7. 仅在 Revert 后验收失败或 SSH 未恢复时，按本页限定对 VM36执行一次
   `Power off`。

不包含：真实 PassWall 配置、PassWall 启停、nft/DHCP/DNS 修改、生产迁移、
VM33 变更、快照删除/合并/consolidate 或任何 ESXi 主机级变更。
