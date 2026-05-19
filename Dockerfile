# 使用轻量级的 Python 3.11 镜像
FROM python:3.11-slim-bookworm

# ==========================================
# 1. 安装系统基础依赖、无头浏览器依赖、扫码图像依赖 & Node.js 24
# ==========================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    sudo \
    build-essential \
    procps \
    # 【浏览器依赖】Camoufox / Playwright / Puppeteer 运行所需的底层动态库
    libnss3 libnspr4 libatk1.0-0 libatk-bridge2.0-0 libcups2 libdrm2 libdbus-1-3 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libasound2 libcairo2 libpango-1.0-0 libx11-xcb1 xvfb \
    # 【交互与视觉依赖】扫码登录、终端二维码展示、OpenCV 图像处理支持库
    libgl1 libglib2.0-0 libzbar0 qrencode \
    # 安装 Node.js 24
    && curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    # 安装 uv (Python极速包管理器)
    && curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# ==========================================
# 2. 创建无密码的 hermes 用户并授予免密 sudo
# ==========================================
RUN useradd -m -s /bin/bash hermes \
    && echo "hermes ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# ==========================================
# 3. 环境变量配置 (强制依赖和缓存写入用户目录，实现持久化)
# ==========================================
ENV HOME=/home/hermes
ENV WORKDIR=$HOME/hermes
# 收束包管理器路径到持久化目录下
ENV NPM_CONFIG_PREFIX=$HOME/.npm-global
ENV PYTHONUSERBASE=$HOME/.local
ENV UV_CACHE_DIR=$HOME/.cache/uv
ENV PIP_USER=yes
# 确保安装的 CLI 插件可以直接全局调用
ENV PATH=$HOME/.local/bin:$HOME/.npm-global/bin:$PATH

# ==========================================
# 4. 准备项目备份 (防止外部挂载空目录导致代码被覆盖隐藏)
# ==========================================
RUN mkdir -p /opt/hermes_backup
COPY --chown=hermes:hermes ./hermes-agent /opt/hermes_backup/hermes-agent
COPY --chown=hermes:hermes ./hermes-web-ui /opt/hermes_backup/hermes-web-ui

# ==========================================
# 5. 创建全局软连接/启动脚本 (无需绝对路径启动)
# ==========================================
RUN mkdir -p /usr/local/bin

# 启动 Agent (后端)
RUN echo '#!/bin/bash\n\
cd $WORKDIR/hermes-agent || exit 1\n\
echo "Starting Hermes Agent..."\n\
uv run python run_agent.py "$@"' > /usr/local/bin/start-agent && \
chmod +x /usr/local/bin/start-agent

# 启动 Web UI (前端)
RUN echo '#!/bin/bash\n\
cd $WORKDIR/hermes-web-ui || exit 1\n\
echo "Starting Hermes Web UI..."\n\
npm install\n\
npm run dev "$@"' > /usr/local/bin/start-ui && \
chmod +x /usr/local/bin/start-ui

# 统一启动脚本 (包含智能目录恢复)
RUN echo '#!/bin/bash\n\
if [ ! -d "$WORKDIR/hermes-agent" ]; then\n\
    echo "Host directory seems empty. Restoring projects from backup..."\n\
    cp -a /opt/hermes_backup/* $WORKDIR/\n\
fi\n\
start-agent & \n\
start-ui & \n\
wait -n' > /usr/local/bin/start-all && \
chmod +x /usr/local/bin/start-all

# ==========================================
# 6. 配置工作目录及权限
# ==========================================
RUN mkdir -p $WORKDIR && chown -R hermes:hermes $HOME
WORKDIR $WORKDIR

# 切换为 hermes 身份运行
USER hermes

# 预创建缓存和依赖目录，确保外部挂载接管时所有权属于 hermes 且结构正确
RUN mkdir -p $HOME/.npm-global/bin $HOME/.local/bin $HOME/.cache/uv $HOME/.camoufox

EXPOSE 3000 8000

CMD ["start-all"]
