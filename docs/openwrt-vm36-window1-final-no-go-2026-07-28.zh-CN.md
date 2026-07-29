# OpenWrt VM36 最终 staging Window 1 收口报告

## 最终结论

- **正式迁移：NO-GO。** 不批准 VM36（`192.168.1.253`）接管生产
  VM33（`192.168.1.254`）。
- VM33 继续承担生产 OpenWrt、PassWall、DNS 和 Codex 代理出口；本轮未修改
  VM33、`.110` Sidecar、Cloudflare、优选 IP 池或 DNS 记录。
- VM36 已执行离线快照 Revert 并恢复为干净 staging 基线。本项目在此停止继续
  start/restart/cold-boot 测试，不再增加第三次试跑。

## 已确认可以保留的成果

1. ImmortalWrt 25.12.1、PassWall 26.7.1-r1 和 Xray 26.3.27-r1 的软件来源、
   安装、升级与回滚路径此前已通过。
2. 生产配置结构转换、23 个 Xray 运行时配置静态测试、单节点 canary、VM36
   冷启动、离线快照和多次 Revert 均已通过。
3. 生产源拓扑为 24 个节点、3 条 ACL、6 条分流规则。结构化迁移后正确拓扑为
   25 个节点、3 条 ACL、8 条分流规则；新增的 1 个节点和 2 条分流规则来自新版
   staging 默认对象，不是未知生产对象。
4. 配置原始字节只在 OpenClaw 内从 `.254` 流向 `.253`，未进入 Windows、Git、
   文档或聊天；未输出节点 UUID、订阅、密码、完整配置或 Xray JSON。

## 两次 Window 1 事实

### 第一次尝试

- 结构化转换和静态 runtime gate 已成功。
- 安装后检查错误地要求迁移结果仍为源拓扑 `24/3/6`，因此在任何 PassWall
  启动前触发 `installed_node_count` 阻断。
- 脚本自动恢复 VM36 默认配置；随后 VM36 关闭并完成离线 Revert。
- 根因是本轮验收脚本断言错误，不是生产配置损坏。

### 第二次尝试

- 修正断言后，转换配置以正确的 `25/3/8` 拓扑成功安装到 VM36；init 仍保持
  disabled。
- 唯一一次 PassWall start 后出现目标端口，但可信监听探针未通过，预期的
  SOCKS、DNS、Google/YouTube 和 1 MiB 下载验收摘要没有形成。
- 安全分类只保留无秘密计数：启动日志 903 字节，匹配 `error` 10 次、`fail`
  3 次；未匹配 fatal、panic、unsupported、invalid、not found、permission
  denied 或 address already in use。
- 端口行计数为 1070=`2`、1041=`2`、11400=`8`、15353=`2`；这些是协议/地址
  维度的 socket 行数，不能当作独立服务实例数，也不能替代 PID 身份和功能请求。
- 按批准规则，没有重复 start、在线修复、PassWall stop 或第三次试跑；VM36
  直接关闭并完成离线 Revert。

## IT 专家组复核

### SRE 结论

- 监听出现不等于数据面可用。可信监听身份与 SOCKS/DNS/HTTP 功能链未形成完整
  成功证据，因此不满足正式割接门槛。
- 第二次失败后停止试跑并回到 VM 级 Revert 是正确动作；继续在同一项目内增加
  controller、ACK、事务脚本或更多窗口不再具有合理收益。

### 安全结论

- 生产 VM33 全程只读，秘密未离开受保护主机，失败没有触发 DNS、路由、
  Cloudflare、节点或 Sidecar 变更。
- 当前回滚状态可信。不得依据“端口存在”绕过功能验收，也不得把 VM36 标记为
  production-ready。

### 迁移结论

- 保留现有 VM33 是最短、风险最低的生产方案。
- VM36 可作为软件源、配置转换和静态兼容性实验资产保留，但不进入正式同 IP
  割接。
- 如未来重新立项，只允许先做一个独立的启动日志根因诊断项目；该项目必须保存
  无秘密错误分类，并在开始前另行审核和授权。它不是本次迁移的自动续篇。

