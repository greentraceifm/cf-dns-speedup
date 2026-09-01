# CFIP 优选 IP 全链路审计记录（2026-09-01）

## 结论

本次自然周期审计未发现新的 CFIP 生产逻辑缺陷，也没有执行生产修复。当前链路符合项目设计：`.110` 负责自然采集和导出，VM36（`.254`）负责隔离 PassWall 门控、候选池维护和受限 Cloudflare 同步。

## 自然周期结果

- `.110` 最近报告时间：2026-09-01 03:42:19（北京时间）。
- Sidecar：`Result=success`、退出码 `0`、`MainPID=0`；timer active/enabled。
- 报告 5 行，均 HTTP 200；导出 3 个 observation 候选。
- 导出候选速度约为 `5.22–5.38 MB/s`，低于优秀候选标志 `6.5 MB/s`，因此没有绕过真实门控直接晋升。
- Sidecar 锁空闲，无临时 Xray 配置、瞬时 CFIP 容器或 `cfip-direct` 附着；三个必要容器均 healthy；Ollama 无驻留模型。
- VM36 04:35 同步状态为 `already_present`，表示当前记录已经符合本周期排序目标，没有必要写入 Cloudflare。

## 当前池与五槽

- 主槽资格池：3 个候选，均为 `primary_baseline_qualified`。
- 竞争资格池：2 个候选，均为 `competition_qualified`。
- `auto`、`auto1`、`auto2` 当前分别为不同 IP；`auto3`、`auto4` 也分别为不同 IP。五条记录无重复。
- 具体记录在 192.168.1.1、192.168.1.254 和 1.1.1.1 三路解析一致，Cloudflare 只读 GET 全部 HTTP 200。

## 运行拓扑与回归

- VM36 一个有效 Xray 进程承载 `1070/1041/11400/15353`，四个监听均存在。
- VM36 Google/YouTube 204 通过。
- 04:35 同步 cron 唯一存在，旧 06:30 cron 不存在。
- 四把项目锁均空闲，未见 CFIP 进程残留。
- 本地 `bash -n`、`git diff --check`、全项目回归和 Sidecar 测试均通过。
- Windows Git Bash 中依赖真实 Linux `flock` 的锁测试跳过；该环境限制不代表生产 Linux 锁测试失败。

## 独立异常：`.110` 宿主直连出口

本次 `.110` 只读审计再次看到宿主机直连 Google 和 YouTube 请求超时（HTTP 000）。这与此前记录的宿主直连 DNS/出口路径异常一致，但同时满足以下事实：

1. Sidecar 自然测速成功并正常导出候选；
2. VM36 代理出口、四监听和 Google/YouTube 204 正常；
3. 五条 DNS 记录三路一致，Cloudflare 只读内容一致；
4. 没有证据表明该宿主直连异常破坏 CFIP 生产测速或自动同步。

因此本次不修改 DNS、PassWall、路由、Cloudflare、Sidecar 门槛或出口策略。只有后续自然 Sidecar 连续失败，并且失败证据明确指向该出口路径时，才应另立网络出口诊断项目。

## 收口建议

当前 CFIP 项目可保持现状运行，不需要继续扩大代码、池模型或 DNS 研究。后续只需按自然周期观察：Sidecar 成功、VM36 同步状态、五槽去重、三路 DNS 一致和 Cloudflare 只读 GET。发现明确的新失败前，不进行人工补跑、手工改写或生产修复。
