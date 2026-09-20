# MikroTik `.1` 固定维护入口复用手册（2026-09-20）

记忆标记：`MIKROTIK-MAINTENANCE-REUSABLE-20260920`

## 结论

以后排查或配置 `192.168.1.1` 可以复用本手册。固定链路是：

```text
本机 -> 192.168.1.140 OpenClaw -> 192.168.1.1 MikroTik
```

只要 `.140` 在线、其主机密钥未更换、RouterOS 上的维护公钥未撤销，就不需要重新询问密码，也不应改走本机直连或密码猜测。

## 固定身份与边界

- RouterOS：`6.49.19 (stable)`。
- 登录用户：`greentraceifm`。
- `.140` 是唯一跳板；本机不直接登录 `.1`。
- `.140` 上的专用私钥路径：
  `/home/ubuntu/.ssh/id_rsa_mikrotik_dns_maint_20260920`
- `.140` 上的 known_hosts 必须使用既有受保护文件。
- RouterOS 6.49.19 的 RSA 兼容参数只在本次连接中添加：
  `-o PubkeyAcceptedAlgorithms=+ssh-rsa`
- 不修改本机或 `.140` 的全局 SSH 配置，不关闭严格主机密钥校验，不启用密码回退。
- 不把密码、私钥、Token、订阅、UUID 或完整配置写入记忆、Notion、GitHub、日志或聊天。

## `.140` 上的标准连接

只在 `.140` 内执行以下形式的连接；实际私钥内容永不读回本机：

```sh
ssh \
  -i /home/ubuntu/.ssh/id_rsa_mikrotik_dns_maint_20260920 \
  -o BatchMode=yes \
  -o StrictHostKeyChecking=yes \
  -o UserKnownHostsFile=/home/ubuntu/.ssh/known_hosts \
  -o PubkeyAcceptedAlgorithms=+ssh-rsa \
  greentraceifm@192.168.1.1
```

连接后看到 RouterOS 提示符才执行 RouterOS 命令。不要把 Linux 命令、Dropbear 命令或 OpenWrt `uci` 命令粘贴到这里。

## 只读预检

首次连接只执行以下只读检查：

```routeros
:put [/system resource get version]
:put [/ip dns get servers]
:put [/ip dns get dynamic-servers]
:put [/ip dns get allow-remote-requests]
:put [/interface pppoe-client get [find name="pppoe-out1"] use-peer-dns]
/ip dns static print detail
/ip dns cache all print detail where name="chatgpt.com"
:put [:resolve "chatgpt.com" server=192.168.1.254]
```

若只读连接失败，按顺序区分：

1. `.140` 不可达；
2. `.1:22` 不可达；
3. 主机密钥不匹配；
4. RSA 算法协商失败；
5. 公钥认证失败；
6. RouterOS 命令或权限失败。

认证失败后不得猜密码、扫描其他文件、放宽 `StrictHostKeyChecking` 或绕过 `.140`。

## 配置变更规则

DNS、路由、防火墙、PPPoE、SSH 公钥和用户变更都属于生产写入。执行前必须有本次明确授权；授权只覆盖已说明的动作，不自动扩展到其他配置。

标准顺序：

1. 先只读记录当前值；
2. 先保存可回滚状态；
3. 一次只改一个逻辑范围；
4. 不重启路由器、不重拨 PPPoE，除非单独授权；
5. 立即验证 `.1`、VM36 `.254` 和本机解析；
6. 失败时只回滚本轮实际改动。

2026-09-20 的 DNS 修复采用了以下拓扑，后续不得无理由反向改回：

```text
客户端 -> MikroTik .1 -> VM36 .254 -> 独立 DNS 上游 8.8.4.4
```

VM36 先脱离 `.1`，再让 `.1` 转发到 VM36，避免 DNS 循环。该次修复未重启路由器、VM36、PassWall、Xray 或接口。

## 回滚边界

发生解析失败或互联网异常时，先恢复 MikroTik，再恢复 VM36，避免先让 VM36 重新依赖 `.1`：

```routeros
/ip dns set servers=223.5.5.5,119.29.29.29,114.114.114.114
/interface pppoe-client set [find name="pppoe-out1"] use-peer-dns=yes
/ip dns cache flush
```

VM36 的回滚命令见：
`docs/mikrotik-dns-repair-2026-09-20.zh-CN.md`

两台 OpenWrt/VM 不得同时占用生产地址 `.254`。网络级最终回滚仍是关闭 VM36 后启动 VM33。

## 临时公钥撤销

需要撤销本次 Codex 维护授权时，先查看 `.1` 上的 SSH 公钥列表，确认 `key-owner` 为：
`codex-mikrotik-dns-maint-20260920`

只删除该条对应的公钥记录，不删除 `terraria-ddns` 或其他既有公钥；删除后再从 `.140` 做一次 BatchMode 连接确认失败。撤销动作本身需要单独授权。

## 不应重复的错误

- 不在 MikroTik 提示符执行 `uci`、`chmod`、`authorized_keys`、`/file add` 等 Linux/Dropbear 命令。
- 不使用旧密码文件作为自动回退。
- 不使用 `StrictHostKeyChecking=no`。
- 不把 Cloudflare 返回的某个 `104.*` 地址写死为“正确答案”。
- 不因一次 DNS 空答案就清缓存、重启服务或修改上游。
- 不把 `.110` 直连外网失败误判为 VM36 或 CFIP 故障。

## 维护后最小验收

- `.1`、`.254`、本机能解析 `chatgpt.com`、`x.com` 和一个普通国内域名；
- `auto` 至 `auto4` 在 `.1`、`.254`、`1.1.1.1` 的实际答案一致；
- VM36 的 PassWall、Xray 四监听 `1070/1041/11400/15353` 和项目锁未受影响；
- Google/YouTube 连通性正常；
- 没有新增 cron、DNS、路由、防火墙、Cloudflare 或优选池变更。

## 记忆同步规则

本手册是项目内权威操作说明。OpenClaw 长期记忆只保存本手册路径、固定链路、认证边界和回滚原则，不保存秘密。Notion 采用带唯一标记的追加写入，并必须读回验证；失败时保留本地记录，不使用临时绕过方案。
