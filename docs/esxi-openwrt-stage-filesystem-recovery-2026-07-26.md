# OpenWrt staging 文件系统离线修复与扩容记录 - 2026-07-26

## 范围与结论

本次只处理 ESXi `192.168.1.238` 上的 staging 虚拟机 `OpenWrt-25.12.1-stage`（VMID 36，临时地址 `192.168.1.253`）。生产 OpenWrt `192.168.1.254`（VMID 33）、PassWall、Cloudflare、CFIP 池、Sidecar、`.110` 和 `.140` 均未迁移或修改。

staging 的 4 GiB 分区此前执行在线 `resize2fs` 时发生部分增长并返回参数错误。修复前根文件系统只有约 374.4 MiB。通过双克隆救援拓扑完成离线检查、最小自动修复和扩容后，根文件系统为约 3.9 GiB，连续两次启动正常，新启动日志无 EXT4、I/O 或文件系统损坏错误。

文件系统验收后，已在 staging 安装官方 release 的 PassWall/Xray 套件；生产切换尚未开始。安装与隔离验收见 `openwrt-stage-passwall-install-2026-07-26.md`。

## 根因与保护措施

原始镜像的 ext4 reserved GDT 元数据在在线扩容路径中触发异常：

```text
reserved block 24 not at offset 23
ext4_resize_fs: error (-22)
```

在线命令虽然报错，但文件系统已从约 290 MiB 部分增长到约 374 MiB。因此没有再次运行在线 `resize2fs`，也没有使用强制参数或 `e2fsck -y`。

离线处理前保留原磁盘不动，并创建两份 VMFS thin 克隆：

```text
/vmfs/volumes/datastore1/OpenWrt-25.12.1-stage-20260726/OpenWrt-25.12.1-stage-thin.vmdk
/vmfs/volumes/datastore1/OpenWrt-25.12.1-stage-20260726/OpenWrt-25.12.1-stage-rescue.vmdk
/vmfs/volumes/datastore1/OpenWrt-25.12.1-stage-20260726/OpenWrt-25.12.1-stage-work.vmdk
```

三块磁盘均通过 `vmkfstools -x check`，ESXi datastore 终检可用空间约 618.3 GiB。

## 离线修复过程

首次双盘启动时，两份克隆具有相同 PARTUUID。内核实际选择了 `sdb2`（work）作为根目录。设备号门控发现根设备为 `8:18` 后立即停止，未对该分区运行 `e2fsck` 或 `resize2fs`。

随后只修改救援盘的 GRUB 参数，将救援启动固定为 `root=/dev/sda2`。再次启动后确认：

```text
救援根分区：sda2，设备号 8:2
待修复分区：sdb2，设备号 8:18
```

卸载 `sdb1/sdb2` 后，只读检查发现唯一明确问题：

```text
Padding at end of inode bitmap is not set.
```

使用 `e2fsck -f -p /dev/sdb2` 完成安全自动修复，返回码 1；随后 `e2fsck -f -n` 返回 0。

离线扩容结果：

```text
扩容前：98,304 个 4 KiB 块
扩容后：1,040,256 个 4 KiB 块
resize2fs 返回码：0
```

扩容后的 `e2fsck -p` 校正 resize inode 7 的尺寸，返回码 1；最终 `e2fsck -f -n` 返回 0。

## 启动验收

VM 36 最终只挂载 `OpenWrt-25.12.1-stage-work.vmdk`。首次启动和再次正常重启均通过：

- 根设备为唯一的 `sda2`（设备号 `8:2`）；
- 根文件系统约 3.9 GiB，已用约 38.5 MiB，使用率约 1%；
- 分区 2 保持 `66560s` 至 `8388607s`；
- EXT4 先只读挂载，再正常重新挂载为读写；
- 新启动日志没有 EXT4 warning、I/O error、corrupt 或 buffer error；
- `.253/24`、网关 `192.168.1.1` 和 DNS `192.168.1.1` 保持不变；
- DHCPv4、DHCPv6、RA 继续禁用，UDP 67/547 无监听；
- 官方仓库此前签名更新成功，`parted`、`e2fsprogs`、`resize2fs` 仍已安装。

生产 VM 33 在整个操作期间保持开机；PC 的 Google 与 YouTube 检查返回 HTTP 204。未停止或重启生产 PassWall。

## 回滚点

VMX 回滚文件：

```text
/vmfs/volumes/datastore1/OpenWrt-25.12.1-stage-20260726/OpenWrt-25.12.1-stage.vmx.pre-offline-fs-20260726
/vmfs/volumes/datastore1/OpenWrt-25.12.1-stage-20260726/OpenWrt-25.12.1-stage.vmx.pre-work-boot-20260726
```

若 work 盘后续启动失败，手动回滚 staging：

1. 只关闭 VM 36，确认 VM 33 仍开机。
2. 备份当前 active VMX。
3. 用 `OpenWrt-25.12.1-stage.vmx.pre-offline-fs-20260726` 恢复 active VMX。
4. 执行 `vim-cmd vmsvc/reload 36`。
5. 启动 VM 36；由于 `ethernet0.startConnected = "FALSE"`，启动后执行 `vim-cmd vmsvc/device.connection 36 4000 true`。
6. 验证 `.253` 对应 MAC `00:0c:29:ec:33:dd`，不得修改或启动第二个 `.254`。

该回滚会回到可启动但根文件系统约 374 MiB 的原 staging 磁盘，不影响生产 `.254`。

## 访问收口

本次临时加入 ESXi 的两条 Codex 公钥已删除，`authorized_keys` 从 2 行恢复为 0 行；公钥撤销已通过登录失败验证。本地临时 RSA 私钥和公钥也已删除。没有保存或记录 ESXi 密码。

## 后续状态

staging 使用 `192.168.1.1` DNS 查询 Google 时得到当前网络的代理映射地址；对 `1.1.1.1:53` 的查询也被现有网络透明处理，只有生产 `.254` DNS 返回 Google 真实地址。`.253` 尚未进入生产 PassWall 路径，因此 Google 直连失败属于预期隔离效果。默认路由、DNS 查询、`1.1.1.1` ICMP 和官方 ImmortalWrt 软件源均可达。

下一步只读比较 `.254` 与 `.253` 的 PassWall UCI 结构和运行依赖。通过前不导入生产节点正文、不启用 `.253` 代理、不切换 `.254`。
