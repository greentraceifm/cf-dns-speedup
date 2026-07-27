# OpenWrt VM36 正式迁移准入评估 - 2026-07-27

## 1. 决策摘要

当前决策为 **NO-GO：尚不能立即把 VM36/.253 正式迁移为生产 .254**。

这不是重建路线失败。VM36 已经从“基础实验 VM”推进到“具有可验证回退能力、
可以进入完整 PassWall 数据面测试”的阶段。缺口集中在生产数据面、重启恢复、
DNS/ACL、真实性能、Xray 长期升级来源和切换断网期间的离线回滚执行，而不是
ESXi、系统盘或基础网络不可用。

若本报告列出的 A、B、C 三个测试窗口全部一次通过，最早可申请安排在
**不早于 2026-07-31 的有人值守低流量窗口**。该日期只是最乐观窗口，
不是承诺；任一门控失败即顺延，不得为赶日期降低门槛。正式切换后还需三个不同
日期的自然 Sidecar/PassWall 观察窗口，全部通过后才算迁移最终验收完成。

## 2. 当前拓扑与版本基线

### 2.1 生产 VM33/.254

- 系统：Kwrt `25.12.0-rc3`；
- luci-app-passwall：`26.6.2-r169`；
- opkg xray-core：`26.6.1-r13`；
- 实际 Xray：`26.6.27`；
- 两个 Xray 进程正常；
- `1070/1041/11400/15353` 监听正常；
- Google/YouTube 为 HTTP 204；
- 当前仍是 Codex 和 LAN 生产代理路径。

### 2.2 staging VM36/.253

- 系统：ImmortalWrt `25.12.1`，APK 包管理；
- luci-app-passwall：`26.7.1-r1`；
- xray-core：`26.3.27-r1`；
- sing-box：`1.12.25-r1`；
- PassWall UCI `enabled=0`，init disabled；
- PassWall Server、HAProxy 自启动均 disabled；
- 无代理进程、目标监听、PassWall 临时目录、marker 或 nft 残留；
- 根文件系统 3.9 GiB，剩余约 3.7 GiB；
- IP `192.168.1.253/24`，MAC `00:0c:29:ec:33:dd`；
- 虚拟网卡已修复为打开电源时自动连接。

### 2.3 相关项目

- `.110` 的 `cfip-sidecar.timer` enabled/active；
- 最新只读状态为 service inactive、Result=success、ExecMainStatus=0；
- `.110` Google/YouTube HTTP 204，Ollama API 可达；
- Sidecar 不依赖 `.140` 常驻；
- 本次迁移不得恢复任何停止或重启 PassWall 的历史 CFIP 路径。

## 3. 已经通过的证据

以下门控已经完成，不需要重新证明设计原理，但实施窗口仍需复核当前状态：

1. ImmortalWrt 25.12.1 镜像、签名摘要、4 GiB ext4 系统盘和 ESXi 6.7 启动通过；
2. PassWall 26.7.1-r1 与官方 Xray 26.3.27-r1 安装依赖闭合；
3. PassWall、PassWall Server、HAProxy、DHCPv4/DHCPv6/RA 隔离和重启基线通过；
4. 生产与 staging 的 UCI schema/引用关系审计通过；
5. 真实配置结构化转换通过，未知引用为 0；
6. 23 个真实 VMess/VLESS 节点的 runtime 同时通过 Xray 26.3.27 和 26.6.27
   静态测试；
7. 一个真实引用节点的 localhost Xray canary 通过 Google 204、YouTube 204 和
   Cloudflare 1 MiB HTTP 200；
8. VM36 冷启动自动联网、离线快照、marker 持久性和一次真实 Revert 全部通过；
9. Revert 后 marker 消失，PassWall disabled、无进程/监听/规则残留；
10. 演练期间 VM33/.254 始终运行，生产代理没有中断。

这些证据证明“能生成配置、单节点能连通、VM 能回退”，但尚未证明“完整 PassWall
可作为生产网关长期运行”。

## 4. 阻断项状态

### P0-1：已解除 - Xray 可维护升级与精确回滚已闭环

2026-07-27 窗口 A 已通过。VM36 使用分离的社区/ImmortalWrt keyring、各自已验签
`packages.adb`、本地 `file://` 仓库，并使用 `--no-network`、`--scripts=no`、
`--commit-hooks=no`，完成：

```text
xray-core 26.3.27-r1 -> 26.7.11-r1 -> 26.3.27-r1
```

升级与降级的求解结果均只涉及 `xray-core`。最终包版本、二进制、`world`、包文件、
init 链接和固定无秘密 fixture 全部恢复基线；PassWall/Xray 全程未启动。临时工作目录
和敏感备份副本已删除，只保留公开制品和通过校验的公开 SHA256 清单。

详细证据见 `passwall-window-a-result-2026-07-27.zh-CN.md`。P0-1 解除不等于批准
窗口 B、生产升级或正式迁移。

### P0-2：完整 PassWall 数据面未启动验证

localhost canary 绕过了 PassWall init、chinadns-ng、dnsmasq、nft、ACL 和完整监听
拓扑。必须在 `.253` 临时地址上完成一次受控完整数据面测试，并验证：

