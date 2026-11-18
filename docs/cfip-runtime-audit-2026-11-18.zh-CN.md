# CFIP 优选 IP 自然周期运行审计

日期：2026-11-18（Asia/Shanghai）

## 结论

本次自然周期运行正常，前一周期修复已生效，没有发现新的生产故障。

- `.110` Sidecar 自然任务成功；
- VM36 `04:35` 自动同步成功；
- `auto4` 按全局五槽去重规则完成安全替换；
- 五个 DNS 槽位当前均为不同 IP；
- PassWall/Xray、四个监听、DNS、Cloudflare 和代理 HTTP 验收通过。

结论：**生产链路符合当前设计目标，进入自然周期观察，不需要继续扩大修复范围。**

## 自然周期结果

VM36 最新同步报告：

```text
observed_at: 2026-11-18 04:36:46
status: updated
record: auto4.greentraceifm.top
candidate: 104.17.131.246
previous: 104.26.1.38
detail: source=global_dedupe_min=3.90_avg=4.17
task_id: 20261118T043500-26903
```

这次更新解决了前一周期的历史重复：

```text
auto1 = 104.26.1.38
auto4 = 104.17.131.246
```

## 生产链路验收

### .110 Sidecar

- service 最近结果：`success`
- timer：`active/enabled`
- 最新报告：存在，5 行
- 导出候选：3 行
- Xray 残留：0
- 瞬时 CFIP 容器：0
- `sub2api`、PostgreSQL、Redis：`healthy`

`.110` 宿主机直连 Google/YouTube 仍可能超时，这是已知宿主直连出口限制；
不作为 VM36 代理链路故障依据。

### VM36 PassWall

- 一个有效 Xray 进程；
- `1070`、`1041`、`11400`、`15353` 四个监听全部存在；
- 三把项目锁空闲；
- 默认路径 Google/YouTube：HTTP `204`；
- SOCKS 路径 Google/YouTube：HTTP `204`；
- 无 CFIP 残留进程。

### 调度

唯一 CFIP 同步任务仍为：

```text
35 4 * * * timeout 1800 /root/cf-dns-speedup/sidecar-auto-sync.sh run >> /root/cf-dns-speedup/sidecar-auto-sync.log 2>&1
```

旧 `06:30` 任务不存在。

### DNS 与 Cloudflare

当前五槽：

```text
auto   = 162.159.237.251
auto1  = 104.26.1.38
auto2  = 104.17.129.81
auto3  = 104.26.7.141
auto4  = 104.17.131.246
```

VM36 本地 resolver、192.168.1.1 和 `1.1.1.1` 返回一致答案。
Cloudflare 五条记录只读 GET 均为 HTTP `200`，内容一致。

## 候选池状态

### 竞争池

当前有 2 个连续 7 日通过的竞争候选：

```text
104.26.7.141   min=4.22 MB/s avg=4.49 MB/s
104.17.131.246 min=3.90 MB/s avg=4.17 MB/s
```

### 主槽基线池

当前有 3 个连续 7 日通过的主槽基线候选：

```text
104.17.129.81  min=4.13 MB/s avg=4.41 MB/s
104.26.1.38    min=4.27 MB/s avg=4.56 MB/s
162.159.237.251 min=4.19 MB/s avg=4.27 MB/s
```

### 观察保留池

当前保留 2 个候选：

```text
104.17.131.246 min=3.90 MB/s avg=4.30 MB/s days=18
104.26.7.141   min=4.22 MB/s avg=4.52 MB/s days=14
```

候选数量满足当前三主槽、两竞争槽模型，没有出现“候选池耗尽”或需要降低
3.5 MB/s 底线的证据。

## 修复效果判断

上一周期的 `failed_rolled_back` 事件已被正确处理：

1. HTTP 门控重试已部署；
2. 2026-11-18 周期完成了安全更新；
3. 更新后没有触发回滚；
4. `auto4` 去重成功；
5. 五槽和三路 DNS 均保持一致。

本次没有：

- 手工修改 DNS；
- 手工运行 Sidecar 或同步；
- 重启 PassWall、Xray、DNS、Docker、Ollama 或 VM；
- 修改 cron、门槛、订阅或凭据。

## 独立观察项

本次 `.110` 审计显示 `OLLAMA_MODELS=0`。这不影响本次 Sidecar、Docker、
候选导出或 VM36 代理链路验收，也没有证据表明它导致 CFIP 故障。暂不在
本轮扩大处理；如后续需要 Ollama 推理功能，应另行进行独立维护窗口核验。

## 最终建议

当前进入自然周期观察即可：

1. 保持唯一 `04:35` 同步任务；
2. 保持 HTTP 门控三次有限重试；
3. 保持每周期最多更新一条 Cloudflare 记录；
4. 不手工改写五槽；
5. 下一周期只读确认 `updated`、`already_present` 或安全等待状态。

本轮没有需要继续实施的生产修复。