## 最终恢复验收

2026-07-28 最终 Revert 后只读复核：

- VM36：`192.168.1.253/24`，ImmortalWrt 25.12.1；DHCP/RA/DHCPv6 disabled；
  PassWall global=0、init disabled；Xray、HAProxy、chinadns-ng、dns2socks、
  sing-box 均为 0；1070/1041/11400/15353 和 DHCP 相关端口均无监听；PassWall
  runtime 路径不存在。
- VM33：`192.168.1.254` 可达；PassWall global=1、init enabled；两个 Xray
  进程及 1070/1041/11400/15353 监听正常；Google/YouTube 均为 HTTP 204。
- OpenClaw：Google/YouTube 均为 HTTP 204。
- `auto`、`auto1`、`auto2`、`auto3`、`auto4` 在 `192.168.1.1`、
  `192.168.1.254` 和 `1.1.1.1` 三个 DNS 视图一致。
- Cloudflare API 未复核；本轮没有 Cloudflare 写操作。

## 后续边界

- 不执行正式迁移，不改 VM33，不重建 `.110`。
- 不再运行本轮 Window 1 工具，不自动诊断或重试 VM36 PassWall。
- 现有 CFIP Sidecar 和 `6.5 MB/s` 真实 PassWall 门槛保持不变；任何 Sidecar
  候选仍不得自动升池或更新 Cloudflare DNS。

## 2026-07-28 根因更正与专家复审

本节覆盖前文将 Window 1 失败归因于“PassWall 数据面未能启动”的暂定判断，但不改变
“尚未批准正式割接”的结论。

### 新诊断证据

- 分阶段诊断在 240 秒超时，最后完成标记为 before_rules_start，将阻塞点定位到
  source /usr/share/passwall/nftables.sh start。
- 静态复核确认 gen_nftset() 在 stdin 为打开的非 TTY 时会调用无参数
  insert_nftset；后者执行 cat 并等待 EOF。
- 先前通过 SSH 执行验证脚本时，服务命令继承了打开的非 TTY stdin，因而稳定阻塞。
  这是验证工具的 stdin 生命周期缺陷，不是 PassWall 正常启动路径的兼容性失败。
- 最小修复仅是在 staging 验证命令中增加 stdin 从 /dev/null 读取；不修改
  PassWall 源码、配置、节点、ACL、DNS、路由或生产 VM33。

### IT 专家组结论

- OpenClaw SRE：根因与观测吻合，允许在 VM36 上做一次受控复验；start 和 restart
  各一次，功能验收必须覆盖可信进程、监听、SOCKS、DNS 和 HTTP。
- 安全审核：动作风险为 high，必须已有明确授权和离线 Revert；秘密只留在 OpenClaw
  受保护通道，禁止触碰 VM33、Cloudflare 和网络控制面。
- 调试与工程质量复核：修复应限定在验证 harness，禁止增加 controller、ACK、
  新事务框架或额外测试窗口。
- 最强反对意见：若 Revert 后 staging 不是干净基线，不得清理后硬跑，必须先回到
  正确离线快照。

### 已实施的本地修复

以下三个 staging 脚本已只增加 stdin 关闭：

- window1-stage-diagnostic-start.sh
- window1-stage-restart.sh
- window1-stage-phase-instrumented-start.sh

三份脚本均通过本地 shell 语法检查。

### 当前停止点

本次 Revert 后只读门控实际得到：PassWall global=1、配置拓扑为 25 个节点、3 条
ACL、8 条分流规则、init disabled、Xray 进程为 0，但仍存在目标监听、PassWall nft
规则及运行态/锁路径。该状态不符合干净 staging 基线，也与前文记录的 global=0、
监听为零、runtime absent 不一致。

因此 VM36 已正常关机；.253 已不可达，.254 可达，PC Google/YouTube 均为
HTTP 204。必须在 ESXi Host Client 中离线 Revert 到名称以
OpenWrt-25.12.1-stage-pre-fulltest- 开头的干净快照，启动后重新通过只读基线，
才能执行一次修正后的 start/restart 复验。当前仍为 staging NO-GO，不影响 VM33
继续生产。
## 2026-07-28 修复复验最终结果

