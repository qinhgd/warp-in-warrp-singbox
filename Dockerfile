# 最终版 Dockerfile: 适配版本号参数，集成 jq, zashboard UI (arm64)
FROM alpine:3.20

# 1. 安装基础依赖
RUN apk update && \
    apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    unzip \
    jq && \
    rm -rf /var/cache/apk/*

# ==================== ↓↓↓ 这里是核心修改 ↓↓↓ ====================
# 声明一个构建参数，它的值将由 release.yml 在构建时传入
ARG SINGBOX_VERSION

# 2. 安装 sing-box (linux-arm64)
# 根据传入的 SINGBOX_VERSION 版本号，自己拼接出标准的 GitHub Release 下载链接
RUN echo "Downloading sing-box version: v${SINGBOX_VERSION}" && \
    SINGBOX_URL="https://github.com/SagerNet/sing-box/releases/download/v${SINGBOX_VERSION}/sing-box-${SINGBOX_VERSION}-linux-arm64.tar.gz" && \
    curl -sLo /tmp/sing-box.tar.gz "${SINGBOX_URL}" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/ && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/*
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
COPY warp-arm64 /usr/local/bin/warp
COPY entry.sh .
COPY config.json.template .

# 5. 从网络下载并固化规则文件
RUN mkdir -p /etc/sing-box/rules && \
    echo "Downloading sing-box rule files..." && \
    curl -sLo /etc/sing-box/rules/geoip-cn.srs "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/sing-box/geoip-cn.srs" && \
    curl -sLo /etc/sing-box/rules/geosite-cn.srs "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/sing-box/geosite-cn.srs" && \
    echo "Rule files download complete."

# 6. Final setup
RUN chmod +x /usr/local/bin/warp && \
    chmod +x entry.sh

# 7. 创建用于存放最终配置的目录
RUN mkdir -p /etc/sing-box

ENTRYPOINT ["/opt/app/entry.sh"]
