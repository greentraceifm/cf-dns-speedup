# VM36 优选 IP 项目迁移执行记录

日期：2026-07-29

## 结论

VM33 的 `/root/cf-dns-speedup` 已完成分层迁移。VM36 已建立活动目录 `/root/cf-dns-speedup`，未恢复旧 cron、旧启动项、旧脚本备份或旧日志；自动测速仍只由 `.110` Sidecar 执行。

完整功能链路现已启用：`.110` 自然测速导出候选，VM36 每天 04:15 通过受限 SSH 拉取，执行隔离 Xray 真实 PassWall 门控；候选达到 `6.5 MB/s` 且连续至少 3 个不同日期通过后，VM36 每次最多更新 `auto3`、`auto4` 中的一条记录。`.140` 只用于维护，不参与日常运行。

当前首次运行状态为 `no_candidate`，表示 `.110` 暂无达到导出条件的候选，因此系统按设计保留现有 Cloudflare 记录。在下一次自然周期和满 24 小时验收完成前，VM33 和 VM37 不退役。

## 实际实施

- VM33 原目录完整只读归档：`/root/openwrt-backup/cf-dns-speedup-vm33-archive-20260729-164720`。
- 活动代码来源：GitHub 提交 `e7dcbe99a3d59472f8468ccda8d6ec31a56bf573`。
- 从旧归档恢复：`config.env`、`cfst`、候选池、冠军池、观察历史、PassWall 历史和门控状态，共 40 个 TSV 状态文件。
- 未恢复：旧代码、旧代码备份、旧 cron、init 链接、日志和测试夹具状态。
- VM36 原生包管理器为 `apk`。为满足原项目直接运行依赖，仅安装 `bash 5.3-r4` 和 `jq 1.8.1-r2`，未升级或移除其他包。
- 依赖安装前记录：`/root/openwrt-backup/cf-dns-speedup-deps-20260729-182002`。

## 安全覆盖

活动配置末尾已强制保持：

- `DRY_RUN=1`；
- 禁止停止代理；
- 禁止候选自动应用和稳定池自动修复；
- 禁止 DNS、冠军池、guard repair、emergency refresh 和 rescue scan 自动写入。

旧的 06:30 优选 cron 未恢复。VM36 仅新增 04:15 Sidecar 自动同步任务；该任务不扫描 IP、不停止或重启 PassWall，只管理竞争槽 `auto3`、`auto4`。稳定槽 `auto`、`auto1`、`auto2` 保持不变。

## 已通过验收

