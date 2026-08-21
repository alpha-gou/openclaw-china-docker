# 通过 Caddy 为 OpenClaw 网关提供 HTTPS 访问

## 背景

OpenClaw 网关（`openclaw-gateway`）默认监听 `18789` 端口，对外提供的是**明文 HTTP** 页面和服务。无论是公网还是内网，HTTP 流量都可能被中间人工具（Wireshark、tcpdump 等）窃听——网关鉴权用的 `OPENCLAW_GATEWAY_TOKEN`、控制台会话、对话内容都会以明文暴露，尤其对**公网服务器（如阿里云 ECS）**，暴露在公网上的明文接口风险更高。

本方案在同一个 `docker-compose.yml` 中增加一个 **Caddy** 反向代理容器：

- Caddy 对外只暴露 **HTTPS 443**，用**自签证书**终止 TLS；
- 加密后的请求由 Caddy 转发给 OpenClaw 的明文 HTTP（`18789`，仅存在于 Docker 内部网络）；
- **OpenClaw 侧零改动**，依然监听明文 HTTP，只是不再对网络层可达。

这样访问者只能看到加密流量，无法再直接抓取明文 18789。

## 架构

```
客户端 ──HTTPS:443（Caddy 自签证书）──►  Caddy  ──HTTP:18789（Docker 内部网络）──► openclaw-gateway
                                       │ reverse_proxy openclaw-gateway:18789
                                       └ 对外仅开放 443，80 不映射
```

| 端口 | 宿主绑定 | 说明 |
| --- | --- | --- |
| `443` | `0.0.0.0` | Caddy HTTPS 入口，对外加密访问（公网场景需在云安全组放行） |
| `80` | 不映射 | 强制只走 HTTPS，避免明文入口 |
| `18789` | `127.0.0.1` | OpenClaw 明文网关，仅宿主机 loopback 可达 |

## 公网 IP 与内网 IP：`CADDY_IP` 填哪个

`CADDY_IP` 的值**必须等于客户端浏览器地址栏实际输入的地址**，因为自签证书的 SAN 要能和它匹配：

- **公网服务器（阿里云 ECS 等）→ 填公网 IP**。Caddy 监听在 `0.0.0.0:443`，无论公网 IP 是直接绑 ECS，还是由云端 SLB/NAT 做 DNAT 转发到内网 IP，公网流量都能进来，证书 SAN 填公网 IP 即可对应 `https://公网IP` 的访问。
- **仅内网部署 → 填内网 IP**。

## 涉及的文件

| 文件 | 改动 |
| --- | --- |
| [`caddy/Caddyfile`](../caddy/Caddyfile) | 新增：Caddy 自签证书 + 反代到 `openclaw-gateway:18789` |
| [`docker-compose.yml`](../docker-compose.yml) | 明文 `18789` 改为绑 `127.0.0.1`；新增 `caddy` service（只暴露 443） |
| [`.env.example`](../.env.example) | 新增 `CADDY_IP` / `CADDY_PORT`；`OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 补充 `https://$CADDY_IP` |
| [`.gitignore`](../.gitignore) | 忽略 `caddy_data/`、`caddy_config/`（证书与运行时数据不入库） |

## 首次部署

### 1. 配置环境变量

在项目根目录 `cp .env.example .env` 后，确认以下配置：

```bash
# —— Caddy HTTPS 反向代理 ——
# 对外固定 IP：公网服务器填公网 IP，仅内网访问则填内网 IP。
# 必须与客户端实际访问时输入的地址一致。
CADDY_IP=1.2.3.4
# 宿主机 HTTPS 端口（默认 443，一般不用改）
CADDY_PORT=443
```

同时确认网关的 Origin 白名单里**包含你的 HTTPS 访问地址**，否则浏览器控制台请求可能被网关拦截：

```bash
OPENCLAW_GATEWAY_ALLOWED_ORIGINS=http://localhost:18789,https://1.2.3.4
```

### 2. 放行端口（公网服务器必做）

