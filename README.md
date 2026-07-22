# cf-dns-speedup

Cloudflare 优选 IP 自动更新脚本，面向 OpenWrt 使用。

这是对原 `cdnopw` 思路的安全修正版：尽量保留中文菜单和原项目使用流程，同时修正混淆代码、测速卡死、危险 DNS 操作和日志刷屏等问题。

## 核心改进

- 保留中文交互菜单和“安装/配置/立即执行/域名清理/卸载/日志”主流程。
- 去除混淆代码，不使用 `eval` 和多层 `base64 | bash`。
- 使用 Cloudflare API Token，不使用 Global API Key。
- 默认 `DRY_RUN=1`，首次运行只预演，不修改 DNS。
- `cfst` 增加总超时，避免测速阶段无限卡死。
- 手动运行时保留 `cfst` 同一行实时进度；主日志只记录关键步骤。
- 定时任务等非交互运行时，`cfst` 原始输出单独写入 `cfst-output.log`。
- 支持配置延迟上下限、下载速度下限、单 IP 超时、下载超时。
- 支持 Cloudflare Pages / R2 / 自有 CDN 文件作为稳定测速 URL。
- DNS 更新和删除均支持 dry-run 预演。

## 一键安装

推荐安装命令：

```sh
curl -fsSL https://raw.githubusercontent.com/greentraceifm/cf-dns-speedup/main/install-openwrt.sh | sh
```

安装完成后会自动打开中文菜单。以后再次打开菜单：

```sh
/root/cf-dns-speedup/menu.sh
```

## 中文菜单

主菜单：

```text
1. 安装/重置脚本
2. 更改各项参数配置
3. 运行一次已配置完成的脚本
4. 删除CF域名指定名称解析记录
5. 卸载
6. 查看运行日志
0. 退出
```

配置菜单包含：

```text
1. 切换推送模式（域名解析推送 / IP 直接推送）
2. 切换 CDN IP 来源（官方 IP / 反代 IP）
3. 切换域名解析方案（多 IP 到一域名 / 每 IP 到每域名）
4. 切换优选 IPv4 或 IPv6
5. 更换端口
6. 开启、关闭测速，更换测速网站
7. 更换 OpenWrt 代理插件
8. 更改测速线程、显示数量、超时、延迟/速度阈值、代理重启等待时间
9. 更换 Cloudflare 解析域名
10. 更换 Cloudflare API Token / Zone ID
11. 关闭、开启 Telegram 通知，更换 Token、用户 ID
12. 切换 Telegram API 接口域名
13. 关闭、开启 PushPlus 微信通知，更换 Token
14. 切换 DRY_RUN 安全测试模式
15. 查看当前配置
0. 返回主菜单
```

## 首次配置流程

1. 运行一键安装命令。
2. 选择 `1. 安装/首次配置`。
3. 输入 Cloudflare API Token、Zone ID、解析域名。
4. 首次保持 `DRY_RUN=1`。
5. 选择 `3. 运行一次已配置完成的脚本`。
6. 查看日志，确认将要创建/更新的 DNS 记录正确。
7. 回到配置菜单，选择 `14. 切换 DRY_RUN 安全测试模式`，切换为 `DRY_RUN=0`。
8. 再次执行，才会真实更新 Cloudflare DNS。

## Cloudflare Token 权限

请创建 Cloudflare API Token，不要使用 Global API Key。

建议权限：

- `Zone:Read`
- `DNS:Edit`
- 作用范围只限制到目标域名 Zone

真实 Token 只保存在 OpenWrt 本机：

```sh
/root/cf-dns-speedup/config.env
```

不要把真实 `config.env` 上传到 GitHub。

## 推荐测速 URL

测速 URL 必须满足：

- 可以通过 Cloudflare CDN 访问。
- 在指定候选 Cloudflare IP 并保持 Host/SNI 时仍返回 `HTTP 200`。
- 文件大小足够稳定，建议日常自动优选使用 `10MB` 左右。
- 路径固定，不依赖 `latest`。

推荐自建 Cloudflare Pages：

```text
https://your-pages-project.pages.dev/10mb.bin
```

不推荐直接使用下面这类 URL，除非已在 OpenWrt 上验证可下载：

```text
https://speed.cloudflare.com/__down?during=download&bytes=104857600
```

原因是部分环境下它会返回 `HTTP 403`，只下载 1 字节，导致 `cfst` 下载速度显示为 `0.00`。

## Cloudflare Pages 自建测速文件

推荐创建 3 个固定文件：

```text
1mb.bin
10mb.bin
20mb.bin
```

