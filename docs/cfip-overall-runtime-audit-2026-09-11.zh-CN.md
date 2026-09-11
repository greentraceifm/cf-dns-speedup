# CFIP 优选 IP 项目整体运行审计与优化建议（2026-09-11）

## 一、结论

项目代码和既有部署架构符合原设计：192.168.1.110 负责 Sidecar 自然测速，VM36（192.168.1.254）负责真实 PassWall 门控、候选池和 Cloudflare 受限同步，auto/auto1/auto2 为主槽，auto3/auto4 为竞争槽。

本次没有发现新的代码缺陷。已知的竞争槽重复转换 Bug 已由提交 0dd2c88 修复并在 43ba222 记录部署；本地专项测试和全项目回归均通过。生产实时自然周期不能在本次标记为完整验收，因为通过 192.168.1.140 进入 192.168.1.110 的只读审计在 sudo 凭据校验处失败。没有执行任何生产写操作，也没有把旧样本冒充新证据。

当前决策：保持现状，不降门槛、不增加 DNS、不恢复旧 06:30 cron、不手工改写 Cloudflare。

## 二、已确认的修复

旧逻辑在 auto3=A、auto4=B 仅发生排序互换时，先写入一个槽的现值，造成两个槽短暂指向同一 IP。现在的逻辑：

- 仅顺序变化时跳过写入，优先保留 IP 多样性；
- 目标集合变化时，只选择不会与另一竞争槽当前值重复的单条更新；
- 没有安全单条转换时进入 awaiting_safe_competition_transition；
- Cloudflare PATCH 前再次检查竞争槽去重不变量；
- 每周期最多写入一条 Cloudflare 记录。

VM36 已部署脚本哈希为 08706fe539d401193649178dc1c5a876ba77a28d849ef96589658740e9fefb6b，回滚目录为 /root/openwrt-backup/cfip-competition-transition-20260907-171126。部署没有重启 PassWall、Sidecar、Docker、Ollama、DNS 或 VM。

## 三、验证结果

### 本地代码和测试

- tests/test-sidecar-auto-sync-plan.sh：通过，覆盖竞争槽纯交换抑制、部分替换、已有重复修复和主槽安全换位。
- tests/run-all-regression-tests.sh：通过，核心回归、操作安全、主锁、路由门控和候选计划测试通过。
- Shell 语法检查和 git diff --check：通过。
- Windows Git Bash 没有原生 Linux flock，锁竞争运行时测试按环境限制跳过；这不是生产测试失败，Linux 生产仍要求真实 flock。

### 生产只读审计

审计已通过 .140 到达维护链路，但读取 .110 时返回 sudo: no password was provided 和 incorrect password attempt。因而本次没有取得最新 Sidecar 报告、容器健康、VM36 最新同步状态、池文件或 Cloudflare 三路 DNS 的实时证据。

这说明当前阻塞点是维护通道凭据，不是已确认的 Sidecar、PassWall 或 Cloudflare 故障。不能猜测密码，也不能绕过 .140 使用历史凭据直接登录生产节点。

## 四、运行风险

P1：实时可观测性暂时阻塞。应先恢复 .140 到 .110 的受保护 sudo 凭据来源，再执行一次只读审计。修复维护通道时只改凭据传递，不修改生产服务。

P2：历史上 Cloudflare API 曾有瞬时 DNS 或 SSL 波动。现有有限重试和失败安全机制有效；不应通过增加 DNS、降低测速门槛或手工 PATCH 处理。

P3：Windows 测试环境缺少原生 flock。建议将锁竞争运行时测试放入 Linux CI 或轻量 Linux 容器，但不需要改生产代码。

## 五、候选池和策略评估

现有分层仍合理：竞争观察底线 3.5 MB/s，不得继续动态降低；竞争槽只接受连续真实隔离 PassWall 门控候选；主槽需要三日同路径基线、至少 4.0 MB/s 和改善门槛；每周期最多更新一条记录；所有槽位应避免重复 IP。

没有本次实时池数据之前，不能声称候选数量充足或不足，也不应为了凑数量降低门槛。竞争槽的作用是已验证的备用路径，不是填满记录。

## 六、最小优化顺序

1. 恢复 .140 到 .110 的受保护只读维护通道。
2. 只读核验一个最新自然周期：Sidecar 状态、导出、VM36 同步、锁、PassWall 四监听、Google/YouTube、五条记录三路 DNS 和 Cloudflare GET。
3. 若健康，保持现状，不恢复旧 cron、不增加 DNS、不手工写 Cloudflare。
4. 若出现新的自然失败，只修复对应模块，先本地测试，再原子部署并保留回滚点。
5. 将 Linux flock 测试迁移到 Linux CI，作为测试基础设施改进。

明确不建议恢复旧 06:30 任务、降低 3.5 MB/s 门槛、直接手工交换五条记录、绕过连续日期门控或扩大扫描规模。

## 七、收口判断

