# CFIP 主槽晋升生产部署收口（2026-08-02）

## 结论

2026-08-02 已完成 CFIP 主槽同路径三日基线与自动晋升功能的生产部署。部署过程未重启 PassWall、Sidecar、Docker、Ollama 或 DNS，未人工触发测速、同步或 Cloudflare 写入。

当前完整链路为：

1. `.110` Sidecar 每日自然测速并导出最多三个 `min >= 3.5 MB/s` 的观察候选。
2. VM36 每日 04:15 拉取候选，并用隔离 Xray 执行真实 PassWall 路径门控。
3. 连续三个不同日期通过的候选才可进入 `auto3/auto4`，每周期最多更新一条记录。
4. `auto/auto1/auto2` 每日建立独立的同路径三日基线。
5. 候选只有先进入竞争槽、真实路径最低速度达到 `4.0 MB/s`、且至少比最弱主槽提高 `25%`，才可参与主槽晋升。
6. 主槽和竞争槽写入均已启用，但仍受三日门控和单记录写入限制；当前没有满足主槽三日基线的数据，因此不会立即写 Cloudflare。

## 自然周期验收

2026-08-02 收到修复后的新自然 Sidecar 成功样本：

- `cfip-sidecar.service`：`Result=success`、`ExecMainStatus=0`、`MainPID=0`。
- 五个候选均为 HTTP 200、下载完整。
- 导出三个观察候选，最低/平均速度分别约为：
  - `104.17.136.163`：`4.46 / 4.47 MB/s`
  - `104.17.147.242`：`4.39 / 4.39 MB/s`
  - `104.21.229.220`：`4.35 / 4.38 MB/s`
- Sidecar 锁空闲，无 Xray JSON 残留、无瞬时 CFIP 容器、`cfip-direct` 无附着。
- `sub2api`、`sub2api-postgres`、`sub2api-redis` 均为 running/healthy。
- Ollama 无驻留模型；`.110` 的 Google/YouTube HTTP 均为 204。
- VM36 04:15 同步结果为 `awaiting_multiday_gate`，未写 Cloudflare，符合故障安全设计。

## 发现并修复的问题

### 1. DNS 验收误报

旧验收探针只识别 `nslookup` 的 `Address 1:` 格式，而 VM36 当前 BusyBox 输出为 `Address:`，导致 `auto..auto4` 被错误报告为 `missing`。

修复后按答案区解析 IPv4。实际核验显示五条记录在 `192.168.1.1`、`192.168.1.254` 和 `1.1.1.1` 三路完全一致，生产 DNS 从未丢失。

### 2. BusyBox 排序不兼容

`sidecar-auto-sync.sh` 原先使用 GNU `sort -t ... -k ...` 按最低速度、平均速度和通过天数排序。VM36 的 BusyBox `sort` 不支持字段排序参数，会退化为整行/IP 字符串顺序，可能遗漏更快候选。

已将竞争槽和主槽的两处排序统一替换为纯 `awk` 数值排序，排序优先级保持不变：

1. 最低速度降序；
2. 平均速度降序；
3. 连续通过天数降序；
4. IP 字符串升序作为稳定决胜条件。

新增可移植性回归样例，确保 IP 字符串顺序与速度顺序冲突时仍按速度选取。

### 3. 部署监听检查被 `pipefail` 误伤

部署脚本在 `set -o pipefail` 下使用 `netstat | grep -q`。`grep` 找到匹配后提前退出，BusyBox `netstat` 收到 SIGPIPE，管道返回 141，导致正常监听被误判为失败。

已改为完整消费输入的 `awk END` 判定，四个监听端口均通过。

### 4. 双文件替换的回滚时序

原部署脚本在两份文件都替换后才设置 `installed=1`。若第一份替换成功、第二份替换失败，回滚不会触发。

已将回滚标志移动到第一次原子替换之前，确保替换窗口中的任意失败都会恢复备份。

## 生产部署结果

- VM36 回滚点：`/root/openwrt-backup/cfip-primary-promotion-20260802-164606`
- `router-candidate-gate.sh` SHA256：`96704f81998125c86318974e249f02daaa72aeaa948c44bf78094ee18463c96a`
- `sidecar-auto-sync.sh` SHA256：`e0e1e0971f948a30020b594c2f1359b2c814e8f5e6a73fc08a00a39f7090eb3a`
- `CFIP_AUTO_SYNC_APPLY=1`
- `CFIP_AUTO_SYNC_PRIMARY_PROMOTION_APPLY=1`
- 主槽资格文件已生成，当前为表头加零条数据。
- 04:15 cron 唯一存在；旧 06:30 cron 不存在。
- PassWall Xray PID 保持为 `17862`；`1070/1041/11400/15353` 均保持监听。
- PassWall 配置哈希和 crontab 哈希在部署前后不变。
- Google/YouTube HTTP 均为 204；项目三个锁均空闲。
- Cloudflare 五条 A 记录只读 GET、VM36 DNS 和公共 DNS 内容逐条一致。

## 测试结果

- `.140` 计划测试通过。
- VM36 BusyBox 计划测试通过。
- 全项目回归测试通过。
- Sidecar 全部测试通过。
- 新增 BusyBox 数值排序回归测试通过。

## 后续自然行为

从下一次 04:15 自然同步开始，VM36 会记录三个主槽的真实 PassWall 同路径基线。至少积累连续三个不同日期后才可能形成主槽资格；即使资格形成，也只有达到 `4.0 MB/s` 且相对最弱主槽提升至少 `25%` 的竞争槽候选才会晋升，并且每周期最多修改一条 Cloudflare 记录。

无需恢复旧 06:30 优选任务。该任务会与当前 Sidecar 链路重复，并存在停止 PassWall 导致代理中断的历史风险。

## 回滚

若后续自然周期出现新故障，先关闭自动写入开关并停止进一步变更。项目级回滚使用上述 VM36 本地备份恢复两份脚本、配置、cron 和状态文件；恢复后只需复核 PassWall PID/监听、HTTP 和三路 DNS，不需要修改稳定池或批量重写 Cloudflare。

网络级最终回滚仍为：关闭 VM36，再启动 VM33；两台不得同时占用 `192.168.1.254`。
