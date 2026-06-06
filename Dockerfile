# OpenClaw Docker 镜像
# FROM node:22-slim
FROM docker.m.daocloud.io/node:22-slim

# 从 国内镜像源 拷贝 Python 3.12 (确保使用与 node 镜像一致的 Debian Bookworm 版本)
# COPY --from=python:3.12-slim-bookworm /usr/local /usr/local
COPY --from=docker.m.daocloud.io/python:3.12-slim-bookworm /usr/local /usr/local

# 设置工作目录
WORKDIR /app

# 设置环境变量
ENV BUN_INSTALL="/usr/local" \
    PATH="/usr/local/bin:$PATH" \
    DEBIAN_FRONTEND=noninteractive

# 1. 环境安装
# 第一阶段：换源和基础更新
RUN rm -f /etc/apt/sources.list.d/* && \
    echo "deb http://mirrors.ustc.edu.cn/debian/ bookworm main contrib non-free non-free-firmware" > /etc/apt/sources.list && \
    echo "deb http://mirrors.ustc.edu.cn/debian-security/ bookworm-security main contrib non-free non-free-firmware" >> /etc/apt/sources.list && \
    apt-get update

# 第二阶段：安装基础工具
RUN apt-get install -y --no-install-recommends \
    bash \
    ca-certificates \
    curl \
    git \
    locales \
    openssh-client \
    procps \
    unzip \
    jq \
    socat \
    tini \
    gosu \
    build-essential \
    docker.io

# 第三阶段：安装多媒体和字体
RUN apt-get install -y --no-install-recommends \
    ffmpeg \
    fonts-liberation \
    fonts-noto-cjk \
    fonts-noto-color-emoji

# 第四阶段：Chromium 单独安装（容易出问题）
RUN apt-get install -y --no-install-recommends chromium

# 第五阶段：Locale 配置
RUN sed -i 's/^# *en_US.UTF-8 UTF-8$/en_US.UTF-8 UTF-8/' /etc/locale.gen && \
    locale-gen && \
    printf 'LANG=en_US.UTF-8\nLANGUAGE=en_US:en\nLC_ALL=en_US.UTF-8\n' > /etc/default/locale

# 第六阶段：Git 和 NPM 配置
RUN git config --system url."https://github.com/".insteadOf ssh://git@github.com/ && \
    npm config set registry https://registry.npmmirror.com

# 第七阶段：Node.js 工具安装（单独一层，便于缓存）
RUN npm install -g openclaw@2026.5.28 opencode-ai@latest clawhub playwright playwright-extra puppeteer-extra-plugin-stealth @steipete/bird

# 第八阶段：安装运行时工具
# RUN curl -fsSL https://bun.sh/install | BUN_INSTALL=/usr/local bash && \
    # curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh
RUN npm install -g bun && \
    ln -sf /usr/local/bin/python3 /usr/local/bin/python && \
    /usr/local/bin/python3 -m pip install --break-system-packages --index-url https://mirrors.aliyun.com/pypi/simple/ uv && \
    /usr/local/bin/python3 -m pip install --no-cache-dir --index-url https://mirrors.aliyun.com/pypi/simple/ websockify

# 第九阶段：QMD
RUN npm install -g @tobilu/qmd@1.1.6

# 第十阶段：Playwright
RUN CHROMIUM_REV=1223 && \
    CFT_VER=148.0.7778.96 && \
    TARGET_DIR=/root/.cache/ms-playwright/chromium-${CHROMIUM_REV} && \
    mkdir -p ${TARGET_DIR}/chrome-linux64 && \
    cd /tmp && \
    curl -fL \
      "https://cdn.npmmirror.com/binaries/chrome-for-testing/${CFT_VER}/linux64/chrome-linux64.zip" \
      -o chrome.zip && \
    unzip -q chrome.zip && \
    # 把解压后的内容放到 playwright 期望的位置
    cp -r chrome-linux64/* ${TARGET_DIR}/chrome-linux64/ && \
    # 写入标记文件（playwright 靠这个判断 installed）
    date > ${TARGET_DIR}/INSTALLATION_COMPLETE && \
    rm -rf /tmp/chrome.zip /tmp/chrome-linux64

# 验证（可选，build 阶段就能提前暴露问题）
RUN npx playwright install-deps chromium || true

# 第十一阶段：清理
RUN apt-get purge -y --auto-remove && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /root/.npm /root/.cache

# 2. 插件安装（作为 node 用户以避免后期权限修复带来的镜像膨胀）
RUN mkdir -p /home/node/.openclaw/workspace /home/node/.openclaw/extensions && \
    chown -R node:node /home/node

USER node
ENV HOME=/home/node
WORKDIR /home/node

# 安装linuxbrew（Homebrew 的 Linux 版本），并配置环境变量
RUN mkdir -p /home/node/.linuxbrew/Homebrew && \
    git clone --depth 1 https://github.com/Homebrew/brew /home/node/.linuxbrew/Homebrew && \
    mkdir -p /home/node/.linuxbrew/bin && \
    ln -s /home/node/.linuxbrew/Homebrew/bin/brew /home/node/.linuxbrew/bin/brew && \
    chown -R node:node /home/node/.linuxbrew && \
    chmod -R g+rwX /home/node/.linuxbrew

ARG CLAWHUB_TOKEN
RUN if [ -n "$CLAWHUB_TOKEN" ]; then clawhub login --token "$CLAWHUB_TOKEN"; fi && \
  cd /home/node/.openclaw/extensions && \
#   git clone --depth 1 -b v4.17.25 https://github.com/Daiyimo/openclaw-napcat.git napcat && \
  git clone --depth 1 https://github.com/Daiyimo/openclaw-napcat.git napcat && \
  cd napcat && \
  npm install --production && \
  timeout 300 openclaw plugins install --dangerously-force-unsafe-install -l . || true && \
  cd /home/node/.openclaw/extensions && \
#   timeout 300 openclaw plugins install --dangerously-force-unsafe-install @soimy/dingtalk || true && \
  timeout 300 openclaw plugins install --dangerously-force-unsafe-install @openclaw/qqbot || true && \
#   timeout 300 openclaw plugins install --dangerously-force-unsafe-install @sunnoy/wecom || true && \
  mkdir -p /home/node/.openclaw /home/node/.openclaw-seed && \
  # 预执行安装命令（容器内需手动交互，此处仅作声明或环境准备）
  #  printf '{\n  "channels": {\n    "feishu": {\n      "enabled": false,\n      "appId": "2222222222222222",\n      "appSecret": "1111111111111111",\n      "accounts": {\n        "default": {\n          "appId": "2222222222222222",\n          "appSecret": "1111111111111111",\n          "name": "OpenClaw Bot"\n        }\n      }\n    }\n  }\n}\n' > /home/node/.openclaw/openclaw.json && \
  # npx -y @larksuite/openclaw-lark-tools install && \
  find /home/node/.openclaw/extensions -name ".git" -type d -exec rm -rf {} + && \
  mv /home/node/.openclaw/extensions /home/node/.openclaw-seed/ && \
  printf '%s\n' '2026.5.28-f1' > /home/node/.openclaw-seed/extensions/.seed-version && \
  rm -rf /tmp/* /home/node/.npm /home/node/.cache
  
# 3. 最终配置
USER root

# 复制初始化脚本并确保换行符为 LF
COPY ./init.sh /usr/local/bin/init.sh
RUN sed -i 's/\r$//' /usr/local/bin/init.sh && \
    chmod +x /usr/local/bin/init.sh

# 设置环境变量
ENV HOME=/home/node \
    TERM=xterm-256color \
    NODE_PATH=/usr/local/lib/node_modules \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    NODE_ENV=production \
    PATH="/home/node/.linuxbrew/bin:/home/node/.linuxbrew/sbin:/usr/local/lib/node_modules/.bin:${PATH}" \
    HOMEBREW_NO_AUTO_UPDATE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1

# 暴露端口
EXPOSE 18789

# 设置工作目录为 home
WORKDIR /home/node

# 使用初始化脚本作为入口点
ENTRYPOINT ["/bin/bash", "/usr/local/bin/init.sh"]
