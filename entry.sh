#!/bin/bash
set -e

# ==============================================================================
# 脚本配置 (来自环境变量)
# ==============================================================================
# --- IP 优选配置 ---
OPTIMIZE_INTERVAL="${OPTIMIZE_INTERVAL:-21600}" # 6 小时
WARP_CONNECT_TIMEOUT="${WARP_CONNECT_TIMEOUT:-4}"
BEST_IP_COUNT="${BEST_IP_COUNT:-20}"

# --- 文件路径 ---
APP_DIR="/opt/app"
BEST_IP_FILE="${APP_DIR}/best_ips.txt"
CONFIG_TEMPLATE="${APP_DIR}/config.json.template"
ACTIVE_CONFIG="/etc/sing-box/config.json"
RELOAD_FLAG_FILE="/tmp/reload.flag"

# ==============================================================================
# 工具函数
# ==============================================================================
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

# ==============================================================================
# IP 优选与配置生成
# ==============================================================================
run_ip_selection() {
    green "🚀 开始优选 WARP Endpoint IP..."
    /usr/local/bin/warp -t "$WARP_CONNECT_TIMEOUT" > /dev/null
    
    if [ -f "result.csv" ]; then
        green "✅ 扫描完成，正在处理结果..."
        
        # ==================== ↓↓↓ 这里是核心修改 ↓↓↓ ====================
        # 新逻辑：
        # 1. 过滤掉延迟为0或超时的IP (`($3+0) > 0`)
        # 2. 按第3列(延迟)进行数字升序排序 (`sort -t, -k3,3n`)
        # 3. 取出排序后最靠前的 N 个IP (`head -n "$BEST_IP_COUNT"`)
        # 4. 格式化为 IP:Port
        awk -F, '($3+0) > 0 {print $0}' result.csv | \
        sort -t, -k3,3n | \
        head -n "$BEST_IP_COUNT" | \
        awk -F, '{print $1":"$2}' | \
        sed 's/[[:space:]]//g' > "$BEST_IP_FILE"
        # ==================== ↑↑↑ 这里是核心修改 ↑↑↑ ====================

        if [ -s "$BEST_IP_FILE" ]; then
            green "✅ 已从有效IP中筛选出延迟最低的 $(wc -l < "$BEST_IP_FILE") 个IP。"
        else
            red "⚠️ 未能从扫描结果中筛选出任何有效的IP。"
        fi
        rm -f result.csv
    else
        red "⚠️ IP 扫描未生成 result.csv 文件。"
    fi
}

update_singbox_config() {
    yellow "🔄 正在更新 sing-box 配置文件..."
    if [ ! -s "$BEST_IP_FILE" ]; then
        red "❌ IP 列表为空！正在执行紧急 IP 优选..."
        run_ip_selection
        if [ ! -s "$BEST_IP_FILE" ]; then
            red "❌ 紧急优选失败，无法更新配置。服务将退出。"
            exit 1
        fi
    fi

    # 从优选列表中随机选择一个 IP:端口
    local random_endpoint=$(shuf -n 1 "$BEST_IP_FILE")
    local new_ip=$(echo "$random_endpoint" | cut -d: -f1)
    local new_port=$(echo "$random_endpoint" | cut -d: -f2)

    green "✅ 已选择新的 Endpoint: ${new_ip}:${new_port}"

    # 使用 jq 精确更新 WARP-OPTIMIZED 出站的 server 和 server_port
    jq --arg ip "$new_ip" --argjson port "$new_port" \
    '( .outbounds[] | select(.tag == "WARP-OPTIMIZED") .server ) |= $ip | ( .outbounds[] | select(.tag == "WARP-OPTIMIZED") .server_port ) |= $port' \
    "$CONFIG_TEMPLATE" > "$ACTIVE_CONFIG"
    
    green "✅ sing-box 配置文件已成功更新到 $ACTIVE_CONFIG。"
}

# ==============================================================================
# 主执行逻辑 (这部分不变)
# ==============================================================================
cd "$APP_DIR" || exit 1

# --- 首次运行设置 ---
green "▶️ 服务初始化..."
run_ip_selection
update_singbox_config

# --- 后台定时任务: 周期性 IP 优选 ---
(
    while true; do
        sleep "$OPTIMIZE_INTERVAL"
        yellow "🔄 [定时任务] 开始周期性 IP 优选..."
        run_ip_selection
        if [ -s "$BEST_IP_FILE" ]; then
            touch "$RELOAD_FLAG_FILE"
            yellow "🔄 [定时任务] IP 列表已更新，已发送热重载信号。"
        else
             yellow "🔄 [定时任务] 未发现更好的IP，跳过本次重载。"
        fi
    done
) &

# --- 主服务循环: 运行并监控 sing-box ---
green "🚀 启动并监控 sing-box 服务..."
while true; do
    /usr/local/bin/sing-box run -c "$ACTIVE_CONFIG" &
    SINGBOX_PID=$!
    
    green "✅ sing-box 服务已启动，进程 PID 为 ${SINGBOX_PID}。"

    while kill -0 "$SINGBOX_PID" >/dev/null 2>&1; do
        if [ -f "$RELOAD_FLAG_FILE" ]; then
            yellow "🔔 接收到热重载信号！"
            rm -f "$RELOAD_FLAG_FILE"
            update_singbox_config
            
            yellow "正在平滑重启 sing-box (PID: ${SINGBOX_PID}) 以应用新配置..."
            kill "$SINGBOX_PID"
            break 
        fi
        sleep 15
    done

    wait "$SINGBOX_PID" 2>/dev/null || true
    red "❌ sing-box 进程已停止。将在5秒后自动重启..."
    sleep 5
done
