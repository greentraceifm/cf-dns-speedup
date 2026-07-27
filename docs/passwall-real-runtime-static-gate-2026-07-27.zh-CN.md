# PassWall 真实配置 runtime 静态门控

## 目标与边界

本阶段验证生产 PassWall 配置经结构化转换后，能否由 ImmortalWrt 25.12.1 / PassWall 26.7.1 在隔离目录生成 Xray runtime，并同时通过 staging 官方核心 `26.3.27` 和生产当前核心 `26.6.27` 的静态配置检查。

全程保持 `.253` PassWall 配置与 init disabled。没有写入 `/etc/config/passwall`，没有启动 PassWall、Xray 或 HAProxy，没有创建代理监听，没有修改 DNS、路由、防火墙、订阅、CFIP 池或 Cloudflare 记录。

真实配置只通过以下内存路径传输：

```text
.254 SSH stdout -> .140 -> Windows cmd.exe 原始字节管道 -> .253 SSH stdin
```

PC 和 `.140` 未落盘配置；`.253` 只在 root 私有 `/tmp` 中短暂转换和测试。生产 Xray 二进制同样使用原始字节管道临时送到 `.253:/tmp`，没有安装或替换 staging `/usr/bin/xray`。

## 门控修正

fixture 审计确认旧配置可能使用 `VMess/VLESS` 大小写和 UCI `list alpn`，而 PassWall 26.7.1 runtime 生成器要求小写协议和逗号分隔 ALPN。静态门控只在私有转换结果副本中做以下正规化：

- `VMess -> vmess`
- `VLESS -> vless`
- 多值 ALPN 转为逗号分隔字符串

虚构 fixture 的两个 Xray 节点均通过正规化、runtime 生成和 `26.3.27` 静态测试。正式执行时，真实配置的协议和 ALPN 已符合新格式，正规化计数均为 0。

## 真实配置结果

```text
STREAM_RUNTIME_STATUS=success
STREAM_SOURCE_BYTES=21066
STREAM_SOURCE_COUNT_NODES=24
STREAM_SOURCE_COUNT_ACL_RULES=3
STREAM_SOURCE_COUNT_SHUNT_RULES=6
MIGRATION_GLOBAL_ENABLED=0
MIGRATION_OUTPUT_COUNT_NODES=25
MIGRATION_OUTPUT_COUNT_ACL_RULES=3
MIGRATION_OUTPUT_COUNT_SHUNT_RULES=8
MIGRATION_REFERENCES_UNKNOWN=0
REAL_RUNTIME_ELIGIBLE_NODES=23
REAL_RUNTIME_TESTED_NODES=23
REAL_RUNTIME_PROTOCOLS_NORMALIZED=0
REAL_RUNTIME_ALPN_NORMALIZED=0
REAL_RUNTIME_STAGING_XRAY_VERSION=26.3.27
REAL_RUNTIME_SECOND_XRAY_VERSION=26.6.27
REAL_RUNTIME_XRAY_TEST=success
REAL_RUNTIME_XRAY_PROCS=0
REAL_RUNTIME_HAPROXY_PROCS=0
REAL_RUNTIME_TARGET_LISTENERS=0
REAL_RUNTIME_SYSTEM_TMP=absent
```

24 个源节点中，23 个为可直接生成 Xray runtime 的 VMess/VLESS 节点，另 1 个为分流控制节点。23 份 runtime 均由两个核心通过 `xray run -test`。

`app.sh run_socks ... no_run=1` 对 23 个节点均返回该分支允许的 `1`，但每份 JSON 非空且两个核心静态校验成功，因此按既有门控规则判定成功。

## 清理与复核

- `.140` 临时源目录为 0；
- `.253` 配置输入、转换结果、runtime、工具和临时生产 Xray 二进制均为 0；
- `.253:/tmp/etc/passwall` 不存在，系统 APK 缓存文件数为 0；
- `.253` PassWall 配置仍为 `enabled=0`，init 仍 disabled；
- `.253` Xray、HAProxy 和目标监听均为 0；
- `.254` 两个 Xray 进程及 `1070/1041/11400/15353` 监听保持正常；
- PC、`.140`、`.254` 的 Google 和 YouTube 均返回 HTTP 204。

## 结论与下一门槛

真实配置的结构兼容和 Xray runtime 静态兼容门槛已经解除。官方 stable `26.3.27` 能解析当前全部真实 VMess/VLESS 节点配置；这修正了此前仅凭版本号无法判断兼容性的不足。

本结果仍不批准生产切换。下一阶段只允许在 `.253` 上启动一个绑定 `127.0.0.1` 的一次性 Xray canary，使用当前实际引用节点验证 SOCKS HTTP、TLS/WS 和基本吞吐；PassWall、DNS、防火墙和生产客户端继续不接入。canary 必须有进程 PID 注册、超时、trap 清理和运行后零残留门控。只有 canary 通过，才评审 `.253` 的临时地址 PassWall 数据面测试。
