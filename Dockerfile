FROM python:3.11-slim

# 基础环境变量，主目录改为 /home/hermes
ENV HERMES_HOME=/home/hermes
ENV PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"
ENV NPM_CONFIG_PREFIX="${HERMES_HOME}/.npm-global"
ENV PIP_USER=1
ENV PYTHONUSERBASE="${HERMES_HOME}/.local"
ENV CAMOUFOX_PORT=9377
ENV TZ=Asia/Shanghai

# 系统依赖（完整）
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

# 时区
RUN ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && echo "${TZ}" > /etc/timezone

# Node.js 24
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# 创建 hermes 用户（家目录为 /home/hermes）及所有子目录
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

# 安装 uv，克隆并安装 hermes-agent
RUN pip install --user uv
RUN git clone https://github.com/NousResearch/hermes-agent.git ${HERMES_HOME}/projects/hermes-agent

WORKDIR ${HERMES_HOME}/projects/hermes-agent
RUN pip install --user -e .
RUN pip install --user -e ".[all]" || \
    (echo "=== [all] install failed, trying subsets ===" && \
     pip install --user -e ".[browser]" && \
     pip install --user -e ".[voice]" && \
     pip install --user -e ".[search]" && \
     pip install --user -e ".[messaging]" && \
     echo "=== Subset install completed ===")

WORKDIR ${HERMES_HOME}
RUN pip install --user camoufox[geoip]
RUN npm install -g npm@latest hermes-web-ui

# 软链接
RUN ln -sf ${HERMES_HOME}/.local/bin/hermes ${HERMES_HOME}/.local/bin/hermes-agent \
    && ln -sf ${HERMES_HOME}/.npm-global/bin/hermes-web-ui ${HERMES_HOME}/.local/bin/hermes-web-ui

# 切回 root 打包并放置启动脚本
USER root

# 打包 /home/hermes 目录，压缩包放在根下
RUN tar czf /hermes.tar.gz -C /home hermes

# 启动脚本（路径全部使用 /home/hermes）
RUN cat > /usr/local/bin/start.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

HERMES_HOME=/home/hermes

# 动态时区
if [ -n "${TZ}" ]; then
    echo "Setting timezone to ${TZ}..."
    ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime 2>/dev/null || \
        echo "Warning: Cannot change timezone (permission denied). Using default."
    echo "${TZ}" > /etc/timezone 2>/dev/null || true
fi

echo "=== Hermes Full Stack Container ==="
echo "Timezone: $(cat /etc/timezone 2>/dev/null || echo 'unknown')"
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"

# 首次挂载检测：若 /home/hermes/.local 目录为空则解压
if [ ! -d "${HERMES_HOME}/.local" ] || [ -z "$(ls -A ${HERMES_HOME}/.local 2>/dev/null)" ]; then
    echo ">>> Initializing ${HERMES_HOME} from built-in archive..."
    tar xzf /hermes.tar.gz -C /home
    chown -R hermes:hermes ${HERMES_HOME}
    echo ">>> Extraction complete."
fi

# 确保必要目录
mkdir -p ${HERMES_HOME}/.hermes ${HERMES_HOME}/.hermes-web-ui ${HERMES_HOME}/.cache/camoufox

# 环境
export PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"

# 确定 hermes 命令
if [ -x "${HERMES_HOME}/projects/hermes-agent/hermes" ]; then
    HERMES_CMD="${HERMES_HOME}/projects/hermes-agent/hermes"
else
    HERMES_CMD="hermes"
fi

# 首次设置 Agent
if [ ! -f "${HERMES_HOME}/.hermes/config.yaml" ]; then
    echo "First startup — initializing Hermes Agent..."
    $HERMES_CMD setup --non-interactive || true
fi

# 提示 Camoufox 浏览器
if [ ! -f "${HERMES_HOME}/.local/bin/camoufox" ]; then
    echo "=========================================="
    echo " Camoufox browser not found."
    echo " Install manually in container:"
    echo "   python -m camoufox fetch"
    echo "=========================================="
fi

echo "Starting Hermes Web UI on port ${PORT:-8648}..."
# 后台启动（不退出）
hermes-web-ui start --port ${PORT:-8648}
sleep 2
echo "Dashboard URL: http://localhost:${PORT:-8648}"

# 保活
echo "Container stay-alive mode..."
exec tail -f /dev/null
SCRIPT_EOF

RUN chmod +x /usr/local/bin/start.sh

EXPOSE 8648 9377
VOLUME ["/home/hermes"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8648/health || exit 1

ENTRYPOINT ["/usr/local/bin/start.sh"]
