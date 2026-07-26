# OpenWrt staging PassWall 安装与隔离验收 - 2026-07-26

## 决策

IT 工程专家组批准只在 `192.168.1.253` staging 安装 ImmortalWrt 25.12.1 官方签名 release 套件，用于验证包依赖、控制面和后续配置迁移。专家组拒绝把 snapshot 包混入 release，也暂不批准用 sing-box 直接替代生产 Xray。

官方候选版本：

```text
luci-app-passwall 26.7.1-r1
luci-i18n-passwall-zh-cn 26.185.01095~2f9cc61
xray-core 26.3.27-r1
sing-box 1.12.25-r1
```

Xray `26.3.27` 低于生产实际运行的 `26.6.27`。因此本次只证明 staging 套件内部兼容，不构成“Xray 核心升级”，也不构成生产切换批准。

## 安装前门控

- staging 根文件系统约 3.9 GiB，文件系统离线检查通过；
- `apk update` 从 `downloads.immortalwrt.org` 获取 7 个官方索引，显示 11,435 个包；
- `apk add --simulate` 显示新增 53 个包，无基础包替换、架构冲突或内核版本冲突；
- 依赖内核模块均匹配 `6.12.94`；
- 生产 `.254` 和 PassWall 保持运行；
- 安装前配置、包清单和 UCI 导出保存在本机受保护目录：

```text
D:/Codex_OpenAI_memory_backup_20260519-060435/.secure-backups/openwrt-stage253-pre-passwall-20260726
```

该目录可能包含敏感配置，只允许本机受保护使用，不得提交到 GitHub、Notion 或聊天记录。

## 安装结果

`apk add luci-app-passwall luci-i18n-passwall-zh-cn xray-core` 完整执行 53/53，最终状态：

```text
OK: 156.7 MiB in 311 packages
```

没有签名、依赖、空间或事务错误。安装后根文件系统使用约 162.5 MiB，剩余约 3.7 GiB。

## 发现并修复的默认副作用

安装后 PassWall 全局开关为 `0`，没有 Xray 或 sing-box 进程，但依赖包 HAProxy 自动启用并监听 staging 的 `81/444/60000`。同时 PassWall 和 PassWall Server被加入自启动。

为维持未配置 staging 的网络隔离，已执行：

- 禁用 `passwall` 自启动；
- 禁用 `passwall_server` 自启动；
- 停止并禁用独立 `haproxy` 服务；
- 不删除任何包，不导入节点，不修改生产 ACL、DNS 或防火墙。

## 重启验收

staging 正常重启后：

- PassWall、中文包、Xray、sing-box 均存在；
- Xray 二进制报告 `26.3.27`；
- PassWall 全局开关仍为 `0`；
- `passwall`、`passwall_server`、`haproxy` 自启动检查均返回未启用；
- 无 Xray、sing-box、HAProxy 进程；
- 无 `81/444/60000/1070/1041/11400/15353` 代理监听；
- DHCPv4、DHCPv6、RA 继续禁用，UDP 67/547 无监听；
- 根分区约 3.9 GiB，启动日志无存储错误；
- 官方 ImmortalWrt 仓库返回 HTTP 200；
- staging LuCI PassWall 路径存在，未登录访问返回 HTTP 403；
- PC 经生产 `.254` 的 Google 与 YouTube 均返回 HTTP 204。

## 下一门控

下一步只读比较生产 PassWall 26.6.2 与 staging PassWall 26.7.1 的 UCI section 类型、关键 option 名、init 行为和生成配置接口。不得输出或复制 UUID、密码、订阅、节点正文、完整 Xray JSON 或 token。

只有结构评估通过后，才可以通过受保护通道把经过清点的配置对象迁入 staging。即使 staging 运行成功，最终生产切换仍需解决 Xray 版本路径，并完成真实 PassWall `6.5 MB/s` 门控和人工维护窗口验收。
