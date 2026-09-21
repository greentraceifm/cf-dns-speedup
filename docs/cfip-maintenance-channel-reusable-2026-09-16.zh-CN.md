# CFIP 固定维护链路复用手册（2026-09-16）

> 2026-09-20 更新：VM36 专用密钥入口已通过三次独立连接和实际只读审计；原密码方式不再用于日常维护，不得回退重试。见 `cfip-vm36-key-maintenance-2026-09-20.zh-CN.md`。`.110` 原固定入口不变。

## 目的

以后排查或维护 CFIP、Sidecar、VM36 DNS 和 PassWall 时，统一复用本手册，不再反复询问如何连接或重复确认普通只读授权。

## 固定拓扑

```text
生产数据面：192.168.1.110 Sidecar -> VM36 192.168.1.254
维护控制面：本机 -> 192.168.1.140 OpenClaw -> 192.168.1.110 / VM36 / MikroTik
```

- `.140` 是唯一维护跳板，不是凌晨 CFIP 生产数据中继；夜间关机不应阻断自然采集和自动同步。
- `.110` 是 Sidecar 和 Sub2API 主机。
- VM36 `.254` 是生产 OpenWrt、PassWall、DNS 和 CFIP 消费端。
- MikroTik `.1` 是 LAN 网关和 DNS 转发入口；RouterOS 维护必须复用
  `docs/mikrotik-maintenance-channel-reusable-2026-09-20.zh-CN.md`。
- VM33 是最终网络回滚节点，VM37 是隔离提取机，不属于日常维护链路。

CFIP 自动同步由 VM36 直接使用 `/root/.ssh/cfip-sidecar-export` 从 `.110`
的受限 `read-cfip-export` 命令拉取候选；`.140` 只负责人工维护、审计和
脚本投递。

详细核验记录见 `docs/cfip-direct-data-plane-closeout-2026-09-21.zh-CN.md`。

### 生产数据面与维护控制面

需要特别区分两条链路：

```text
生产数据面（夜间自动运行）：.110 Sidecar -> VM36 .254 -> Cloudflare
维护控制面（人工/审计使用）：本机 -> .140 OpenClaw -> .110 或 VM36
```

- VM36 的 `sidecar-auto-sync.sh` 默认并实际使用 `ollama@192.168.1.110`、
  `/root/.ssh/cfip-sidecar-export` 和 `/root/.ssh/known_hosts`，不是通过 `.140`
  拉取候选。
- `.140` 只提供维护入口、审计和受保护跳板，不是凌晨 Sidecar 候选导出或
  Cloudflare 同步的运行依赖。
- 因此 `.140` 夜间关机时，维护控制面暂时不可用，但不应据此判定生产数据面
  中断。判断生产是否故障，应查看 `.110` 自然任务和 VM36 的同步报告，而不是
  先检查 `.140` 是否开机。
- 本结论已于 2026-09-21 通过只读核验确认：VM36 的实际同步 cron 为唯一
  `04:35` 任务，实际远端为 `.110`，受限 `read-cfip-export` 直连成功，旧
  `06:30` 任务不存在。
- VM36 使用 Dropbear 客户端拉取 `.110`。维护核验不得擅自加入 OpenSSH 专用的
  `-F /dev/null`、`-T` 等参数；应复用生产脚本原始调用，否则可能出现 SSH 返回
  0 但导出正文为空的假故障。

## `.110` 固定入口

优先使用 `.140` 上的固定只读入口：

```text
/home/ubuntu/.openclaw/tools/cfip-maintenance-readonly.sh
```

该入口通过 `ollama-server` SSH 别名进入 `.110`，并调用 `.110` 上 root-owned 的固定审计命令。必须保持严格主机密钥校验；不得恢复旧 `ssh_ollama.expect` 密码提取方式，不得使用任意 `sudo -n sh -s` 或任意 root shell。

## VM36 固定入口

日常统一在 `.140` 调用：

```sh
/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh --check
```

已审核的只读脚本通过同一入口的 `--stdin` 传递。固定入口隔离默认 SSH 配置，强制专用密钥、严格 known_hosts、BatchMode 和禁止密码回退；私钥仅在 `.140`，不得读取或拷回本机。

