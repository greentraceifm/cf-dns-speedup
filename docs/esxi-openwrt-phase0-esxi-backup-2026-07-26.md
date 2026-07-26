# ESXi/OpenWrt 阶段 0 主机备份记录 - 2026-07-26

## 结论

`.238` ESXi 主机清单、网络映射、VM 自动启动顺序、主机配置包和 `.254`
虚拟硬件/快照链均已完成核验。主机配置包已下载到 PC 的非 Git 受保护目录，
归档结构和 SHA256 校验通过。

本批次没有关闭或重启 ESXi、虚拟机、PassWall、Docker、Ollama、Sidecar
或 DNS，没有修改 VM、vSwitch、datastore、快照、Cloudflare、地址池、
防火墙、路由、订阅或定时任务。

## 主机与 datastore

- 主机：`192.168.1.238`。
- SSH RSA 指纹与 `.140` 已知主机记录一致。
- 版本：VMware ESXi 6.7.0 build `20497097`。
- `datastore1`：VMFS-6，总大小 `792153030656` bytes，可用
  `665366560768` bytes。
- VM 清单：`Openwrt_Jump63`（VMID 33）、`Ros`（VMID 34）、
  `Ubuntu-Ollama`（VMID 35）、`Windows10`（VMID 7）。

## 自动启动顺序

当前 ESXi 自动启动顺序与恢复依赖一致：

1. `Ros`：start order 1，delay 20 秒。
2. `Openwrt_Jump63`：start order 2，delay 40 秒。
3. `Ubuntu-Ollama`：start order 3。
4. `Windows10`：不自动启动。

## 网络映射

- `vSwitch0` 使用 `vmnic0`，包含 `Management Network` 和 `VM Network`。
- `WAN6` 使用 `vmnic5`。
- `LAN5` 使用 `vmnic4`。
- `LAN4` 使用 `vmnic3`。
- `LAN3` 使用 `vmnic2`。
- `LAN2` 使用 `vmnic1`。
- 所有 vSwitch MTU 为 1500，所有 port group VLAN ID 为 0。
- 六张 I211 均为 admin/link up；除 `vmnic1` 外均为 1000 Mbps Full；
  `vmnic1` 仍只协商到 10 Mbps Full。这是变更前已存在的链路问题。

## `.254` 虚拟硬件

- VM：`Openwrt_Jump63`，VMID 33。
- VMX：`[datastore1] Openwrt_Jump63/Openwrt_Jump63.vmx`。
- 虚拟硬件：vmx-14；固件：BIOS；1 vCPU；1024 MB 内存。
- 一张 generated MAC 虚拟网卡，连接 `VM Network`，当前 connected 且
  startConnected。
- 虚拟磁盘标称容量为 4 GiB。

实际 MAC、物理网卡 MAC、配置包哈希和精确恢复字段只保存在 PC 受保护恢复
清单中，不进入 GitHub。

## 快照链风险

`.254` 当前不是单一基础磁盘，而是两层快照链：

```text
jump63uefi-000002.vmdk
  -> jump63uefi-000001.vmdk
     -> jump63uefi.vmdk
```

ESXi 报告存在两个快照，第二个是第一个的子节点。当前活动磁盘为
`jump63uefi-000002.vmdk`。

因此后续冷备份必须满足：

- 正常关闭 VM 后复制或导出整个 `Openwrt_Jump63` 目录；
- 包含 VMX、VMSD、基础磁盘、全部 delta/descriptor 和相关元数据；
- 禁止只复制当前 `000002.vmdk`；
- 独立冷备份和恢复验证完成前，不删除、合并或 consolidate 快照；
- 回滚期内不升级 VM hardware、固件模式或磁盘格式。

## ESXi 主机配置包

已依次执行 ESXi `sync_config` 和 `backup_config`，并通过主机返回的一次性
下载地址获取配置包。PC 保存位置：

```text
D:\Codex_OpenAI_memory_backup_20260519-060435\.secure-backups\esxi-238-phase0-20260726-0900
```

目录内包含主机配置包、实际恢复清单、`.254` 详细恢复信息和 SHA256 清单。
目录 ACL 只允许当前用户、SYSTEM 和 Administrators；压缩包结构与全部
SHA256 均已验证。该目录不属于 Git 仓库，禁止同步到 GitHub、Notion 或
普通聊天记录。

## 阶段 0 收口

旧 `.254` 已于 2026-07-26 在关机状态完成完整 VM 目录冷备份，并在重新
开机后通过 PassWall、DNS、HTTP、`.110`、Docker、Ollama 和 Sidecar
恢复验收。21 个源文件的 SHA256 已在 PC 重新计算，缺失和不一致均为 0。
详细记录见 `esxi-openwrt-cold-backup-2026-07-26.md`。

至此阶段 0 的配置备份、ESXi 主机配置包和旧 VM 独立冷备份均已完成。
冷备份尚未在隔离 VM 中执行实际恢复启动测试，因此仍不得删除旧 VM、合并
现有快照、升级旧 VM hardware 或直接开始生产切换。下一阶段只能先进行
隔离恢复演练或新 VM/T5 实验，并继续遵守手工回滚说明书。
