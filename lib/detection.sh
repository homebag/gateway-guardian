#!/bin/bash
# detection.sh - 多层检测模块 (v3.2 修复版)

# ============================================================
# 配置
# ============================================================
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
HTTP_TIMEOUT="${HTTP_TIMEOUT:-5}"
OPENCLAW_CMD="${OPENCLAW_CMD:-/home/yt/.npm-global/bin/openclaw}"

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
        _debug "HTTP OK (code: $http_code)"
        return 0
    else
        _debug "HTTP FAIL (code: $http_code)"
        return 1
    fi
}

# ============================================================
# 进程检测
# ============================================================
check_process() {
    if pgrep -f "openclaw-gateway" >/dev/null 2>&1; then
        _debug "Process OK"
        return 0
    else
        _debug "Process FAIL"
        return 1
    fi
}

# ============================================================
# Systemd 检测
# ============================================================
check_systemd() {
    local status
    status=$(systemctl --user is-active openclaw-gateway 2>/dev/null)
    
    if [[ "$status" == "active" ]]; then
        _debug "Systemd OK (status: $status)"
        return 0
    else
        _debug "Systemd FAIL (status: $status)"
        return 1
    fi
}

# ============================================================
# 综合检测 (v3.2 修复版)
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
    
    echo "$result"
    
    # v3.2 修复: 正确判断逻辑
    # 情况1: Systemd 正常 + HTTP 正常 = 一定正常
    if [ $systemd_ok -eq 1 ] && [ $http_ok -eq 1 ]; then
        return 0
    fi
    
    # 情况2: Systemd 正常但 HTTP 失败 = 可能有问题
    if [ $systemd_ok -eq 1 ] && [ $http_ok -eq 0 ]; then
        # Systemd 显示 active 但 HTTP 失败，可能是假死
        return 1
    fi
    
    # 情况3: Systemd 失败 = 确定故障
    if [ $systemd_ok -eq 0 ]; then
        return 1
    fi
    
    # 默认返回
    return 0
}

wait_for_gateway() {
    local max_wait="${1:-15}"
    local waited=0
    
    while [[ $waited -lt $max_wait ]]; do
        if check_http; then
            return 0
        fi
        sleep 2
        waited=$((waited + 2))
    done
    return 1
}

get_gateway_details() {
    echo "=== Gateway 详细状态 ==="
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    echo "--- HTTP ---"
    check_http && echo "OK" || echo "FAIL"
    
    echo ""
    echo "--- Process ---"
    pgrep -f "openclaw-gateway" && echo "OK" || echo "FAIL"
    
    echo ""
    echo "--- Systemd ---"
    systemctl --user is-active openclaw-gateway
}

# 命令行入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-status}" in
        status)
            check_gateway_health >/dev/null 2>&1 && echo "OK" || echo "FAIL"
            ;;
        http) check_http && echo "OK" || echo "FAIL" ;;
        process) check_process && echo "OK" || echo "FAIL" ;;
        systemd) check_systemd && echo "OK" || echo "FAIL" ;;
        details) get_gateway_details ;;
    esac
fi
