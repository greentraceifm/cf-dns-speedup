# OpenWrt VM36 正式割接与 5 分钟回滚卡

## 当前对象

- ESXi Host Client：https://192.168.1.238
- 旧生产 VM33：Openwrt_Jump63，当前地址 192.168.1.254
- 新候选 VM36：OpenWrt-25.12.1-stage，当前地址 192.168.1.253
- VM36 回退快照：OpenWrt-25.12.1-stage-pre-marker-revert-drill-20260727-154536

严禁同时启动两个使用 192.168.1.254 的 VM。不要删除、合并快照或修改虚拟磁盘。

## 割接前

1. 保持本卡和 ESXi Host Client 在 LAN 本地打开，不依赖 Codex 或互联网。
2. 确认 VM33、VM36 名称无误；VM33 当前 Powered on，VM36 在预置后必须
   Powered off。
3. Codex 将 VM36 磁盘配置预置为 .254，但不 reload 网络；随后正常关闭 VM36。
4. 确认 VM36 已显示 Powered off 后，才允许关闭 VM33。

## 正式切换

1. Codex 从 VM33 guest 内执行正常 poweroff。由于 OpenWrt 没有 VMware Tools，
   不使用 Host Client 的“关闭客户机操作系统”。
2. 在 Host Client 等待 VM33 明确显示 Powered off，最多等待 90 秒。
3. VM33 未关机时禁止启动 VM36；若 90 秒仍未关闭，停止割接。
4. VM33 Powered off 后，只启动 VM36，并确认网卡 Connected 和
   Connect at power on。
5. 最多等待两分钟，确认 192.168.1.254 可 ping、LuCI/SSH 可达、DNS 和代理恢复。
6. Codex 会话恢复后，由 Codex 完成监听、HTTP、DNS、ACL、Sidecar 和 Docker
   只读验收。

## 立即回滚

出现 .254 不可达、DNS/代理失败、VM36 启动错误或 Codex 两分钟后仍未恢复时：

1. 在 Host Client 关闭 VM36；确认它明确 Powered off。
2. 不修改、不 Revert、不删除 VM36 或其快照。
3. 只启动旧 VM33 Openwrt_Jump63，确认网卡 Connected。
4. 最多等待两分钟；在 Windows 管理员终端运行：

       arp -d 192.168.1.254
       ping 192.168.1.254

5. 确认 PC Google/YouTube 恢复；恢复后保持 VM36 关机，不再次尝试割接。

## 禁止事项

- 不修改 Cloudflare、auto..auto4、DNS、路由、防火墙、订阅、凭据或 CFIP 池。
- 不关闭或重启 .110 Sidecar、Docker、Ollama、.140 OpenClaw 或 ESXi 主机。
- 不删除 VM33、VM36、快照、VMX 或 VMDK。
- 不在新旧 VM 同时启动时排查 .254；先确保只有一个 .254。