#!/bin/bash
set -e

# ==============================================================================
# Script Configuration (from Environment Variables)
# ==============================================================================
# --- IP Selection Config ---
OPTIMIZE_INTERVAL="${OPTIMIZE_INTERVAL:-21600}" # 6 hours
WARP_CONNECT_TIMEOUT="${WARP_CONNECT_TIMEOUT:-4}"
BEST_IP_COUNT="${BEST_IP_COUNT:-20}"

# --- File Paths ---
APP_DIR="/opt/app"
BEST_IP_FILE="${APP_DIR}/best_ips.txt"
CONFIG_TEMPLATE="${APP_DIR}/config.json.template"
ACTIVE_CONFIG="/etc/sing-box/config.json"
RELOAD_FLAG_FILE="/tmp/reload.flag"

# ==============================================================================
# Utility Functions
# ==============================================================================
red() { echo -e "\033[31m\033[01m$1\033[0m"; }
green() { echo -e "\033[32m\033[01m$1\033[0m"; }
yellow() { echo -e "\033[33m\033[01m$1\033[0m"; }

# ==============================================================================
# IP Optimization & Config Generation
# ==============================================================================
run_ip_selection() {
    green "🚀 开始优选 WARP Endpoint IP..."
    /usr/local/bin/warp -t "$WARP_CONNECT_TIMEOUT" > /dev/null
    
    if [ -f "result.csv" ]; then
        green "✅ 扫描完成，正在处理结果..."
        
        awk -F, '($3+0) > 0 {print $0}' result.csv | \
        sort -t, -k3,3n | \
        head -n "$BEST_IP_COUNT" | \
        awk -F, '{print $1":"$2}' | \
        sed 's/[[:space:]]//g' > "$BEST_IP_FILE"

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

    local random_endpoint=$(shuf -n 1 "$BEST_IP_FILE")
    local new_ip=$(echo "$random_endpoint" | cut -d: -f1)
    local new_port=$(echo "$random_endpoint" | cut -d: -f2)

    # ==================== ↓↓↓ THE FIX IS HERE ↓↓↓ ====================
    # Sanitize the port number to ensure it contains only digits.
    new_port=$(echo "$new_port" | tr -dc '0-9')
    # ==================== ↑↑↑ THE FIX IS HERE ↑↑↑ ====================

    green "✅ 已选择新的 Endpoint: ${new_ip}:${new_port}"

    jq --arg ip "$new_ip" --argjson port "$new_port" \
    '( .outbounds[] | select(.tag == "WARP-OPTIMIZED") .server ) |= $ip | ( .outbounds[] | select(.tag == "WARP-OPTIMIZED") .server_port ) |= $port' \
    "$CONFIG_TEMPLATE" > "$ACTIVE_CONFIG"
    
    green "✅ sing-box 配置文件已成功更新到 $ACTIVE_CONFIG。"
}

# ==============================================================================
# Main Execution Logic (This part remains unchanged)
# ==============================================================================
cd "$APP_DIR" || exit 1

# --- Initial Setup ---
green "▶️ 服务初始化..."
run_ip_selection
update_singbox_config

# --- Background Task: Periodic IP Optimization ---
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

# --- Main Service Loop: Run and monitor sing-box ---
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
