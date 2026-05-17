FROM ubuntu:24.04
ENV UI_PORT=8648
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV UV_INSTALL_DIR="/tools/bin"
ENV UV_PYTHON_INSTALL_DIR="/tools/uv/python"
ENV UV_CACHE_DIR="/tools/uv/cache"
ENV UV_TOOL_DIR="/tools/uv/tools"
# 这里的 PATH 保持原样，因为我们会用软链接让它生效
ENV PATH="/usr/local/lib/hermes-agent/.venv/bin:$UV_INSTALL_DIR:$PATH"
ENV HERMES_AGENT_DIR="/usr/local/lib/hermes-agent"
ENV GATEWAY_ALLOW_ALL_USERS=true
ENV WEIXIN_GROUP_POLICY=open
ENV HERMES_YOLO_MODE=1

RUN mkdir -p /tools/bin && \
    mkdir -p /tools/uv/{python,tools,cache} && \
    chmod -R 777 /tools

# cn only
ENV UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
ENV NPM_CONFIG_REGISTRY="https://registry.npmmirror.com"
ENV PLAYWRIGHT_DOWNLOAD_HOST="https://npmmirror.com/mirrors/playwright"
ENV N_NODE_MIRROR="https://npmmirror.com/mirrors/node"

RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt update -y && \
    apt dist-upgrade -y && \
    apt install -y vim screen htop iotop iftop curl ca-certificates lsof npm \
    git ripgrep ffmpeg build-essential python3-dev python-is-python3 libffi-dev sudo \
    libgtk-3-0 libglib2.0-0 libx11-6 libxrender1 libxext6 libdbus-1-3 \
    unzip zip jq wget poppler-utils tesseract-ocr tesseract-ocr-chi-sim libgl1 && \
    apt clean && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g n && \
    n 24

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN cd /usr/local/lib && \
    git clone --depth 1 https://ghfast.top/https://github.com/NousResearch/hermes-agent.git || \
    git clone --depth 1 https://gitclone.com/github.com/NousResearch/hermes-agent.git || \
    git clone --depth 1 https://ghproxy.net/https://github.com/NousResearch/hermes-agent.git

RUN git config --global url."https://ghfast.top/https://github.com".insteadOf "https://github.com"

RUN cd /usr/local/lib/hermes-agent && \
    export PLAYWRIGHT_DOWNLOAD_HOST="" && \
    bash scripts/install.sh && \
    /tools/bin/uv run python -m playwright install chromium || true && \
    rm -rf /root/.cache /root/.npm

RUN cd /usr/local/lib/hermes-agent && \
    /tools/bin/uv pip install \
    requests httpx aiohttp beautifulsoup4 lxml \
    numpy pandas pillow opencv-python-headless \
    pyyaml python-dotenv pydantic pdfplumber PyMuPDF

RUN npm root -g && npm install -g hermes-web-ui axios cheerio dotenv

# 【关键步骤 1】：安装完所有依赖后，将整个 venv 移动到 /opt 备用
RUN mv /usr/local/lib/hermes-agent/.venv /opt/venv-backup

RUN useradd -m -s /bin/bash hermes && chown -R hermes:hermes /home/hermes && chmod 700 /home/hermes && \
    echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes && \
    chmod 0440 /etc/sudoers.d/hermes && \
    usermod -aG systemd-timesync hermes

# 将所有核心目录（包括刚才备份的 venv）的所有权交给 hermes 用户
RUN chown -R hermes:hermes /tools && \
    chown -R hermes:hermes /usr/local/lib/hermes-agent && \
    chown -R hermes:hermes /usr/local/lib/node_modules/hermes-web-ui && \
    chown -R hermes:hermes /opt/venv-backup

# 【关键步骤 2】：编写智能启动脚本
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'sudo chown -R hermes:hermes /home/hermes' >> /entrypoint.sh && \
    echo 'if [ ! -d "/home/hermes/agent-venv" ]; then' >> /entrypoint.sh && \
    echo '    echo "📦 Initializing persistent Python virtual environment..."' >> /entrypoint.sh && \
    echo '    cp -a /opt/venv-backup /home/hermes/agent-venv' >> /entrypoint.sh && \
    echo 'fi' >> /entrypoint.sh && \
    echo 'sudo rm -rf /usr/local/lib/hermes-agent/.venv' >> /entrypoint.sh && \
    echo 'sudo ln -s /home/hermes/agent-venv /usr/local/lib/hermes-agent/.venv' >> /entrypoint.sh && \
    echo 'sudo chown -h hermes:hermes /usr/local/lib/hermes-agent/.venv' >> /entrypoint.sh && \
    echo 'echo "🚀 Starting Hermes Web UI..."' >> /entrypoint.sh && \
    echo 'hermes-web-ui start $UI_PORT && sleep infinity' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

WORKDIR /home/hermes
VOLUME /home/hermes
USER hermes
EXPOSE 8648

CMD ["/entrypoint.sh"]
