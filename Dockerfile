FROM ubuntu:24.04
ENV UI_PORT=8648
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV UV_INSTALL_DIR="/tools/bin"
ENV UV_PYTHON_INSTALL_DIR="/tools/uv/python"
ENV UV_CACHE_DIR="/tools/uv/cache"
ENV UV_TOOL_DIR="/tools/uv/tools"
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
    pyyaml python-dotenv pydantic pdfplumber PyMuPDF huggingface_hub

RUN npm root -g && npm install -g hermes-web-ui axios cheerio dotenv

# 将整个 venv 移动到 /opt 备用
RUN mv /usr/local/lib/hermes-agent/.venv /opt/venv-backup

RUN useradd -m -s /bin/bash hermes && chown -R hermes:hermes /home/hermes && chmod 700 /home/hermes && \
    echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes && \
    chmod 0440 /etc/sudoers.d/hermes && \
    usermod -aG systemd-timesync hermes

RUN chown -R hermes:hermes /tools && \
    chown -R hermes:hermes /usr/local/lib/hermes-agent && \
    chown -R hermes:hermes /usr/local/lib/node_modules/hermes-web-ui && \
    chown -R hermes:hermes /opt/venv-backup

# 【修改点】：重写入口脚本，加入备份时间变量支持
RUN cat <<'EOF' > /entrypoint.sh
#!/bin/bash

# --- 1. 修复挂载目录与虚拟环境 ---
sudo chown -R hermes:hermes /home/hermes

if [ ! -d "/home/hermes/agent-venv" ]; then
    echo "📦 正在初始化持久化 Python 虚拟环境..."
    cp -a /opt/venv-backup /home/hermes/agent-venv
fi
sudo rm -rf /usr/local/lib/hermes-agent/.venv
sudo ln -s /home/hermes/agent-venv /usr/local/lib/hermes-agent/.venv
sudo chown -h hermes:hermes /usr/local/lib/hermes-agent/.venv

# --- 2. 变量配置 ---
BACKUP_NAME="hermes_full_backup.tar.gz"
REPO_ID="$HF_DATASET_ID"
LOG_FILE="/home/hermes/.hermes-web-ui/server.log"

# 读取自定义备份时间（分钟），如果未设置则默认 10 分钟
BACKUP_INTERVAL_MINUTES=${BACKUP_INTERVAL:-10}
BACKUP_INTERVAL_SECONDS=$((BACKUP_INTERVAL_MINUTES * 60))

export NODE_NO_WARNINGS=1

# --- 3. 启动时：全量恢复 ---
if [ -n "$REPO_ID" ]; then
    echo "🔄 正在从 Dataset 恢复数据: $REPO_ID..."
    python3 << END_PY
from huggingface_hub import hf_hub_download
import os
try:
    hf_hub_download(repo_id='$REPO_ID', filename='$BACKUP_NAME', repo_type='dataset', local_dir='.')
    print('✅ 下载备份成功。')
except Exception as e:
    print(f'⚠️ 未发现初始备份或下载失败: {e}')
END_PY
    if [ -f "$BACKUP_NAME" ]; then
        echo "📦 正在执行全量数据恢复..."
        tar -xzf "$BACKUP_NAME" -C /home/hermes/
        rm "$BACKUP_NAME"
        echo "✅ 恢复完成。"
    fi
fi

# --- 4. 运行中：定时执行备份 ---
if [ -n "$REPO_ID" ] && [ -n "$HF_TOKEN" ]; then
    (
      while true; do
        sleep $BACKUP_INTERVAL_SECONDS
        echo "⏳ --- 正在执行定时全量备份 (间隔: ${BACKUP_INTERVAL_MINUTES} 分钟) ---"
        # 排除掉虚拟环境等无需备份的大文件，减小包体积
        tar -czf "/tmp/$BACKUP_NAME" -C /home/hermes \
            --exclude='agent-venv' \
            --exclude='.cache' \
            --exclude='.npm' \
            .
        
        python3 << END_PY
from huggingface_hub import HfApi
import os
api = HfApi()
try:
    api.upload_file(
        path_or_fileobj='/tmp/$BACKUP_NAME',
        path_in_repo='$BACKUP_NAME',
        repo_id='$REPO_ID',
        repo_type='dataset',
        token=os.environ.get('HF_TOKEN')
    )
    print('✅ 全量备份同步完成。')
except Exception as e:
    print(f'❌ 同步失败: {e}')
END_PY
      done
    ) &
fi

# --- 5. 启动服务 ---
echo "🚀 正在启动 Hermes Web UI..."
mkdir -p /home/hermes/.hermes-web-ui
touch "$LOG_FILE"

# 兼容原本脚本中的 WEBUI_TOKEN 变量
if [ -n "$WEBUI_TOKEN" ]; then
    export AUTH_TOKEN="$WEBUI_TOKEN"
fi

hermes-web-ui start $UI_PORT &

# --- 6. 容器保活 ---
tail -f "$LOG_FILE"
EOF

# 兼容 Windows 换行符导致的报错
RUN sed -i 's/\r$//' /entrypoint.sh && \
    chmod +x /entrypoint.sh

WORKDIR /home/hermes
VOLUME /home/hermes
USER hermes
EXPOSE 8648

CMD ["/entrypoint.sh"]
