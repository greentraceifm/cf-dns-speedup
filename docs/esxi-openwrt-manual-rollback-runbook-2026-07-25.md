# ESXi/OpenWrt 重建手工回滚说明书 - 2026-07-25

## 用途

当新 OpenWrt VM 或可选的 Samsung T5 ESXi 8 实验失败，且自动回滚、Codex、
PassWall 或互联网均不可用时，使用本说明书。整个流程不依赖 `.140` 和任何
外部服务。

变更前必须打印本文档，并根据 ESXi Host Client 和变更前清单填写下面所有
空白。纸质说明书中不要填写密码、token、订阅、UUID 或节点凭据。

## 变更前恢复卡

```text
日期、时间和现场操作人：_______________________________________________
ESXi 管理地址：https://192.168.1.238
ESXi 本地控制台管理 IP/VLAN：__________________________________________
旧 OpenWrt VM 名称：Openwrt_Jump63
旧 OpenWrt VM inventory ID：___________________________________________
旧 OpenWrt VMX datastore 路径：________________________________________
旧 OpenWrt 虚拟磁盘路径：______________________________________________
旧 OpenWrt 虚拟网卡 MAC：______________________________________________
旧 OpenWrt port group：VM Network
旧 OpenWrt 固件模式 / vHW 版本：_______________________________________
新 OpenWrt VM 名称和 inventory ID：____________________________________
新 OpenWrt 虚拟网卡 MAC：______________________________________________
已验证无冲突的临时管理 IP：___________________________________________
临时 IP 完成 DHCP/静态地址排除的时间：_________________________________
ESXi 6.7 主机配置备份路径和校验值：____________________________________
旧 OpenWrt 冷备份/导出路径和校验值：___________________________________
受保护 OpenWrt 配置备份路径：__________________________________________
Intel SSD 型号/序列号末位：____________________________________________
Samsung T5 型号/序列号末位：___________________________________________
开机画面显示的一次性启动菜单按键：_____________________________________
最近一次已知正常回滚测试日期/结果：____________________________________
```

必须保留的物理网卡映射：

| ESXi 网卡 | 当前用途 / port group |
| --- | --- |
| `vmnic0` | Management Network / VM Network |
| `vmnic5` | WAN6 |
| `vmnic4` | LAN5 |
| `vmnic3` | LAN4 |
| `vmnic2` | LAN3 |
| `vmnic1` | LAN2；变更前只协商到 10 Mbps |

现场必须准备连接 `.238` 的显示器和键盘、一台可以设置静态备用地址的 LAN
笔记本，以及 ESXi Host Client 访问能力。`.238` 没有 IPMI，因此没有人员
在设备旁边时，禁止开始 ESXi 冷启动实验。

## 立即生效的安全规则

回滚期间：

- 不更新 Cloudflare DNS 或 `auto..auto4`；
- 不修改候选池、冠军池或稳定池；
- 不降低或绕过真实 PassWall `6.5 MB/s` 门槛；
- 不修改防火墙、路由、订阅、凭据或 Sidecar 策略；
- 不运行 CFIP 扫描、`external-observe`、`stability-update` 或候选应用动作；
- 不删除任何 OpenWrt VM、datastore、快照、虚拟磁盘或备份；
- 不合并快照，不升级 VM hardware，不升级 VMFS；
- 不反复重启 PassWall，应优先恢复完整的已知正常旧 VM；
- 新旧 OpenWrt VM 绝不能同时占用 `.254`。

如果实际屏幕与本文步骤不一致，立即停止并记录屏幕和错误原文。禁止临时
猜测并执行存储、datastore 或分区操作。

## 故障决策树

```text
LAN 内能否直接打开 https://192.168.1.238？
|
+-- 能 -> 当前是否从 Intel SSD 启动 ESXi 6.7？
|         |
|         +-- 是 -> 执行“回滚 .254 虚拟机”。
|         |
|         +-- 否 / 当前是 T5 上的 ESXi 8 -> 执行“返回 Intel ESXi 6.7”。
|
+-- 不能 -> 现场能否打开 ESXi Direct Console（DCUI）？
          |
          +-- 能 -> 先执行“恢复 ESXi 管理访问”。
          |
          +-- 不能 -> 停止连续断电重试。先检查显示器、电源和线缆，
                       记录指示灯与屏幕状态后，只允许一次受控重启。
```

## 回滚 `.254` 虚拟机

新 VM 出现管理、DNS、代理、ACL、路由、防火墙、监听端口或性能验收失败时，
执行本流程。

1. 从 LAN 直连客户端打开 `https://192.168.1.238` 并使用本地方式登录，
   不依赖 PassWall 或 `.140`。
