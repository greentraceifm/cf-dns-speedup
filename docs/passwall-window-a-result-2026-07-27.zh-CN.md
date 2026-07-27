# PassWall 窗口 A：Xray 单包升级与精确回滚结果

## 1. 结论

窗口 A 于 2026-07-27 完成，结论为 **PASS**。

VM36（`192.168.1.253`）在 PassWall/Xray 全程不启动的条件下完成：

```text
xray-core 26.3.27-r1 -> 26.7.11-r1 -> 26.3.27-r1
```

升级和降级的实际求解结果都只涉及 `xray-core` 一个包。生产 VM33（`.254`）、
Sidecar（`.110`）和 OpenClaw（`.140`）没有执行安装、停止、重启或切换。

本结果只解除迁移准入项 P0-1，不批准窗口 B、启动 VM36 PassWall、生产升级或正式
迁移。

## 2. 审批与信任模型

- 原窗口 A 方案已获三位 IT 审核人一致批准；
- APK v3 信任模型修正案已获三位 IT 审核人一致批准；
- 用户已授权本窗口实施；
- APK v3 对两个包文件直接执行 `apk verify` 均返回 `UNTRUSTED signature`，因此
  没有直接安装 APK，也没有使用 `--allow-untrusted`；
- 社区升级与官方回滚分别使用独立 keyring、已验签 `packages.adb` 和本地
  `file://` 仓库，信任根、索引和 cache 没有混用。

## 3. 固定制品

社区候选：

- `xray-core-26.7.11-r1.apk`：
  `ff0d0c1c3b73bd0774fca1574ee6a49c304478cdd354c2fdf023a64d69ca06cb`；
- 社区索引：
  `c637eb915b95c42d164969109958a4fd3e1b4e91af99e56ae47e6cca27c85033`；
- 社区公钥：
  `52802b143489214e13b78f96599a147a638205cc22d9dd6d71229504e38ddc00`；
- 候选二进制：
  `ce3d0365893f21c1e67c18de2ff6798e49478e30d49f8022b4fba0ecc3d8fa61`。

官方回滚：

- `xray-core-26.3.27-r1.apk`：
  `40c16105f6c63c3df03d492cb4fdced84451a57395cb50f31be5ea5a4c985416`；
- ImmortalWrt 官方索引：
  `25beb13d40c8804a624bb15e55c25d4cffeaee74713f50dd52b0097d5cb84c87`。

## 4. 实际事务

两次事务都使用：

```text
--no-network --scripts=no --commit-hooks=no
```

升级命令为：

```text
apk fix --upgrade xray-core
```

降级命令为：

```text
apk add xray-core=26.3.27-r1
```

降级后从 root-only 备份原子恢复原始 `/etc/apk/world`。升级前、升级后和降级后，
固定无秘密 fixture 均通过 Xray `run -test`。没有启动 PassWall、Xray 或 HAProxy，
目标监听始终为 0。

## 5. 恢复验收

VM36 最终状态：

- `xray-core=26.3.27-r1`，二进制版本 `26.3.27`；
- `/etc/apk/world` 与升级前备份逐字节一致；
- `/usr/bin/xray`、`/etc/config/xray`、`/etc/init.d/xray`、示例配置、APK 元数据和
  keep.d 文件均与升级前备份逐字节一致；
- `/etc/rc.d/S99xray` 链接有效；
- PassWall UCI `enabled=0`，init disabled；
- Xray/HAProxy 进程为 0，`1070/1041/11400/15353` 监听为 0；
- 系统 APK repositories、keys 和 cache 没有社区仓库残留；
- 默认网关 `192.168.1.1` 可达。

VM36 在 PassWall 禁用时对 Google/YouTube 的裸机直连检查超时。该项不是窗口 A 的
通过门槛，历史 204 是经受控 localhost Xray canary 获得，不能混称为裸机直连。
窗口 B 必须在完整 PassWall 数据面启动后重新验证代理 HTTP、DNS、监听和恢复，不能
用本窗口结果替代。

生产复核：

- `.254` PassWall enabled/running；按 `/proc/*/exe` 计数为两个 Xray 进程；
- `.254` 的 `1070/1041/11400/15353` 均有监听，Google/YouTube 均为 HTTP 204；
- `.110` service inactive、Result=success、ExecMainStatus=0、MainPID=0；
- `.110` timer enabled/active/waiting，Google/YouTube 均为 HTTP 204。

## 6. 清理与留存

- 已删除 VM36 `/tmp/cfip-window-a-20260727-205949`；
- 已删除 root-only 回滚目录中的 APK database、系统文件副本、`world` 和旧的混合
  SHA256 清单；
- VM36 仅保留 5 个公开 APK/索引/公钥文件和 `PUBLIC-SHA256SUMS`；公开清单已用
  `sha256sum -c` 验证通过；
- `.140` 本轮上传脚本和临时 VM36 主机公钥文件已删除；
- ESXi 快照没有创建、删除、合并、Revert 或 consolidate。

公开制品留存目录：

```text
/root/openwrt-backup/xray-window-a-20260727-212400/public
```

## 7. 后续边界

P0-1 已解除，迁移整体仍为 **NO-GO**。未完成项仍包括：

- P0-2：完整 PassWall 临时地址数据面；
- P0-3：重启、冷启动、DNS、ACL 和单测试客户端语义；
- P0-4：真实 PassWall `>=6.5 MB/s` 性能门槛；
- P0-5：正式切换期间不依赖 Codex 的离线回滚演练。

窗口 B 必须另写最小实施方案，重新经过 IT 专家组审核和用户单独授权。窗口 A 成功
不能用于自动启动 PassWall、改 DNS、改路由、改订阅、升级生产核心或迁移 `.254`。
