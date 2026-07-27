# PassWall staging localhost canary 验收

## 目标与边界

在真实配置 runtime 静态门控通过后，本阶段只验证 `.253` 官方 Xray `26.3.27` 能否使用一个当前实际引用节点建立真实 VMess+WS+TLS 数据面。

canary 只绑定 `.253` 的 `127.0.0.1:19080`，不监听 LAN，不启用 PassWall，不写 `/etc/config/passwall`，不修改 DNS、防火墙、路由、订阅、CFIP 池或 Cloudflare 记录。生产 `.254` 始终保持在线。

节点标识、地址、UUID、配置正文和 runtime JSON 均未输出或保存。脚本只登记本次 Xray PID，并通过 trap 在成功或失败时终止该 PID、等待退出并删除私有 `/tmp` 工作目录。

## 执行结果

真实配置仍先经过结构转换和全部 23 个 Xray 节点的静态检查。随后从当前实际引用中选择一个直接 VMess/VLESS 节点，单独生成 localhost SOCKS runtime。

```text
REAL_CANARY_STATUS=success
REAL_CANARY_TESTED_NODES=1
REAL_CANARY_GOOGLE_HTTP=204
REAL_CANARY_YOUTUBE_HTTP=204
REAL_CANARY_DOWNLOAD_HTTP=200
REAL_CANARY_DOWNLOAD_BYTES=1048576
REAL_CANARY_DOWNLOAD_SPEED_BPS=506498
REAL_CANARY_XRAY_VERSION=26.3.27
REAL_CANARY_POST_XRAY_PROCS=0
REAL_CANARY_POST_TARGET_LISTENERS=0
```

Google 和 YouTube 均通过 SOCKS 返回 HTTP 204，Cloudflare 1 MiB 下载完整返回 HTTP 200。单次 1 MiB 下载约为 `506,498 B/s`，约 `0.48 MiB/s`。该值只证明真实数据面可用；样本太小、连接建立开销占比过高，不能作为吞吐性能结论，不能与真实 PassWall `6.5 MB/s` 门槛比较，也不能触发节点、池或 DNS 变更。

## 清理与生产复核

- `.140` 本次源工具目录已删除；
- `.253` 输入、转换、runtime、canary 日志和工具目录残留均为 0；
- `.253:/tmp/etc/passwall` 不存在；
- `.253` PassWall 配置仍为 `enabled=0`，init 仍 disabled；
- `.253` Xray、HAProxy、`19080` 和既有目标监听均为 0；
- `.254` 两个 Xray 进程和 `1070/1041/11400/15353` 监听正常；
- PC 和 `.254` 的 Google/YouTube 均返回 HTTP 204。

## 结论与下一门槛

`.253` 已通过以下三层门控：真实配置结构转换、两个 Xray 版本的全部节点 runtime 静态检查、官方 `26.3.27` 的单节点 localhost 真实数据面。当前证据否定了“官方 stable 因版本号较低而必然不能运行现有节点”的假设。

`.253` 仍不是生产就绪。下一阶段应在新的受控窗口，把转换后的配置写入 staging 的独立备份路径并评审一次临时地址 PassWall 数据面测试；该阶段会首次触碰 `.253` 正式配置、init 逻辑和 staging 防火墙，因此必须先建立 `.253` 配置备份、写入回滚和 LAN 隔离门控。生产切换仍需等待完整 PassWall 数据面、重启恢复、DNS/ACL、性能和 Xray 长期版本策略全部通过。
