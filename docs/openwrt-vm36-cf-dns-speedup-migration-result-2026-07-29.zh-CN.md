# VM36 优选 IP 项目迁移执行记录

日期：2026-07-29

## 结论

VM33 的 `/root/cf-dns-speedup` 已完成分层迁移。VM36 已建立活动目录 `/root/cf-dns-speedup`，但未恢复旧 cron、旧启动项、旧脚本备份或旧日志；自动测速仍只由 `.110` Sidecar 执行。

当前状态为“部署完成，等待自然周期和 24 小时稳定性验收”。在该验收完成前，VM33 和 VM37 不退役。

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

VM36 未创建任何优选 IP cron，也未启动测速、扫描或 Cloudflare 更新。

## 已通过验收

- 当前代码本地及 VM36 回归测试全部通过；
- shell 语法、`cfst` x86_64 离线帮助命令通过；
- Cloudflare Token、Zone、DNS API 仅 GET 验证通过，未更新记录；
- `health-check` 和 `passwall-node-topology` 只读命令通过；
- PassWall UCI、DHCP UCI、路由、Xray PID、启动链接和 crontab 在迁移前后保持不变；
- VM36 当前一个 Xray 进程正常承载 `1070/1041/11400/15353` 四个监听端口；
- `auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路解析一致；
- PC、`.140`、`.254`、`.110` 的 Google/YouTube HTTP 检查通过；
- `.110` Sidecar timer 正常、服务无运行中 MainPID、上次结果成功、Ollama 空闲；
- ESXi 状态：VM33 关机，VM36 与 VM37 运行，VM37 网卡与 VM36 MAC 不同。

VM36 缺少独立 `stat` 命令属于 BusyBox applet 差异；已使用 `ls` 完成目录 `700`、配置 `600` 权限验收，不需要为此安装额外工具。

## 待完成

- 使用受保护 sudo 通道只读复核 `.110` 的四个 Docker 容器、Sidecar lock、`cfip-direct` 附着和 `/run` Xray JSON 残留；普通 SSH 用户无 Docker socket 权限。
- 等待一次自然 Sidecar 周期成功，再观察满 24 小时。
- 上述两项通过后才可退役 VM33，并注销、删除 VM37。

## 回滚

项目级回滚只需将 VM36 的 `/root/cf-dns-speedup` 改名隔离；该目录没有 cron 或启动项，因此不需要重启 PassWall。

网络级最终回滚保持不变：关闭 VM36，再启动 VM33；两台虚拟机不得同时占用 `192.168.1.254`。
