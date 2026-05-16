# cf-dns-speedup

Cloudflare 优选 IP 自动更新脚本，面向 OpenWrt 使用。

这是对原 `cdnopw` 思路的安全修正版：尽量保留中文菜单和原项目使用流程，只修正关键风险和容易卡死的问题。

## 修正内容

- 保留中文交互菜单。
- 保留“安装/变更配置/立即执行/域名清理/卸载”的主流程。
- 去除混淆代码，不使用 `eval` 和多层 `base64 | bash`。
- 使用 Cloudflare API Token，不使用 Global API Key。
- `cfst` 增加总超时，避免测速阶段无限卡死。
- 测速时保留 `cfst` 实时输出，可以看到进度和速度；交互终端保持同一行刷新，主日志只记录关键步骤。
- 默认 `DRY_RUN=1`，首次运行只测试，不修改 DNS。
- 不自动停止或重启 PassWall、OpenClash 等代理插件，避免路由器断网。
- 不自动批量删除 Cloudflare DNS 记录，避免误删解析。

## 一键安装

推荐安装命令：

```sh
curl -fsSL https://raw.githubusercontent.com/greentraceifm/cf-dns-speedup/main/install-openwrt.sh | sh
```

如果 GitHub raw 缓存还没刷新，用固定最新版：

```sh
curl -fsSL https://raw.githubusercontent.com/greentraceifm/cf-dns-speedup/dc48384337a3d7578d6678d0a9c1349f72f29a22/install-openwrt.sh | sh
```

安装完成后会自动打开中文菜单。

以后再次打开菜单：

```sh
/root/cf-dns-speedup/menu.sh
```

## 中文菜单

主菜单已经尽量保持原项目风格：

```text
1.安装/重置脚本
2.更改各项参数配置
3.运行一次已配置完成的脚本
4.删除CF域名指定名称解析记录
5.卸载
6.查看运行日志
0. 退出
```

变更参数配置菜单：

```text
1. 切换推送模式（域名解析推送 / IP 直接推送）
2. 切换 CDN IP 来源（官方 IP / 反代 IP）
3. 切换域名解析方案（多 IP 到一域名 / 每 IP 到每域名）
4. 切换优选 IPv4 或 IPv6
5. 更换端口
6. 开启、关闭测速，更换测速网站
7. 更换 OpenWrt 代理插件
8. 更改测速线程、显示数量、总超时、代理重启等待时间
9. 更换 Cloudflare 解析域名
10. 更换 Cloudflare API Token / Zone ID
11. 关闭、开启 Telegram 通知，更换 Token、用户 ID
12. 切换 Telegram API 接口域名
13. 关闭、开启 PushPlus 微信通知，更换 Token
14. 切换 DRY_RUN 安全测试模式
15. 查看当前配置
0. 返回主菜单
```

## 首次使用流程

1. 运行一键安装命令。
2. 选择 `1. 安装/首次配置`。
3. 输入 Cloudflare API Token、Zone ID、完整解析域名。
4. 首次保持 `DRY_RUN=1`。
5. 选择 `3. 立即执行优选并更新 DNS`。
6. 查看日志，确认出现 `dry-run: would update ...`。
7. 回到菜单，选择 `14. 切换 DRY_RUN 安全测试模式`，切换为 `DRY_RUN=0`。
8. 再次执行，才会真实更新 Cloudflare DNS。

## Cloudflare Token 权限

请创建 Cloudflare API Token，不要使用 Global API Key。

建议权限：

- `Zone:Read`
- `DNS:Edit`
- 作用范围只限制在目标域名 Zone

## 配置文件

真实配置保存在 OpenWrt：

```sh
/root/cf-dns-speedup/config.env
```

不要把真实的 `config.env` 上传到 GitHub。

## 定时任务

每天凌晨 3 点执行：

```cron
0 3 * * * /root/cf-dns-speedup/cf-dns-speedup.sh >/tmp/cf-dns-speedup.cron.log 2>&1
```

## 仓库隐私

当前仓库是公开仓库：

```text
https://github.com/greentraceifm/cf-dns-speedup
```

别人可以看到代码和文档，但看不到你的真实 Cloudflare Token。真实密钥只应保存在 OpenWrt 本机的 `config.env`。

如果改成私有仓库，公开一键安装命令会失效，需要额外配置 GitHub 认证拉取。

## 故障排查

查看日志：

```sh
cat /root/cf-dns-speedup/run.log
```

`run.log` 只记录关键步骤、优选结果和 DNS 更新过程。手动运行菜单时，`cfst` 进度会在终端同一行刷新；定时任务等非交互运行时，`cfst` 原始输出会写入：

```sh
cat /root/cf-dns-speedup/cfst-output.log
```

## 与原项目功能对齐

当前版本目标是保留原项目的功能和菜单，同时修正关键风险。

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

仍然建议首次保持 `DRY_RUN=1`，确认日志无误后再切换为 `DRY_RUN=0`。

如果测速仍然慢或容易失败，建议在菜单里把参数调保守：

```text
测速线程：16
结果数量：3
总超时：600
测速网站：留空，只做延迟优选
```
