# CFIP 固定维护链路复用手册（2026-09-16）

## 目的

以后排查或维护 CFIP、Sidecar、VM36 DNS 和 PassWall 时，统一复用本手册，不再反复询问如何连接或重复确认普通只读授权。

## 固定拓扑

```text
本机 -> 192.168.1.140 OpenClaw -> 192.168.1.110
本机 -> 192.168.1.140 OpenClaw -> VM36 192.168.1.254
```

- `.140` 是唯一维护跳板。
- `.110` 是 Sidecar 和 Sub2API 主机。
- VM36 `.254` 是生产 OpenWrt、PassWall、DNS 和 CFIP 消费端。
- VM33 是最终网络回滚节点，VM37 是隔离提取机，不属于日常维护链路。

## `.110` 固定入口

优先使用 `.140` 上的固定只读入口：

```text
/home/ubuntu/.openclaw/tools/cfip-maintenance-readonly.sh
```

该入口通过 `ollama-server` SSH 别名进入 `.110`，并调用 `.110` 上 root-owned 的固定审计命令。必须保持严格主机密钥校验；不得恢复旧 `ssh_ollama.expect` 密码提取方式，不得使用任意 `sudo -n sh -s` 或任意 root shell。

## VM36 固定入口

VM36 维护配置只允许在 `.140` 进程内读取：

```text
/home/ubuntu/.config/openclaw/openwrt-smartdns.env
```

使用方式：

1. 在 `.140` 进程内加载配置。
2. 将密码只放入进程环境变量 `SSHPASS`。
3. 使用 `sshpass -e ssh`，不得把密码放入命令行参数、脚本文件、日志或输出。
4. 强制使用：

```text
-o StrictHostKeyChecking=yes
-o UserKnownHostsFile=/home/ubuntu/.ssh/known_hosts
-o ConnectTimeout=10
```

5. 只执行预先限定的只读脚本或通过 stdin 传递的只读诊断内容。
6. 完成后清除 `SSHPASS` 和配置变量。

### 重要调用约束

不得同时使用 `BatchMode=yes` 和 `sshpass -e` 做密码认证。`BatchMode=yes` 会禁止密码提示，导致正确密码也返回 `Permission denied (publickey,password)`。密码方式应明确使用：

```text
-o PreferredAuthentications=password
-o PubkeyAuthentication=no
```

同时仍保持严格主机密钥校验。

## 自动执行规则

- 普通只读诊断、状态查询、报告生成和本地测试：直接按本手册执行，不重复询问用户授权。
- 已明确授权的低风险修复：按既定回滚点、原子替换和后检规则执行，不重复询问同一授权。
- 生产写入、Cloudflare 记录变更、PassWall/DNS/VM 重启、凭据变更、删除或不可逆操作：仍需在临界动作前确认。
- 如果已有受保护凭据认证失败：最多检查一次调用方式、一次行尾格式和既有密钥；随后停止并报告精确阻塞，不猜密码、不扫描其他文件、不绕过跳板。
- 不能从 OpenClaw 记忆恢复不存在或已失效的密码。OpenClaw 记忆和 Notion 只记录入口、规则、状态和回滚，不记录密码、Token、UUID、订阅或完整配置。

## DNS 只读诊断标准

对 `auto3.greentraceifm.top` 至少连续查询三轮，并比较：

- `192.168.1.1`
- `192.168.1.254`
- `1.1.1.1`

同时检查 `auto`、`auto1`、`auto2`、`auto4`，记录返回码、答案、TTL、查询时间、超时、`SERVFAIL` 和 `NXDOMAIN`。

只有出现连续可复现的“仅 VM36 空答案、其他 resolver 正常”时，才提出最小缓存/转发修复；一次性异常只记录，不清缓存、不重载、不重启。

## 本次确认结果

2026-09-16 17:00 CST 从 `.140` 对 VM36 DNS 进行了三轮只读查询：`auto3` 在 `.1`、`.254`、`1.1.1.1` 均返回 `NOERROR -> 104.26.1.38`；其他四个槽位三路也一致。因此此前空答案按一次性或瞬时转发异常收口，不执行 DNS 修复。

`.140 -> VM36` 的 SSH 认证仍需独立恢复，但不影响从 `.140` 直接访问 VM36 的 53 端口完成本次 DNS 只读诊断。

## 回滚与安全边界

- 本手册本身不改变生产配置。
- 不恢复旧 `06:30` cron。
- 不手工批量修改 `auto` 至 `auto4`。
- 不增加 DNS 上游，不改订阅、凭据、路由、防火墙或 PassWall 版本。
- 网络级回滚仍为：关闭 VM36 后启动 VM33，确保两台不同时占用 `.254`。