- 在云厂商安全组放行 TCP `443`（仅暴露这一项对外加密访问即可）。
- 再次确认 **`18789` 不要**对公网开放（本方案已绑 `127.0.0.1`）。

### 3. 启动服务

```bash
docker compose up -d
```

Caddy 首次启动会自动用本地 CA 给 `CADDY_IP` 签发自签证书，并持久化到 `caddy_data/` 目录。

## 导出根证书并安装（消除浏览器警告）

### 为什么必须装根证书

浏览器**永远不会主动信任一段未知的 CA 证书**——这是 TLS 安全模型的基本设计（否则任何人都能伪造证书冒充你的服务器）。

- 不安装根证书时：每次访问 `https://IP` 都会弹「连接不是私密连接 / 不安全」警告，需要手动点「高级 → 仍然访问」。浏览器会**临时放行一段时间，但有期限**，到期再弹。
- 安装根证书后：信任**该 CA 签发的全部证书**，警告**彻底消失**，一劳永逸。

### 1. 导出 Caddy 根证书

在项目根目录执行（`caddy_data` 即 compose 中 `./caddy_data:/data` 的映射）：

```bash
cat caddy_data/pki/authorities/local/root.crt
```

复制输出的整段证书内容（`-----BEGIN CERTIFICATE-----` ... `-----END CERTIFICATE-----`）。也可以直接打开该文件。

### 2. 各平台安装

- **macOS**：双击 `root.crt` 或用「钥匙串访问」打开 → 选「系统」钥匙串 →「证书」表 → 双击该证书 →「信任」展开 →「使用此证书时」选「始终信任」→ 输入密码确认。
- **Windows**：双击 `root.crt` →「安装证书」→ 存储位置选「本地计算机」→「将所有证书都放入下列存储」→「浏览」选「**受信任的根证书颁发机构**」→ 完成。
- **Linux**：
  - Chrome/Chromium：右上角菜单 → 设置 → 隐私和安全 → 安全 → 管理证书 → 证书颁发机构 → 导入。
  - Firefox：设置 → 隐私与安全 → 证书 → 查看证书 → 证书颁发机构 → 导入 → 勾选「信任由此证书颁发机构来标识网站」。
  - 系统级（Ubuntu/Debian）：`sudo cp root.crt /usr/local/share/ca-certificates/openclaw-root.crt && sudo update-ca-certificates`。
- **iOS**：将 `root.crt` 发送到设备打开 → 安装描述文件 → 设置 → 通用 → 关于本机 → 证书信任设置 → 打开该 CA 的「完全信任」开关。
- **Android**：设置 → 安全 → 加密与凭据 → 安装证书 → CA 证书 → 选择 `root.crt`。

> ⚠️ **根证书 = 信任你服务器的钥匙，要像私钥一样保管**。谁拿到 root.crt 并信任它，谁就在替你的服务器做身份背书。
> - 只应把它安装到**你亲自管控、愿意信任的客户端**（团队成员、自己的设备）。
> - **不要**把 root.crt 作为公开文件分发给陌生公网用户，也不要把它提交到公开仓库或分享链接。
> - 一旦怀疑泄露，应重建证书并让受影响客户端重新安装。

## 使用方法

### 正常 HTTPS 访问

```text
https://<CADDY_IP>
```

- 浏览器地址栏**必须带 `https://`**；如果访问 `http://<CADDY_IP>`，因为 80 端口不映射，会直接无法连接（这是有意为之，关闭了明文入口）。
- 输入正确的 `OPENCLAW_GATEWAY_TOKEN` 即可正常使用网关控制台，与控制台交互、机器人回调、流式输出等全部走加密通道。

### SSH 隧道明文兜底（可选）

明文 `18789` 已绑到宿主机 `127.0.0.1`，仅本机进程可达。若某工具需要走原始明文接口（例如某些不认自签证书的本地脚本、调试场景），可在宿主机上建立隧道：

```bash
ssh -L 18789:127.0.0.1:18789 user@<宿主>
# 然后通过本机 http://127.0.0.1:18789 访问明文网关
```

