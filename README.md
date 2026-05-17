# 🧠 Hermes Web UI (Docker Edition)

> **一站式 Hermes 可视化控制台 · 内置 Agent · 国内镜像加速 · Ubuntu 24.04**

一个基于 **Ubuntu 24.04 + Node 24 + Python (uv)** 的 **Hermes Web UI** 生产级 Docker 镜像，集成：

- ✅ Hermes Web UI
- ✅ Hermes Agent（NousResearch）
- ✅ FFmpeg / Git / Vim
- ✅ 国内 APT / PyPI / NPM 镜像
- ✅ 非 root 用户运行（hermes）

---

## 🚀 快速启动

```bash
docker run -d \
  --name hermes \
  -p 8648:8648 \
  -e UI_PORT=8648 \
  -e HF_DATASET_ID="你的/dataset-repo" \
  -e HF_TOKEN="你的hf_token" \
  -e BACKUP_INTERVAL=30 \
  ghcr.io/wangguoxing99/hermes-docker:latest
```
查看token
```
docker logs hermes
```
访问：

👉 http://localhost:8648/#/?token=56595a74837707c876df1c8086e2c974a1a1ac8493b0634582

---

## 🔧 环境变量说明

| 变量名 | 默认值 | 说明 |
|------|------|------|
| `UI_PORT` | `8648` | Web UI 监听端口 |
| `HF_DATASET_ID` | `huggingface部署时填` | huggingface的datasets名称 |
| `HF_TOKEN` | `huggingface部署时填` | huggingface令牌 |
| `WEBUI_TOKEN` | `自定义` | Web UI 访问密码（非必须） |
| `BACKUP_INTERVAL` | `10` | huggingface自动备份时间分钟数设置，默认10分钟 |

---

## 📦 镜像组成

### 基础环境
- Ubuntu 24.04 LTS
- Node.js **v24**
- Python（由 **uv** 管理）
- npm 镜像：`npmmirror.com`

### 核心组件
- **hermes-web-ui**
- **hermes-agent**
- playwright（下载源已加速）
- ffmpeg / ripgrep / htop / vim

---

## 📁 数据持久化

```bash
-v /opt/hermes:/home/hermes
```
或huggingface自动备份恢复

挂载后：
- Hermes 配置
- Agent 状态
- 用户数据

都会保留在宿主机上。

---

## 👤 运行身份

| 用户 | 说明 |
|----|----|
| `hermes` | 默认运行用户 |
| sudo | ✅ 免密 |
| 权限 | 非 root，更安全 |

---

## 🧩 常见问题

### ❓ 为什么端口是 8648？
这是 **Hermes Web UI 默认端口**，可以通过变量修改。

### ❓ 国内构建慢？
已默认启用：
- ✅ 阿里云 APT
- ✅ 清华 PyPI
- ✅ npmmirror
- ✅ Playwright 镜像

### ❓ 如何进入容器调试？

```bash
docker exec -it hermes bash
su - hermes
```

---

## 📜 License

MIT © Hermes Community
