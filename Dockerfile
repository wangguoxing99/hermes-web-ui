FROM python:3.11-slim

# 设置环境变量
ENV HERMES_HOME=/hermes
ENV PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"
ENV NPM_CONFIG_PREFIX="${HERMES_HOME}/.npm-global"
ENV PIP_USER=1
ENV PYTHONUSERBASE="${HERMES_HOME}/.local"
# Camoufox 相关环境变量
ENV CAMOUFOX_PORT=9377
ENV CAMOUFOX_BINARY_PATH="${HERMES_HOME}/.local/bin/camoufox"
ENV CAMOUFOX_CONFIG_PATH="${HERMES_HOME}/.cache/camoufox/config.yaml"
ENV BROWSER_TYPE="camoufox"

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    # 基础工具
    curl \
    wget \
    git \
    ca-certificates \
    gnupg \
    # 编译依赖
    build-essential \
    gcc \
    g++ \
    make \
    cmake \
    pkg-config \
    # Python 依赖
    python3-dev \
    libffi-dev \
    libssl-dev \
    # 多媒体处理
    ffmpeg \
    ripgrep \
    # 音频处理依赖（语音功能需要）
    portaudio19-dev \
    libsndfile1-dev \
    libpulse-dev \
    # 图片处理（扫码、二维码）
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libwebp-dev \
    # 文件类型检测
    libmagic-dev \
    # Camoufox 浏览器系统依赖
    libnss3 \
    libnspr4 \
    libatk1.0-0t64 \
    libatk-bridge2.0-0t64 \
    libcups2t64 \
    libdrm2 \
    libdbus-1-3 \
    libxkbcommon0 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxrandr2 \
    libgbm1 \
    libpango-1.0-0 \
    libcairo2 \
    libasound2t64 \
    libatspi2.0-0t64 \
    libwayland-client0 \
    libgtk-3-0 \
    libdbus-glib-1-2 \
    libxss1 \
    # 终端和字体支持
    xterm \
    fonts-noto-color-emoji \
    fonts-wqy-microhei \
    fonts-dejavu-core \
    fontconfig \
    # 其他工具
    procps \
    htop \
    vim \
    less \
    netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# 安装 Node.js 24.x
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 验证版本
RUN node --version && npm --version

# 创建 hermes 用户和目录
RUN useradd -m -d ${HERMES_HOME} -s /bin/bash hermes \
    && mkdir -p ${HERMES_HOME}/projects \
    && mkdir -p ${HERMES_HOME}/.local/bin \
    && mkdir -p ${HERMES_HOME}/.npm-global \
    && mkdir -p ${HERMES_HOME}/.cache/camoufox \
    && mkdir -p ${HERMES_HOME}/.hermes \
    && mkdir -p ${HERMES_HOME}/.hermes-web-ui \
    && chown -R hermes:hermes ${HERMES_HOME}

# 切换到 hermes 用户
USER hermes
WORKDIR ${HERMES_HOME}

# 安装 uv
RUN pip install --user uv

# 克隆 hermes-agent 项目（单独步骤，利用 Docker 缓存）
RUN git clone https://github.com/NousResearch/hermes-agent.git ${HERMES_HOME}/projects/hermes-agent

# 进入项目目录
WORKDIR ${HERMES_HOME}/projects/hermes-agent

# 先安装核心依赖
RUN uv pip install --user -e .

# 再安装所有可选依赖 [all]，带容错回退
RUN uv pip install --user -e ".[all]" || \
    (echo "=== [all] install failed, trying key subsets ===" && \
     uv pip install --user -e ".[browser]" && \
     uv pip install --user -e ".[voice]" && \
     uv pip install --user -e ".[search]" && \
     uv pip install --user -e ".[messaging]" && \
     echo "=== Subset install completed ===")

# 恢复工作目录
WORKDIR ${HERMES_HOME}

# 安装 Camoufox Python 包
RUN pip install --user camoufox[geoip]

# 下载 Camoufox 浏览器
RUN python -m camoufox fetch

# 安装 Camoufox CLI
RUN npm install -g camoufox-cli \
    && camoufox-cli install --with-deps 2>/dev/null || true

# 更新 npm 并全局安装 hermes-web-ui
RUN npm install -g npm@latest \
    && npm install -g hermes-web-ui

# 创建软链接
RUN ln -s ${HERMES_HOME}/projects/hermes-agent/hermes ${HERMES_HOME}/.local/bin/hermes-agent \
    && ln -s ${HERMES_HOME}/.npm-global/bin/hermes-web-ui ${HERMES_HOME}/.local/bin/hermes-web-ui

# ============================================================
# 内置启动脚本
# ============================================================
RUN printf '%s\n' \
    '#!/bin/bash' \
    'set -e' \
    '' \
    'echo "=== Hermes Full Stack Container ==="' \
    'echo "Node.js version: $(node --version)"' \
    'echo "npm version: $(npm --version)"' \
    'echo "Python version: $(python --version)"' \
    'echo "Camoufox browser: $(camoufox --version 2>/dev/null || echo installed)"' \
    '' \
    '# 初始化必要目录' \
    'mkdir -p /hermes/.hermes' \
    'mkdir -p /hermes/.hermes-web-ui' \
    'mkdir -p /hermes/.cache/camoufox' \
    '' \
    '# 检查 Camoufox 浏览器是否已下载' \
    'if [ ! -f "${CAMOUFOX_BINARY_PATH}" ] && [ ! -f "/hermes/.local/bin/camoufox" ]; then' \
    '    echo "Camoufox browser not found, downloading..."' \
    '    python -m camoufox fetch 2>/dev/null || \' \
    '    camoufox-cli install 2>/dev/null || \' \
    '    echo "Warning: Camoufox auto-install failed, please run manually"' \
    'else' \
    '    echo "Camoufox browser found at ${CAMOUFOX_BINARY_PATH}"' \
    'fi' \
    '' \
    '# 如果首次启动，自动配置 Hermes Agent' \
    'if [ ! -f "/hermes/.hermes/config.yaml" ]; then' \
    '    echo "First startup — initializing Hermes Agent..."' \
    '    hermes-agent setup --non-interactive || true' \
    'fi' \
    '' \
    'echo "Starting Hermes Web UI on port ${PORT:-8648}..."' \
    'echo "Dashboard URL: http://localhost:${PORT:-8648}"' \
    '' \
    'exec hermes-web-ui start --port ${PORT:-8648}' \
    > ${HERMES_HOME}/start.sh \
    && chmod +x ${HERMES_HOME}/start.sh

# 暴露端口
EXPOSE 8648
# Camoufox 调试端口
EXPOSE 9377

# 持久化数据卷
VOLUME ["/hermes/.hermes", "/hermes/.hermes-web-ui", "/hermes/.cache"]

# 健康检查
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=3 \
    CMD curl -f http://localhost:8648/health || exit 1

ENTRYPOINT ["/bin/bash", "/hermes/start.sh"]
