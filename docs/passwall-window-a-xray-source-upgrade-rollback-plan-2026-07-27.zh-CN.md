# PassWall 窗口 A：Xray 来源、升级与精确回滚实施方案

## 1. 决策与范围

本窗口只处理 staging VM36（`192.168.1.253`）上的 `xray-core`，目标是证明：

1. 候选 `26.7.11-r1` 来自可审计、带签名索引的持久仓库；
2. APK 架构、依赖和事务范围可控；
3. VM36 可以从当前 `26.3.27-r1` 升级到 `26.7.11-r1`，再精确降级回
   `26.3.27-r1`；
4. 全程不启动 PassWall/Xray，不改变生产 VM33（`.254`）、Sidecar（`.110`）
   或 OpenClaw（`.140`）。

本窗口不安装或升级 `luci-app-passwall`，不做完整 PassWall 数据面测试，不做生产
迁移。历史文件 `passwall-stage-full-test-implementation-plan-2026-07-27.zh-CN.md`
仍是未批准草案，不得执行。

## 2. 来源证据

### 2.1 仓库关系

- Openwrt-Passwall 官方组织的 `openwrt-passwall` 构建工作流（当前提交
  `edbf910e5a6c91addca7e4de53f501b4e0b2ee61`）明确把
  `moetayuko/openwrt-passwall-build` 列为软件包来源，并链接同名 SourceForge
  项目。
- `moetayuko/openwrt-passwall-build`（核验提交
  `9ecbf27d6ea174036e3e83c5a81906b2fb84a035`）说明其制品使用官方 OpenWrt SDK
  构建。其工作流从 Openwrt-Passwall 官方三个仓库的固定提交构建，使用仓库密钥
  签名 APK，并把 `dist/` 上传到 SourceForge 项目
  `/home/frs/project/openwrt-passwall-build/`。
- 该仓库 README 给出的 25.12/x86_64 持久地址为：

```text
https://master.dl.sourceforge.net/project/openwrt-passwall-build/apk.pub
https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/x86_64/passwall_packages/packages.adb
https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-25.12/x86_64/passwall_luci/packages.adb
```

这是一条“Openwrt-Passwall 官方项目明确推荐的社区二进制仓库”信任链，不是
ImmortalWrt 官方 feed。它只足以进入隔离 staging 验证，不能绕过本方案的签名、
依赖、回滚和专家审批门控。

### 2.2 公钥与制品复核

2026-07-27 从 GitHub 构建仓库和 SourceForge 分别取得公钥，内容相同。本地留存、
SourceForge 重取结果如下：

| 制品 | 字节数 | SHA256 |
|---|---:|---|
| `apk.pub` | 178 | `52802b143489214e13b78f96599a147a638205cc22d9dd6d71229504e38ddc00` |
| `passwall_packages/packages.adb` | 5,217 | `c637eb915b95c42d164969109958a4fd3e1b4e91af99e56ae47e6cca27c85033` |
| `xray-core-26.7.11-r1.apk` | 12,240,648 | `ff0d0c1c3b73bd0774fca1574ee6a49c304478cdd354c2fdf023a64d69ca06cb` |
| `luci-app-passwall-26.7.24-r1.apk` | 833,685 | `d1026d99a21b27e3d806b2d92c79d059e153e5a0632d984b39e2467ce6799f6d` |

SourceForge 目录页明确列出 `packages.adb` 与
`xray-core-26.7.11-r1.apk`；固定版本 Xray APK 于本次通过 HTTPS 镜像重新下载，
与 2026-07-26 本地留存文件逐字节哈希一致。`luci-app-passwall` 的一致性只作为
来源旁证，本窗口不安装该包。

## 3. 风险等级与授权

Action Gate 将“staging 包升级和降级演练”判定为高风险、不可自动执行，要求：

- 先完成只读证据采集；
- 三位 IT 审核人一致批准本方案；
- 使用用户已经明确授予的本窗口实施授权；
- 升级前确认现有 VM36 快照可见且没有合并、删除或 consolidate；
- 任一门控失败立即停止，不在同一窗口修复后重试。

生产 VM33/`.254` 不在授权范围内。

## 4. 运行前硬门控

以下必须同时通过：

1. VM36 身份为 `192.168.1.253/24`、MAC `00:0c:29:ec:33:dd`、ImmortalWrt
   `25.12.1`，且本机不持有 `.254`。
2. 当前 `xray-core=26.3.27-r1`，二进制版本 `26.3.27`；
   `luci-app-passwall=26.7.1-r1`。
3. PassWall UCI `enabled=0`，PassWall、PassWall Server、HAProxy init disabled；
   无 Xray/PassWall/HAProxy/chinadns-ng/dns2socks 进程、目标监听、临时目录、锁、
   `PSW_*` nft 规则或 DHCP/RA 服务。
