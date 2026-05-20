FROM python:3.11-slim

# 设置环境变量
ENV HERMES_HOME=/hermes
ENV PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"
ENV NPM_CONFIG_PREFIX="${HERMES_HOME}/.npm-global"
ENV PIP_USER=1
ENV PYTHONUSERBASE="${HERMES_HOME}/.local"
# Camoufox 相关环境变量（浏览器按需安装，此处仅预设路径）
ENV CAMOUFOX_PORT=9377
ENV CAMOUFOX_BINARY_PATH="${HERMES_HOME}/.local/bin/camoufox"
ENV CAMOUFOX_CONFIG_PATH="${HERMES_HOME}/.cache/camoufox/config.yaml"
ENV BROWSER_TYPE="camoufox"
# 时区设置（默认上海，可通过 -e TZ=xxx 覆盖）
ENV TZ=Asia/Shanghai

# 安装系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl wget git ca-certificates gnupg \
    build-essential gcc g++ make cmake pkg-config \
    python3-dev libffi-dev libssl-dev \
    ffmpeg ripgrep \
    portaudio19-dev libsndfile1-dev libpulse-dev \
    libjpeg-dev libpng-dev libtiff-dev libwebp-dev \
    libmagic-dev \
    libnss3 libnspr4 libatk1.0-0t64 libatk-bridge2.0-0t64 \
    libcups2t64 libdrm2 libdbus-1-3 libxkbcommon0 \
    libxcomposite1 libxdamage1 libxfixes3 libxrandr2 \
    libgbm1 libpango-1.0-0 libcairo2 libasound2t64 \
    libatspi2.0-0t64 libwayland-client0 libgtk-3-0 \
    libdbus-glib-1-2 libxss1 \
    xterm fonts-noto-color-emoji fonts-wqy-microhei \
    fonts-dejavu-core fontconfig \
    tzdata procps htop vim less netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# 配置时区
RUN ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime \
    && echo "${TZ}" > /etc/timezone

# 安装 Node.js 24.x
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

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

# 克隆 hermes-agent 项目
RUN git clone https://github.com/NousResearch/hermes-agent.git ${HERMES_HOME}/projects/hermes-agent

WORKDIR ${HERMES_HOME}/projects/hermes-agent

# 安装核心依赖
RUN pip install --user -e .

# 安装 [all] 可选依赖，带容错
RUN pip install --user -e ".[all]" || \
    (echo "=== [all] install failed, trying key subsets ===" && \
     pip install --user -e ".[browser]" && \
     pip install --user -e ".[voice]" && \
     pip install --user -e ".[search]" && \
     pip install --user -e ".[messaging]" && \
     echo "=== Subset install completed ===")

WORKDIR ${HERMES_HOME}

# 安装 Camoufox Python 包（仅接口库，不含浏览器二进制文件）
RUN pip install --user camoufox[geoip]

# 更新 npm 并全局安装 hermes-web-ui
RUN npm install -g npm@latest \
    && npm install -g hermes-web-ui

# 创建软链接
RUN ln -sf ${HERMES_HOME}/.local/bin/hermes ${HERMES_HOME}/.local/bin/hermes-agent \
    && ln -sf ${HERMES_HOME}/.npm-global/bin/hermes-web-ui ${HERMES_HOME}/.local/bin/hermes-web-ui

# ============================================================
# 内置启动脚本（逐行 echo，最可靠的方式）
# ============================================================
RUN echo '#!/bin/bash' > /hermes/start.sh && \
    echo 'set -e' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo '# 根据环境变量动态设置时区' >> /hermes/start.sh && \
    echo 'if [ -n "${TZ}" ]; then' >> /hermes/start.sh && \
    echo '    echo "Setting timezone to ${TZ}..."' >> /hermes/start.sh && \
    echo '    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime' >> /hermes/start.sh && \
    echo '    echo "${TZ}" > /etc/timezone' >> /hermes/start.sh && \
    echo 'fi' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo 'echo "=== Hermes Full Stack Container ==="' >> /hermes/start.sh && \
    echo 'echo "Timezone: $(cat /etc/timezone) ($(date +%Z))"' >> /hermes/start.sh && \
    echo 'echo "Node.js version: $(node --version)"' >> /hermes/start.sh && \
    echo 'echo "npm version: $(npm --version)"' >> /hermes/start.sh && \
    echo 'echo "Python version: $(python --version)"' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo '# 初始化必要目录' >> /hermes/start.sh && \
    echo 'mkdir -p /hermes/.hermes' >> /hermes/start.sh && \
    echo 'mkdir -p /hermes/.hermes-web-ui' >> /hermes/start.sh && \
    echo 'mkdir -p /hermes/.cache/camoufox' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo '# 检查 Camoufox 浏览器是否已安装' >> /hermes/start.sh && \
    echo 'if [ ! -f "/hermes/.local/bin/camoufox" ]; then' >> /hermes/start.sh && \
    echo '    echo "=========================================="' >> /hermes/start.sh && \
    echo '    echo " Camoufox browser not found."' >> /hermes/start.sh && \
    echo '    echo " Install manually in container:"' >> /hermes/start.sh && \
    echo '    echo "   python -m camoufox fetch"' >> /hermes/start.sh && \
    echo '    echo "   or: camoufox-cli install"' >> /hermes/start.sh && \
    echo '    echo "=========================================="' >> /hermes/start.sh && \
    echo 'fi' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo '# 首次启动初始化' >> /hermes/start.sh && \
    echo 'if [ ! -f "/hermes/.hermes/config.yaml" ]; then' >> /hermes/start.sh && \
    echo '    echo "First startup — initializing Hermes Agent..."' >> /hermes/start.sh && \
    echo '    hermes-agent setup --non-interactive || true' >> /hermes/start.sh && \
    echo 'fi' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo 'echo "Starting Hermes Web UI on port ${PORT:-8648}..."' >> /hermes/start.sh && \
    echo 'echo "Dashboard URL: http://localhost:${PORT:-8648}"' >> /hermes/start.sh && \
    echo '' >> /hermes/start.sh && \
    echo 'exec hermes-web-ui start --port ${PORT:-8648}' >> /hermes/start.sh

# 给脚本加执行权限
RUN chmod +x /hermes/start.sh

# 验证脚本确实生成了
RUN echo "=== Verifying start.sh ===" && \
    ls -la /hermes/start.sh && \
    echo "=== Script content (first 5 lines) ===" && \
    head -5 /hermes/start.sh && \
    echo "=== Script content (last 5 lines) ===" && \
    tail -5 /hermes/start.sh

EXPOSE 8648
EXPOSE 9377

VOLUME ["/hermes/.hermes", "/hermes/.hermes-web-ui", "/hermes/.cache"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8648/health || exit 1

ENTRYPOINT ["/bin/bash", "/hermes/start.sh"]
