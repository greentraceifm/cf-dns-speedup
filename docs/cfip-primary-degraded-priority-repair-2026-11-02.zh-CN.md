# CFIP 主槽降级优先修复与全链路验收报告

日期：2026-11-02（Asia/Shanghai）

## 一、最终结论

本次修复已完成部署，代码回归测试和 VM36 即时验收均通过。生产链路当前可用：

- `.110` Sidecar 自然运行成功并导出候选；
- VM36 `04:35` 自动同步成功执行；
- 2026-11-02 04:38:17 已更新 `auto3.greentraceifm.top` 一条记录；
- PassWall/Xray、四个监听、Google/YouTube 代理访问、项目锁和三路 DNS 均正常；
- 本次没有重启 PassWall、DNS、Sidecar、Docker、Ollama 或虚拟机；
- 本次没有手工修改 Cloudflare。

当前仍可观察到历史状态：`auto1` 与 `auto4` 仍指向相同 IP。代码已经加入全局五槽去重和并发快照保护，但本次自然周期先安全完成了 `auto3` 的竞争槽更新，没有手工强改重复记录。后续自然周期会在候选满足门控且单记录替换安全时处理；没有安全候选时保持现状并报告原因。

因此，本次结论是：**修复已部署，主链路正常，未发现修复后的新故障；五槽历史重复仍需等待自然门控处理，不应人工批量改写。**

## 二、发现的根因

本轮重新检查确认存在两个相互关联的调度问题：

1. 主槽规划遇到现任 IP 连续低于主槽最低速度，或出现明确 HTTP/下载失败时，旧逻辑可能继续优先消费竞争候选，导致降级主槽不能及时获得安全替换。
2. PassWall 的 UCI 全局节点在部分运行态下不完整，但实际 Xray `global.json` 已经存在并承载四个监听。旧诊断只看 UCI 时会误报 `missing_global`，将有效运行拓扑误判为故障。

这不是 Sidecar、Cloudflare 权威 DNS 或 PassWall 进程本身的故障。`.110` 宿主机直连 Google/YouTube 超时属于已知宿主直连出口现象，不能用来否定 VM36 的代理链路。

## 三、实施的修复

### 1. 主槽降级优先级

- 根据主槽真实隔离 PassWall 历史判断降级：
  - 最近连续两个不同日期低于 `4.0 MB/s`；或
  - 最近一次出现明确 HTTP、下载字节或清理失败。
- 降级主槽优先从已完成真实门控的候选中选择替换。
- 主槽修复完成前，不先消费唯一安全候选去更新 `auto3/auto4`。
- 没有安全替换时输出 `awaiting_primary_repair_candidate`，保持 Cloudflare 不变。
- 保留一次周期最多更新一条 Cloudflare 记录和单记录失败回滚约束。

### 2. 全局五槽去重

- 候选必须同时避开 `auto`、`auto1`、`auto2`、`auto3`、`auto4` 当前已经暴露的 IP。
- 更新前重新拉取五槽快照，发现并发变化立即停止该次写入。
- 更新后重新读取五槽并确认只有目标记录变化，且不会造成新的重复。
- 重复保护拒绝时刷新报告，不以进程异常退出掩盖真实状态。

### 3. PassWall 运行态拓扑回退诊断

- 当 UCI 全局节点不可用时，读取实际运行时 `global.json`。
- 输出 `runtime_fallback` 和运行时地址，避免将有效的 Xray 运行拓扑误报为 `missing_global`。
- 该诊断改动不重启 PassWall，也不改变任何运行配置。

## 四、代码与部署记录

VM36 生产目录：`/root/cf-dns-speedup`

本次部署的脚本哈希：

```text
sidecar-auto-sync.sh
240b1e25df37d837d22c9e46e68a000b67ac3bd16b22ecff493bb3a0bea857f8

cf-dns-speedup.sh
3fcdec7a6eb1c0da699b42fc8efce2abde61500c449b072c87431504c0c4b76b
```

Root-only 回滚目录：

```text
/root/openwrt-backup/cfip-primary-repair-20261102-194532
```

部署特征：

- 原子替换脚本；
- 先备份，再语法检查和 BusyBox 计划测试；
- PassWall PID 与监听保持不变；
- cron 保持不变；
- Cloudflare 写入次数为 0（部署阶段）。

## 五、本次自然周期证据

VM36 自动同步报告：

```text
observed_at: 2026-11-02 04:38:17
status: updated
record: auto3.greentraceifm.top
new_ip: 104.17.131.246
detail: source=challenger_min=4.24_avg=4.42
```

当前唯一同步任务：

```text
35 4 * * * timeout 1800 /root/cf-dns-speedup/sidecar-auto-sync.sh run ...
```

旧 `06:30` 任务不存在。

PassWall/Xray：

- 一个有效 Xray 运行进程；
- `1070`、`1041`、`11400`、`15353` 四个监听均存在；
- 项目锁均为空闲；
- Google 和 YouTube 默认路径及 SOCKS 路径均返回 HTTP 204。

当前五槽三路 DNS 结果：

```text
auto   = 162.159.134.98
auto1  = 104.26.1.38
auto2  = 104.17.129.81
auto3  = 104.17.131.246
auto4  = 104.26.1.38
```

`192.168.1.1`、VM36 本地 resolver 和 `1.1.1.1` 对上述记录返回一致结果；当前 `auto1/auto4` 的重复属于待自然门控处理的历史状态，不是本次部署新造成的重复。

## 六、测试结果

已通过：

- `bash -n sidecar-auto-sync.sh`
- `bash -n cf-dns-speedup.sh`
- `tests/run-all-regression-tests.sh`
- `sidecar/tests/run-tests.sh`
- `tests/test-sidecar-auto-sync-plan.sh`
- `tests/test-router-candidate-gate.sh`
- `tests/test-router-canary-plan.sh`
- `tests/test-router-canary-mock.sh`
- `git diff --check`
- VM36 BusyBox 计划测试
- VM36 生产即时只读验收

回归覆盖内容包括：

- 主槽降级优先于竞争槽；
- 健康主槽保持不变；
- 五槽全局去重；
- 并发快照变化拒绝写入；
- 单记录更新和更新后完整校验；
- 运行时 JSON 回退诊断。

## 七、后续收口边界

下一次自然 `04:35` 周期只需观察：

1. 是否出现 `awaiting_primary_repair_candidate`、`already_present` 或 `updated`；
2. 若更新，确认最多只有一条记录变化；
3. 若仍无安全候选，保留现状并记录精确门控原因。

不需要手工补跑同步、不需要恢复旧 `06:30` 任务、不需要手工 PATCH Cloudflare，也不需要为处理历史重复而重启 PassWall 或 DNS。

## 八、回滚

如后续自然周期出现异常，先停止后续变更，不重启生产服务。VM36 可使用本次备份恢复两个脚本：

```sh
app=/root/cf-dns-speedup
backup=/root/openwrt-backup/cfip-primary-repair-20261102-194532
cp -p "$backup/sidecar-auto-sync.sh" "$app/sidecar-auto-sync.sh"
cp -p "$backup/cf-dns-speedup.sh" "$app/cf-dns-speedup.sh"
chmod 700 "$app/sidecar-auto-sync.sh" "$app/cf-dns-speedup.sh"
bash -n "$app/sidecar-auto-sync.sh"
bash -n "$app/cf-dns-speedup.sh"
sha256sum "$app/sidecar-auto-sync.sh" "$app/cf-dns-speedup.sh"
```

网络级最终回滚仍是：关闭 VM36 后启动 VM33，确保两台机器不得同时占用 `192.168.1.254`。
