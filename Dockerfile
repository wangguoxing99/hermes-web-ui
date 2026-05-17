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
ENV PLAYWRIGHT_DOWNLOAD_HOST=https://npmmirror.com/mirrors/playwright

RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources && \
    sed -i 's|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt update -y && \
    apt dist-upgrade -y && \
    apt install -y vim screen htop iotop iftop curl ca-certificates lsof npm \
    git ripgrep ffmpeg build-essential python3-dev libffi-dev sudo \
    libgtk-3-0 libglib2.0-0 libx11-6 libxrender1 libxext6 libdbus-1-3 && \
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

# 核心修改点：执行完整的官方 install.sh（移除sed删减操作），并补充 Playwright 的 Chromium 浏览器内核
RUN curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o install.sh && \
    bash install.sh && \
    cd /usr/local/lib/hermes-agent && \
    /tools/bin/uv run playwright install chromium && \
    rm -rf /root/.cache /root/.npm

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

# 在 root 环境下全局安装 hermes-web-ui 避免权限和依赖丢失
RUN npm root -g && npm install -g hermes-web-ui && \
    chmod 777 /usr/local/lib/node_modules/hermes-web-ui/dist

# 切换为 hermes 身份运行容器
WORKDIR /home/hermes
VOLUME /home/hermes
USER hermes
EXPOSE 8648

CMD ["/entrypoint.sh"]
