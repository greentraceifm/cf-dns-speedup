# CFIP 优选 IP 运行审计与修复报告

日期：2026-11-19（Asia/Shanghai）

## 结论

本次检查确认生产链路正常，没有需要修改 VM36、Cloudflare、DNS、PassWall
或调度的生产故障。

- `.110` Sidecar 自然任务成功，timer 为 `active/enabled`，导出 3 个候选；
- VM36 `04:35` 同步任务完成，但因候选与 `auto` 当前地址重复，被全局去重保护安全拒绝；
- 五个槽位当前均为不同 IP，三路 DNS 查询最终全部一致；
- PassWall/Xray、四个监听、项目锁和 Google/YouTube 代理 HTTP 验收正常；
- 候选资格池仍有 2 个竞争候选和 3 个主槽基线候选，未出现候选池耗尽；
- 未手工修改 DNS 或 Cloudflare，未重启任何生产服务。

最终判断：**符合当前设计目标，继续自然周期运行，不需要扩大生产修复范围。**

## 本次自然周期

VM36 最新同步报告：

```text
observed_at=2026-11-19 04:36:17
status=awaiting_safe_competition_transition
candidate_ip=162.159.237.251
record_name=auto3.greentraceifm.top
previous_ip=104.26.7.141
detail=duplicate_guard_rejected:duplicate_with=auto.greentraceifm.top
task_id=20261119T043500-19510
```

对应日志为：

```text
safe single-record update rejected by global duplicate guard; no Cloudflare write
```

这不是同步崩溃。候选地址已被 `auto` 占用，若写入 `auto3` 会制造跨槽重复，
因此脚本按设计拒绝写入并等待下一周期。

## 生产状态

### `.110` Sidecar

- service 最近结果：`success`
- timer：`active/enabled`
- 最新报告：存在，5 行
- 候选导出：存在，3 行
- Xray 残留：0
- 瞬时 CFIP 容器：0
- `sub2api`、PostgreSQL、Redis：`healthy`
- `.110` 宿主机直连 Google/YouTube 仍可能超时；这是宿主直连出口限制，
  不作为 VM36 代理链路故障。

### VM36

- 受保护密钥认证：通过；
- 一个有效 Xray 进程；
- `1070`、`1041`、`11400`、`15353` 四个监听全部存在；
- 项目锁空闲；
- 默认路径和 SOCKS 路径的 Google/YouTube 均为 HTTP `204`；
- CFIP 残留进程：0。

唯一同步 cron 仍为：

```text
35 4 * * * timeout 1800 /root/cf-dns-speedup/sidecar-auto-sync.sh run >> /root/cf-dns-speedup/sidecar-auto-sync.log 2>&1
```

旧 `06:30` 任务不存在。

### 五槽与 DNS

```text
auto   = 162.159.237.251
auto1  = 104.26.1.38
auto2  = 104.17.129.81
auto3  = 104.26.7.141
auto4  = 104.17.131.246
```

修正后的审计入口连续复核三路 DNS 后，VM36 本地、`192.168.1.1` 和
`1.1.1.1` 均返回上述对应地址。MikroTik `.1` 的只读 `:resolve` 也返回
`104.26.7.141`。

第一次完整审计中 `192.168.1.1` 对 `auto3` 出现一次 `NO_ANSWER`，随后三轮
原始 `nslookup` 均成功，且没有 `SERVFAIL`、`NXDOMAIN` 或超时日志。因此判定
为一次性查询异常，不是权威 DNS、持续缓存或监听故障。

## 候选池

通过 VM36 受保护只读入口核对：

- `router-candidate-competition-qualified.tsv`：表头外 2 个竞争候选；
- `router-primary-baseline-qualified.tsv`：表头外 3 个主槽基线候选；
- Sidecar 导出：3 个候选；
- 最新自然候选测试包含多个通过真实门控的记录。

候选容量满足“三主槽、两竞争槽”模型，没有降低 `3.5 MB/s` 底线的理由。
当前周期拒绝的是地址重复，不是候选数量不足。

## 本次修复

只修复本机只读审计工具：

文件：`tools/Invoke-CfipReadonlyAudit.ps1`

修复内容：

1. 每个域名、每个 DNS 服务器最多重试 3 次；
2. 只解析 `Name:` 之后的 `Address:` 行；
3. 避免把 DNS 服务器自身的 `Address:` 行误认为目标域名答案；
4. 不改变生产脚本、DNS、Cloudflare、cron 或服务。

该修复解释并消除了审计入口对一次性空答案的放大误报，不需要部署到 VM36。

## 测试

通过：

- PowerShell 语法解析；
- `git diff --check`；
- 全项目回归测试；
- Sidecar 测试；
- 修复后的固定链路完整只读审计；
- VM36 原始 DNS 三轮复核；
- 五槽三路 DNS、PassWall 四监听、HTTP `204` 和锁检查。

Windows Git Bash 的真实 `flock` 竞争测试按既有规则跳过，因为该环境不提供
生产 Linux 的 `flock`；VM36 生产锁后验为空闲。

## 收口建议

保持现状并等待自然周期：

1. 不手工改写 `auto3`；
2. 不降低候选门槛；
3. 不恢复旧 `06:30` cron；
4. 下一周期继续观察是否出现不与五槽重复的合格候选；
5. 只有发生连续 DNS 空答案、HTTP 门控失败或回滚失败时，才开启新的生产修复。

本轮状态：`CLOSED_WITH_KNOWN_ISSUES`。

这里的已知项仅指本周期候选因重复被安全拒绝，当前五槽本身没有重复，
不是生产故障。
