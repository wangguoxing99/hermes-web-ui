FROM ubuntu:24.04

ENV UI_PORT=8648
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# ===== 用户级目录配置 =====
# 所有工具和项目都装在 hermes 家目录下，用户级权限
ENV HERMES_HOME="/home/hermes"
ENV NPM_CONFIG_PREFIX="${HERMES_HOME}/.npm-global"
ENV NPM_CONFIG_CACHE="${HERMES_HOME}/.npm-cache"
ENV NODE_PATH="${NPM_CONFIG_PREFIX}/lib/node_modules"
ENV UV_INSTALL_DIR="${HERMES_HOME}/.local/bin"
ENV UV_PYTHON_INSTALL_DIR="${HERMES_HOME}/.uv/python"
ENV UV_CACHE_DIR="${HERMES_HOME}/.uv/cache"
ENV UV_TOOL_DIR="${HERMES_HOME}/.uv/tools"
ENV HERMES_AGENT_DIR="${HERMES_HOME}/hermes-agent"
ENV PATH="${HERMES_AGENT_DIR}/.venv/bin:${UV_INSTALL_DIR}:${NPM_CONFIG_PREFIX}/bin:${PATH}"
ENV GATEWAY_ALLOW_ALL_USERS=true
ENV WEIXIN_GROUP_POLICY=open
ENV HERMES_YOLO_MODE=1

# cn mirrors (npm registry 保留国内镜像，加速 npm install)
ENV NPM_CONFIG_REGISTRY="https://registry.npmmirror.com"
ENV PLAYWRIGHT_DOWNLOAD_HOST="https://npmmirror.com/mirrors/playwright"
# 如果需要其他国内镜像，取消下面注释
# ENV UV_INDEX_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
# ENV N_NODE_MIRROR="https://npmmirror.com/mirrors/node"

# ===== Step 1: 系统依赖（root 必要） =====
# 如果需要阿里云 apt 镜像，取消下面注释
# RUN sed -i 's|http://archive.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources && \
#     sed -i 's|http://security.ubuntu.com/ubuntu/|http://mirrors.aliyun.com/ubuntu/|g' /etc/apt/sources.list.d/ubuntu.sources

RUN apt update -y && \
    apt dist-upgrade -y && \
    apt install -y \
        curl ca-certificates git sudo vim screen \
        npm build-essential python3-dev python-is-python3 libffi-dev \
        libgtk-3-0 libglib2.0-0 libx11-6 libxrender1 libxext6 libdbus-1-3 \
        libgl1 ffmpeg ripgrep poppler-utils tesseract-ocr tesseract-ocr-chi-sim \
        unzip zip jq wget lsof htop iotop iftop \
    && apt clean && \
    ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ===== Step 2: 创建 hermes 用户 + 用户级目录结构 =====
RUN useradd -m -s /bin/bash hermes && \
    mkdir -p ${HERMES_HOME}/.npm-global \
             ${HERMES_HOME}/.npm-cache \
             ${HERMES_HOME}/.local/bin \
             ${HERMES_HOME}/.uv/python \
             ${HERMES_HOME}/.uv/tools \
             ${HERMES_HOME}/.uv/cache && \
    chown -R hermes:hermes ${HERMES_HOME}

RUN echo "hermes ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/hermes && \
    chmod 0440 /etc/sudoers.d/hermes

# ===== Step 3: 以 hermes 用户安装 Node 24（直接下载二进制包，不用 n 管理器） =====
USER hermes
WORKDIR ${HERMES_HOME}

RUN npm config set prefix "${NPM_CONFIG_PREFIX}" && \
    npm config set cache "${NPM_CONFIG_CACHE}" && \
    npm config set registry "https://registry.npmmirror.com"

# 直接下载 Node 24 二进制包（比用 n 管理器更快更稳）
RUN curl -fsSL https://nodejs.org/dist/v24.15.0/node-v24.15.0-linux-x64.tar.xz | \
    tar -xJ -C ${HERMES_HOME} --strip-components=1 && \
    mkdir -p ${NPM_CONFIG_PREFIX}/bin ${NPM_CONFIG_PREFIX}/lib && \
    mv ${HERMES_HOME}/bin/node ${NPM_CONFIG_PREFIX}/bin/ && \
    mv ${HERMES_HOME}/bin/npm ${NPM_CONFIG_PREFIX}/bin/ && \
    mv ${HERMES_HOME}/bin/npx ${NPM_CONFIG_PREFIX}/bin/ && \
    mv ${HERMES_HOME}/lib/node_modules ${NPM_CONFIG_PREFIX}/lib/ && \
    rm -rf ${HERMES_HOME}/bin ${HERMES_HOME}/lib ${HERMES_HOME}/include ${HERMES_HOME}/share

