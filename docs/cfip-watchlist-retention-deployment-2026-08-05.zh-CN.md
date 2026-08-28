# CFIP 挑战者保留机制部署记录（2026-08-05）

## 结论

本次优化已经完成代码实现、IT 专家组评审、Linux 全量回归、VM36 原子部署和即时生产验收。

核心问题是每日 Sidecar 导出的候选 IP 经常变化，VM36 原逻辑只测试当天 3 条候选，导致同一 IP 很难连续通过 3 个不同日期的真实 PassWall 门控，竞争资格长期为 0。此次修复没有降低门槛，也没有增加测速次数或流量。

## 专家组结论

SRE、安全、工程可靠性和可验证性视角联合评审结论为“有条件通过”。实施边界如下：

- 每周期仍最多测试 3 个候选；
- 固定保留最多 2 个正在形成连续通过记录的挑战者；
- 剩余名额接纳当天 Sidecar 最新候选；
- `3.5 MB/s` 竞争门槛、`4.0 MB/s` 主槽门槛和 `25%` 主槽晋升条件不变；
- 每周期最多修改一条 Cloudflare 记录；
- 不新增服务、cron、扫描次数或凭据权限；
- 只有本周期实际复测且已完成三日资格的候选才能进入 DNS 计划。

## 实现

涉及生产代码：

- `sidecar-auto-sync.sh`
  - 新增 root-only `router-candidate-watchlist.tsv` 状态协议；
  - 每周期形成最多 3 条的 `2 个保留 + 1 个新候选` 测试计划；
  - 连续通过天数优先，其次按最低速度、平均速度排序；
  - 本周期失败候选立即退出保留列表；
  - 旧资格文件中未在本周期复测的条目不能进入 Cloudflare 计划；
  - 状态文件使用临时文件、`0600` 权限和原子改名。
- `router-candidate-gate.sh`
  - 新增严格的本周期 allowlist；
  - 保留候选必须是 Cloudflare IPv4，并绑定到当天导出 epoch；
  - allowlist 最多 3 条，拒绝重复、额外字段和非法来源；
  - 未放开任意 IP 测试能力。

同时修复两处只读诊断：Sidecar 导出表头检查兼容 v1/v2；公共 DNS 单次缺失时只读等待后复查一次。

## 测试

- 相关脚本 `bash -n`：通过；
- 候选调度定向测试：通过；
- 路由门控定向测试：通过；
- `.140` Linux 全项目回归：通过；
- Sidecar 全套测试：通过。

新增覆盖包括：第一天 3 个新候选、第二/三天保留 2 个并引入 1 个新候选、三日资格形成、失败淘汰、重复去重、最多 3 条、孤立旧资格禁止写入，以及原有主槽排序和 25% 晋升条件保持不变。

## 生产部署

部署时间：2026-08-05 11:48 CST。

部署前 VM36 脚本与 Git HEAD 哈希完全一致，没有覆盖生产独有改动。部署采用哈希硬门控、三把项目锁、root-only 备份和原子替换；没有运行 Sidecar 或完整同步任务。

- 新 `router-candidate-gate.sh` SHA256：`67ffa269f04c43bcb86e1f6dd231d6ebeddfbed9c2df9fe88973a7c62cf04f24`
- 新 `sidecar-auto-sync.sh` SHA256：`95508b8e8e572c241b078fe417fc28546a25cf667e6dbef9dc9f746920281a4f`
- VM36 回滚目录：`/root/openwrt-backup/cfip-watchlist-20260805-114821`
- PassWall 重启：0 次；
- cron 变化：无；
- Cloudflare/DNS 写入：无；
- watchlist：部署时未预建，由下一次自然 04:15 周期原子生成。

## 即时验收

