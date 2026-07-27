# Xray 版本静态兼容复核

## 阶段边界

- 只验证 ImmortalWrt 25.12.1 的官方 Xray 候选和生产 Xray 26.6.27 的 fixture 静态兼容性。
- 未安装或替换 staging Xray，未启动 PassWall、Xray 或 HAProxy，未修改防火墙和生产配置。
- 未再次传输真实 PassWall 配置。

## 官方 APK feed

- 使用一次性 `/tmp` APK root 读取 ImmortalWrt `25.12.1` 的七个官方签名 feed，共解析 11,411 个包。
- 官方 feed 中唯一的 `xray-core` 候选仍为 `26.3.27-r1`，没有达到生产 `26.6.27`，因此未下载或安装 APK。
- `apk --root` 隔离了数据库，但绝对 `--cache-dir /var/cache/apk` 曾在系统缓存目录生成七个索引文件。运行前缓存文件数为 0，七个文件已按精确路径删除，复核恢复为 0。
- `/lib/apk/db/installed`、`/etc/apk/world` 和 feed 配置的 SHA256 与运行前一致。

## 生产二进制临时测试

- 经 `.140` 受保护通道只读取得 `.254` 当前 Xray 元数据：版本 `26.6.27`，x86_64，大小 37,433,470 字节。
- 二进制通过 Windows `cmd.exe` 原始字节管道直接送入 `.253:/tmp`；未落盘到 PC 或 `.140`，到达后大小和 SHA256 与生产一致。
- 未安装或替换 staging `/usr/bin/xray`。临时二进制只执行 `version` 和 `run -test`。
- 同一份 fixture runtime JSON 在生产 Xray `26.6.27` 下静态校验成功，Xray/HAProxy 进程与目标监听保持为 0。
- 测试后候选二进制、输入目录和工作目录全部删除。

```text
RUNTIME_FIXTURE_STATUS=success
RUNTIME_FIXTURE_BYTES=2684
RUNTIME_FIXTURE_XRAY_VERSION=26.6.27
RUNTIME_FIXTURE_GENERATOR_RC=1
RUNTIME_FIXTURE_XRAY_TEST=success
```

## 运行后复核

- PC、`.140`、`.254` 的 Google/YouTube 均为 HTTP 204。
- `.254` 两个 Xray 进程和既有监听正常。
- `.253` PassWall 配置及 init 仍 disabled，Xray/HAProxy 进程与目标监听均为 0。
- `.253` 在 PassWall disabled 状态下直连 Google/YouTube 超时，但官方 ImmortalWrt HTTPS feed 可访问；该现象不影响生产代理路径。
- staging 系统 APK 缓存恢复为 0，包数据库、world 和 feed 哈希未改变。

## 结论与停止点

已证明 PassWall 26.7.1 的隔离生成结果可被生产 Xray 26.6.27 静态接受，但官方 25.12.1 feed 仍无法提供不低于生产版本的可安装包。本阶段不手工替换系统二进制，不启动 staging PassWall，也不再次传输真实配置。

下一阶段必须独立解决“可维护的持久 Xray 来源”：选择与 ImmortalWrt 25.12.1 兼容且签名、架构、依赖和回滚均可验证的 APK，或重新选择包含合格 Xray 包的 staging 固件/feed。真实配置 runtime 静态测试仍需单独授权。