日常定时任务建议使用：

```text
10mb.bin
```

文件大小建议：

```text
日常自动优选：10 MB
更精细但更慢：20 MB
不建议日常：100 MB 或 1 GB
```

在 OpenWrt 上验证测速 URL：

```sh
curl -L --connect-timeout 6 --max-time 30 -o /dev/null \
  -w 'http=%{http_code} ip=%{remote_ip} total=%{time_total} size=%{size_download} speed=%{speed_download}\n' \
  'https://your-pages-project.pages.dev/10mb.bin'
```

如果返回 `HTTP 200` 且 `size_download` 接近文件大小，再填入菜单的测速地址。

## 推荐参数

OpenWrt 软路由日常建议：

```text
测速线程：16
下载测速数量：100
最终显示/更新数量：5
单 IP 延迟测试超时：4
cfst 总超时：3600
下载测速超时：25
平均延迟下限：0
平均延迟上限：220
下载速度下限：0
测速 URL：Cloudflare Pages 10MB 文件
```

说明：

- 延迟下限保持 `0` 即可，一般不需要过滤低延迟。
- `CFST_DOWNLOAD_COUNT` 控制参与下载测速的候选数量，`CFST_RESULT_COUNT` 控制最终显示和更新 DNS 的数量。
- `CFST_PREFER_MIN_SPEED` 是软高吞吐门槛：达到门槛的 IP 会优先进入最终结果；数量不足时会用次优结果补齐，避免域名缺少 IP。
- `CFST_DOWNLOAD_COUNT_STEP` 和 `CFST_DOWNLOAD_COUNT_MAX` 用于自适应扩大测速范围：高吞吐候选不足时，按步长增加下载测速候选数量，直到满足最终数量或达到上限。
- 面向 4K 视频吞吐的每日清晨任务建议先使用 `CFST_DOWNLOAD_COUNT=100`、`CFST_RESULT_COUNT=5`，扩大下载测速候选池。
- 面向 4K 视频吞吐优先，延迟上限建议 `220`；如果更重视网页交互手感，可临时测试 `150` 或 `200`。
- 如果 `100` 个候选配合 10MB 文件仍不稳定，再把测速 URL 切到 `20mb.bin`，并把 `CFST_TOTAL_TIMEOUT` 提高到 `4200`、`CFST_DOWNLOAD_TIMEOUT` 提高到 `30`。
- 下载速度硬下限 `CFST_MIN_SPEED` 建议保持 `0`；如果想优先筛高吞吐，优先使用 `CFST_PREFER_MIN_SPEED=10` 这种软门槛。
- 如果只想做延迟排序，可关闭下载测速，让 `CFST_URL` 留空。

## 定时任务

旧的 06:30 全量优选 cron 会停止或重启代理，已经永久禁用，不得恢复为无人值守任务。当前候选发现由独立 Sidecar 的 systemd timer 在约 03:30 运行；路由器 canary 仍是手动、隔离、无 PassWall 重启的动作。

无人值守路由器配置必须保持：

```text
CFST_ALLOW_PROXY_STOP=0
```

脚本主日志仍在：

```sh
/root/cf-dns-speedup/run.log
```

## 无停机 Sidecar 观察

`sidecar/` 提供面向独立 Ubuntu/Docker 主机的无停机观察组件。它使用独立 `ipvlan` 地址进行直连发现，再用临时 Xray 容器串行验证最多 5 个候选，不停止或切换 OpenWrt 上正在运行的 PassWall。

安全边界：

- Sidecar 地址必须在 PassWall 中配置为精确的直连旁路；禁止复用受代理 ACL 控制的主机地址。
- 运行前检查 Ollama 空闲、系统负载、可用内存、磁盘和既有容器健康状态。
- 现有 `cfip-direct` 必须是 `ipvlan L2`，并匹配 parent、subnet 和 gateway；镜像 tag 必须匹配构建时记录的 image ID。
- Sidecar 与宿主清理任务使用独立锁互斥；清理运行中 Sidecar 会在任何测速前安全让步。
- 宿主清理只能清理旧 stopped container、dangling image 和有超时上限的 BuildKit cache，不得运行 host-wide `docker system prune -a` 或 network prune。
- `status` 必须同时查看 `service_result`、`service_exec_status` 和报告时间；systemd reset-failed 后的 `Result=success` 不能覆盖真实非零退出码。
- Xray 明文配置只通过 systemd encrypted credential 解密到 `/run`。
- Sidecar 报告只进入观察流程，不更新 Cloudflare DNS，也不直接进入稳定冠军池。
- `sidecar/router-bypass.sh` 只做 UCI 持久配置和增量 nft 规则，不 reload 或 restart PassWall。

