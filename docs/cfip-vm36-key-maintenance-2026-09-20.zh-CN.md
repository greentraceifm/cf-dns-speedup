# VM36 固定密钥维护入口

## 当前状态

2026-09-20：用户控制台返回 `VM36_KEY_INSTALLED`。**专用密钥入口已恢复并验收，连续三个独立连接均返回 `VM36_KEY_AUTH=PASS`，后续实际只读审计也成功。** 语法检查与非法参数拒绝测试通过。

VM36 授权文件权限为 600；`sysupgrade -l` 包含 `/etc/dropbear/authorized_keys`。临时 HTTP 18080 投递服务及临时防火墙规则已收口，12:46 复核无 18080 监听。没有修改 root 密码或重启生产服务。

入口脚本 SHA256：`00fdce8d1c0a5c9ed6e962dbd1d986f6b709793a257534cf6ce2daeefb024f90`。

该方案取代 VM36 人工维护对 `openwrt-smartdns.env` 密码的依赖，不更改其他项目的密码配置，不修改 `.110` 维护入口。

## 持久设计

- 路径固定：本机 -> `.140` -> VM36 `.254`，不允许跳过 `.140`。
- 私钥只保留在 `.140`：`/home/ubuntu/.ssh/id_ed25519_cfip_vm36_maint`，权限 600。
- 公钥指纹：`SHA256:h6y7kkw5F97H0nGiAf3Im6XC3C/XdQjUNA8KO2hOS48`。
- `.140` 入口：`/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh`。
- 入口隔离默认 SSH 配置，指定专用密钥和既有 known_hosts；禁止密码回退、agent 和连接转发。
- VM36 公钥放在 `/etc/dropbear/authorized_keys`，追加而非覆盖，并禁用该密钥的转发与 PTY。
- root 密码和控制台救援保留，不放宽密码策略，不重启服务。
- 该密钥可执行 root 维护命令，**不是服务器强制只读沙箱**。工具的存在不等于授权任何生产变更；普通审计只执行只读命令，生产变更仍遵守用户授权。

## 已完成的一次性控制台步骤

以下仅作为恢复参考，日常维护不要重复安装，也不要重新开启临时 HTTP 投递服务。

仅在 **VM36 的 root 控制台**执行，不能在 `.140`、VM33 或 Windows PowerShell 执行：

```sh
(
set -eu
k='no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDyOkfRmAdSDmi0s4kH+Q1j/epEANANgK/uVyNsGK7/4 cfip-vm36-maint-20260920'
a=/etc/dropbear/authorized_keys
test "$(id -u)" = 0
test ! -L "$a"
test -d /etc/dropbear
umask 077
if test -f "$a"; then cp -p "$a" "$a.bak-$(date +%Y%m%d-%H%M%S)"; else touch "$a"; fi
grep -qxF "$k" "$a" || printf '\n%s\n' "$k" >> "$a"
chmod 600 "$a"
echo VM36_KEY_INSTALLED
)
```

不使用 `passwd`，不删除旧授权，不重启 Dropbear、PassWall、DNS 或 VM。

## 验收与日常调用

控制台安装后，由维护代理从 `.140` 执行：

```sh
/home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh --check
```

必须连续三个独立连接返回 `VM36_KEY_AUTH=PASS`，再用 `--stdin` 传入已审核的只读脚本，补齐同步/资格/池/锁/监听核验。不能在公钥安装前不断试连。

同时检查 VM36 的配置备份清单包含 `/etc/dropbear/authorized_keys`；只检查、不实际刷机或重启。若不包含，另行收敛处理备份保留问题。正常升级应复用密钥；重建 VM、恢复旧快照、重装 `.140` 或主机密钥变化不在“永远免维护”的保证范围内。

日常先调用此固定入口，不再读取旧密码文件。失败按网络、主机身份、密钥认证、远端命令四类记录，不反复请求同一授权或猜密码。

### Windows 固定调用

本机使用已有 `.140` 维护密钥；不读取其正文。PowerShell 中执行：

```powershell
ssh.exe -F NUL `
  -i C:/Users/Leopold/.ssh/openclaw_fallback_ed25519 `
  -o IdentitiesOnly=yes -o BatchMode=yes `
  -o StrictHostKeyChecking=yes `
  -o UserKnownHostsFile=C:/Users/Leopold/.ssh/known_hosts `
  -o ConnectTimeout=10 `
  ubuntu@192.168.1.140 `
  /home/ubuntu/.openclaw/tools/cfip-vm36-ssh.sh --check
```

多行脚本通过 `--stdin` 传递时，使用 UTF-8、LF 和结尾换行；可先将无秘密脚本编码为 Base64，在 `.140` 解码后通过管道传入固定入口。Base64 仅处理传输格式，不是加密，不能用来记录密码或 Token。

本次 VM36 没有 `stat` 命令，审计改用 `ls -ln`；不为检查权限额外安装软件。远端缺少工具或脚本传输错误应单独报告，不得再次归因于认证失败。

## 回滚

保留现有 root 控制台。在需要撤销新密钥时，只移除带 `cfip-vm36-maint-20260920` 标记的这一行，不覆盖后续其他授权；必要时核对上述时间戳备份。旧密码及其他密钥本方案不动。

不要把私钥放入本地仓库、GitHub、Notion、普通记忆或聊天。灾难恢复时使用既有安全备份或通过控制台重新建立密钥，不以放宽主机校验代替恢复。
