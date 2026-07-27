# PassWall runtime 配置生成 fixture 门控记录

## 本阶段边界

- 目标仅为验证 ImmortalWrt `25.12.1` / PassWall `26.7.1-r1` 在 disabled 状态下能否隔离生成临时 Xray runtime 配置。
- 未读取或再次传输生产 PassWall 配置，未访问或修改 `.254`。
- 未执行 `apk update`、安装、升级、PassWall 启动、Xray 启动、防火墙变更或生产切换。
- 测试输入为只含虚构地址和虚构凭据的 fixture。

## 只读审计结论

- staging 使用 `apk-tools 3.0.5`，没有 `opkg`。
- 已安装 `luci-app-passwall 26.7.1-r1` 和 `xray-core 26.3.27-r1`。
- 当前本地 APK 索引只显示已安装版本，尚未证明存在高于生产 Xray `26.6.27` 的可验证候选包。
- `app.sh run_socks ... no_run=1` 会生成配置且不调用 Xray、不启动进程、不进入防火墙 `start` 路径。
- 该函数在 `no_run=1` 时可能因末尾条件表达式返回 `1`；门控只在生成文件非空且 `xray run -test` 成功时接受返回码 `0/1`。
- 当前 LuCI `luci.model.uci` 是固定读取 `/etc/config` 的 ubus 代理，不能切换配置目录。测试工具只在私有副本中改用原生 UCI 游标，并以 `foreach` 等价实现唯一的 `get_first()` 读取。

## fixture 兼容修正

结构迁移 fixture 有意包含旧式/边界写法，不能直接作为 PassWall 26.7.1 runtime fixture：

- `protocol 'VMess'` 在私有副本中正规化为 schema 要求的 `vmess`。
- 两条 `list alpn` 在私有副本中正规化为逗号分隔的 `option alpn 'h2,http/1.1'`。

这些修正只作用于虚构 runtime fixture，没有修改结构迁移器，也不能替代对真实配置字段的后续核验。

## 实际验收结果

```text
RUNTIME_FIXTURE_STATUS=success
RUNTIME_FIXTURE_BYTES=2684
RUNTIME_FIXTURE_XRAY_VERSION=26.3.27
RUNTIME_FIXTURE_GENERATOR_RC=1
RUNTIME_FIXTURE_XRAY_TEST=success
RUNTIME_FIXTURE_XRAY_PROCS=0
RUNTIME_FIXTURE_HAPROXY_PROCS=0
RUNTIME_FIXTURE_TARGET_LISTENERS=0
RUNTIME_FIXTURE_SYSTEM_TMP=absent
```

运行后复核：

- staging PassWall UCI 仍为 `enabled=0`，init 仍 disabled。
- Xray 和 HAProxy 进程均为 0。
- `1070/1041/11400/15353` 监听均为 0。
- `/tmp/etc/passwall` 未创建。
- 输入目录和一次性工作目录均无残留。

## 当前结论与停止点

隔离 runtime 生成机制已经通过 fixture 门控，但这不等于真实生产配置兼容性验收，也不批准启动 staging PassWall 或切换 `.254`。

下一硬阻塞仍是 staging Xray `26.3.27` 低于生产 `26.6.27`。下一阶段只能先独立解决版本校验：取得架构、签名、来源和依赖均可验证的 `x86_64` Xray 候选，或以不安装的临时测试二进制完成静态兼容验证。未经单独授权，不更新 APK 索引、不安装包、不再次传输真实配置。