2. 打开**新 OpenWrt VM** 控制台，记录当前屏幕状态。
3. 关闭**新 OpenWrt VM**。如果正常 guest shutdown 在约定的短时间内没有
   完成，且代理已经不可用，可以在 ESXi 中执行一次 `Power off`。不要删除
   或取消注册新 VM。
4. 在新 VM 设置中取消生产虚拟网卡的 `Connect at power on`，或者保持整个
   新 VM 关机，以防止 IP 冲突。
5. 确认旧 `Openwrt_Jump63` 仍指向恢复卡记录的 VMX、虚拟磁盘、虚拟网卡
   MAC 和 `VM Network`。不要改动快照或虚拟硬件。
6. 确认旧 VM 虚拟网卡的 `Connected` 和 `Connect at power on` 已选中。
7. 只启动旧 `Openwrt_Jump63`，并打开其 ESXi 控制台。
8. 最多等待两分钟完成正常启动。确认控制台显示预期的旧版本，且没有文件
   系统恢复错误。
9. 只清除 LAN 笔记本本机对 `192.168.1.254` 的旧 ARP/邻居项，然后 ping
   `.254`。不要清空整个路由器的邻居表。
10. 确认 `.254` 回到恢复卡记录的旧 MAC。如果是其他 MAC 响应，立即停止，
    说明还有另一个 `.254` 实例在线。
11. 执行本文“回滚后的健康检查”。全部通过后，让新 VM 保持关机并保留
    所有现场证据。

如果完整的旧 VM 可以启动，不得再恢复 `/etc`、opkg 数据库或单独替换
PassWall 文件。VM 级回滚是首选恢复方式。

## 旧 `.254` 无法启动时

1. 保持新 VM 关机且虚拟网卡断开。
2. 记录旧 VM 控制台错误以及 ESXi task/event 原文。
3. 对照恢复卡检查旧 VM 指向的 VMX 和磁盘路径。任何提示将创建、格式化、
   升级、移动或合并磁盘的操作都必须取消。
4. 如果 ESXi 询问 VM 是 `moved` 还是 `copied`，且当前对象本应是未移动的
   原 VM，先取消并重新核对 inventory 和 VMX，不要随意生成新身份。
5. 如果原 inventory 条目消失但 datastore 正常，通过 Datastore Browser
   找到恢复卡记录的原始 VMX，选择 `Register VM`。启动前再次核对磁盘和
   MAC。
6. 如果原磁盘丢失、不可访问或报告损坏，立即停止。不要挂载名称相似的
   磁盘。按照备份产品的正式流程恢复经过校验的独立冷备份。
7. 如果没有经过验证的冷备份，进入需要专家处理的紧急状态。禁止自行修复
   snapshot chain。

## 恢复 ESXi 管理访问

使用现场 ESXi Direct Console User Interface（DCUI）：

1. 更改前先阅读并拍照记录当前屏幕。
2. 确认主机供电正常，管理网线仍连接到映射为 `vmnic0` 的物理端口。
3. 打开 `Configure Management Network`，只比较管理网卡、VLAN、IPv4、
   子网掩码和网关是否与恢复卡一致，暂不修改。
4. 运行 `Test Management Network`。单独 DNS 测试失败不能证明本地管理网络
   故障，关键是本地链路、网关和 `192.168.1.238` 是否可达。
5. 如果选错了网卡、VLAN 或地址，并且恢复卡中的正常值明确无歧义，只恢复
   这些精确值；DCUI 提示时只重启一次 management network。不要执行整机
   ESXi 配置重置。
6. 如果 `vmnic0` 没有链路，检查已经记录的网线和交换机端口。禁止通过随机
   交换 WAN/LAN 网线试错，必须依据物理网卡映射。
7. Host Client 恢复后，先确定当前启动盘和 ESXi 版本，再进入对应回滚流程。

## 返回 Intel ESXi 6.7

Samsung T5 上的 ESXi 8 安装、启动、驱动、网络、存储或重复冷启动验收失败
时，执行本流程。

1. 记录 ESXi 8 屏幕和错误，并注明是否启动过任何生产 VM。
2. 如果 DCUI 有响应，从 DCUI 正常关闭测试主机。如果无响应，只有在磁盘
   活动停止或系统明确死机后，才执行一次受控断电。
3. 不再从一次性启动菜单选择 Samsung T5。如果 BIOS 持久顺序仍是 Intel
   第一，正常重启应自动返回 Intel 上的 ESXi 6.7。
4. 如果没有自动返回，使用恢复卡记录的按键进入固件一次性启动菜单，按照
   已记录的**型号和序列号**选择 Intel SSD，不要选择容量相似的通用名称。
5. 恢复期间不要再次选择 T5，不修改 SATA 模式、UEFI/Legacy 模式、
   Secure Boot 或任何分区设置。
6. 确认 ESXi 控制台显示 6.7 U3 build `20497097`，管理地址为
   `192.168.1.238`。
