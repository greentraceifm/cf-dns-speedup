# cf-dns-speedup

Cloudflare 优选 IP 自动更新脚本，面向 OpenWrt 使用。

这是对原 `cdnopw` 思路的安全修正版：尽量保留中文菜单和原项目使用流程，只修正关键风险和容易卡死的问题。

## 修正内容

- 保留中文交互菜单。
- 保留“安装/变更配置/立即执行/域名清理/卸载”的主流程。
- 去除混淆代码，不使用 `eval` 和多层 `base64 | bash`。
- 使用 Cloudflare API Token，不使用 Global API Key。
- `cfst` 增加总超时，避免测速阶段无限卡死。
- 测速时保留 `cfst` 实时输出，可以看到进度和速度，同时写入日志。
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

主菜单：

```text
1. 安装/首次配置
2. 变更参数配置
3. 立即执行优选并更新 DNS
4. 域名清理（安全版暂不自动批量删除 DNS）
5. 卸载脚本
6. 查看当前配置
7. 查看运行日志
0. 退出
```

变更参数配置菜单：

```text
1. 切换推送模式（安全版固定为域名解析推送）
2. 切换 CDN IP 来源（安全版固定为官方 IP 列表）
3. 切换域名解析方案（安全版固定为单记录更新）
4. 切换优选 IPv4 / IPv6
5. 更换端口
6. 开启、关闭测速，更换测速网站
7. 更换代理插件（安全版不自动控制代理插件）
8. 更改 cfst 总超时时间、线程、结果数量
9. 更换 Cloudflare 解析域名
10. 更换 Cloudflare API Token / Zone ID
11. 通知配置（暂未实现，避免保存第三方 token）
12. 切换 DRY_RUN 安全测试模式
13. 查看当前配置
14. 返回主菜单
```

## 首次使用流程

1. 运行一键安装命令。
2. 选择 `1. 安装/首次配置`。
3. 输入 Cloudflare API Token、Zone ID、完整解析域名。
4. 首次保持 `DRY_RUN=1`。
5. 选择 `3. 立即执行优选并更新 DNS`。
6. 查看日志，确认出现 `dry-run: would update ...`。
7. 回到菜单，选择 `12. 切换 DRY_RUN 安全测试模式`，切换为 `DRY_RUN=0`。
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

## 与原项目功能差异

当前版本不是完全等价复刻，而是“保留主流程 + 修正高风险点”的安全版。

保留：

- 中文菜单。
- 安装/变更配置/立即执行/查看日志。
- Cloudflare 官方 IP 优选。
- IPv4 / IPv6 选择。
- 端口选择。
- 下载测速地址配置。
- `cfst` 实时测速输出。
- 更新 Cloudflare DNS 记录。

暂不保留或改为手动：

- 不自动停止或重启 PassWall、OpenClash 等代理插件。
- 不自动批量删除 Cloudflare DNS 记录。
- 不保存 Telegram、PushPlus 等第三方通知 token。
- 不使用 Cloudflare Global API Key。
- 不使用混淆安装器。

如果你确认某个旧功能确实需要，我会逐项加回，但会加超时、确认提示和回滚保护。

如果测速仍然慢或容易失败，建议在菜单里把参数调保守：

```text
测速线程：16
结果数量：3
总超时：600
测速网站：留空，只做延迟优选
```
