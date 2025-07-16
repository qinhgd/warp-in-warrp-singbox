# 最终版 Dockerfile: 集成 jq, zashboard UI, 并从网络自动下载规则 (arm64)
FROM alpine:3.20

# 1. 安装基础依赖, 新增 jq 用于处理 JSON
RUN apk update && \
    apk add --no-cache \
    bash \
    curl \
    ca-certificates \
    unzip \
    jq && \
    rm -rf /var/cache/apk/*

# 2. 安装 sing-box (linux-arm64)
RUN LATEST_URL=$(curl -sL "https://api.github.com/repos/SagerNet/sing-box/releases/latest" | grep "browser_download_url" | grep "linux-arm64" | cut -d '"' -f 4) && \
    curl -sLo /tmp/sing-box.tar.gz "$LATEST_URL" && \
    tar -xzf /tmp/sing-box.tar.gz -C /tmp && \
    mv /tmp/sing-box-*/sing-box /usr/local/bin/ && \
    chmod +x /usr/local/bin/sing-box && \
    rm -rf /tmp/*

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

# ==================== ↓↓↓ 这里是修改的部分 ↓↓↓ ====================
# 5. 从网络下载并固化规则文件
# 不再需要本地的 'rules' 文件夹，直接在构建时从网络获取
RUN mkdir -p /etc/sing-box/rules && \
    echo "Downloading sing-box rule files..." && \
    # 使用 jsDelivr CDN 加速从 GitHub 下载，稳定性较好
    curl -sLo /etc/sing-box/rules/geoip-cn.srs "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/sing-box/geoip-cn.srs" && \
    curl -sLo /etc/sing-box/rules/geosite-cn.srs "https://cdn.jsdelivr.net/gh/Loyalsoldier/v2ray-rules-dat@release/sing-box/geosite-cn.srs" && \
    echo "Rule files download complete."
# ==================== ↑↑↑ 这里是修改的部分 ↑↑↑ ====================

# 6. Final setup
RUN chmod +x /usr/local/bin/warp && \
    chmod +x entry.sh

# 7. 创建用于存放最终配置的目录
RUN mkdir -p /etc/sing-box

ENTRYPOINT ["/opt/app/entry.sh"]
