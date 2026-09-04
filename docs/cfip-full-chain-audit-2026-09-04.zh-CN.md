# CFIP 优选 IP 全链路排查记录（2026-09-04）

## 结论

本次完成本地回归和生产只读复核，未发现需要修改生产链路的可复现逻辑 bug。当前 `.110` Sidecar、VM36 自动同步、候选池、PassWall、DNS 和 Cloudflare 记录均符合设计预期。

## 当前运行结果

- `.110` 自然 Sidecar 最近报告为 2026-09-03 19:42 UTC，服务 `success`、退出码 `0`、`MainPID=0`，timer `active/enabled`。
- 报告 5 行均为 HTTP 200，导出 3 个 observation 候选，速度约 `5.18–5.30 MB/s`；低于 `6.5 MB/s` 优秀标志但高于观察底线，未错误晋升是正确行为。
- Sidecar 锁空闲，无 Xray 残留、瞬时 CFIP 容器或 `cfip-direct` 附着；`sub2api`、PostgreSQL、Redis 均为 running/healthy；Ollama 无驻留模型。
- VM36 2026-09-04 04:36 自动同步状态为 `already_present`，未执行 Cloudflare 写入。
- 主槽资格池 3 个候选，竞争资格池 2 个候选；`auto` 至 `auto4` 为 5 个不同 IP，三路 DNS 与 Cloudflare 只读内容一致。
- VM36 只有 1 个有效 Xray 进程，`1070/1041/11400/15353` 全部监听；四把项目锁空闲，唯一同步 cron 正常，旧 `06:30` cron 不存在。
- 三轮复核中 Google 与 YouTube 均返回 HTTP 204，之前单次 Google HTTP 000 判定为瞬时解析/连接波动，不改 DNS。

## 已修复的排查工具缺陷

旧的自然周期审计脚本仍硬编码过期的 `sidecar-auto-sync.sh` 哈希 `ab50...`，会把当前正确部署误报为 mismatch。已更新为当前生产哈希 `814a...`。该问题只影响审计判断，不影响 Sidecar、同步或 Cloudflare 写入。

## 验证

- 生产脚本语法检查通过。
- 全项目回归测试通过。
- Sidecar 全套测试通过；Windows Git Bash 仅跳过依赖真实 Linux `flock` 的运行时段。

## 收口建议

保持现状运行，不降低门槛、不新增 DNS、不恢复旧 `06:30` 任务、不手工改写 `auto` 至 `auto4`。后续仅观察自然周期；只有出现新的自然失败、五槽重复、三路 DNS 不一致或 Cloudflare 只读内容不一致时，才启动下一轮最小修复。
