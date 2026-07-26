# ESXi/OpenWrt 冷备份验收记录 - 2026-07-26

## 结论

旧生产 OpenWrt 虚拟机 `Openwrt_Jump63`（VMID 33）已在关机状态完成一次
完整目录冷备份。备份后原 VM 已重新启动，`.254`、PassWall、DNS、HTTP、
`.110`、Docker、Ollama 和 Sidecar 均恢复正常。本次没有修改 VM 硬件、
快照链、PassWall 配置、Cloudflare、CFIP 地址池、防火墙、路由、订阅或
定时任务。

## 备份位置与范围

PC 受保护目录：

```text
D:\Codex_OpenAI_memory_backup_20260519-060435\.secure-backups\openwrt-vm33-cold-20260726\Openwrt_Jump63
```

- 正式复制时间约为 2026-07-26 16:04:26 至 16:05:21 CST。
- 目录包含 22 个文件：21 个源文件和 1 个源 SHA256 清单。
- 逻辑总大小为 `6,162,052,437` bytes。
- VMX、VMSD、基础 VMDK、两层 snapshot VMDK、VMSN 和 VMEM 均存在。
- 快照链仍为 `000002 -> 000001 -> base`，没有删除、合并或 consolidate。
- `.lck` 文件或目录为 0。

早期仅用于验证 Windows SCP 通道的单个 VMX 测试件已在正式备份验收后删除，
避免与完整冷备份混淆。

## 完整性验收

ESXi 在 VM 关机状态生成了包含 21 项的源 SHA256 清单。本机恢复文件 ACL
继承后，对全部 21 个源文件重新计算 SHA256，结果为：

- 已检查：21；
- 缺失：0；
- 哈希不一致：0；
- 非法清单条目：0；
- 结论：PASS。

Windows `scp` 创建的文件最初带有“禁用继承且无访问规则”的 ACL，导致
目录可列出但文件内容不可读。该问题只涉及本地访问控制，不涉及复制内容。
现已对正式备份内 22 个文件恢复父目录 ACL 继承，并逐个确认可读。备份根目录
及正式 VM 目录继续使用受保护 ACL，只允许当前用户、SYSTEM 和
Administrators 完全控制。

受保护目录中的 `BACKUP-VERIFICATION.txt` 保存详细无秘密验收结果；顶层
`SHA256SUMS` 覆盖操作卡、说明文件、验收记录和源 SHA256 清单，便于后续
检查文档层是否发生变化。整个受保护目录不进入 GitHub、Notion 或普通聊天
记录。

## 恢复后运行状态

恢复验收确认：

- `.254` ping 和 SSH 正常；
- PassWall 有两个 Xray 进程，版本为 `26.6.27`；
- `1070`、`1041`、`11400`、`15353` 监听恢复；
- 当前活动 CFIP 任务为 0；
- `auto..auto4` 在 `192.168.1.1`、`192.168.1.254` 和 `1.1.1.1`
  三个 DNS 视图一致；
- PC、`.140`、`.110` 和路由器的 Google/YouTube 检查均为 HTTP 204；
- `.110` Docker active，PID `1144`，四个既有容器 healthy；
- Ollama active 且无驻留模型；
- Sidecar timer enabled/active/waiting，service inactive/success；
- Sidecar 锁空闲，无 Xray JSON 或瞬时容器残留。

Cloudflare API 本次未复核。公共 DNS 一致不能替代 API 一致性声明。

## 当前安全边界

该冷备份已通过逐文件一致性校验，但尚未在隔离 VM 中执行实际恢复启动测试。
因此：

- 不删除或覆盖当前生产 VM；
- 不删除、合并或 consolidate 现有快照；
- 不升级旧 VM hardware、固件模式或虚拟磁盘格式；
- 不把该冷备份作为唯一恢复层级；
- 后续新 VM/T5 实验必须先在独立网络和临时地址完成启动、接口、DNS、
  PassWall 与回滚演练，不能直接接管 `.254`。

旧 VM 手工恢复仍以 `esxi-openwrt-manual-rollback-runbook-2026-07-25.md`
为准。紧急情况下只启动原 VM 的 ESXi Shell 命令为：

```text
vim-cmd vmsvc/power.on 33
```