4. VM36 现有快照
   `OpenWrt-25.12.1-stage-pre-marker-revert-drill-20260727-154536` 可见且快照链
   无告警；当前系统盘 backing 必须明确指向该快照之后的正确 delta，ESXi 没有
   VM36 task 或 consolidation 请求，datastore 可用空间不少于 10 GiB。不得创建、
   删除、合并或 consolidate 快照。
5. VM33/`.254` Powered on，两个生产 Xray 进程、`1070/1041/11400/15353`
   监听、Google/YouTube HTTP 204 正常。
6. `.110` Sidecar timer/service 保持当前健康状态；本窗口不启动任何 Sidecar
   任务。
7. VM36 可用空间至少 2 GiB，系统 APK 数据库、world、repositories、keys、
   init enable 状态和无秘密运行摘要已采集；APK 锁空闲、无其他包事务，installed
   database/world 可解析且一致性检查通过。

任一项不满足：停止，不安装、不重启、不自动修复。

## 5. 隔离签名与事务资格检查

1. 在 VM36 `/tmp` 下创建 root-only、单次使用的 APK root、cache、keys 和空
   repositories 文件。隔离 root 必须复制 VM36 当前 APK installed database、
   world 和模拟依赖解析所需的最小系统状态；不得写入系统 `/etc/apk/keys`、系统
   repositories 或 `/var/cache/apk`。
2. 从上述固定 HTTPS 地址重新取得 `apk.pub`、`packages.adb` 和
   `xray-core-26.7.11-r1.apk`。只有公钥与本报告固定 SHA256 匹配时才继续。
3. 使用隔离 APK root 验证 `packages.adb` 签名。候选包验证 keyring 只能包含
   固定 SHA256 的社区仓库公钥；禁止混入 ImmortalWrt 官方公钥，禁止
   `--allow-untrusted`，禁止忽略签名警告。
4. 由 APK 工具读取候选元数据，必须同时满足：包名 `xray-core`、版本
   `26.7.11-r1`、架构 `x86_64`。下载来源不能由包内元数据推断；必须另外证明
   已验签 `packages.adb` 中对应记录的包名、版本、架构、大小和包校验值与实际
   APK 一致，并且实际文件由第 2.1 节固定仓库地址取得。
5. 对候选执行隔离模拟事务。允许的事务范围只有 `xray-core` 从
   `26.3.27-r1` 变为 `26.7.11-r1`；出现新增、删除、替换其他包，或要求升级
   `luci-app-passwall`、libc、内核、openssl、dnsmasq、firewall、apk-tools 时停止。
6. 从 ImmortalWrt 官方 25.12.1 feed 下载并保留精确回滚包
   `xray-core-26.3.27-r1.apk`，使用只包含 ImmortalWrt 官方公钥的独立 keyring
   验证其官方签名、`x86_64` 架构和可模拟降级事务；禁止混入社区仓库公钥。缺少
   精确回滚包或独立信任根时禁止升级。
7. 分别检查新旧 APK 的 control metadata、install scripts、triggers、文件清单、
   owner 和 mode。只允许已审核的 Xray 核心文件范围；存在服务启停、配置写入、
   网络操作或其他非预期路径时停止并重新审批。
8. 解包候选到临时目录，只执行二进制版本检查，并使用无秘密、结构等价且来源固定的
   fixture 执行 `run -test`；不得使用尚未证明仍存在的真实 23 节点 runtime，不得
   启动代理、监听端口或联网 canary。真实节点 runtime 留到窗口 B 的受控真实配置
   流程。
9. VM36 的 `apk-tools 3.0.5` 没有 `--allow-downgrades` 选项。必须在复制当前
   installed database/world 的隔离 root 中，用固定旧版 APK、明确版本约束、
   `--no-network`、临时 `--keys-dir` 和空 `--repositories-file` 验证实际降级
   命令。若工具不能在不启用 force/不扩大事务的条件下模拟降级，停止，不得升级。
10. 清理隔离 root 前记录允许字段。必须证明系统 APK 数据库、world、repositories、
   keys 和系统 cache 与检查前一致。

## 6. VM36 单包升级演练

只有第 5 节全部通过后才执行：

1. 在 VM36 本地创建 root `0700` 回滚目录，保存：
   - 当前 `xray-core-26.3.27-r1.apk`；
   - 候选 `xray-core-26.7.11-r1.apk`；
   - `/usr/bin/xray`；
   - APK installed database、world 和 `xray-core` 包元数据；
   - 无秘密状态摘要与 SHA256 清单。
2. 实际读取并验证备份可读；敏感系统数据库保持 root-only，不复制到 Windows、
   GitHub、Notion 或 OpenClaw memory。
