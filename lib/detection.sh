#!/bin/bash
# detection.sh - 多层检测模块 (v3.1 修复版)
# 独立运行，不依赖外部函数

# ============================================================
# 配置 (默认值，可被外部覆盖)
# ============================================================
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"
RPC_TIMEOUT="${RPC_TIMEOUT:-5}"
OPENCLAW_CMD="${OPENCLAW_CMD:-openclaw}"

# ============================================================
# 日志函数 (内部使用)
# ============================================================
_debug() {
    [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*" >&2
}

# ============================================================
# HTTP 检测 (优先级最高)
# ============================================================
check_http() {
    local port="${1:-$GATEWAY_PORT}"
    local url="http://127.0.0.1:$port/health"
    
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" \
        --connect-timeout "$HTTP_TIMEOUT" \
        --max-time "$HTTP_TIMEOUT" \
        "$url" 2>/dev/null)
    
    if [[ "$http_code" == "200" ]]; then
        _debug "HTTP 检测通过 (状态码: $http_code)"
        return 0
    else
        _debug "HTTP 检测失败 (状态码: $http_code)"
        return 1
    fi
}

# ============================================================
# 进程检测
# ============================================================
check_process() {
    if pgrep -f "openclaw-gateway" >/dev/null 2>&1; then
        _debug "进程检测通过"
        return 0
    else
        _debug "进程检测失败"
        return 1
    fi
}

# ============================================================
# Systemd 检测
# ============================================================
check_systemd() {
    local status
    status=$(systemctl --user is-active openclaw-gateway 2>/dev/null)
    
    # 注意: activating 也是正常状态 (正在启动)
    if [[ "$status" == "active" ]] || [[ "$status" == "activating" ]]; then
        _debug "Systemd 检测通过 (状态: $status)"
        return 0
    else
        _debug "Systemd 检测失败 (状态: $status)"
        return 1
    fi
}

# ============================================================
# 综合检测 (主函数)
# ============================================================
check_gateway_health() {
    local http_ok=0
    local process_ok=0
    local systemd_ok=0
    local result=""
    
    # HTTP 检测
    if check_http; then
        http_ok=1
        result+="http:OK "
    else
        result+="http:FAIL "
    fi
    
    # 进程检测
    if check_process; then
        process_ok=1
        result+="process:OK "
    else
        result+="process:FAIL "
    fi
    
    # Systemd 检测
    if check_systemd; then
        systemd_ok=1
        result+="systemd:OK "
    else
        result+="systemd:FAIL "
    fi
    
    # 输出结果
    echo "$result"
    
    # 优化判断逻辑:
    # 1. 如果 systemd 正常，Gateway 就在运行 (最重要)
    # 2. 或者 HTTP + 进程都失败才认为失败
    if [ $systemd_ok -eq 1 ]; then
        return 0
    fi
    
    # systemd 不正常时，需要 HTTP 和进程都失败才算失败
    if [ $http_ok -eq 0 ] && [ $process_ok -eq 0 ]; then
        return 1
    fi
    
    # 进程正常但 systemd 不正常，认为正常 (可能正在启动)
    return 0
}

# ============================================================
# 等待 Gateway 启动
# ============================================================
wait_for_gateway() {
    local max_wait="${1:-15}"
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if check_http; then
            _debug "Gateway 已就绪 (等待 ${waited}s)"
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    
    _debug "Gateway 启动超时"
    return 1
}

# ============================================================
# 详细状态 (用于调试)
# ============================================================
get_gateway_details() {
    echo "=== Gateway 详细状态 ==="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    echo "--- HTTP 检测 ---"
    if check_http; then
        echo "状态: OK"
        curl -s --max-time 3 "http://127.0.0.1:$GATEWAY_PORT/health" 2>/dev/null | head -5 || echo "(无响应体)"
    else
        echo "状态: FAIL"
    fi
    
    echo ""
    echo "--- 进程检测 ---"
    local pids
    pids=$(pgrep -f "openclaw-gateway" 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "状态: OK"
        echo "PID: $pids"
    else
        echo "状态: FAIL (无进程)"
    fi
    
    echo ""
    echo "--- Systemd 检测 ---"
    systemctl --user status openclaw-gateway 2>/dev/null | head -5
}

# ============================================================
# 命令行入口
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-status}" in
        status)
            if check_gateway_health >/dev/null 2>&1; then
                echo "Gateway 运行正常"
                exit 0
            else
                echo "Gateway 异常"
                exit 1
            fi
            ;;
        http)
            check_http && echo "HTTP: OK" || echo "HTTP: FAIL"
            ;;
        process)
            check_process && echo "Process: OK" || echo "Process: FAIL"
            ;;
        systemd)
            check_systemd && echo "Systemd: OK" || echo "Systemd: FAIL"
            ;;
        details)
            get_gateway_details
            ;;
        *)
            echo "用法: $0 {status|http|process|systemd|details}"
            ;;
    esac
fi