- 新脚本哈希匹配；
- 回滚目录存在，共保存 9 个文件；
- 三把项目锁均空闲；
- PassWall Xray PID 保持 `14386`；
- `1070/1041/11400/15353` 四监听正常；
- VM36、PC、OpenClaw、Sidecar 的 Google/YouTube HTTP 检查正常；
- `auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路一致；
- Cloudflare 五条记录只读 GET 与 DNS 内容一致；
- 唯一 04:15 cron 保持，旧 06:30 任务仍未恢复。

## 后续自然验收

2026-08-06 04:15 CST 的自然同步周期应首次生成最多 2 条 watchlist 记录。验收只需确认：

- 本周期测试总数不超过 3；
- 计划结构为最多 2 条 retained 加至少 1 条 staging 新候选；
- 失败候选不会保留；
- 未满三日时状态仍为 `awaiting_multiday_gate`，不会更新 Cloudflare；
- PassWall、DNS、HTTP 和 cron 保持不变。

不得为了立即看到竞争槽更新而手动运行同步、降低门槛或制造候选。

## 回滚

如下一自然周期发现实现异常，只需从以下目录恢复两份脚本，不需要重启 PassWall，也不需要修改 DNS：

`/root/openwrt-backup/cfip-watchlist-20260805-114821`

恢复后验证旧哈希、四监听、HTTP、cron 和五条 DNS 一致；本次新增 watchlist 可改名隔离，不应批量修改 Cloudflare 记录。

## 自然周期收口（2026-08-10）

- 2026-08-06 和 2026-08-07 04:15 同步曾被部署遗留的 `/tmp/cf-dns-speedup.lock` 阻断；该文件为无进程、无文件描述符占用的 0 字节 stale lock，已于 2026-08-07 安全删除。
- 修复后 2026-08-08、2026-08-09、2026-08-10 三个自然周期均完成隔离 Xray 真实 PassWall 复测，未停止或重启 PassWall。
- `104.17.154.110` 连续三日通过，窗口最低/平均速度为 `4.24/4.35 MB/s`；`104.21.236.218` 同样连续三日通过，窗口最低/平均速度为 `4.21/4.35 MB/s`。
- 2026-08-09 每周期单条写入规则更新了主槽 `auto`；2026-08-10 更新了竞争槽 `auto3`，没有批量修改 Cloudflare。
- `auto3` 当前为 `104.17.154.110`；`auto` 与 `auto1` 的暂时重复是主槽按单条写入逐步重排的中间状态，不绕过现有稳定池和门槛。
- `auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致；PassWall Xray PID、`1070/1041/11400/15353` 监听及 Google/YouTube HTTP 204 正常。
- `.110` 最新自然 Sidecar 服务 `Result=success`、`ExecMainStatus=0`、`MainPID=0`，timer 保持 active；下一周期继续由现有 timer/cron 自然推进，无需人工触发。

结论：挑战者保留、连续三日门控、竞争槽写入、主槽排序和每周期最多一条记录的完整链路已形成生产证据，可以保持现状运行。

## 2026-08-14 最终只读复核与维护入口修复

### CFIP 生产状态

- `.110` 最新自然报告为 `sidecar-observation-20260814-193458.tsv`，共 5 条记录，两个 HTTP 轮次均为 `200`；字段 10 均为 `low`，表示本轮没有达到候选速度门槛，不是任务失败。
- `cfip-sidecar.service` 自然结束后为 `inactive/dead`、`Result=success`、`ExecMainStatus=0`、`MainPID=0`；timer 保持 enabled/active。
- Sidecar 锁空闲，无 `/run` Xray JSON、无瞬时 CFIP 容器、`cfip-direct` 附着数为 0。
- `sub2api`、PostgreSQL、Redis 均为 running/healthy，重启计数为 0；日志上限分别保持 `50m x 3`、`20m x 3`、`20m x 3`。
- `.110` 根分区使用率 21%，inode 使用率 2%；Ollama 无驻留模型；Google 和 YouTube 均为 HTTP 204。

### VM36 与 Cloudflare

