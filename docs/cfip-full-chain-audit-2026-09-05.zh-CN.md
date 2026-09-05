# CFIP 优选 IP 全链路排查与修复记录（2026-09-05）

## 结论

本次发现并修复一个真实的兼容性缺陷：Sidecar 自然采集和候选导入均成功，但 VM36 自动同步在 PassWall 候选门控阶段因使用已不存在的旧 runtime JSON 文件名而安全退出。Cloudflare 没有发生错误写入，现有 DNS、PassWall 和五槽内容未被破坏。

## 故障事实

- `.110` Sidecar 自然周期成功，导出候选并完成导入。
- VM36 自动同步先遇到一次 Cloudflare API 域名解析瞬时失败；随后重试进入候选门控。
- 门控报错为 `PassWall runtime JSON is missing or symlinked`。
- 当前 PassWall 仍正常运行，一个 Xray 进程承载 `1070/1041/11400/15353`。
- 旧路径 `TCP_UDP_SOCKS.json` 不存在；当前运行时配置文件名为 `global.json`，位于 PassWall 的默认 ACL 目录。

## 根因

`router-candidate-gate.sh` 将旧版 PassWall 的固定文件名作为唯一 runtime JSON 来源。PassWall 升级或配置生成方式变化后，文件名变为 `global.json`，导致门控无法生成隔离 Xray 配置，自动同步按设计安全退出。

## 修复

- 保留显式 `CFIP_ROUTER_CANARY_RUNTIME_JSON` 配置优先级。
- 当未显式指定路径、旧路径不存在且默认 ACL 目录存在 `global.json` 时，使用该明确备用路径。
- 继续拒绝符号链接、超大文件和不包含唯一 VMess 地址的 JSON；没有放宽安全校验，也没有改动 DNS、Cloudflare、PassWall、cron 或测速门槛。
- VM36 已完成原子替换；旧脚本 root-only 备份位于：
  `/root/openwrt-backup/cfip-runtime-json-fallback-20260905-174500`

## 验证

- 本地 `bash -n`、router canary mock/plan、全项目回归和 Sidecar 全套测试通过。
- Windows Git Bash 中依赖真实 Linux `flock` 的运行段按环境限制跳过。
- VM36 生产后检通过：Xray 进程仍为 1 个，四个监听均正常，项目锁空闲，Google 与 YouTube 返回 HTTP 204。
- 未重启 PassWall，未手动运行 Sidecar 或自动同步，未修改 Cloudflare 五条记录。

## 后续

下一次自然周期观察自动同步是否能正常进入候选门控。若仍失败，只记录新的精确原因并停止自动修复；不通过人为补跑、降低门槛或修改 DNS 解决。
