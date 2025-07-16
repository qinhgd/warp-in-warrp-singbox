FROM alpine:3.20

ARG WARP_VERSION="v2.1.5"
ARG TARGETARCH

# 安装 sing-box, curl, warp-go, sed
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories && \
    set -ex && \
    apk update && \
    apk add --no-cache sing-box curl sed

RUN set -ex && \
    curl -fsSL -o /tmp/warp.tar.gz \
      "https://github.com/P3TERX/warp-go/releases/download/${WARP_VERSION}/warp-go_${WARP_VERSION#v}_linux_${TARGETARCH}.tar.gz" && \
    tar -xzf /tmp/warp.tar.gz -C /tmp && \
    mv /tmp/warp-go /usr/local/bin/warp && \
    chmod +x /usr/local/bin/warp && \
    rm /tmp/warp.tar.gz

# 下载并固定规则集文件
RUN set -ex && \
    mkdir -p /etc/sing-box/rules && \
    curl -L -o /etc/sing-box/rules/geosite-cn.srs "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/geosite-cn.srs" && \
    curl -L -o /etc/sing-box/rules/geoip-cn.srs "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-cn.srs"

# 复制配置文件和脚本
WORKDIR /app
COPY config.json.template .
COPY start.sh .
COPY update_ip.sh .
RUN chmod +x start.sh update_ip.sh

ENTRYPOINT ["./start.sh"]