VM36 授权文件权限 600，正常 sysupgrade 备份清单已确认包含该文件。恢复旧快照、重建 VM 或重装 `.140` 仍需单独恢复密钥，不保证这些操作后自动可用。

旧 `openwrt-smartdns.env` 密码入口保留给其他历史用途，本手册不再用它登录 VM36，也不修改该文件。普通只读失败先区分网络、主机身份、密钥认证和远端命令，不重复尝试旧密码。

### VM36 直连 `.110` 的验证规则

VM36 上的同步脚本使用 Dropbear SSH 客户端。验证 `.110` 导出时必须复用生产
调用方式，不要加入 OpenSSH 专属或在 Dropbear 上行为不同的 `-F /dev/null`、
`-T` 等参数。验证必须同时记录 SSH 退出码、标准错误、导出字节数、表头和
候选行数；不能把一次手工命令的空标准输出直接判定为生产导出为空。

## MikroTik `.1` 固定入口

RouterOS `.1` 不使用 OpenWrt/Linux 命令。必须先进入 `.140`，再使用
`.140` 上的专用 RSA 私钥和既有 known_hosts 登录 `greentraceifm@192.168.1.1`。
RouterOS 6.49.19 只在该次 SSH 调用中添加
`PubkeyAcceptedAlgorithms=+ssh-rsa`；不得关闭严格主机校验或启用密码回退。

标准命令、只读检查、授权边界、公钥撤销和 DNS 回滚见：
`docs/mikrotik-maintenance-channel-reusable-2026-09-20.zh-CN.md`

本机维护 `.1` 时，普通只读检查不再重复询问授权；DNS、路由、防火墙、
PPPoE、SSH 公钥、用户、重启和删除操作仍需在临界动作前确认。

## 自动执行规则

- 普通只读诊断、状态查询、报告生成和本地测试：直接按本手册执行，不重复询问用户授权。
- 已明确授权的低风险修复：按既定回滚点、原子替换和后检规则执行，不重复询问同一授权。
- 生产写入、Cloudflare 记录变更、PassWall/DNS/VM 重启、凭据变更、删除或不可逆操作：仍需在临界动作前确认。
- 如果已有受保护凭据认证失败：最多检查一次调用方式、一次行尾格式和既有密钥；随后停止并报告精确阻塞，不猜密码、不扫描其他文件、不绕过跳板。
- 不能从 OpenClaw 记忆恢复不存在或已失效的密码。OpenClaw 记忆和 Notion 只记录入口、规则、状态和回滚，不记录密码、Token、UUID、订阅或完整配置。

### `.140` 夜间关机时的故障判定

`.140` 不在线时不执行“改造生产链路”或反复尝试登录。按以下最小顺序判断：

1. 等 `.140` 恢复后，通过固定入口补做维护审计；
2. 以 `.110` 的 Sidecar timer/service、最新导出和 VM36 的 `sidecar-auto-sync.latest.tsv`
   为生产证据；
3. 只有在 VM36 本机配置明确指向 `.140`，或 VM36 -> `.110` 受限拉取失败时，才提出生产修复；
4. `.140` 关闭本身不是修改 DNS、恢复旧 cron、重启 PassWall 或切换 VM33 的理由。

## DNS 只读诊断标准

对 `auto3.greentraceifm.top` 至少连续查询三轮，并比较：

- `192.168.1.1`
- `192.168.1.254`
- `1.1.1.1`

同时检查 `auto`、`auto1`、`auto2`、`auto4`，记录返回码、答案、TTL、查询时间、超时、`SERVFAIL` 和 `NXDOMAIN`。

只有出现连续可复现的“仅 VM36 空答案、其他 resolver 正常”时，才提出最小缓存/转发修复；一次性异常只记录，不清缓存、不重载、不重启。

## 本次确认结果

2026-09-16 17:00 CST 从 `.140` 对 VM36 DNS 进行了三轮只读查询：`auto3` 在 `.1`、`.254`、`1.1.1.1` 均返回 `NOERROR -> 104.26.1.38`；其他四个槽位三路也一致。因此此前空答案按一次性或瞬时转发异常收口，不执行 DNS 修复。