7. 打开 Host Client，在启动 VM 前检查 Intel datastore、port group、
   vSwitch、物理网卡映射、VM inventory 和自动启动设置。
8. 按本文规定的恢复顺序启动 VM。回滚期间拒绝 ESXi 提议的 VMFS、VM
   hardware 或 VMware Tools 升级。

如果 Intel SSD 没有出现在固件启动列表中，立即关机。只有断电后，并且现场
人员能够无歧义识别设备时，才可以重新插接 Intel SSD。绝不能初始化或格式化
任何磁盘。

## 虚拟机恢复启动顺序

如果事先独立验证过 ESXi autostart 顺序且与以下依赖关系一致，可以使用自动
启动；否则手工按顺序执行：

1. 启动 `Ros`，等待 WAN/LAN 接口和 LAN 网关稳定。
2. 启动已知正常的旧 `Openwrt_Jump63`，验证 `.254`、DNS 和 PassWall。
3. 启动 `Ubuntu-Ollama`（`.110`），等待 Docker 和现有容器恢复。
4. 最后启动 `.140` 等可选管理服务。`.140` 不是 CFIP、`.254` 或 `.110`
   的运行依赖。

回滚期间不得启动新 OpenWrt VM。

## 回滚后的健康检查

依次执行，并记录时间和通过/失败：

1. `.238`：LAN 内 Host Client 可达；ESXi 为预期 6.7 build；Intel
   datastore 存在；vSwitch/port group/NIC 映射未变；没有 VM balloon、
   swap 或异常存储告警。
2. `Ros`：预期 WAN/LAN 链路均正常；LAN 网关可达；没有无法解释的接口
   重映射。
3. `.254`：ping、SSH/LuCI 可达；版本和包版本是旧系统基线；dnsmasq 和
   SmartDNS 正常运行。
4. PassWall：enabled；存在两个 `/usr/bin/xray` 进程；`1070`、`1041`、
   `11400`、`15353` 正常监听；日志没有新增 fatal、panic、invalid 或
   unsupported 错误。
5. DNS：`auto`、`auto1`、`auto2`、`auto3`、`auto4` 通过 LAN DNS、`.254`
   和 `1.1.1.1` 返回一致结果。回滚期间不能通过写 Cloudflare 修复不一致。
6. HTTP：LAN PC、路由器、`.110` 和开机时的 `.140` 均通过 Google 204
   和 YouTube 检查，并且要测试真实 PassWall 路径，不能只测直连 WAN。
7. `.110`：内存仍约 16 GiB；Swap 没有持续增长；Docker daemon 稳定；
   四个现有容器 running/healthy；Ollama 响应正常且没有异常驻留模型。
8. Sidecar：timer enabled/active/waiting；service 没有卡住；项目锁空闲；
   `cfip-direct` 没有瞬时容器附着；不存在
   `/run/cfip-sidecar/xray-*.json` 残留。
9. CFIP：没有扫描/更新进程或锁；历史代理停止任务仍保持禁用；恢复期间
   没有池或 `auto` 记录变化。

Cloudflare API 只能使用现有安全只读方法复核。如果该能力不可用，应明确记录
“Cloudflare API 未复核”，不能根据公共 DNS 结果推断 API 一致。

## 必须停止的紧急条件

出现以下任一情况，立即停止并保留证据：

- 两个 OpenWrt VM 同时占用 `.254`，或该 IP 的 MAC 来回变化；
- Intel SSD/datastore 消失，或者任何界面提示初始化；
- snapshot chain 或虚拟磁盘丢失、损坏；
- NIC 角色不再符合记录的物理映射；
- 主机反复重启、丢失 T5/Intel 存储或持续失去管理网络；
- 完整旧 VM 启动后 PassWall 监听仍无法恢复；
- 恢复旧 VM 后三路 DNS 仍不一致；
- 下一步必须修改 Cloudflare、防火墙、路由、订阅、凭据、池或 Sidecar
  门槛才能继续；
- 现场人员不能明确识别旧 VM、Intel SSD、port group 或生产网线。

需要记录：墙钟时间、当前启动盘和 ESXi build、已开机 VM、控制台截图、
错误原文、ESXi recent tasks/events、最先失败的健康检查，以及是否修改或
启动过任何生产 VM/datastore。记录中不得包含凭据或代理配置正文。

## 回滚成功状态

当 Intel ESXi 6.7 稳定运行、只有旧 `Openwrt_Jump63` 占用 `.254`、
PassWall/DNS/代理检查通过、`.110` 和 Sidecar 健康，并且恢复过程中没有修改
Cloudflare、池、防火墙、路由或订阅时，回滚才算完成。新 VM 和 T5 应保持
关机且完整保留，供后续分析；不要立即再次尝试迁移。
