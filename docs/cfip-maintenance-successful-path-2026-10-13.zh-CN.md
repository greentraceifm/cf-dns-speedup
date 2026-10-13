# CFIP 成功维护链路固化记录（2026-10-13）

记忆标记：`CFIP-MAINTENANCE-SUCCESSFUL-PATH-20261013`

## 固定入口

本机使用：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-CfipReadonlyAudit.ps1
```

从项目目录运行。脚本只读地依次调用：

1. 本机严格 SSH 到 `.140`，执行 `/home/ubuntu/.openclaw/tools/cfip-maintenance-readonly.sh`，由 `.140` 再通过 `ollama-server` SSH 别名连接 `.110` 并调用固定 root-only 审计。
2. 调用 `/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh --check` 验证 VM36 专用密钥。
3. 将 UTF-8 无 BOM、LF 的只读审计脚本编码后，经 `.140` 上的 `cfip-vm36-ssh.sh --stdin` 传给 VM36；输出自然同步、cron、锁、Xray/监听、槽位三路 DNS、默认与 SOCKS HTTP 探测及残留进程。

脚本使用固定本机 `.140` 密钥和 `known_hosts`，启用 `StrictHostKeyChecking=yes`、`BatchMode=yes`，不读密码、不接受密码回退。远端工具或 SSH 返回非零即停止。它不启动 Sidecar/扫描/同步，不修改 Cloudflare、DNS、cron、服务或 VM。脚本不做 Cloudflare API GET；需要 API 权威记录复核时，另按审核过的只读流程执行。

## 关键纠错

`.110` 的 sudo 白名单属于 `.110` 上的 `ollama` 账户。以下命令：

```sh
sudo -n /usr/local/sbin/cfip-maintenance-audit
```

只能由 `.140` 的 `cfip-maintenance-readonly.sh` 经 `ollama-server` SSH 在 `.110` 执行。不得在 `.140` 本机直接运行。直接在 `.140` 执行会报 `sudo: a password is required`，原因是目标主机错误；这**不能**证明手册丢失、`.110` sudo 授权失效或生产链路异常。

遇到授权错误时，先确认主机和被调用的固定入口。入口调用错误时改用本机固定 PowerShell 入口重跑一次；若正确入口仍返回认证失败，再停止并记录阶段。不得猜密码、读旧密码文件、任意登录 `.110`、绕过 `.140` 或放宽主机校验。

## 2026-10-13 实跑验证

- `.140` 严格 SSH 成功；`.110` 固定审计成功；VM36 `VM36_KEY_AUTH=PASS`。
- `.110` Sidecar Result=success、timer active/enabled；报告 5 行、导出 3 行；无 Xray 残留、瞬时容器或 `cfip-direct` 附着；三个必要容器 healthy，Ollama 空闲。
- VM36 自然同步报告为 `already_present`；唯一 04:35 cron 存在；同步、candidate gate、主项目锁空闲。
- VM36 Xray 与 `1070/1041/11400/15353` 监听正常；`auto` 至 `auto4` 在本地、`.1`、`1.1.1.1` 答案一致；Google/YouTube 默认及 SOCKS 探测均 HTTP 204；无 CFIP 残留进程。
- `.110` 直连 Google/YouTube 超时，但其直连路径不等于 VM36 代理路径，不判为生产代理故障。

没有修改生产配置或服务。此记录不保存任何密码、Token、私钥或完整配置。