部署前先运行：

```sh
sidecar/tests/run-tests.sh
```

生产部署先用单个已知 IP 执行 `canary`，确认独立出口和两轮代理下载都正常后，才启用夜间 timer。`canary` 不运行 50/100 地址直连扫描。

三夜观察完成后，可在维护窗口手工运行单候选路径诊断：

```sh
systemctl start cfip-sidecar-diagnose@104.17.136.166.service
```

`diagnose` 不由 timer 调用，也不运行 IP 扫描。它固定串行执行四组两轮下载，对比当前/放宽 CPU 配额、候选 IP/原 profile 地址、主/备用 20 MB 下载端点。报告写入 `/var/lib/cfip-sidecar/diagnostics/`，不包含 profile 地址、凭据或 profile hash。诊断结果只用于定位瓶颈，不更新 DNS、PassWall、冠军池或稳定池。

## 故障排查

查看主日志：

```sh
tail -n 120 /root/cf-dns-speedup/run.log
```

查看 cron 输出：

```sh
cat /tmp/cf-dns-speedup.cron.log
```

查看结果文件：

```sh
cat /root/cf-dns-speedup/result.csv
```

如果下载速度一直是 `0.00`，优先检查测速 URL：

```sh
curl -L --connect-timeout 6 --max-time 30 -o /dev/null \
  -w 'http=%{http_code} size=%{size_download} speed=%{speed_download}\n' \
  '你的测速URL'
```

如果返回 `403`、`404` 或只下载几百字节，说明 URL 不适合作为 `cfst` 下载测速地址。

## 回滚

更新前建议备份：

```sh
mkdir -p /root/openwrt-backup
cp -a /root/cf-dns-speedup /root/openwrt-backup/cf-dns-speedup-before-change-$(date +%F-%H%M%S)
```

只回滚配置：

```sh
cp /root/openwrt-backup/你的备份/config.env /root/cf-dns-speedup/config.env
chmod 600 /root/cf-dns-speedup/config.env
```

## 仓库隐私

当前仓库是公开仓库：

```text
https://github.com/greentraceifm/cf-dns-speedup
```

别人可以看到代码和文档，但看不到你的真实 Cloudflare Token。真实密钥只应保存在 OpenWrt 本机的 `config.env`。

如果改成私有仓库，公开一键安装命令会失效，需要额外配置 GitHub 认证拉取。

## 与原项目功能对齐

## 当前无停机运行方式（2026-07-18）

本节覆盖前文旧的 06:30 停代理示例。无人值守的 06:30 和 15:30 停代理任务已经禁用；无人值守配置必须保持 `CFST_ALLOW_PROXY_STOP=0`。

当前安全流程是：Sidecar 独立出口观察，导出通过两轮 HTTP 和硬性 6.5 MB/s 门槛的脱敏候选；路由器只写 staging 队列；先运行私有回环 Xray 的 `canary-plan`，再在明确窗口运行独立 canary。独立 canary 不停止、重启或切换现有 PassWall。

候选必须有三个不同日期和三个不同 Sidecar 导出批次的通过记录，才进入竞争池。进入稳定池或更新 `auto` 之前，仍必须通过现有真实 PassWall 6.5 MB/s 门控。直连或 Sidecar 速度高，不能单独触发 DNS 更新。

保留：

- 中文菜单。
- 安装/变更配置/立即执行/查看日志。
- Cloudflare 官方 IP 优选。
- CDN 反代 IP 库优选。
- 反代 IP 国家/地区识别。
- IPv4 / IPv6 选择。
- 端口选择。
- 下载测速地址配置。
- `cfst` 实时测速输出。
- 域名解析推送 / IP 直接输出。
- 多个优选 IP 解析到一个域名。
- 每个优选 IP 解析到每个域名。
- 更新 Cloudflare DNS 记录。
- 删除指定域名的 Cloudflare A/AAAA 记录。
- Passwall、Passwall2、SSR-Plus、Clash、OpenClash、Bypass、V2raya、Hello-World、Homeproxy、MihomoTProxy、ShellCrash 代理插件停启。
- Telegram 通知。
- PushPlus 通知。

安全修正：

- 不使用 Cloudflare Global API Key。
- 不使用混淆安装器。
- 真实更新和删除 DNS 前可用 `DRY_RUN=1` 预演。
- `cfst` 有总超时，避免卡死。
- 代理插件停启有超时和日志提示。
- 日志不再被 `cfst` 实时进度刷屏。
