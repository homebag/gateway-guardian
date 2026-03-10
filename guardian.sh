#!/bin/bash
# guardian.sh - Gateway Guardian v3.0 主入口
# 
# v3.0 新特性:
# - 优化检测间隔 (45s)
# - 2次重试即介入
# - 持久化运行保障
# - 本地加密备份
# - GitHub 远程备份 (可选)
# - 安全审计

set -o pipefail

# 获取脚本所在目录
GUARDIAN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 加载配置
source "$GUARDIAN_DIR/config/guardian.conf"

# 加载模块
source "$GUARDIAN_DIR/lib/detection.sh"
source "$GUARDIAN_DIR/lib/recovery.sh"
source "$GUARDIAN_DIR/lib/notification.sh"
source "$GUARDIAN_DIR/lib/backup.sh"
source "$GUARDIAN_DIR/lib/security.sh"

# ============================================================
# 日志函数
# ============================================================

LOG_FILE="/tmp/openclaw-guardian.log"

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 颜色
    local color=""
    case "$level" in
        DEBUG) color='\033[0;34m' ;;
        INFO)  color='\033[0;32m' ;;
        WARN)  color='\033[1;33m' ;;
        ERROR) color='\033[0;31m' ;;
    esac
    local nc='\033[0m'
    
    echo -e "$timestamp [$color$level$nc] $message" >> "$LOG_FILE"
    echo -e "$timestamp [$color$level$nc] $message"
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { [[ "$DEBUG" == "true" ]] && log "DEBUG" "$@"; }

# ============================================================
# 状态管理
# ============================================================

STATE_DIR="$GUARDIAN_DIR/state"
STATE_FILE="$STATE_DIR/guardian.state"

init_state() {
    mkdir -p "$STATE_DIR"
    
    if [ ! -f "$STATE_FILE" ]; then
        cat > "$STATE_FILE" << EOF
{
    "version": "3.0",
    "start_time": "$(date -Iseconds)",
    "last_check": null,
    "consecutive_failures": 0,
    "total_restarts": 0,
    "total_rollbacks": 0,
    "total_backups": 0,
    "last_backup": null,
    "last_recovery": null,
    "uptime_seconds": 0
}
EOF
        log_info "状态文件已初始化"
    fi
}

get_state() {
    local key="$1"
    local value
    
    # 读取值，正确处理带引号和不带引号的 JSON 值
    value=$(grep "\"$key\"" "$STATE_FILE" 2>/dev/null | \
        sed -E 's/.*"'"$key"'":[[:space:]]*"([^"]*)".*/\1/; t; s/.*"'"$key"'":[[:space:]]*([^,}]+).*/\1/')
    
    # 清理
    value=$(echo "$value" | tr -d '"' | tr -d ',' | xargs 2>/dev/null)
    
    echo "$value"
}

update_state() {
    local key="$1"
    local value="$2"
    
    if [[ "$value" =~ ^[0-9]+$ ]]; then
        sed -i "s/\"$key\"\s*:\s*[0-9]*/\"$key\": $value/" "$STATE_FILE"
    else
        sed -i "s/\"$key\"\s*:\s*\"[^\"]*\"/\"$key\": \"$value\"/" "$STATE_FILE"
    fi
}

# ============================================================
# 持久化保障
# ============================================================

# 确保 Guardian 持续运行
ensure_persistence() {
    # 检查 systemd 服务是否启用
    if ! systemctl --user is-enabled openclaw-guardian &>/dev/null; then
        log_warn "Guardian 服务未启用，正在启用..."
        systemctl --user enable openclaw-guardian
    fi
    
    # 写入心跳
    update_state "last_check" "$(date -Iseconds)"
}

# ============================================================
# 主循环
# ============================================================

