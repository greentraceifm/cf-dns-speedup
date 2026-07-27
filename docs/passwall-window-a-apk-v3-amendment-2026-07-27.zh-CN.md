# PassWall 窗口 A：APK v3 信任与事务修正案

## 1. 触发原因

窗口 A 隔离检查发现，原方案关于“直接对本地 APK 做独立签名验证并直接安装”的
假设不成立。VM36 使用 `apk-tools 3.0.5`：

- 社区公钥可验证 SourceForge `passwall_packages/packages.adb`；
- ImmortalWrt 官方公钥可验证官方 `packages/x86_64/packages/packages.adb`；
- 但新旧两个 APK 直接执行 `apk verify` 均返回 `UNTRUSTED signature`。

因此禁止直接以 APK 文件参数安装，也禁止使用 `--allow-untrusted`。本修正案把实际
事务改为“两个分离的本地文件仓库 + 各自已验签索引 + 精确包约束”。

## 2. 已完成的隔离证据

### 2.1 两套分离信任根

社区仓库：

- 公钥 SHA256：
  `52802b143489214e13b78f96599a147a638205cc22d9dd6d71229504e38ddc00`；
- 索引 SHA256：
  `c637eb915b95c42d164969109958a4fd3e1b4e91af99e56ae47e6cca27c85033`；
- 索引验签成功；
- 索引中的 `xray-core` 为 `26.7.11-r1`、`x86_64`、12,240,648 字节，
  依赖仅 `ca-bundle` 和 `libc`。

ImmortalWrt 官方仓库：

- 25.12.1 `packages/x86_64/packages/packages.adb` SHA256：
  `25beb13d40c8804a624bb15e55c25d4cffeaee74713f50dd52b0097d5cb84c87`；
- 索引使用 VM36 既有 ImmortalWrt 官方 keyring 验签成功；
- 索引中的 `xray-core` 为 `26.3.27-r1`、`x86_64`、11,899,024 字节，
  依赖仅 `ca-bundle` 和 `libc`。

两套 keyring、repository file 和 cache 全部分离，未混用。

### 2.2 克隆 APK 数据库往返

在 `/tmp` 隔离 root 中复制 VM36 当前 installed database/world，仅使用本地
`file://` 仓库、分离 keyring、空 cache 和 `--no-network`：

```text
SIMULATE_UPGRADE=(1/1) xray-core 26.3.27-r1 -> 26.7.11-r1
ISOLATED_UPGRADE=success
SIMULATE_DOWNGRADE=(1/1) xray-core 26.7.11-r1 -> 26.3.27-r1
ISOLATED_DOWNGRADE=success
OTHER_PACKAGE_CHANGES=0
XRAY_PROCESSES=0
TARGET_LISTENERS=0
```

候选二进制 SHA256 为
`ce3d0365893f21c1e67c18de2ff6798e49478e30d49f8022b4fba0ecc3d8fa61`，
版本 `26.7.11`。仓库固定的无秘密 fixture 通过 `run -test`，没有启动 Xray、
HAProxy 或目标监听。

### 2.3 安装脚本与文件范围

新旧包都包含 `post-install`、`post-upgrade` 和 `pre-deinstall`。脚本会调用
OpenWrt `default_postinst/default_prerm`；默认行为可能启用或启动包内 init 脚本。
因此实际升级和降级必须同时使用：

```text
--scripts=no --commit-hooks=no
```

候选 `26.7.11-r1` 的文件范围只有：

- `/usr/bin/xray`；
- `/lib/apk/packages/xray-core.*`；
- `/lib/upgrade/keep.d/xray-core`。

当前官方 `26.3.27-r1` 还包含：

- `/etc/config/xray`；
- `/etc/init.d/xray`；
- `/etc/xray/config.json.example`。

所以升级期间这三个旧包文件会暂时不存在，`/etc/rc.d/S99xray` 会暂时成为悬空
链接。VM36 当前没有 standalone Xray 进程；本窗口禁止重启 VM36、禁止调用 Xray
init、禁止启动 PassWall。隔离 root 已证明降级后旧包全部规定路径逐哈希恢复。

## 3. 修订后的实际事务

### 3.1 升级

1. 重新执行所有原方案硬门控和 ESXi 快照/backing/空间检查。
2. 在 VM36 root-only 回滚目录保存当前 APK database、world、Xray 包文件、
   `/usr/bin/xray` 和无秘密摘要，实际验证备份可读。
3. 重新验证社区索引签名、APK 固定 SHA256、索引包哈希绑定；建立只含候选索引和
   候选 APK 的本地 `file://` 仓库。
4. 使用社区 keyring、空临时 cache、`--no-network`、`--scripts=no`、
   `--commit-hooks=no`，先模拟再执行：

```text
apk fix --upgrade xray-core
```

`apk fix` 的隔离演练证明只升级一个包，且保持 `/etc/apk/world` 哈希不变。
5. 验证版本、包数据库、固定 fixture、无进程/监听、PassWall disabled 和生产隔离。

### 3.2 降级

1. 只有 APK 锁空闲、事务结束、database/world 可解析时才继续；否则立即进入离线
   VM36 Revert。
2. 重新验证 ImmortalWrt 官方索引签名、旧 APK 固定 SHA256、索引包哈希绑定；
   建立只含官方索引和旧 APK 的独立本地 `file://` 仓库。
3. 使用官方 keyring、另一空临时 cache、`--no-network`、`--scripts=no`、
   `--commit-hooks=no`，先模拟再执行精确约束：

```text
apk add xray-core=26.3.27-r1
```

4. 该命令会把 world 临时改成固定版本约束。事务成功且数据库健康后，立即从本窗口
   root-only 备份原子恢复原始 `/etc/apk/world`，并验证哈希完全一致。若安装或
   world 恢复任一步失败，不继续调用 APK，进入离线 VM36 Revert。
5. 验证旧包版本、二进制、全部规定路径、`S99xray` 链接目标、固定 fixture、
   database/world、PassWall disabled、无进程/监听和生产健康均恢复基线。

## 4. 停止与清理

- 禁止 `--allow-untrusted`、直接 APK 文件安装、混合 keyring、系统 feed/key/cache
  写入、联网依赖解析、PassWall/Xray 启停和 VM 重启。
- 任一求解结果出现第二个包即停止。
- 任一数据库、world、包文件、init 链接或网络基线不能恢复即停止 SSH 修复，并按
  已验证流程先关闭 VM36，再离线 Revert；不得操作 VM33。
- 正常往返后删除 `/tmp` 的索引、keyring、cache、克隆数据库、fixture 和日志；
  VM36 只保留公开新旧 APK、公钥和无秘密哈希清单。

本修正案已于 2026-07-27 获三位 IT 审核人一致批准，并按本修正案完成 VM36 系统 root 的单包升级与精确降级往返。实际结果见 `passwall-window-a-result-2026-07-27.zh-CN.md`。
