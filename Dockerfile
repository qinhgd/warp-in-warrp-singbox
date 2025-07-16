# 最终版 Dockerfile: 使用 apk 安装 sing-box，最稳定可靠 (arm64)
FROM alpine:3.20

# ==================== ↓↓↓ 这里是核心修改 ↓↓↓ ====================
# 1. 启用 testing 源，以便安装最新版的 sing-box
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories

# 2. 一次性更新并安装所有依赖
# 直接通过 apk 安装 sing-box，无需手动下载、解压和移动
RUN apk update && \
    apk add --no-cache \
        bash \
        curl \
        ca-certificates \
        unzip \
        jq \
        sing-box
# ==================== ↑↑↑ 这里是核心修改 ↑↑↑ ====================

# 3. 下载并固化 Clash API 的 Web UI (zashboard)
RUN mkdir -p /opt/app/ui && \
    echo "Downloading zashboard Web UI..." && \
    curl -sL "https://github.com/Zephyruso/zashboard/releases/latest/download/dist.zip" -o /tmp/zashboard.zip && \
    unzip /tmp/zashboard.zip -d /opt/app/ui/ && \
    echo "UI download complete." && \
    rm -rf /tmp/zashboard.zip

# 4. 拷贝应用核心文件
WORKDIR /opt/app
# 不再需要安装 warp 工具，因为 sing-box 的 wireguard 出站已经包含了 WARP 功能
# 如果您仍需要 warp-cli 工具进行 IP 优选，请取消下面的注释
# COPY warp-arm64 /usr/local/bin/warp
# RUN chmod +x /usr/local/bin/warp
COPY entry.sh .
COPY config.json.template .

# 5. 从网络下载并固化规则文件
RUN mkdir -p /etc/sing-box/rules && \
    echo "Downloading sing-box rule files..." && \
    curl -sLo /etc/sing-box/rules/geoip-cn.srs "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/sing-box/geoip-cn.srs" && \
    curl -sLo /etc/sing-box/rules/geosite-cn.srs "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/sing-box/geosite-cn.srs" && \
    echo "Rule files download complete."

# 6. Final setup
RUN chmod +x entry.sh

# 7. 创建用于存放最终配置的目录
RUN mkdir -p /etc/sing-box

ENTRYPOINT ["/opt/app/entry.sh"]
