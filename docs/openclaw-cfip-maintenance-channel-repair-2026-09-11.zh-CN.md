# OpenClaw CFIP 维护通道修复记录（2026-09-11）

## 结论

CFIP 生产链路正常，问题仅在 root-only 维护审计工具：旧执行器从 ssh_ollama.expect 提取历史 sudo 密码，并通过 sudo -S 执行。该密码已不能通过当前 .110 校验，导致审计返回 incorrect password attempt。

本次没有修改 Sidecar、PassWall、Docker、Ollama、DNS、Cloudflare、cron 或 VM。

## 已完成

- 从 OpenClaw 记忆确认正确 SSH 入口为 ollama-server，严格主机密钥校验。
- 确认 .140 到 .110 的 SSH 公钥登录正常。
- 在 .140 安装 /home/ubuntu/.openclaw/tools/cfip-maintenance-readonly.sh，权限 0700。
- 新工具不读取 ssh_ollama.expect，不保存或输出密码，只使用严格 SSH 别名和 sudo -n。
- 旧工具若存在已保留为 cfip-maintenance-readonly.sh.pre-20260911。
- .140 入口已修正为只调用固定命令 /usr/local/sbin/cfip-maintenance-audit；不再尝试 sudo -n sh -s，避免超出 .110 的最小 sudo 白名单。

## 当前阻塞

.110 当前 sudo -n 返回：sudo: a password is required。

这说明 SSH 密钥通道可用，但 ollama 用户没有免密执行 root 审计命令的权限。新工具按安全设计直接失败，不回退到过期密码，也不猜测密码。

用户执行安装器后，固定审计授权安装成功；随后第一次远程调用因 .140 入口仍调用 sudo -n sh -s 而失败。入口已改为直接调用固定审计命令，第二次完整审计成功。

成功审计结果：Sidecar Result=success，timer active/enabled，报告 5 行、导出 3 行，无 Xray 残留、无瞬时容器、cfip-direct 附着 0；sub2api、PostgreSQL、Redis 均 running/healthy，Docker PID 1144，Ollama 无驻留模型。.110 直连 Google/YouTube 仍为 HTTP 000 超时，但这不是安装或 Sidecar 失败。

## 永久修复选项

### 选项 A：恢复受保护密码源

由管理员在授权环境更新 .140 的维护凭据来源，并确认该凭据可验证 .110 的 sudo。之后旧密码执行器应废弃，新工具作为唯一入口。

### 选项 B：最小范围 NOPASSWD 审计入口

在 .110 上由 root 创建一个固定、root-owned、不可由 ollama 修改的只读审计包装器，只输出 Sidecar 状态、报告元数据、容器健康摘要、锁和网络状态；在 /etc/sudoers.d/ 只允许 ollama 无密码执行这一个固定包装器。禁止允许任意 sh -s、任意脚本路径或完整 root shell。

该选项需要一次管理员 root 操作，当前不能自动实施，因为现有密码和 root SSH 授权均未验证成功。

## 手工恢复后验收

在 .110 管理员授权完成后，只需在 .140 执行一次：

ssh -o BatchMode=yes -o StrictHostKeyChecking=yes ollama-server 'sudo -n id -u'

只有返回 0 才继续 CFIP root-only 只读审计。若失败，继续保持现状，不重试生产任务，不修改 DNS 或 Cloudflare。

## 收口判断

CFIP 项目本身已收口：最新自然同步为 already_present，五槽去重、三路 DNS、Cloudflare 只读 GET、PassWall 和四监听均正常。剩余工作是维护授权的单点修复，不能通过继续排查业务代码解决。
