# OpenWrt staging PassWall 配置结构审计 - 2026-07-26

## 范围

本次只比较生产 `192.168.1.254` 与 staging `192.168.1.253` 的 PassWall section 类型、option 名、节点协议形状和运行状态。没有输出或复制节点 ID、地址、UUID、密码、订阅、完整 Xray JSON 或 token。

生产数据通过 `.140` 的现有受保护维护通道读取，密码只进入 `SSHPASS` 环境变量。所有远端脚本只输出 `PW_` 前缀的元数据。

## 版本与运行状态

```text
生产 PassWall：26.6.2-r169
生产 xray-core 包：26.6.1-r13
生产 Xray 实际版本：26.6.27
生产 Xray 进程：2
生产监听：1070/1041/11400/15353 全部存在

staging PassWall：26.7.1-r1
staging xray-core：26.3.27-r1
staging Xray 实际版本：26.3.27
staging Xray 进程：0
staging 代理监听：无
```

## Section 对应关系

生产与 staging 都包含以下核心 section 类型：

```text
global
global_app
global_delay
global_forwarding
global_haproxy
global_other
global_rules
global_singbox
global_subscribe
global_xray
nodes
shunt_rules
```

生产额外存在 3 个 `acl_rule`、24 个 `nodes` 和 6 个 `shunt_rules`。staging 默认只有 1 个内建分流节点和 6 个分流规则。新版本仍支持 `acl_rule`，所以这些对象可以迁移，但不能覆盖新版本新增的默认全局字段。

## 节点兼容性

生产节点分布：

```text
协议：VLESS 14，VMess 10
传输：WS 23，raw 1
TLS：启用 19，关闭 5
```

生产当前被全局或 ACL 引用的真实节点只有两种引用，去重后均为：

```text
Xray / VMess / WS / TLS=1，共 2 个节点
```

另有 2 个引用为直连、默认等特殊目标。staging 26.7.1 代码对以下生产关键字段均有实际引用：

```text
type, protocol, address, port, uuid, transport,
ws_host, ws_path, tls, tls_serverName, tls_allowInsecure,
encryption, security, alpn, utls, fingerprint,
tcpMptcp, tcp_fast_open
```

因此当前活动的 VMess+WS+TLS 拓扑具备配置层兼容性。尚未导入节点，也未运行新核心配置测试，所以这不是运行兼容性最终批准。

## 无引用旧字段

生产配置共有 138 个唯一的“section 类型 + option 名”。在 staging 代码中没有任何引用的旧字段为：

```text
global.close_log_tcp
global.close_log_udp
global.localhost_tcp_proxy_mode
global.localhost_udp_proxy_mode
global.trojan_loglevel
global_app.brook_file
global_app.singbox_file
global_app.trojan_go_file
global_delay.auto_on
global_forwarding.use_nft
global_other.nodes_ping
global_singbox.sniff_override_destination
global_subscribe.ss_aead_type
nodes.tcpNoDelay
```

迁移规则：

- `global_forwarding.use_nft` 必须映射为 `global_forwarding.prefer_nft`；
- `global_app.singbox_file` 是旧拼写，新版本保留 `sing_box_file`，旧字段删除；
- `nodes.tcpNoDelay` 在新代码中已移除，删除，不猜测替代值；
- 其余旧兼容、日志、延迟和已移除内核字段不迁移；
- 新版本新增的 DNS、列表策略、`geoview_file`、`show_node_info` 等默认字段必须保留，不能被生产旧文件整体覆盖。

## 决策

配置迁移可继续，但必须使用结构化转换：以 staging 26.7.1 默认配置为基底，导入经过清点的节点、ACL 和分流对象，再逐项映射受支持的全局字段。禁止直接覆盖 `/etc/config/passwall`，禁止整体覆盖 `/etc`。

下一步应先生成不输出秘密的迁移转换器和 dry-run 清单。只有转换后的配置能被 staging UCI 解析、PassWall 保持 disabled、Xray `run -test` 通过，并且没有意外进程、监听或防火墙变化，才可以在 staging 启动一次受控代理测试。

生产 `.254` 在本次审计期间没有停止、重启或修改。
