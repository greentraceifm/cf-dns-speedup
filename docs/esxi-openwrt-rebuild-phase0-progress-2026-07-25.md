# ESXi/OpenWrt 重建阶段 0 进度记录 - 2026-07-25

## 本次范围

本批次只执行不影响代理运行的阶段 0 工作：重新核验 `.254` 和 `.110`，
建立 OpenWrt 受保护配置备份，并在首个需要 ESXi 身份验证的边界停止。

本次没有关闭或重启 `.254`、`.110`、PassWall、Docker、Ollama、Sidecar、
DNS 或任何虚拟机；没有运行 CFIP 扫描；没有修改 Cloudflare、地址池、
防火墙、路由、订阅、定时任务或服务拓扑。

## 运行前核验

2026-07-25 22:54 至 23:01 CST 的只读结果：

- `.254` 存在两个 Xray 进程；`1070`、`1041`、`11400`、`15353` 均有监听；
  dnsmasq 和 SmartDNS 正常运行。
- 历史 06:30 和 15:30 代理停止任务继续保持禁用；当前无 CFIP 任务运行。
- 路由器 Google 和 YouTube 均返回 HTTP 204。
- `auto`、`auto1`、`auto2`、`auto3`、`auto4` 在 `192.168.1.1`、
  `192.168.1.254` 和 `1.1.1.1` 三个 DNS 视图中完全一致。
- 旧审计脚本曾把 `auto2` 显示为空；独立 `dig` 证明这是 BusyBox
  `nslookup` 输出解析假阴性，不是 DNS 缺失或漂移。
- `.110` 总内存 `15,993 MB`、可用 `15,198 MB`、Swap 使用量为零、
  load1 为 `0.06`。
- `.110` Docker active，PID `1144`；`sub2api`、`k12-reg`、
  `sub2api-postgres`、`sub2api-redis` 均为 healthy。
- `cfip-direct` 附着数为零；Ollama active 且没有驻留模型；Sidecar timer
  enabled/active/waiting；Sidecar service inactive/success。
- Sidecar 锁不存在；没有 `/run/cfip-sidecar/xray-*.json`；没有瞬时 Sidecar
  容器；`.110` Google 和 YouTube 均返回 HTTP 204。

Cloudflare API 本批次未复核。公共 DNS 一致不能替代 API 一致性声明。

## 已建立备份

在 `.254` 使用系统 `sysupgrade -b` 创建受保护配置备份，同时保存已安装包
清单、安全版本摘要和 SHA256 清单。所有文件均在本机通过 SHA256 校验。

路由器本机路径：

```text
/root/openwrt-backup/openwrt-rebuild-phase0-20260725-225924
```

通过受保护 SSH 通道逐文件复制到 `.140`，并再次使用同一 SHA256 清单验证：

```text
/home/ubuntu/.openclaw/backups/openwrt-rebuild-phase0-20260725-225924
```

两个目录均为 `0700`，文件均为 `0600`。备份包含敏感 OpenWrt 配置，禁止
复制到 GitHub、Notion、普通文档或聊天记录。本记录不包含备份内容、凭据、
节点 UUID、订阅或配置哈希。

备份后复核再次确认两个 Xray 进程、四个监听、dnsmasq、SmartDNS、HTTP 204
和无活动 CFIP 任务，说明备份操作没有影响生产运行。

## 当前停止点

尚未完成 `.238` 的新一轮主机 inventory 和 ESXi host configuration bundle。
原因是当前 PC 没有 `.238` 的已验证 SSH host key/无密码登录；原凭据截图不能
复制为第二份秘密文件；浏览器控制组件因本机沙箱初始化错误无法复用现有
Host Client 会话。

为避免凭据进入命令行、日志或磁盘，本批次在此停止。此前已记录的 ESXi
硬件和 VM 基线仍属于旧证据，不能冒充本次新核验。

## 下一安全动作

1. 用户在 Chrome 中打开并登录 `https://192.168.1.238`，保持 Host Client
   页面在线；不要在聊天中发送密码。
2. 恢复浏览器控制后，只读导出 VM、datastore、vNIC、MAC、port group、
   autostart 和物理网卡映射。
3. 使用 ESXi 6.7 对应的 host configuration backup 功能生成配置包，并在
   主机外验证文件可读和校验值。
4. 完成上述验收后，再单独安排旧 `.254` 正常关机和独立冷备份窗口。

在 `.238` 主机配置备份和旧 `.254` 冷备份完成前，不创建新 VM，不开始
Samsung T5/ESXi 8 实验，也不切换生产 `.254`。
