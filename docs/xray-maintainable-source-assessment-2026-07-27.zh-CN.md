# Xray 可维护来源评估

## 目标与边界

本阶段只核验用于 ImmortalWrt 25.12.1 staging 的 Xray 持久安装来源，目标版本必须不低于生产 `26.6.27`。候选还必须同时满足：`x86_64`、索引签名可信、依赖范围可控，并能作为 APK 由系统包管理器持续维护。

本阶段没有安装或替换任何软件包，没有启动 staging PassWall、Xray 或 HAProxy，没有传输真实 PassWall 配置，也没有修改生产 `.254`。

## 官方渠道枚举

2026-07-27 只读检查了以下 ImmortalWrt 官方目录：

- `releases/25.12.1/packages/x86_64/packages`
- `releases/25.12-SNAPSHOT/packages/x86_64/packages`
- `releases/packages-25.12/x86_64/packages`
- `snapshots/packages/x86_64/packages`

四个目录中唯一的 Xray 候选均为：

```text
xray-core-26.3.27-r1.apk
```

该版本低于生产 `26.6.27`，不满足版本硬门控。

Openwrt-Passwall 官方渠道也已核验：

- `openwrt-passwall` 最新 release 为 `26.7.24-1`，25.12+ 资产只有 PassWall 插件及其中文包 APK，不包含 Xray 核心 APK。
- `openwrt-passwall-packages` release 只发布组件版本 API 缓存和源码归档，不发布 Xray 核心 APK 或签名包仓库。
- 官方 `xray-core` 源码配方版本为 `26.7.11`，但源码配方不是签名 APK，也没有形成可由 staging 包管理器验证和回滚的持久来源。

因此，自行编译、混用 OpenWrt 仓库或手工替换 `/usr/bin/xray` 均不在本阶段授权范围内，也不能作为可维护来源。

## 隔离签名验证

使用 `.253` 上一次性的 `/tmp` APK root 验证 `25.12-SNAPSHOT` 官方索引。可信公钥只复制到临时 root；索引缓存使用真实 `/tmp` 绝对路径，没有使用系统 `/var/cache/apk`。

结果：

```text
INDEX_UPDATE_RC=0
INDEX_SIGNATURE=trusted
SEARCH=xray-core-26.3.27-r1
VERSION_COMPARE_TO_26.6.27=<
SYSTEM_INSTALLED_DB=unchanged
SYSTEM_WORLD=unchanged
SYSTEM_REPOS=unchanged
SYSTEM_CACHE_FILES=unchanged:0
```

临时 root 和缓存已清理。由于版本门控未通过，没有下载候选 APK，也没有继续做包内二进制和依赖验收。

## 运行状态复核

- `.253` PassWall 配置仍为 `enabled=0`，init 仍 disabled。
- `.253` 没有 Xray、HAProxy 进程或目标监听，临时探测目录和系统 APK 缓存均为 0。
- `.254` 仍运行 Xray `26.6.27`，两个 Xray 进程及 `1070/1041/11400/15353` 既有监听存在。
- PC、`.140`、`.254` 的 Google 和 YouTube 均返回 HTTP 204。

## 结论与停止点

状态为 `no_qualified_official_candidate`。当前没有同时满足版本、架构、官方签名来源和可维护安装要求的 Xray APK，因此不下载、不安装、不替换、不启动 staging PassWall，也不推进实际迁移。

安全恢复条件只有两个：

1. ImmortalWrt 25.12 官方签名仓库发布不低于 `26.6.27` 的 `x86_64` Xray APK；或
2. 另立评审，建设具有可复现构建、独立签名、包仓库索引和精确回滚包的内部来源。

为避免扩大问题，当前路线选择第一项并等待官方仓库更新。生产 `.254` 和既有优选 IP 项目继续按原状态运行。