main() {
    log_info "=========================================="
    log_info "Gateway Guardian v3.0 启动"
    log_info "=========================================="
    log_info "检测间隔: ${CHECK_INTERVAL}s"
    log_info "最大重试: ${MAX_RETRIES} 次"
    log_info "冷却期: ${COOLDOWN_PERIOD}s"
    log_info "端口: ${GATEWAY_PORT}"
    log_info "=========================================="
    
    # 初始化
    init_state
    
    # 安全检查
    if ! verify_encryption_key &>/dev/null; then
        log_warn "未配置加密密钥，备份将不加密"
    fi
    
    # 发送启动通知
    send_notification "🚀 Guardian v3.0 已启动" "info"
    
    local consecutive_failures=0
    local in_cooldown=false
    local cooldown_start=0
    
    while true; do
        # 确保持久化
        ensure_persistence
        
        # 执行检测
        local result
        result=$(check_gateway_health)
        local status=$?
        
        if [ $status -eq 0 ]; then
            # Gateway 正常
            log_info "Gateway 正常 [$result]"
            if [ $consecutive_failures -gt 0 ]; then
                log_info "Gateway 已恢复正常 (之前失败: $consecutive_failures 次)"
            fi
            consecutive_failures=0
            in_cooldown=false
            
            # 更新状态
            update_state "last_check" "$(date -Iseconds)"
            
            # 定期备份 (每6小时)
            local last_backup=$(get_state "last_backup")
            local now=$(date +%s)
            local backup_interval=21600  # 6小时
            
            if [ -z "$last_backup" ] || [ "$last_backup" = "null" ]; then
                log_info "执行首次备份..."
                create_local_backup && update_state "last_backup" "$(date -Iseconds)"
            else
                local last_ts=$(date -d "$last_backup" +%s 2>/dev/null || echo 0)
                if [ $((now - last_ts)) -gt $backup_interval ]; then
                    log_info "执行定期备份..."
                    create_local_backup && update_state "last_backup" "$(date -Iseconds)"
                fi
            fi
            
        else
            # Gateway 异常
            ((consecutive_failures++))
            update_state "consecutive_failures" "$consecutive_failures"
            
            log_warn "Gateway 异常 [$result] (连续失败: $consecutive_failures)"
            
            # 第一次检测到异常时发送通知
            if [ $consecutive_failures -eq 1 ]; then
                send_notification "⚠️ Gateway 检测到异常，正在监控..." "warn"
            fi
            
            # 检查冷却期
            local now=$(date +%s)
            if [ "$in_cooldown" = true ]; then
                local remaining=$((COOLDOWN_PERIOD - (now - cooldown_start)))
                if [ $remaining -gt 0 ]; then
                    log_debug "冷却期中，剩余 ${remaining}s"
                    sleep "$CHECK_INTERVAL"
                    continue
                else
                    in_cooldown=false
                fi
            fi
            
            # 判断是否需要介入
            if [ $consecutive_failures -ge $MAX_RETRIES ]; then
                log_error "达到重试阈值 ($consecutive_failures >= $MAX_RETRIES)，开始介入..."
                
                # 发送开始恢复通知
                send_notification "⚠️ Gateway 异常，正在尝试恢复..." "warn"
                
                # 先备份当前配置
                log_info "备份当前配置..."
                local backup_file
                backup_file=$(create_local_backup)
                
                # 尝试恢复
                if attempt_recovery; then
                    log_info "✅ 恢复成功"
                    send_notification "✅ Gateway 已恢复" "info"
                    
                    update_state "total_restarts" "$(($(get_state total_restarts) + 1))"
                    update_state "last_recovery" "$(date -Iseconds)"
                    consecutive_failures=0
                else
                    log_error "❌ 恢复失败，需要人工介入"
                    send_notification "🚨 Gateway 恢复失败，请人工检查" "critical"
                fi
                
                # 进入冷却期
                in_cooldown=true
                cooldown_start=$(date +%s)
            fi
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# ============================================================
# 信号处理
# ============================================================

cleanup() {
    log_info "收到退出信号，正在停止..."
    send_notification "👋 Guardian v3.0 已停止" "info"
    exit 0
}

trap cleanup SIGTERM SIGINT

# ============================================================
# 入口
# ============================================================

case "${1:-}" in
    --status)
        echo "=== Guardian v3.0 状态 ==="
        cat "$STATE_FILE" 2>/dev/null || echo "无状态文件"
        ;;
    --detect)
        check_gateway_health
        echo "检测结果: $?"
        ;;
    --backup)
        create_local_backup
        ;;
    --restore)
        restore_backup "${2:-}"
        ;;
    --audit)
        run_security_audit
        ;;
    --version)
        echo "Gateway Guardian v3.0"
        ;;
    *)
        main
        ;;
esac