- 两个 Xray 实例；
- `1070/1041/11400/15353` 预期监听；
- Google/YouTube、DNS 和 Cloudflare 下载；
- 测试前后配置、规则、路由、锁和临时目录完全恢复；
- `.254` 全程不变。

此前的 `passwall-stage-full-test-implementation-plan-2026-07-27.zh-CN.md` 是被拒绝
的历史草稿，不得直接执行。必须基于已验证快照能力重新写最小方案并重新审批。

### P0-3：重启恢复和生产语义未验证

完整数据面通过后还需单独验证：

- PassWall 按批准方式自启动；
- 两次正常重启后进程、监听、DNS、nft、路由和锁均自动恢复；
- 至少一次 VM36 完整关机后冷启动，无需人工连接网卡，PassWall 自启动、两个
  Xray、目标监听、DNS、nft、路由和锁均自动恢复；
- 仅一个非关键测试客户端使用 `.253` 验证透明代理、全局节点和 ACL；
- SmartDNS/dnsmasq、本地域名及 `auto..auto4` 三路解析语义正确；
- 不发布 `.253` 为全网 DHCP/DNS，不影响 Codex 使用的 `.254`。

### P0-4：真实性能门槛未通过

canary 的 1 MiB 样本约 0.48 MiB/s，只证明可连通，不能用于性能判断。正式迁移前
必须通过真实 PassWall 路径测试当前生产节点和至少一个候选节点。HTTP、TLS/WS、
稳定性正常，且既有 `>=6.5 MB/s` 门槛不得降低。任何 Sidecar 结果仍不能绕过真实
PassWall 门控。

### P0-5：切换期间 Codex 会失联，离线回滚尚未演练

`.254` 承担当前 Codex 代理。正式切换需要关闭 VM33，已有连接会中断，无法保证
无缝或零会话丢失。Codex 不能作为切换期间唯一控制者。

切换前必须有中文离线操作卡，并由现场用户掌握：

- 通过 LAN 直连 `https://192.168.1.238`；
- 只关闭/启动正确 VM；
- 新 VM 改为 `.254` 后的 ARP、DNS、监听和 HTTP 验收；
- 失败时在 5 分钟预算内关闭新 VM、启动旧 VM33，并恢复原网络；
- 不依赖互联网、`.140`、Codex 或聊天记录完成回滚。

## 5. 最小后续阶段与预计时间

### 窗口 A：已完成 - 软件包来源与升级回滚资格

2026-07-27 已完成并通过。来源、签名索引、架构、依赖、单包事务、实际升级、精确
降级、恢复验收和清理均闭环。该窗口只解除 P0-1。

### 窗口 B：完整 PassWall 临时地址数据面

预计 60-90 分钟。只在 `.253` 启动一次完整 PassWall，localhost/LAN 暴露受限，
不启用 DHCP/RA，不改任何生产客户端。失败立即恢复或 Revert，不同窗口重试。

### 窗口 C：重启、单客户端、DNS/ACL 和性能

预计 1 个白天测试窗口加至少 1 个自然夜间观察。需要一个非关键测试客户端。
完成两次正常重启、至少一次完整关机冷启动恢复、透明代理/ACL、DNS 语义和真实
`6.5 MB/s` 门控。

### 正式切换窗口

只有 A/B/C 全部通过并经最终专家审核后，才可安排。最早不早于
2026-07-31 的有人值守低流量窗口；这只是最乐观估计，不构成保证。更稳妥是
2026-08-01 或之后。窗口要求用户在 `.238` 现场 Host Client
旁值守，接受已有连接短暂中断，目标恢复预算 5 分钟。

切换后旧 VM33 保持关机但完整保留，不删除、不改硬件、不处理快照。连续三个不同
日期的自然 Sidecar/PassWall 窗口全部健康后，迁移才从“切换成功”转为“正式验收”。

## 6. 正式迁移 GO 条件

以下必须同时为真：

- Xray/PassWall 安装来源、签名、升级和精确回滚通过；
- 完整 PassWall 数据面、两次正常重启和至少一次完整关机冷启动恢复、DNS、ACL、
  透明代理通过；
- 真实 PassWall HTTP 和 `>=6.5 MB/s` 门槛通过；
- `.253` 不提供 DHCP/RA，不产生地址/MAC 冲突；
- Sidecar、CFIP、Cloudflare DNS 和池策略不发生未经授权的写入；
- VM36 快照链健康，VM33 冷备与现有回滚材料可读；
- 中文离线切换/回滚操作卡经现场人员演练；
- 最终切换方案获得 IT 专家组一致批准和用户单独授权。

任一条件未满足即为 NO-GO。

## 7. 推荐结论

继续使用 `.254` 生产，不做立即切换。窗口 A 已完成；下一步候选是窗口 B 的完整
PassWall 临时地址数据面，但必须另写最小方案、重新经过 IT 专家组审核并取得用户
单独授权。窗口 B 不需要停止 `.254`，也不得影响当前已稳定运行的 Sidecar 优选 IP
项目。
