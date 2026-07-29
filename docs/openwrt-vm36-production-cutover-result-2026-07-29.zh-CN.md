# OpenWrt VM36 正式割接结果 - 2026-07-29

## 结论

2026-07-29 约 12:49 CST，VM36 已从 staging .253 接管生产地址
192.168.1.254/24，即时割接验收通过。旧 VM33 Openwrt_Jump63 保持关机且完整
保留，未删除、升级、改硬件或处理快照。

本次没有修改 Cloudflare、auto 记录、CFIP 池、Sidecar 门槛、订阅、凭据、路由或
防火墙。Cloudflare API 未复核。

## 割接过程

1. Window 1 完成 start、restart、完整冷启动和 16 轮隔离客户端验收。
2. VM36 磁盘网络配置预置为 .254/24，运行网络保持 .253/24，没有产生 IP 冲突。
3. VM36 正常关机后，VM33 正常关机；现场确认 VM33 Powered off 后只启动 VM36。
4. .253 不再响应；.254 ARP MAC 为 VM36 固定 MAC 00:0c:29:ec:33:dd。
5. 新 .254 SSH 主机密钥与原 VM36/.253 受信任主机密钥完全匹配。

## 新 .254 验收

- PassWall init enabled，可信监听稳定，nft 结构不变。
- SOCKS Google/YouTube 均为 HTTP 204；DNS 成功；1 MiB 下载完整；ACL 保留。
- PC 默认网关为 .254，用户确认 YouTube 4K 视频播放流畅。
- 切换后的首轮 Windows IPv4 generate_204 曾短暂超时；复测 Google 与
  Cloudflare 恢复 204，VM36 本机 SOCKS 和 OpenClaw 的 YouTube 均为 204，真实
  YouTube 4K 播放正常，因此定级为单次探测假阴性，不执行回滚或配置修复。
- OpenClaw 默认路由为 .254，Google/YouTube 均为 HTTP 204。

## .110 与 DNS 收口

- cfip-sidecar.timer enabled/active，service inactive。
- Docker PID 存在；sub2api、k12-reg、sub2api-postgres、sub2api-redis
  均 running/healthy。
- cfip-direct 附着容器为 0；Sidecar 锁空闲；无 Xray JSON 残留。
- .110 Google/YouTube 均为 HTTP 204。
- Ollama API 可用，当前有 1 个驻留模型；按既定语义属于 busy，不是网络故障，
  自然 Sidecar 周期可安全跳过。
- auto..auto4 在 192.168.1.1、新 192.168.1.254 和 1.1.1.1 三路解析一致。

## 当前边界

- 当前为“正式割接即时验收通过”，不是长期观察完成。
- 保留旧 VM33 关机冷备；不要删除、启动或修改。新旧 VM 不得同时占用 .254。
- 下一步只等待一次自然 Sidecar 周期和约 24 小时代理/DNS 观察；不新增诊断、
  restart、性能门槛或迁移窗口。
- 若出现 .254、DNS、代理或 ACL 故障，按
  openwrt-vm36-production-cutover-card-2026-07-29.zh-CN.md 关闭 VM36并启动 VM33。