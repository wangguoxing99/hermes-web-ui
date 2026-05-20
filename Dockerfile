FROM python:3.11-slim

ENV HERMES_HOME=/home/hermes
ENV PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"
ENV NPM_CONFIG_PREFIX="${HERMES_HOME}/.npm-global"
ENV PIP_USER=1
ENV PYTHONUSERBASE="${HERMES_HOME}/.local"
ENV CAMOUFOX_PORT=9377
ENV TZ=Asia/Shanghai

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

RUN ln -sf /usr/share/zoneinfo/${TZ} /etc/localtime && echo "${TZ}" > /etc/timezone

RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

RUN useradd -m -d ${HERMES_HOME} -s /bin/bash hermes \
    && mkdir -p ${HERMES_HOME}/projects \
    && mkdir -p ${HERMES_HOME}/.local/bin \
    && mkdir -p ${HERMES_HOME}/.npm-global \
    && mkdir -p ${HERMES_HOME}/.cache/camoufox \
    && mkdir -p ${HERMES_HOME}/.hermes \
    && mkdir -p ${HERMES_HOME}/.hermes-web-ui \
    && chown -R hermes:hermes ${HERMES_HOME}

USER hermes
WORKDIR ${HERMES_HOME}

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

RUN ln -sf ${HERMES_HOME}/.local/bin/hermes ${HERMES_HOME}/.local/bin/hermes-agent \
    && ln -sf ${HERMES_HOME}/.npm-global/bin/hermes-web-ui ${HERMES_HOME}/.local/bin/hermes-web-ui

USER root
RUN tar czf /hermes.tar.gz -C /home hermes

RUN cat > /usr/local/bin/start.sh << 'SCRIPT_EOF'
#!/bin/bash
set -e

HERMES_HOME=/home/hermes

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

if [ ! -d "${HERMES_HOME}/.local" ] || [ -z "$(ls -A ${HERMES_HOME}/.local 2>/dev/null)" ]; then
    echo ">>> Initializing ${HERMES_HOME} from built-in archive..."
    tar xzf /hermes.tar.gz -C /home
    chown -R hermes:hermes ${HERMES_HOME}
    echo ">>> Extraction complete."
fi

mkdir -p ${HERMES_HOME}/.hermes ${HERMES_HOME}/.hermes-web-ui ${HERMES_HOME}/.cache/camoufox

export PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"

# 自动修复 hermes 命令
if ! command -v hermes >/dev/null 2>&1; then
    echo ">>> Hermes command not found, auto-installing..."
    cd ${HERMES_HOME}/projects/hermes-agent
    pip install --user -e . 2>&1 | tail -5
    cd ${HERMES_HOME}
    ln -sf ${HERMES_HOME}/.local/bin/hermes ${HERMES_HOME}/.local/bin/hermes-agent 2>/dev/null
    export PATH="${HERMES_HOME}/.local/bin:${HERMES_HOME}/.npm-global/bin:${PATH}"
    echo ">>> Hermes Agent installed."
fi

if [ ! -f "${HERMES_HOME}/.hermes/config.yaml" ]; then
    echo "First startup — initializing Hermes Agent..."
    hermes setup --non-interactive || true
fi

if [ ! -f "${HERMES_HOME}/.local/bin/camoufox" ]; then
    echo "=========================================="
    echo " Camoufox browser not found."
    echo " Install manually in container:"
    echo "   python -m camoufox fetch"
    echo "=========================================="
fi

echo "Starting Hermes Web UI on port ${PORT:-8648}..."
hermes-web-ui start --port ${PORT:-8648}
sleep 2
echo "Dashboard URL: http://localhost:${PORT:-8648}"

echo "Container stay-alive mode..."
exec tail -f /dev/null
SCRIPT_EOF

RUN chmod +x /usr/local/bin/start.sh

EXPOSE 8648 9377
VOLUME ["/home/hermes"]

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8648/health || exit 1

ENTRYPOINT ["/usr/local/bin/start.sh"]