本节覆盖上一节“当前停止点”。用户在 ESXi Host Client 中确认唯一快照
OpenWrt-25.12.1-stage-pre-marker-revert-drill-20260727-154536，并完成离线
Revert 与 VM36 启动。

### 正确 Revert 基线

- 已审核的干净基线脚本通过。
- VM36 可达，PassWall global=0、init disabled，目标监听和 runtime 均为零。
- VM33/.254 可达，PC Google/YouTube 均为 HTTP 204。

### 最小修复执行

- 结构化配置恢复成功：25 个节点、3 条 ACL、8 条分流规则。
- PassWall init 始终保持 disabled。
- 唯一一次修正后 start：RC=0，耗时 2 秒；此前同一路径会在 240 秒超时。
- start 后可信身份探针通过：PID/starttime/规范化可执行路径/SHA256 稳定，
  1070 仅绑定 loopback。
- SOCKS Google/YouTube 均为 204；本地两级 DNS 成功；1 MiB 下载完整；
  ACL 来源与数量保留；启动日志没有 fatal、panic、unsupported、invalid、error
  或 fail。
- 唯一一次修正后 restart：RC=0，耗时 4 秒。
- restart 后 nft 结构不变，可信监听稳定，SOCKS/DNS/HTTP/下载/ACL 全部通过。
- 验收期间 VM33/.254 始终可达，PC Google/YouTube 始终为 HTTP 204。

### IT 专家组最终结论

- 根因已闭环：故障属于 SSH 验证 harness 未关闭 stdin，不是 ImmortalWrt、
  PassWall 或 Xray 的运行兼容性问题。
- 将验证命令 stdin 指向 /dev/null 是充分且最小的修复，不需要修改 PassWall 源码。
- VM36 状态由“运行态 NO-GO”更新为“staging 运行态 GO”。
- 本结论不等于正式割接授权：VM36 仍为 .253 staging，VM33/.254 继续生产；
  不修改 DNS、Cloudflare、路由、Sidecar、节点池或凭据。
- 本轮到此收敛，不增加 controller、ACK、额外 restart 或新诊断窗口。
## 2026-07-29 冷启动与隔离客户端最终验收

- VM36 PassWall init 已从 disabled 改为 enabled；启用动作本身没有启动服务、
  产生监听或 runtime。
- VM36 正常关机后由 ESXi Host Client 完整冷启动，无需手工连接网卡或补启动
  PassWall。
- 冷启动后 global=1、init enabled、25 个节点和 3 条 ACL 保留；可信监听、
  SOCKS、DNS、Google/YouTube HTTP 204、1 MiB 下载、ACL 和 nft 结构全部通过。
- OpenClaw 使用独立临时网络命名空间和地址 192.168.1.251，以 VM36/.253 为
  默认网关连续运行 16 轮，DNS、Google 和 YouTube 各成功 16 次，历时 986 秒；
  首尾 1 MiB 下载均通过。
- 临时命名空间、macvlan 和专用 resolv 目录已自动删除；OpenClaw 主默认路由始终
  指向生产 VM33/.254。
- 验收期间 VM33/.254 始终可达，PC Google/YouTube 始终为 HTTP 204。

结论：最短迁移方案的 Window 1 已完成，VM36 是已验证的生产候选。下一步只能按
离线操作卡执行 Window 2 同 IP 割接；正式割接前后均不得修改 Cloudflare、DNS、
Sidecar、CFIP 池、订阅或凭据。
## 2026-07-29 Window 2 结果

VM36 已接管 192.168.1.254/24，即时验收通过；旧 VM33 保持关机完整保留。详细
证据见 openwrt-vm36-production-cutover-result-2026-07-29.zh-CN.md。迁移最终收口只
剩下一次自然 Sidecar 周期和约 24 小时代理/DNS 观察。