# CFIP 优选 IP 全链路自然周期复核（2026-09-06）

## 结论

2026-09-06 自然周期验证通过。上一轮 PassWall runtime JSON 路径兼容修复已生效，VM36 自动同步正常完成，本轮未发现需要修改生产链路的新 Bug。

## 运行结果

- `.110` Sidecar 服务只读状态为 `Result=success`、`ExecMainStatus=0`、`MainPID=0`；timer 为 `active/enabled`。
- VM36 04:35 自动同步在 04:36 完成，状态为 `already_present`，没有不必要的 Cloudflare 写入。
- 主槽 3 个候选、竞争槽 2 个候选均通过连续多日真实隔离 PassWall 门控。
- `auto` 至 `auto4` 五个地址互不重复。
- 五条记录在 `192.168.1.1`、`192.168.1.254` 和 `1.1.1.1` 三路解析一致，并与 Cloudflare 只读内容一致。
- VM36 一个 Xray 进程正常承载 `1070/1041/11400/15353`；四把项目锁空闲。
- Google 与 YouTube 均返回 HTTP 204。

## 修复确认

上一轮修复的 `global.json` 备用路径已通过自然周期验证，证明自动同步已经能够继续进入门控和排序流程。未重启 PassWall，未手动补跑 Sidecar 或同步，未修改门槛、DNS、Cloudflare、cron 或池。

## 工具问题

本地历史审计脚本仍保存旧版 `router-candidate-gate.sh` 哈希，曾将当前已部署版本显示为 mismatch。这只影响审计工具判断，不影响生产链路；后续审计应使用 2026-09-05 修复后的部署哈希。

## 收口建议

当前保持现状，不再扩大优化。继续观察自然周期即可；只有出现新的自然失败、槽位重复、三路 DNS 不一致或 Cloudflare 只读不一致时，才启动下一轮最小修复。
