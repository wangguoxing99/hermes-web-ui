FROM ubuntu:24.04
ENV UI_PORT=8648
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV UV_INSTALL_DIR="/tools/bin"
ENV UV_PYTHON_INSTALL_DIR="/tools/uv/python"
ENV UV_CACHE_DIR="/tools/uv/cache"
ENV UV_TOOL_DIR="/tools/uv/tools"
ENV PATH="$UV_INSTALL_DIR:$PATH"
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

# 补充了 OCR、PDF解析、解压工具及图像处理底层依赖 libgl1
RUN apt update -y && \
    apt dist-upgrade -y && \
    apt install -y vim screen htop iotop iftop curl ca-certificates lsof npm \
    git ripgrep ffmpeg build-essential python3-dev libffi-dev sudo \
    libgtk-3-0 libglib2.0-0 libx11-6 libxrender1 libxext6 libdbus-1-3 \
    unzip zip jq wget poppler-utils tesseract-ocr tesseract-ocr-chi-sim libgl1 && \
    apt clean && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 直接配置镜像并安装 Node 24
RUN npm config set registry https://registry.npmmirror.com && \
    npm install -g n && \
    n 24

RUN curl -LsSf https://astral.sh/uv/install.sh | sh

RUN cd /usr/local/lib && \
    git clone --depth 1 https://ghfast.top/https://github.com/NousResearch/hermes-agent.git || \
    git clone --depth 1 https://gitclone.com/github.com/NousResearch/hermes-agent.git || \
    git clone --depth 1 https://ghproxy.net/https://github.com/NousResearch/hermes-agent.git

RUN git config --global url."https://ghfast.top/https://github.com".insteadOf "https://github.com"

# 临时取消 Playwright 镜像，使用 GitHub 的海外网络直接秒下官方包
RUN cd /usr/local/lib/hermes-agent && \
    export PLAYWRIGHT_DOWNLOAD_HOST="" && \
    bash scripts/install.sh && \
    /tools/bin/uv run python -m playwright install chromium || true && \
    rm -rf /root/.cache /root/.npm

# 预装常用的 Python 扩展库（爬虫、数据、图像、PDF解析等），供插件和 Skill 调用
RUN cd /usr/local/lib/hermes-agent && \
    /tools/bin/uv pip install \
    requests httpx aiohttp beautifulsoup4 lxml \
    numpy pandas pillow opencv-python-headless \
    pyyaml python-dotenv pydantic pdfplumber PyMuPDF

# 创建 hermes 用户并配置免密 sudo
RUN useradd -m -s /bin/bash hermes && chown -R hermes:hermes /home/hermes && chmod 700 /home/hermes && \
    echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes && \
    chmod 0440 /etc/sudoers.d/hermes && \
    usermod -aG systemd-timesync hermes

# 对 tools 赋权给 hermes 用户
RUN chown -R hermes:hermes /tools && \
    chmod 755 /tools/bin -R

# 启动脚本：增加 sudo chown 自动修复宿主机挂载目录的权限问题
RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'sudo chown -R hermes:hermes /home/hermes' >> /entrypoint.sh && \
    echo 'hermes-web-ui start $UI_PORT && sleep infinity' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# 预装全局 Node.js 常用依赖，并安装 hermes-web-ui
RUN npm root -g && npm install -g hermes-web-ui axios cheerio dotenv && \
    chmod 777 /usr/local/lib/node_modules/hermes-web-ui/dist && \
    chmod -R 755 /usr/local/lib/node_modules

# 切换为 hermes 身份运行容器
WORKDIR /home/hermes
VOLUME /home/hermes
USER hermes
EXPOSE 8648

CMD ["/entrypoint.sh"]
