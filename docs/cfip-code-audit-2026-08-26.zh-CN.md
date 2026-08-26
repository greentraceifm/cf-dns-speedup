# CFIP 优选 IP 项目代码审计与测试环境修正（2026-08-26）

## 结论

本次审计未发现需要修改生产逻辑的确定性 bug。发现并修复的是 Windows Git Bash 测试环境兼容问题，生产脚本未部署新版本，未停止或重启任何服务。

## 已修复

- `sidecar/tests/test_path_probe_retry.sh` 增加与测试运行器一致的 `python3` 到 `python` 回退。
- `sidecar/tests/test_resource_contracts.sh` 增加同样的 Python 回退。
- 资源契约测试在 Windows Git Bash 缺少 Linux `flock` 时明确跳过内核锁运行时段；原生 Linux 仍要求 `flock`，不会放宽生产锁要求。
- `sidecar/tests/test_diagnostic_contract.sh` 在 Windows Git Bash 不再把 POSIX 权限映射误报为失败；原生 Linux 仍校验导出目录为 `755`。

## 验证证据

- 四个生产 Bash 脚本和 Sidecar 主脚本 `bash -n` 通过。
- Sidecar 全套测试通过。
- 全项目回归测试通过。
- `git diff --check` 通过。
- 修正提交：`4330c6b`，已推送到 GitHub `main`。
- 本次没有执行 Sidecar、扫描、诊断、同步、Cloudflare 写入、PassWall 重启或生产部署。

## 尚未取得的证据

- `.140:22` 在本次审计中连接超时，因此无法通过既有受保护 OpenClaw 维护通道读取 `.110` 和 `.254` 的新自然周期状态。
- Notion/ OpenClaw 记忆未写入；未绕过 `.140` 使用历史密码或其他凭据。
- Windows Git Bash 没有原生 Linux `flock`，锁竞争运行时测试仍需在 Linux/VM/CI 中执行。

## 后续最小优化建议

1. 将 Sidecar 测试放入 Linux CI 或轻量 Linux 容器，保留 Windows Git Bash 只做语法和便携性测试。
2. 把 Python 解释器回退和 `flock` 能力探测提取为测试公共辅助文件，避免新增测试重复出现同类误报。
3. `.140` 恢复后只做一次生产只读审计：最新自然报告、VM36 同步状态、PassWall 四监听、锁、五条 DNS 三路一致和 Cloudflare 只读 GET。
4. 在生产端继续保持现有门槛、单记录写入和主槽/竞争槽门控，不因本次测试环境修正降低标准或手动补跑周期。

## 收敛边界

在 `.140` 恢复前，不继续扩大代码重构、不修改生产脚本、不调整 DNS/Cloudflare/PassWall/cron，也不把旧生产样本当作本次新验收证据。
