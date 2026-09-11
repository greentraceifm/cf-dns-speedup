# CFIP 与 OpenClaw 维护通道收口同步摘要（2026-09-11）

记忆标记：CFIP-MAINTENANCE-CLOSEOUT-20260911

## 当前结论

- CFIP 生产链路已收口：192.168.1.110 负责 Sidecar 自然测速，VM36（192.168.1.254）负责真实 PassWall 门控、候选池和受限 Cloudflare 同步。
- 最新自然同步状态为 `already_present`，表示本周期无需修改 Cloudflare。
- `auto` 至 `auto4` 当前五个槽位均为不同 IP；三路 DNS 与 Cloudflare 只读结果一致。
- VM36 的 PassWall 生产拓扑、四个监听、项目锁和代理连通性正常；旧 06:30 任务保持停用。

## OpenClaw 维护入口

- 本机维护路径固定为：本机 -> 192.168.1.140 OpenClaw -> `ollama-server`（192.168.1.110）。
- .140 使用严格主机密钥校验和批处理 SSH。
- .110 的 root-only 审计通过固定命令 `/usr/local/sbin/cfip-maintenance-audit` 提供。
- .140 入口为 `/home/ubuntu/.openclaw/tools/cfip-maintenance-readonly.sh`，只调用上述固定审计命令。
- 旧密码提取和任意 `sudo -n sh -s` 路径已废弃。

## 固定边界

- 维护入口只读，不修改 Sidecar、PassWall、Docker、Ollama、DNS、Cloudflare、cron、timer 或 VM。
- 不恢复旧 06:30 cron，不手工改写 `auto` 记录，不人为降低测速门槛。
- 后续仅观察自然周期；只有出现新的可复现失败，才开展对应模块的最小修复。
- 网络级回滚：关闭 VM36 后启动 VM33，确保两台不同时占用 192.168.1.254。

## 收口状态

- 生产代码、部署结果和维护通道修复已保存在本地中文记录并推送 GitHub。
- 本摘要用于 OpenClaw 记忆和 Notion 的无秘密同步；同步采用唯一 marker 幂等追加并要求读后验证。