代码层面已收口：已知竞争槽重复 Bug 有修复、专项测试和回滚点。生产层面只差正确维护凭据下的一次最新自然周期只读验收。在此之前保持现状是最小风险路径。

## 八、重试后的实时只读核验（2026-09-11 20:22 CST）

已从 OpenClaw 记忆确认正确维护方式，改用本机维护手册规定的严格 SSH 别名 ollama-server，未再从旧 expect 文件提取密码，也未绕过 .140。本次只读核验成功取得以下实时证据。

### .110 Sidecar

- cfip-sidecar.service：inactive、Result=success、MainPID=0。
- cfip-sidecar.timer：active/enabled。
- Docker PID 为 1144；无 /run/cfip-sidecar/xray-*.json 残留。
- 由于非 root 维护用户权限限制，本次没有把容器列表和 cfip-direct 附着数作为完整通过项；root-only 审计包装器仍需后续修正凭据来源后再补一次。
- .110 本机直连 Google/YouTube 探测均超时（HTTP 000）。这反映的是 .110 当前直连出口路径，不等于 Sidecar 服务失败；Sidecar 自然任务本身已成功结束，不能据此修改 DNS 或停止 Sidecar。

### VM36 与同步链路

- VM36 已运行约 44 天，负载约 0.02，根分区使用 7%，内存约 70 MB / 1 GB，资源余量充足。
- 四个生产脚本哈希与当前审计基线匹配；sidecar-auto-sync.sh 为已部署竞争槽去重修复版本。
- 最新同步报告：2026-09-11 04:36:17 already_present，说明本周期目标已匹配，没有不必要写入。
- 2026-09-08 曾按新逻辑更新 auto3 一条记录；2026-09-09 至 09-11 均为 already_present。这证明修复后的单记录转换没有再次制造竞争槽重复。
- 主槽当前为三个不同 IP：104.17.129.81、104.17.153.15、104.17.134.190。
- 竞争槽当前为两个不同 IP：104.26.1.38、104.17.158.61。
- 主槽资格池和竞争资格池均有 2 个以上连续 6 日的真实隔离 PassWall 资格记录；当前不需要降低 3.5 MB/s 门槛。
- 唯一 04:35 cron 为 1 个，旧 06:30 cron 为 0；四把项目锁均 free，CFIP 进程 idle。
- 一个 Xray 进程承载 1070/1041/11400/15353，四个监听均正常；VM36 Google/YouTube 均 HTTP 204。

### DNS 与 Cloudflare

- auto 至 auto4 在 192.168.1.1、192.168.1.254、1.1.1.1 三路解析完全一致。
- Cloudflare 五条只读 GET 均 HTTP 200，内容与三路 DNS 一致。
- 当前五槽均为不同 IP，之前的 auto3/auto4 重复问题已在自然周期中恢复，不需要人工 PATCH。
- 日志仍出现过 api.cloudflare.com 瞬时解析失败；本周期只读 GET 最终成功，同步状态为 already_present。现有有限重试和失败安全机制有效，暂不改变 DNS、Cloudflare 出口或同步策略。

## 九、最终建议

1. 生产主链路目前可继续稳定运行，保持现状即可。
2. 不恢复旧 06:30 cron，不降低门槛，不增加 DNS，不手工改写五条记录。
3. 将 .110 直连 HTTP 超时作为独立的出口路径观测项；只有 Sidecar 自然服务失败或导出链路失败时，才另立修复任务。
4. 后续可单独修正 root-only 审计包装器，使其不依赖旧 ssh_ollama.expect 密码字段；这属于维护工具修复，不应改动生产链路。
5. 将 Linux flock 运行时测试放入 Linux CI，继续保持 Windows Git Bash 只做便携测试。

截至本次核验，没有需要立即修改生产配置的 Bug。

## 十、维护通道最终收口（2026-09-11 20:50 CST）

用户在 .110 上执行上传的安装器成功，输出 CFIP_MAINTENANCE_INSTALL=OK 和 CFIP_MAINTENANCE_TEST=OK。随后修正 .140 入口，使其直接调用 .110 的固定命令 /usr/local/sbin/cfip-maintenance-audit，不再尝试未被授权的 sudo -n sh -s。

最终 root-only 只读审计通过：

- Sidecar Result=success，timer active/enabled；
- 最新报告 5 行，导出 3 行；
- 无 Xray 残留、无瞬时 CFIP 容器，cfip-direct 附着数为 0；
- sub2api、PostgreSQL、Redis 均 running/healthy；
- Docker PID 为 1144，Ollama 无驻留模型。

.110 直连 Google/YouTube 仍返回 HTTP 000 超时，但 VM36 代理路径此前实时核验均为 HTTP 204；该现象不属于维护授权或 Sidecar 失败，不触发生产改动。

至此，CFIP 生产链路和 OpenClaw 维护链路均已收口。后续只保留自然周期观察，不再扩大代码或网络优化。