上述是 9 月 16 日的 DNS 结果。9 月 20 日已恢复密钥 SSH；新的 45 次 DNS 查询和 Cloudflare 五记录 GET 也一致，详见当天整体运行审计，不把历史样本当成当天证据。

## 常驻服务重启验收

仅在用户明确授权短暂中断时，才执行本节；普通巡检与自然 Sidecar 周期不需要重启。

2026-09-20 已完成一次受控演练：

- `.110` 只能通过白名单入口 `sudo -n /usr/local/sbin/sub2api-maintenance restart` 重启 Sub2API 常驻容器。重启后必须确认 Sub2API、PostgreSQL、Redis 均 healthy，Web 与 Ollama 健康检查均为 HTTP 200。
- 不手动执行 `cfip-sidecar.service restart` 或 `start`。该 service 是一次性真实测速任务，手动启动会产生额外扫描；只核验其 timer 为 active/enabled，并由下一自然周期验证。
- VM36 重启 PassWall 前，应检查生产配置实际生效的项目锁；重启后等待 Xray、PassWall DNS、ChinaDNS 与 `1070/1041/11400/15353` 监听恢复，再检查默认路径和显式 SOCKS `127.0.0.1:1070` 的 Google/YouTube 均为 HTTP 204。
- 重启后核验唯一 `04:35` 同步 cron 仍在、旧 `06:30` 任务不存在，并对 `auto` 至 `auto4` 比较 VM36 本地与公共 resolver 的实际 A 答案。

DNS 验收不得把答案写死为 `104.*` 或任何固定网段。2026-09-20 当前正确答案之一为 `162.159.134.98`；此前仅因临时验收脚本错误假定 `104.*` 而误报失败。对于这些预期有 A 记录的槽位，空答案、`SERVFAIL/NXDOMAIN`、超时或 resolver 答案不一致需要进一步核验，不单凭一次差异判定故障。

### 验收记录的更正与限制

- 重启批次检查的是 `/var/lock/cfip-*.lock`，并非代码默认的项目锁，不能作为真实锁空闲证据。代码默认路径为 `/tmp/cfip-sidecar-auto-sync.lock`、`/tmp/cfip-candidate-gate.lock`、`/tmp/cf-dns-speedup.lock`，另有 `/tmp/cf-dns-speedup-passwall-node-observe.lock`；配置可覆盖，使用前核对生效路径。一次释放即结束的探测不能防止后续竞争。
- 重启批次仅计数同步脚本行，并以字符串 `06:30` 检索旧任务，未重新严格解析 cron 的分钟/小时字段；唯一 `04:35` 与旧任务不存在的完整证据来自同日较早审计，不冒充重启后新证据。
- `pgrep -x xray` 未命中不能单独判定进程消失；本次通过实际进程路径及监听确认。该 PassWall init 不支持 `status`，返回用法提示不是服务失败。
- 重启后的 HTTP 测试使用了 `curl -k`，只能证明连通性，不能证明 TLS 证书校验通过；今后标准验收不使用 `-k`。
- 实际仅重启 Sub2API 应用容器和 PassWall，没有重启 VM、宿主机、Docker、Ollama、主 DNS 服务或 OpenClaw。Sub2API 是同机关联服务，不是 CFIP 数据同步执行器，日常 CFIP 检查不需要重启它。
- 没有手动重跑 Sidecar/同步，没有在重启后重新做 Cloudflare API GET 或完整三路 45 次 DNS 查询；自然周期成功证据来自重启前。未精确测量代理中断时长，不承诺下次永不报错。

## 回滚与安全边界

- 本手册本身不改变生产配置。
- 不恢复旧 `06:30` cron。
- 不手工批量修改 `auto` 至 `auto4`。
- 不增加 DNS 上游，不改订阅、凭据、路由、防火墙或 PassWall 版本。
- 网络级回滚仍为：关闭 VM36 后启动 VM33，确保两台不同时占用 `.254`。
