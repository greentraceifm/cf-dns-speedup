# CFIP 挑战者保留机制部署记录（2026-08-05）

## 结论

本次优化已经完成代码实现、IT 专家组评审、Linux 全量回归、VM36 原子部署和即时生产验收。

核心问题是每日 Sidecar 导出的候选 IP 经常变化，VM36 原逻辑只测试当天 3 条候选，导致同一 IP 很难连续通过 3 个不同日期的真实 PassWall 门控，竞争资格长期为 0。此次修复没有降低门槛，也没有增加测速次数或流量。

## 专家组结论

SRE、安全、工程可靠性和可验证性视角联合评审结论为“有条件通过”。实施边界如下：

- 每周期仍最多测试 3 个候选；
- 固定保留最多 2 个正在形成连续通过记录的挑战者；
- 剩余名额接纳当天 Sidecar 最新候选；
- `3.5 MB/s` 竞争门槛、`4.0 MB/s` 主槽门槛和 `25%` 主槽晋升条件不变；
- 每周期最多修改一条 Cloudflare 记录；
- 不新增服务、cron、扫描次数或凭据权限；
- 只有本周期实际复测且已完成三日资格的候选才能进入 DNS 计划。

## 实现

涉及生产代码：

- `sidecar-auto-sync.sh`
  - 新增 root-only `router-candidate-watchlist.tsv` 状态协议；
  - 每周期形成最多 3 条的 `2 个保留 + 1 个新候选` 测试计划；
  - 连续通过天数优先，其次按最低速度、平均速度排序；
  - 本周期失败候选立即退出保留列表；
  - 旧资格文件中未在本周期复测的条目不能进入 Cloudflare 计划；
  - 状态文件使用临时文件、`0600` 权限和原子改名。
- `router-candidate-gate.sh`
  - 新增严格的本周期 allowlist；
  - 保留候选必须是 Cloudflare IPv4，并绑定到当天导出 epoch；
  - allowlist 最多 3 条，拒绝重复、额外字段和非法来源；
  - 未放开任意 IP 测试能力。

同时修复两处只读诊断：Sidecar 导出表头检查兼容 v1/v2；公共 DNS 单次缺失时只读等待后复查一次。

## 测试

- 相关脚本 `bash -n`：通过；
- 候选调度定向测试：通过；
- 路由门控定向测试：通过；
- `.140` Linux 全项目回归：通过；
- Sidecar 全套测试：通过。

新增覆盖包括：第一天 3 个新候选、第二/三天保留 2 个并引入 1 个新候选、三日资格形成、失败淘汰、重复去重、最多 3 条、孤立旧资格禁止写入，以及原有主槽排序和 25% 晋升条件保持不变。

## 生产部署

部署时间：2026-08-05 11:48 CST。

部署前 VM36 脚本与 Git HEAD 哈希完全一致，没有覆盖生产独有改动。部署采用哈希硬门控、三把项目锁、root-only 备份和原子替换；没有运行 Sidecar 或完整同步任务。

- 新 `router-candidate-gate.sh` SHA256：`67ffa269f04c43bcb86e1f6dd231d6ebeddfbed9c2df9fe88973a7c62cf04f24`
- 新 `sidecar-auto-sync.sh` SHA256：`95508b8e8e572c241b078fe417fc28546a25cf667e6dbef9dc9f746920281a4f`
- VM36 回滚目录：`/root/openwrt-backup/cfip-watchlist-20260805-114821`
- PassWall 重启：0 次；
- cron 变化：无；
- Cloudflare/DNS 写入：无；
- watchlist：部署时未预建，由下一次自然 04:15 周期原子生成。

## 即时验收

- 新脚本哈希匹配；
- 回滚目录存在，共保存 9 个文件；
- 三把项目锁均空闲；
- PassWall Xray PID 保持 `14386`；
- `1070/1041/11400/15353` 四监听正常；
- VM36、PC、OpenClaw、Sidecar 的 Google/YouTube HTTP 检查正常；
- `auto` 至 `auto4` 在 `192.168.1.1`、`192.168.1.254`、`1.1.1.1` 三路一致；
- Cloudflare 五条记录只读 GET 与 DNS 内容一致；
- 唯一 04:15 cron 保持，旧 06:30 任务仍未恢复。

## 后续自然验收

2026-08-06 04:15 CST 的自然同步周期应首次生成最多 2 条 watchlist 记录。验收只需确认：

- 本周期测试总数不超过 3；
- 计划结构为最多 2 条 retained 加至少 1 条 staging 新候选；
- 失败候选不会保留；
- 未满三日时状态仍为 `awaiting_multiday_gate`，不会更新 Cloudflare；
- PassWall、DNS、HTTP 和 cron 保持不变。

不得为了立即看到竞争槽更新而手动运行同步、降低门槛或制造候选。

## 回滚

如下一自然周期发现实现异常，只需从以下目录恢复两份脚本，不需要重启 PassWall，也不需要修改 DNS：

`/root/openwrt-backup/cfip-watchlist-20260805-114821`

恢复后验证旧哈希、四监听、HTTP、cron 和五条 DNS 一致；本次新增 watchlist 可改名隔离，不应批量修改 Cloudflare 记录。