- 当前代码本地及 VM36 回归测试全部通过；
- shell 语法、`cfst` x86_64 离线帮助命令通过；
- Cloudflare Token、Zone、DNS GET 验证通过；对 `auto4` 当前内容执行一次幂等 PATCH 后，API 内容、三路 DNS、PassWall PID/监听及 Google/YouTube HTTP 均保持不变，确认写权限和回滚所需写路径可用；
- 一次 APPLY=1 空候选复验在同步开始前的 Cloudflare 摘要 GET 阶段遇到瞬时 pi.cloudflare.com DNS 解析失败，未进入同步、未发生写入；随后五条记录只读 GET 和 .110 导出复核均恢复通过，此项保留为下一自然周期观察点；
- VM36 自动同步脚本 SHA256 为 `569ba4c4c8d8b9f3a540206c1fc9a883e172d91d96f51a6562e466beae12f857`，独立写开关已启用，04:15 cron 唯一存在；
- VM36 到 `.110` 使用专用受限密钥，服务端强制命令只能读取候选导出文件，禁止交互 shell、PTY 和端口转发；
- `health-check` 和 `passwall-node-topology` 只读命令通过；
- PassWall UCI、DHCP UCI、路由、Xray PID、启动链接和 crontab 在迁移前后保持不变；
- VM36 当前一个 Xray 进程正常承载 `1070/1041/11400/15353` 四个监听端口；
- `auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致；
- PC、`.140`、`.254`、`.110` 的 Google/YouTube HTTP 检查通过；
- `.110` Sidecar timer 正常、服务无运行中 MainPID、上次结果成功、Ollama 空闲；
- ESXi 状态：VM33 关机，VM36 与 VM37 运行，VM37 网卡与 VM36 MAC 不同。

VM36 缺少独立 `stat` 命令属于 BusyBox applet 差异；已使用 `ls` 完成目录 `700`、配置 `600` 权限验收，不需要为此安装额外工具。

## 待完成

- 等待一次自然 Sidecar 周期成功，再观察满 24 小时。
- 自然周期产生合格候选时，确认 04:15 任务形成 `awaiting_multiday_gate`、`already_present` 或成功更新记录的真实运行证据；不得人为降低门槛制造更新。
- 上述验收通过后才可退役 VM33，并注销、删除 VM37。

## 回滚

项目级回滚先删除 VM36 crontab 中唯一的 `sidecar-auto-sync.sh` 行，再将 `/root/cf-dns-speedup` 改名隔离；不需要重启 PassWall。部署备份保存在 VM36 的 `/root/openwrt-backup/cfip-auto-sync-<时间戳>`。

网络级最终回滚保持不变：关闭 VM36，再启动 VM33；两台虚拟机不得同时占用 `192.168.1.254`。

## 2026-07-30 Sidecar 自然周期故障修复

### 故障结论

- `.110` 最新自然 Sidecar 在扫描和测速前安全退出，错误为 `required container is not healthy: k12-reg`。
- `k12-reg` 在 `.110` 上已无容器、镜像、卷、网络、systemd unit 或项目定义；72 小时 Docker 事件也无相关记录。它是已退役业务留下的过时必要容器清单，不应恢复一个用途不明的容器来绕过门控。
- 失败期间 Sidecar `MainPID=0`、锁空闲、无 Xray JSON 或临时容器残留，`cfip-direct` 附着数为 0；没有进入扫描、测速或 DNS 写入。
- VM36 04:15 任务读取到上一份导出，但导出日期未前进，三日门控保持 `awaiting_multiday_gate`，未更新 Cloudflare，故障安全边界有效。
- SmartDNS 不是故障原因。VM36 当前继续使用 `dnsmasq` 和 PassWall 的既有 DNS 分流拓扑，本次未安装或修改 SmartDNS。

### 最小修复

- Sidecar 默认必要容器和示例配置改为：`sub2api sub2api-postgres sub2api-redis`。
- 新增默认容器清单回归契约，防止已退役的 `k12-reg` 再次进入默认门控。
- `.110` 生产 `/etc/cfip-sidecar/sidecar.env` 显式固定同一三容器清单，避免以后因默认值漂移产生不同结果。
- Sidecar 专项测试和全项目回归测试均通过。
- 部署过程中两次因部署器自身校验字符串转义问题触发事务回滚；两次均验证脚本、配置和备份逐字节恢复，未启动 Sidecar、未影响网络。修正部署器后第三次事务成功。

### 部署与验收

- `.110` 新脚本 SHA256：`bf349d04674c8b93b33e09804eb30effec66099912ad5c05de6cbb84995622c4`。
- root-only 回滚点：`/var/backups/cfip-sidecar/required-containers-fix-20260730-224816`。
- 部署未手动启动或重启 Sidecar、Docker、Ollama、PassWall、DNS，也未修改 Cloudflare、候选池、门槛或 cron。
- `.110` Docker PID 保持 `1144`；三个必要容器均 healthy，Ollama 无驻留模型，锁和残留检查通过，Google/YouTube 均为 HTTP 204。
- VM36 自动同步脚本仍为已部署版本，状态保持 `awaiting_multiday_gate`；一个 Xray 进程正常承载 `1070/1041/11400/15353`，`dnsmasq` 和项目锁正常。
- PC Google/YouTube 均为 HTTP 204；`auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致。
- `cfip-sidecar.service` 的 `Result=exit-code` 仍反映修复前最后一次自然失败；本次未用手工启动或 `reset-failed` 擦除证据。需要下一次自然 timer 成功后才能完成运行时闭环。
- `.110` 与 `.140` 显示的主机时间标签进入未来日期 `2026-07-31`，与本次权威日期 `2026-07-30` 不一致。未自动校时，该时间标签不得计入连续三日门控或作为第三日晋升证据。