3. 安装前最后一刻再次确认 APK 锁空闲、无其他事务、installed database/world
   可解析且一致性检查通过；PassWall 仍 disabled 且没有任何相关进程。再次模拟同一
   命令，求解结果必须只有 `xray-core` 一个包。
4. 只安装已验证的单个本地 `xray-core-26.7.11-r1.apk`。安装前再次校验固定
   SHA256；实际安装使用只包含固定社区公钥的 root-only 临时 `--keys-dir`、
   `--no-network`、空 `--repositories-file` 和 root-only 空临时
   `--cache-dir`。禁止 `--allow-untrusted`，禁止读取或写入系统
   `/var/cache/apk`；不得写系统 keys/repositories，不得联网解析依赖；禁止
   `apk upgrade`、禁止安装 PassWall 插件、禁止添加永久 feed。
5. 安装后必须证明：已安装包和二进制均为 `26.7.11`，只有 `xray-core` 包状态
   变化；PassWall/init/UCI、DNS、DHCP/RA、nft、路由和监听保持不变。
6. 对第 5 节固定无秘密 fixture 再执行 `run -test`。任一失败立即停止升级阶段；
   先按第 7 节判断 APK 数据库是否健康，不启动 PassWall 或 Xray。

## 7. 精确降级演练

升级事务完整结束后，本窗口必须把 VM36 恢复到原基线。首先验证 APK 锁空闲、事务
已经结束、installed database 可解析且一致性检查通过。只有数据库健康时才允许执行
下面的精确降级；安装中断、锁异常或数据库不健康时不得再次调用 APK，立即关闭 VM36
并转入已批准的离线快照 Revert：

1. 再次校验固定 SHA256，只安装已验证并留存的本地
   `xray-core-26.3.27-r1.apk`，使用第 5.9 节已经模拟成功的精确命令、明确版本
   约束、只包含 ImmortalWrt 官方公钥的独立临时 `--keys-dir`、
   `--no-network`、空 `--repositories-file` 和 root-only 空临时
   `--cache-dir`；禁止混入社区公钥，禁止 `--allow-untrusted`，禁止读取或写入
   系统 `/var/cache/apk`、联网及其他包事务。降级前再次模拟同一命令，求解结果
   必须只有 `xray-core`；APK 3.0.5 不存在的降级参数不得臆造。
2. 验证已安装包和二进制均恢复为 `26.3.27-r1/26.3.27`。
3. 对第 5 节固定无秘密 fixture 再执行 `run -test`。
4. 比较 APK database、world、repositories、keys、PassWall UCI、init enable、
   DNS、DHCP/RA、nft、路由、进程、监听和锁；除 APK 数据库中可解释的安装时间
   字段外，必须恢复原语义。
5. 复核 VM33/`.254`、`.110` 及 PC/.140 HTTP 健康项不变。

如果精确降级失败、VM36 失联、包数据库异常或出现残留，停止 SSH 修复。严格复用
已批准并验证过的 VM36 离线 Revert 流程：用户在 Host Client 核对目标为 VM36，
先关闭 VM36，再选择指定快照 Revert，最后启动并验收；禁止在线 Revert，禁止操作
VM33。Revert 后本窗口结束，不再重试。

## 8. 清理与证据留存

正常降级并验收后：

1. 删除 VM36 `/tmp` 下本窗口创建的 APK root、cache、临时 keys/index、fixture、
   installed database 备份和检查日志。
2. VM36 本地只允许保留两个公开 APK、公开公钥及无秘密 SHA256 清单；不得保留
   真实配置、节点 runtime、订阅或系统数据库副本。
3. 复核 `/tmp`、系统 keys/repositories/cache、APK 锁、进程、监听和临时规则无
   本窗口残留。
4. Windows/GitHub/Notion/OpenClaw memory 只记录公开来源、公开制品哈希和无秘密
   结果，不复制 VM36 系统数据库或配置。

## 9. 通过标准与后续边界

窗口 A 只有在以下全部成立时通过：

- 来源、公钥、索引签名、架构、依赖和模拟事务全部通过；
- Xray 26.3.27 -> 26.7.11 -> 26.3.27 的实际单包往返成功；
- 三个版本点的固定无秘密 fixture 静态测试全部通过；
- PassWall 始终 disabled，代理进程和目标监听始终为 0；
- VM36 包管理、UCI、init、DNS、DHCP/RA、nft、路由、锁及临时目录恢复基线；
- VM33/`.254`、Sidecar `.110` 和现有生产网络不变。

通过只解除迁移报告中的 P0-1，不代表允许窗口 B、正式迁移或生产升级。窗口 B 必须
基于窗口 A 实际结果另写最小方案并重新审核。