- VM36 最新自动同步状态为 `updated`；竞争槽和主槽写开关均为 1。
- 生产脚本哈希保持：`router-candidate-gate.sh=67ffa269f04c43bcb86e1f6dd231d6ebeddfbed9c2df9fe88973a7c62cf04f24`，`sidecar-auto-sync.sh=95508b8e8e572c241b078fe417fc28546a25cf667e6dbef9dc9f746920281a4f`。
- 唯一 `04:15` cron 存在，旧 `06:30` cron 为 0；同步锁文件虽存在，但 `flock` 实测为空闲锁，不是 stale lock 或运行中任务。
- PassWall 一个 Xray 进程正常承载 `1070/1041/11400/15353`，VM36 Google/YouTube 均为 HTTP 204。
- `auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析完全一致，并与 Cloudflare 只读 GET 内容一致。
- 本轮没有手工启动 Sidecar、扫描、诊断或自动同步，没有修改 Cloudflare、DNS、门槛、cron、timer、PassWall 或路由。

### OpenClaw 维护入口

- 旧 `/home/ubuntu/.openclaw/tools/ssh_ollama.expect` 仍直连 `ollama@192.168.1.110`，与当前仅允许密钥别名的访问方式不兼容，会报 `Permission denied (publickey)`。
- 已备份旧文件并原子切换为 `ollama-server` SSH 别名，强制 `StrictHostKeyChecking=yes` 和固定 known_hosts；新文件权限为 `0600`，SHA256 为 `ba0cfde72d287c55c62ea475c9c555c466c730f292716d3d57943fd12080bea3`。
- 回滚文件：`ssh_ollama.expect.pre-alias-fix-20260814` 和 `ssh_ollama.expect.pre-no-password-prompt-20260814`。
- 首版验证发现 expect PTY 不适合承载 `sudo -S`：输入可能被终端回显到内部命令转录。最终版本已禁止所有交互密码提示，只负责密钥 SSH；root 操作继续使用既有的 sudo-stdin 包装器。记录不包含凭据值。

### 时间标签边界

`.140` 和 VM36 本轮输出了 `2026-08-15` 主机时间。按当前权威日期 `2026-08-14`，这些未来时间标签只视为主机时钟偏差，不用于连续日期门控或自然周期证据；本次有效自然报告仍以 `sidecar-observation-20260814-193458.tsv` 为准。本次未自动校时。

### 结论

CFIP 生产链路继续保持健康。本轮没有发现需要调整候选门槛、扫描规模、五槽策略或 PassWall 的新缺陷。维护入口的重复连接故障及密码提示回显路径已经封堵；由于凭据曾进入内部工具转录，是否轮换维护凭据应作为独立安全决定，不在本次无停机收口中自动执行。

## 2026-08-19 主槽池不足异常退出修复

### 故障现象与根因

- VM36 的唯一 `04:15` cron 在 2026-08-17、2026-08-18 和 2026-08-19 均已正常触发；候选导入、3 个竞争候选 canary 和 2 个主槽 canary 实际完成。
- `sidecar-auto-sync.latest.tsv`、history 和 state 却停在 2026-08-16，原因不是 cron 漏跑，而是主槽排序阶段输出 `ERROR: primary ranking pool has fewer than three qualified IPs` 后异常退出。
- 当前只有 2 个主槽 IP 形成完整三日同路径基线时，代码把“排序池不足 3 个”误判为致命错误。按既有设计，这种状态应保持 `PRIMARY_BASELINE_READY=0`，安全返回并记录 `awaiting_primary_baseline`，不得中断整轮状态收口。
- 该缺陷没有产生错误的 Cloudflare 写入，五条 DNS 记录和 PassWall 运行拓扑均未被改变，故障安全边界有效。

### 修复与测试

- `build_primary_targets()` 在主槽排序池不足 3 个时改为清理临时文件并正常返回，不再调用 `die`。
- 新增两条主槽资格数据的回归场景，要求 `PRIMARY_BASELINE_READY=0` 且主槽目标文件为空，证明该状态会安全失败关闭。
- `tests/test-sidecar-auto-sync-plan.sh` 和全项目回归测试通过；现有 `3.5 MB/s` 竞争门槛、`4.0 MB/s` 主槽门槛、`25%` 改善条件、连续三日门控和每周期最多一条 Cloudflare 写入规则均未改变。

### 生产部署与即时验收

部署时间：2026-08-19 12:28 CST。

- 旧生产脚本 SHA256：`95508b8e8e572c241b078fe417fc28546a25cf667e6dbef9dc9f746920281a4f`。
- 新生产脚本 SHA256：`852890f5e6f1b9c7c22cfe2444b880dc2530fa473a86ae9f9cce87b549d8360f`。
- VM36 root-only 回滚目录：`/root/openwrt-backup/cfip-primary-pool-shortfall-20260819-122841`。
- 部署使用旧哈希硬门控、三把项目锁、VM36 本机回归测试、root-only 备份和原子替换；没有手工运行 Sidecar 或 `sidecar-auto-sync.sh run`。
- PassWall 重启 0 次，cron 变化 0，Cloudflare 写入 0；一个 Xray 进程和 `1070/1041/11400/15353` 四监听保持正常。
- 五条记录在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致，Cloudflare 五条只读 GET 成功，VM36、OpenClaw 和 Sidecar 的 Google/YouTube HTTP 均正常。
- `.110` 最新自然 Sidecar 周期 `Result=success`、`ExecMainStatus=0`、`MainPID=0`，共 5 条双轮 HTTP 200 结果并导出 3 个 observation 候选；锁、Xray JSON、瞬时容器和 `cfip-direct` 均无残留，三个必要容器 healthy，Ollama idle。

### 下一自然周期

不补跑 2026-08-19 的自动同步。等待 2026-08-20 04:15 CST 的自然任务验证：

- 主槽基线仍不足 3 个时，`sidecar-auto-sync.latest.tsv` 应刷新为 `awaiting_primary_baseline`，不再出现主槽排序池不足异常；
- 若届时已形成 3 个完整主槽基线，则按原有排序和单记录写入规则正常推进；
- 两种结果均不得绕过连续三日、速度门槛或每周期单条写入限制。

## 2026-08-19 主槽重复与 auto/auto1 冗余修复

### 新发现

- 只读复核确认 Cloudflare 与 VM36 本地 DNS 内容一致：`auto` 和 `auto1` 当前都指向 `104.17.153.15`；`auto2=104.17.134.190`、`auto3=104.17.135.183`、`auto4=104.17.153.186`。
- 这不是 SmartDNS 缓存或三路 DNS 不一致，而是 Cloudflare 主槽内容本身重复，导致 PassWall 实际上用两个名称承载同一个地址，冗余失效。截图中的 `auto`、`auto1` 超时不能仅凭 DNS 解释，仍需以后续真实 PassWall 使用结果判断上游链路质量。
- `.110` 最近自然 Sidecar、VM36 canary 和连续日期资格均正常。主槽资格文件已有 `104.17.153.15`（7 日，最低 4.19 MB/s）和 `104.17.134.190`（7 日，最低 4.14 MB/s）；竞争槽已有 `104.17.135.183`（7 日，最低 4.20 MB/s）和 `104.17.153.186`（7 日，最低 4.06 MB/s）。
- 之前的“主槽资格不足 3 条”修复解决了异常退出，但没有解决主槽重复时无法形成 3 个不同主槽基线的问题，因此需要单独的重复槽修复分支。

### 修复规则

- 仅当当前三个主槽存在重复 IP 时启用；正常主槽晋升的 25% 改善门槛保持不变。
- 候选必须已经进入竞争资格文件，满足真实隔离 PassWall 连续日期门控和主槽最低 4.0 MB/s 门槛，并且最低速度严格高于当前最弱主槽。
- 修复只替换重复的那个槽位，保留已有不同 IP 的主槽位置和顺序；当前数据预期下一自然周期最多将 `auto1` 从 `104.17.153.15` 替换为 `104.17.135.183`，但不人工预写 Cloudflare。
- 仍遵守每周期最多修改一条 Cloudflare 记录；没有合格不同候选时保持原值，安全等待。

### 实现与验收

- `build_primary_targets()` 新增重复主槽检测和定向填槽逻辑；不会把最优候选无条件重排到 `auto`，避免再次制造槽位抖动。
- 新增回归场景覆盖：`auto` 与 `auto1` 重复、已有主槽两条、竞争槽候选连续 7 日且最低速度高于弱槽时，只把候选填入重复槽。
- Windows Git Bash 的权限模拟导致本地 Sidecar 套件测试误报；已在 `.140` Linux 临时目录执行全量项目回归，结果为 `all project regression tests passed`、`all sidecar tests passed`。
- VM36 部署时间：2026-08-19 19:14 CST。
- 新 `sidecar-auto-sync.sh` SHA256：`856ecbe0fbeab0006c55db5c9175da60a520d142e2c20e8a48ad9070d41864ed`。
- root-only 回滚目录：`/root/openwrt-backup/cfip-duplicate-primary-repair-20260819-191454`。
- 部署前后 PassWall PID/四监听、cron、配置和 HTTP 健康保持不变；PassWall 重启 0 次、Cloudflare 写入 0 次。

### 后续自然验收

- 不手动运行同步，也不人工修改 `auto` 或 `auto1`。
- 下一次自然 `04:15` 任务应在锁、网络和 API 读取正常时，按单记录规则处理重复槽；若 Cloudflare API 短暂不可达，任务应保持故障安全，不写入半成品。
- 收口时必须确认 `auto`、`auto1`、`auto2` 三个主槽为不同 IP，五条记录三路 DNS 一致，PassWall 实际连通性恢复；若仍出现超时，再独立评审上游 VMess/profile/服务端容量，不再把问题归咎于 DNS。

## 2026-08-20 主锁误判与自然周期时序修复

### 自然周期结果与根因

- `.110` 的新自然 Sidecar 周期成功结束：报告时间为 2026-08-20 04:17:45 CST，共 5 条双轮 HTTP 200 结果并导出 3 个 observation 候选；服务结果、timer、锁、容器、Ollama、残留清理和 HTTP 均正常。
- VM36 的 04:15 自然任务没有消费该批候选，日志明确记录 `ERROR: main CFIP project lock is present`；最新同步报告仍停在 2026-08-16。
- `/tmp/cf-dns-speedup.lock` 是普通文件，`flock` 实测空闲。部署事务会创建该文件并在退出时释放锁，但文件本身会保留；旧代码只检查路径是否存在，因此把“空闲遗留文件”误判为“任务正在运行”。
- 同时确认存在独立时序问题：本轮 Sidecar 在 04:17:45 才完成，晚于 VM36 的 04:15 cron。即使修复锁判断，04:15 仍可能读取上一日导出。

### 最小修复

- `sidecar-auto-sync.sh` 与 `router-candidate-gate.sh` 统一按真实锁状态判断：路径不存在为可用，遗留目录锁为占用，普通文件只有在 `flock` 真实失败时才视为占用，其他异常文件类型继续故障安全阻断。
- 新增锁语义回归测试，覆盖路径不存在、空闲普通文件、真实活动文件锁和旧式目录锁四种情况，并加入全项目回归入口。
- VM36 唯一同步 cron 从 04:15 后移到 04:35，为本轮 04:17:45 的 Sidecar 完成时间保留约 17 分钟余量；旧 06:30 任务继续保持禁用。
- 候选门槛、三日门控、主槽 25% 改善条件、每周期最多一条 Cloudflare 写入、五槽策略和 PassWall 配置均未改变。

### 测试、部署与回滚

- Windows Git Bash 定向测试和全项目回归通过；`.140` 使用真实 `flock` 的 Linux 全项目回归通过。
- VM36 第一次部署事务在写入前发现完整路由器测试依赖 GNU `date`，与 BusyBox `date` 不兼容并安全退出；当时脚本、cron 和生产状态均未改变。VM36 最终只运行兼容的语法、真实锁语义和同步计划测试，完整回归仍由 `.140` 承担。
- 部署时间：2026-08-20 10:17 CST。
- 新 `sidecar-auto-sync.sh` SHA256：`47cb47b1c0ca450209ea3747961b313d3d8ce19e1d4d9d048ea10c96123b2df7`。
- 新 `router-candidate-gate.sh` SHA256：`9ee5c76e76feb7198209ebb6e4f1ab0f7672951194fc860c6efdd9e60121413b`。
- root-only 回滚目录：`/root/openwrt-backup/cfip-main-lock-schedule-fix-20260820-101711`，包含旧两脚本和原 crontab。
- 部署后独立复核证明：遗留普通锁文件存在且空闲时，两份生产脚本均正确放行；唯一 04:35 cron、PassWall 一个 Xray、`1070/1041/11400/15353` 和 Google/YouTube HTTP 均正常。
- 本次 PassWall 重启 0 次、Cloudflare 写入 0 次，没有手工补跑 Sidecar、canary 或自动同步。

### 下一自然周期

等待 2026-08-21 的自然 Sidecar 与 04:35 VM36 同步，不补跑 2026-08-20：

- 不应再出现空闲 `/tmp/cf-dns-speedup.lock` 导致的误阻断；
- VM36 应消费当天完成的新导出并刷新同步报告；
- 若重复主槽修复满足既有资格与单记录门控，可自然更新一条主槽；否则应记录安全等待状态；
- 最终仍需确认 `auto`、`auto1`、`auto2` 去重、五条 DNS 三路一致和 PassWall 实际连通性，之后才能完成该缺陷的自然周期收口。

## 2026-08-20 全面锁协议与重复消费审计修复

### 审计发现

- 主项目仍使用旧式 `mkdir` 目录锁，而 Sidecar 自动同步、候选门控已使用文件 `flock`；混合协议会让不同执行面无法可靠识别彼此是否真实运行。
- `passwall-node-observe.sh` 持有观察锁后调用主脚本，缺少合法嵌套调用标识，可能被新的协调检查误判为并发任务。
- 同一个 Sidecar `source_export_epoch` 若被跨日重复复测，旧资格统计可能把同一份导出累计成多个有效日期。
- 自动同步缺少独立的短时导出有效期，异常 cron 有机会再次消费上一日导出。
- 第一版锁修复中的 `busy && die` 会在 `set -e` 环境把“锁空闲”的返回码 1 误当作脚本失败；VM36 BusyBox 也不支持测试夹具使用的 `sleep 0.1`。

### 最小修复范围

- `cf-dns-speedup.sh` 主锁改为文件 `flock`，兼容并迁移陈旧旧式目录锁；活动旧任务、符号链接和异常锁类型继续故障安全阻断。
- 主脚本、Sidecar 自动同步、候选门控和 PassWall 观察任务统一检查四把协调锁；观察脚本通过 `CFST_PASSWALL_NODE_OBSERVE_OWNER=1` 标识合法的内部嵌套调用。
- 竞争和主槽资格按 `source_export_epoch` 去重，同一导出不能跨日期累积资格。
- 自动同步默认只接受最近 `21600` 秒内的 Sidecar 导出；该限制不改变 3.5/4.0 MB/s 门槛、连续三日门控、25% 改善条件、五槽策略或单周期最多一条写入规则。
- 将锁判断改为显式 `if`，并把 BusyBox 测试等待改为整数秒。

### 测试、部署和回滚

- `.140` 真实 Linux 环境重新执行全项目回归，结果为 `all project regression tests passed` 和 `all sidecar tests passed`；主锁语义、四锁协调、router canary、候选门控、自动同步计划及语法检查均通过。
- VM36 于 2026-08-20 11:41 CST 完成四脚本原子部署；生产哈希为：
  - `cf-dns-speedup.sh`：`b1a9154d866e44aa69bff62ae3f49237016f08edb91541872eb101a7bbb45f10`
  - `passwall-node-observe.sh`：`bd95b440a1f2a6bc91a61f80cc05ae5d013788c9253fef7a02ce194604e26f36`
  - `sidecar-auto-sync.sh`：`c0ed8ac2a1bbc33845ec5e525afc49dddba703cc5653996b4af6b09f8eaac380`
  - `router-candidate-gate.sh`：`74be18ac4e9c8a3a1b67a2f29d3bb424d912bab1e599f43ac8c49184fe047971`
- root-only 回滚目录：`/root/openwrt-backup/cfip-full-lock-audit-fix-20260820-114136`。
- 部署没有重启 PassWall，没有运行 Sidecar、canary 或自动同步，没有写 Cloudflare，也没有修改 04:35 cron、DNS、门槛、池、订阅、路由或防火墙。
- 独立只读后检确认：四脚本哈希一致，唯一 04:35 cron 保持不变，旧 06:30 不存在，四把锁均空闲或不存在，无 CFIP 残留进程；一个 Xray 进程和 `1070/1041/11400/15353` 四监听正常，Google/YouTube 均返回 HTTP 204，Cloudflare 只读 GET 返回 HTTP 200 且响应结构有效。
- `sidecar-auto-sync.latest.tsv` 仍是 2026-08-16 的旧自然结果；这是部署后尚未到下一次 04:35 自然同步的预期状态，不手工补跑。

### 收口判断

- 本轮发现的确定性代码缺陷已修复，并通过真实 Linux 与生产 BusyBox 兼容路径验证。
- 2026-08-21 的自然 Sidecar 与 04:35 自动同步仍是最后的跨主机时序验收：应消费当天新导出、刷新同步报告，并继续遵守单记录写入和全部既有门控。
- 在该自然周期通过前，只能认定代码修复与即时生产健康验收完成，不能提前宣称整个项目已完成长期稳定性收口。

## 2026-08-23 主槽重复修复优先级收口

### 自然周期事实

- `.110` 自然 Sidecar 周期于 2026-08-22 19:46:26 UTC 成功完成，报告 5 行均为 HTTP 200，并导出 3 个 observation 候选；Sidecar、timer、锁、Xray 临时文件、瞬时容器、`cfip-direct`、三个必要容器、Ollama 和 Google/YouTube HTTP 均通过只读验收。
- VM36 的 04:35 自然同步于 2026-08-23 04:36:10 完成，状态为 `updated`，按既有门控仅更新 `auto3`；04:35 是唯一同步 cron，旧 06:30 cron 不存在，PassWall 四监听和三路 DNS 均正常。
- 同步后仍观察到 `auto`、`auto1` 重复为 `104.17.153.15`，且 `auto4` 镜像到同一地址。该事实证明问题位于自动同步目标排序，不是 Sidecar 采集失败或 DNS 解析不一致。

### 根因与最小修复

- 原同步顺序先处理 `auto3/auto4` 竞争槽，再处理主槽；当主槽已重复时，竞争槽镜像逻辑仍固定选择 `primary1/primary2`，会继续制造重复镜像，导致主槽重复长期得不到单记录修复机会。
- `sidecar-auto-sync.sh` 现先检测三个主槽是否重复；有合格主槽修复目标时，优先处理主槽，再进入竞争槽更新。稳定镜像从当前三个主槽中选择未重复使用的不同 IP；没有可用的不同镜像时保持当前竞争槽值并安全等待。
- 3.5 MB/s 竞争门槛、4.0 MB/s 主槽门槛、连续三日门控、主槽 25% 改善条件、每周期最多一条 Cloudflare 写入和 PassWall 不重启边界均未改变。

### 测试与生产部署

- 本地 `bash -n`、`.140` 真实 Linux 定向测试、全项目回归、锁协调、候选门控和 Sidecar 测试全部通过。
- VM36 于 2026-08-23 15:20:22 CST 完成原子部署。生产 `sidecar-auto-sync.sh` SHA256 为 `9427f414819628ba748ed3ba8d8e9aeea414363aedae71ebaaabd148b454f192`。
- root-only 回滚目录：`/root/openwrt-backup/cfip-primary-dedupe-priority-fix-20260823-152022`，包含旧脚本、配置、cron 和相关状态文件及校验清单。
- 部署后只读后检：脚本哈希、备份校验、cron、三把锁、单 Xray 与 `1070/1041/11400/15353`、无同步残留、自动写开关和 Google/YouTube HTTP 全部通过；PassWall 重启 0 次，Cloudflare 写入 0 次。

### 后续自然验收

- 不手动补跑同步，不人工修改 `auto` 或 `auto1`。
- 下一次自然 04:35 周期只读确认主槽重复修复是否按单记录规则开始执行；若门控不足，允许安全等待，不降低阈值、不改 DNS。
- 只有自然周期确认 `auto/auto1/auto2` 三个主槽去重后，才记录该缺陷完成；若仍重复，应继续依据同步报告判断是资格不足还是上游真实路径问题，不再扩大架构范围。

## 2026-08-25 自然周期复核结果

### 真实样本

- `.110` 最近自然 Sidecar 报告时间为 `2026-08-25 04:09:51 CST`，服务 `Result=success`、`ExecMainStatus=0`、`MainPID=0`，timer active/enabled。
- 报告 5 行均为 HTTP 200，导出 3 个 observation 候选；Sidecar 锁空闲、Xray 临时配置残留 0、`cfip-direct` 附着 0，`sub2api`、`sub2api-postgres`、`sub2api-redis` 均 running/healthy，Google/YouTube 均 HTTP 204。
- VM36 `04:35` 自然同步于 `2026-08-25 04:36:25 CST` 完成，状态为 `updated`，只更新 `auto3.greentraceifm.top`：`104.17.129.81 -> 104.17.130.125`，符合每周期最多一条记录规则。

### 当前槽位与链路

- 主槽已去重：`auto=104.17.153.15`、`auto1=104.17.129.81`、`auto2=104.17.134.190`。
- 竞争槽为 `auto3=104.17.130.125`、`auto4=104.17.153.15`；`auto4` 是没有第二个竞争候选时的稳定镜像，不属于主槽重复。
- 五条记录在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致；Cloudflare 五条只读 GET 均 HTTP 200。
- VM36 一个 Xray 进程承载 `1070/1041/11400/15353`，四端口均监听，Google/YouTube 均 HTTP 204；四个生产脚本哈希与 2026-08-23 部署基线一致。

### Ollama 观察

- 复核时 `/api/ps` 显示 `nomic-embed-text:latest` 短暂驻留，预计于 `2026-08-25 15:30:38 CST` 过期。该模型不是 Sidecar 本轮失败原因；自然 Sidecar 已在更早时段成功完成。
- Sidecar 的 `ollama_is_idle` 门控行为正确：模型驻留时让出测速，不自动杀模型、不重启 Ollama，避免影响 OpenClaw embedding 服务。

### 结论

- 本轮未发现新的生产代码缺陷。此前的主槽重复问题已在自然周期中得到实际修复验证，当前 `auto/auto1/auto2` 已恢复三地址冗余。
- 不恢复旧 `06:30` 任务，不调整门槛、DNS、PassWall、候选池或 Ollama 策略。后续保持自然周期观察即可。

## 2026-08-28 Sidecar 出口漂移故障复核

### 现象与根因

- `.110` 的 `cfip-sidecar.service` 曾在 `2026-08-27 19:33 UTC` 以 `ExecMainStatus=1` 退出，日志为宿主机与 Sidecar 公网出口不一致；这是 Sidecar 的既有安全门控主动退出，不是 Sub2API Compose 故障。
- 当前配置 `SIDECAR_HOST_EXIT_RELATION=same` 与稳定拓扑一致。`2026-08-28` 只读探针确认宿主机和 Sidecar 均成功取得同一公网出口，因此没有证据支持修改该配置。
- 复核同时确认 `sub2api`、`sub2api-postgres`、`sub2api-redis` 均为 running/healthy，负载约 `0.01`，可用内存约 `14.3 GiB`，Sidecar 锁空闲、无临时 Xray JSON；故障范围仅限一次出口漂移。

### 修复与后检

- 通过既有 `.140 -> ollama-server` 受保护维护链路执行 `systemctl reset-failed cfip-sidecar.service`，清除过期的 systemd failed 标记；没有启动或重启 Sidecar、Sub2API、Docker、PassWall、DNS 或 VM。
- 修复后状态为 `ActiveState=inactive`、`Result=success`，timer 仍为 `active/enabled`，锁空闲且无 Xray 残留；三项实际生产容器继续 healthy。`ExecMainStatus=1` 仅保留为最近一次历史执行退出码，不代表当前服务失败。
- 未修改 `sidecar.env`、出口关系、候选门槛、cron、Cloudflare、DNS 或任何生产路由。下一次自然 timer 会重新执行原有三次重试与出口关系门控。

### 收口结论

本次没有需要修改的生产代码缺陷。问题是一次性出口路径漂移加上 systemd 保留历史失败状态；当前链路已恢复为正常、可等待自然周期验证。若未来再次发生同样日志，应记录为实际出口漂移并继续保持安全退出，不应为了“保持成功”而取消出口关系检查或强行改为 `different`。