## 验证

```bash
# 1. 服务都在运行
docker compose ps

# 2. HTTPS 可达（-k 临时忽略本地未装证书的警告；公网服务器也可换公网 IP 验证）
curl -vk https://<CADDY_IP>/

# 3. 根证书已生成（供安装）
ls -l caddy_data/pki/authorities/local/root.crt

# 4. 明文端口仅绑 loopback
lsof -iTCP:18789 -sTCP:LISTEN   # 宿主上应显示 127.0.0.1
```

## 常见问题与排障

**Q1：Caddy 证书相关报错 / 访问打不开？**
确认 `CADDY_IP` 已填成客户端实际访问的 IP（公网服务器务必填公网 IP），`.env` 已在项目根目录生效；改完后 `docker compose up -d --force-recreate caddy` 重建。公网还需确认安全组放行 443。

**Q2：原来 `http://IP:18789` 的网络访问连不上了？**
这是预期行为——明文端口已不再对网络暴露。请改用 `https://IP`。需要明文时走上面的 SSH 隧道。

**Q3：换了 IP 后证书还匹配吗？**
需要把 `CADDY_IP` 改成新 IP 并重建 Caddy，让它重新签一张带新 SAN 的证书；同时更新 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS`。设备上已安装的 root.crt 无需重装（根证书不受机器 IP 变化影响）。

**Q4：浏览器反复弹警告？**
多半是本机没装根证书，或证书在 `caddy_data` 被清理后重新生成过。安装根证书即可根除。

**Q5：国内网络拉取 `caddy:2-alpine` 镜像超时？**
将服务镜像改为国内镜像前缀，例如 `docker.m.daocloud.io/library/caddy:2-alpine`。

**Q6：控制台能进但部分请求失败？**
检查 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 是否包含当前的 `https://<CADDY_IP>` Origin，缺少会导致网关拒绝跨源请求。

**Q7：Caddy 和网关重启后证书会变吗？**
不会。`caddy_data/` 已做持久化挂载，CA 与签发的证书不随容器重建而丢失。

**Q8：这个方案适合推向公网陌生用户吗？**
自签证书适合**你自己或团队成员**访问。向陌生公网用户开放时，根证书无法也不应公开分发。理想做法是给这台服务器配一个**域名**（可泛解析到 ECS），把 Caddy 改用 Let's Encrypt 自动申请`浏览器原生信任`的证书——用户无需安装任何根证书。见下文"升级到域名 + 公开证书"。

## 升级到域名 + 公开证书（推荐做公网）

如果你能拿到一个域名（例如 `claw.example.com`，甚至 `*.example.com` 泛解析到本机），Caddy 可改为自动申请受信任证书：

```caddyfile
# caddy/Caddyfile
{
  email 你的邮箱   # 用于 Let's Encrypt 通知
}

https://claw.example.com {
  tls {
    dns <提供商> { token ... }   # 可选：用 DNS 挑战以支持裸 IP/无公网回连
  }
  reverse_proxy openclaw-gateway:18789
}
```

改用域名后：浏览器原生信任证书，客户端**不再需要安装任何根证书**，同时可把 `OPENCLAW_GATEWAY_ALLOWED_ORIGINS` 设为 `https://claw.example.com`。这是公网开放的推荐形态。

> 说明：Let's Encrypt 的 HTTP-01/TLS-ALPN 挑战需要 80/443 能对外回连；若不想开放 80，或需要裸 IP/内网续期，建议给域名配 DNS 挑战（如阿里云 DNS 插件）。

## 卸载 / 回退

```bash
docker compose stop caddy
docker compose rm caddy
```

如需彻底恢复明文可达，还原 `docker-compose.yml` 中 `openclaw-gateway` 的 `ports` 行（去掉 `127.0.0.1:` 前缀），并可删除 `caddy/` 与 `caddy_data/`、`caddy_config/`。

## 相关文档

- [快速开始](quick-start.md)
- [配置指南](configuration.md)
- [故障排查](faq.md)