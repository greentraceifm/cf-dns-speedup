# CFIP 优选 IP 项目代码审计与测试环境修正（2026-08-26）

## 结论

本次审计先发现 Windows Git Bash 测试环境兼容问题，随后在生产只读审计中确认了主槽单记录换位会制造重复 IP 的真实逻辑缺陷。该缺陷已修复并安全部署；没有停止或重启 PassWall、Sidecar、Docker、Ollama 或 DNS。

## 已修复

- `sidecar/tests/test_path_probe_retry.sh` 增加与测试运行器一致的 `python3` 到 `python` 回退。
- `sidecar/tests/test_resource_contracts.sh` 增加同样的 Python 回退。
- 资源契约测试在 Windows Git Bash 缺少 Linux `flock` 时明确跳过内核锁运行时段；原生 Linux 仍要求 `flock`，不会放宽生产锁要求。
- `sidecar/tests/test_diagnostic_contract.sh` 在 Windows Git Bash 不再把 POSIX 权限映射误报为失败；原生 Linux 仍校验导出目录为 `755`。
- `sidecar-auto-sync.sh` 新增主槽专用待写目标门：单记录更新时，若目标 IP 已被其他主槽占用则跳过，避免一次更新制造 `auto/auto1` 重复。
- 增加回归测试复现并阻止“一条记录换位导致另一主槽重复”的场景。

## 验证证据

- 四个生产 Bash 脚本和 Sidecar 主脚本 `bash -n` 通过。
- Sidecar 全套测试通过。
- 全项目回归测试通过。
- `git diff --check` 通过。
- 修正提交：`4330c6b`，已推送到 GitHub `main`。
- 生产修复提交：`17c5abe`，已推送到 GitHub `main`。
- VM36 已原子部署新 `sidecar-auto-sync.sh`，哈希为 `4b2f66a5213041694c77a0aa8515df9a7f54a43849b341eb9ce5680675a43765`。
- root-only 回滚点：`/root/openwrt-backup/cfip-primary-slot-swap-fix-20260826-112939`。
- 部署后只读后检通过：PassWall/Xray PID 未变、`1070/1041/11400/15353` 监听正常、唯一 04:35 cron 保持、旧 06:30 cron 不存在、四把锁空闲、Google/YouTube HTTP 204、五条 DNS 三路一致。
- 当前 `auto` 与 `auto1` 的重复内容仍保持原样，等待下一次自然 04:35 同步由新门控安全处理；本轮没有手动改 Cloudflare。

## 尚未取得的证据

- `.140:22` 已恢复，已通过既有严格主机密钥和 OpenClaw 受保护维护通道完成 `.110/.254` 只读审计。
- `.110` Sidecar 成功退出、timer active/enabled、报告和导出有效、无残留 Xray/容器、三个必要容器 healthy、Ollama 无驻留模型。
- `.110` 首轮 Google/YouTube 曾短暂超时，随后重复只读检查恢复 HTTP 204；未据此修改 DNS。
- OpenClaw 记忆已写入：`/home/ubuntu/.openclaw/workspace/memory/2026-08-26-openwrt-cfip-primary-slot-swap-repair.md`，写入后 SHA256 为 `90a3f01d...7c6c041`。
- Notion 项目页本轮探测通过 `.140` SSH 超时，未写入；保留为待同步事项，不使用未授权的直接 Token 路径。
- Windows Git Bash 没有原生 Linux `flock`，锁竞争运行时测试仍需在 Linux/VM/CI 中执行。

## 后续最小优化建议

1. 将 Sidecar 测试放入 Linux CI 或轻量 Linux 容器，保留 Windows Git Bash 只做语法和便携性测试。
2. 把 Python 解释器回退和 `flock` 能力探测提取为测试公共辅助文件，避免新增测试重复出现同类误报。
3. 等下一次自然 04:35 周期，只读确认新门控没有再产生重复；不手动补跑同步。
4. 在生产端继续保持现有门槛、单记录写入和主槽/竞争槽门控，不降低标准。

## 收敛边界

本轮修复已收敛完成；后续只观察下一次自然周期，不继续扩大代码重构、不手动调整 DNS/Cloudflare/PassWall/cron，也不把旧生产样本冒充新验收证据。
