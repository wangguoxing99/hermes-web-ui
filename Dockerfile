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

# 修复点 3: 避免直接删除 /root，改为清理具体的缓存目录
RUN curl -fsSL https://ghproxy.net/https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh -o install.sh && \
    sed -i 's/\$UV_CMD pip install -e ".\\[all\\]"/\$UV_CMD pip install -e "."/' install.sh && \
    sed -i '/^main() {/,/^}/ s/install_node_deps/#install_node_deps/' install.sh && \
    bash install.sh && \
    rm -rf /root/.cache /root/.npm

# 修复点 1: 先创建 hermes 用户，然后再执行 chown
RUN useradd -m -s /bin/bash hermes && chown -R hermes:hermes /home/hermes && chmod 700 /home/hermes && \
    echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes && \
    chmod 0440 /etc/sudoers.d/hermes && \
    usermod -aG systemd-timesync hermes

# 创建完用户后，现在可以安全地对 /tools 进行赋权了
RUN chown -R hermes:hermes /tools && \
    chmod 755 /tools/bin -R

RUN echo '#!/bin/bash' > /entrypoint.sh && \
    echo 'sudo chown -R hermes:hermes /home/hermes' >> /entrypoint.sh && \
    echo 'hermes-web-ui start $UI_PORT && sleep infinity' >> /entrypoint.sh && \
    chmod +x /entrypoint.sh

# 修复点 4: 在切换为非 root 用户前，直接用 root 身份安装全局 npm 包，避免 PATH 丢失问题
RUN npm root -g && npm install -g hermes-web-ui && \
    chmod 777 /usr/local/lib/node_modules/hermes-web-ui/dist

# 切换为普通用户身份并暴露端口
WORKDIR /home/hermes
VOLUME /home/hermes
USER hermes
EXPOSE 8648

CMD ["/entrypoint.sh"]
