# OpenClaw-China-Docker (alpha-gou维护版)



本项目源于：https://github.com/justlovemaki/openclaw-china-docker



## 新特性

- openclaw 升级为最新正式版（2026.6.1）
- 镜像构建时支持国内环境，在阿里云服务器上运行良好。（对于window、linux可能不支持）
- 新增 Caddy HTTPS 反向代理（默认启用）：对外只暴露加密 443，默认关闭明文 18789，公网/内网访问更安全。**注意**：需要在 `.env` 配置 `CADDY_IP`（公网服务器填公网 IP，且要与客户端实际访问地址一致），未配置会导致 `caddy` 容器启动失败。用不到 HTTPS 时可注释掉 `docker-compose.yml` 中的 `caddy` service 并还原网关明文端口。详见 [HTTPS 反向代理](docs/caddy-https.md)。

## 项目简介

OpenClaw 的国内环境 Docker 一键部署方案（alpha-gou 维护版），基于 [justlikemaki/openclaw-china-docker](https://github.com/justlovemaki/openclaw-china-docker) 二次维护。

- 将命令行 AI 助手 OpenClaw 打包为可直接运行的 Docker 服务，提供 Web 控制台与多种 IM 渠道机器人（Telegram / 飞书 / 钉钉 / 企业微信 / QQ / NapCat）。
- 面向中国大陆环境优化：使用国内 Debian / 阿里云 / npmmirror 镜像源，在阿里云 ECS 上开箱即用。
- 内置 Caddy HTTPS 反向代理，对外仅暴露加密 443、默认关闭明文 18789，保护网关鉴权与对话流量不被抓包。

## 使用方式

前置条件：已安装 Docker 与 Docker Compose。

### 1. 获取代码

```bash
git clone <本仓库地址>
cd openclaw-china-docker
```

### 2. 准备镜像（二选一）

**A. 使用预构建镜像（最省事，`.env` 默认即此）**

```bash
docker compose pull
```

**B. 自行构建镜像**

```bash
# 默认最新版
docker build -t justlikemaki/openclaw-docker-cn-im:latest .

# 指定 OpenClaw 版本
docker build --build-arg OPENCLAW_VERSION=2026.6.1 -t justlikemaki/openclaw-docker-cn-im:latest .

# 可选：带 clawhub 登录 token 以拉取私有扩展
docker build --build-arg CLAWHUB_TOKEN=你的token -t justlikemaki/openclaw-docker-cn-im:latest .
```

> 自行构建时镜像 tag 必须与 `.env` 中 `OPENCLAW_IMAGE` 一致，否则 compose 会去拉取远端镜像而非使用本地构建结果。

### 3. 配置环境变量

```bash
cp .env.example .env
```

至少配置以下几项：

| 变量 | 说明 |
| --- | --- |
| `MODEL_ID` / `BASE_URL` / `API_KEY` | 默认模型 ID、模型服务地址、模型密钥 |
| `OPENCLAW_GATEWAY_TOKEN` | Web 控制台登录 token |
| `CADDY_IP` | 客户端实际访问的 IP（公网服务器填公网 IP，且与访问地址一致）；未配置会导致 `caddy` 容器启动失败 |

> 完整可选项见 [`.env.example`](.env.example)，IM 渠道（飞书/钉钉/企微/QQ/Telegram/NapCat）按需填写。

### 4. 启动容器

```bash
docker compose up -d
```

查看日志 / 停止：

```bash
docker compose logs -f
docker compose down
```

### 5. 访问服务

```bash
https://<CADDY_IP>
```

- 浏览器首次访问会有自签证书警告，安装 Caddy 根证书可消除（见 [HTTPS 反向代理](docs/caddy-https.md)）。
- 明文 `18789` 已绑 `127.0.0.1`，仅本机可达；需要明文兜底时走 SSH 隧道：`ssh -L 18789:127.0.0.1:18789 user@host`。

更多细节见 [快速开始](docs/quick-start.md) 与 [配置指南](docs/configuration.md)。