# 刷新 PATH
ENV PATH="${NPM_CONFIG_PREFIX}/bin:${PATH}"

# ===== Step 4: 以 hermes 用户安装 uv（用户级） =====
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR="${UV_INSTALL_DIR}" sh

# 验证
RUN node --version && npm --version && ${UV_INSTALL_DIR}/uv --version

# ===== Step 5: 克隆 hermes-agent 到用户目录 =====
RUN git config --global url."https://ghfast.top/https://github.com".insteadOf "https://github.com" && \
    git clone --depth 1 https://ghfast.top/https://github.com/NousResearch/hermes-agent.git ${HERMES_AGENT_DIR} || \
    git clone --depth 1 https://gitclone.com/github.com/NousResearch/hermes-agent.git ${HERMES_AGENT_DIR} || \
    git clone --depth 1 https://ghproxy.net/https://github.com/NousResearch/hermes-agent.git ${HERMES_AGENT_DIR}

# ===== Step 6: 安装 hermes-agent（用户级 uv） =====
WORKDIR ${HERMES_AGENT_DIR}

RUN export PLAYWRIGHT_DOWNLOAD_HOST="" && \
    bash scripts/install.sh && \
    ${UV_INSTALL_DIR}/uv run python -m playwright install chromium || true

# ===== Step 7: 用户级 pip 安装常用包 =====
RUN ${UV_INSTALL_DIR}/uv pip install \
    requests httpx aiohttp beautifulsoup4 lxml \
    numpy pandas pillow opencv-python-headless \
    pyyaml python-dotenv pydantic pdfplumber PyMuPDF huggingface_hub

# ===== Step 8: 安装 hermes-web-ui（用户级 npm -g） =====
RUN npm install -g hermes-web-ui axios cheerio dotenv

# 验证
RUN ls -la ${NPM_CONFIG_PREFIX}/bin/hermes-web-ui* && \
    ls -la ${NODE_PATH}/hermes-web-ui/

# ===== Step 9: 清理用户级缓存 =====
RUN rm -rf ${NPM_CONFIG_CACHE}/* ${UV_CACHE_DIR}/* ${HERMES_HOME}/.cache

# ===== Step 10: 入口脚本（内联） =====
USER root
RUN cat > /entrypoint.sh << 'SCRIPT'
#!/bin/bash
sudo chown -R hermes:hermes /home/hermes

BACKUP_NAME="hermes_full_backup.tar.gz"
REPO_ID="$HF_DATASET_ID"
LOG_FILE="/home/hermes/.hermes-web-ui/server.log"
BACKUP_INTERVAL_MINUTES=${BACKUP_INTERVAL:-10}
BACKUP_INTERVAL_SECONDS=$((BACKUP_INTERVAL_MINUTES * 60))
export NODE_NO_WARNINGS=1

# --- Huggingface 恢复 ---
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

# --- 定时备份 ---
if [ -n "$REPO_ID" ] && [ -n "$HF_TOKEN" ]; then
    (
      while true; do
        sleep $BACKUP_INTERVAL_SECONDS
        echo "⏳ --- 定时全量备份 (间隔: ${BACKUP_INTERVAL_MINUTES} 分钟) ---"
        tar -czf "/tmp/$BACKUP_NAME" -C /home/hermes \
            --exclude='agent-venv' \
            --exclude='.cache' \
            --exclude='.npm-cache' \
            --exclude='.uv/cache' \
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

# --- 启动 ---
echo "🚀 正在启动 Hermes Web UI..."
mkdir -p /home/hermes/.hermes-web-ui
touch "$LOG_FILE"

if [ -n "$WEBUI_TOKEN" ]; then
    export AUTH_TOKEN="$WEBUI_TOKEN"
fi

hermes-web-ui start $UI_PORT &

tail -f "$LOG_FILE"
SCRIPT
RUN chmod +x /entrypoint.sh
USER hermes

WORKDIR ${HERMES_HOME}
VOLUME ${HERMES_HOME}
EXPOSE 8648

CMD ["/entrypoint.sh"]

