#!/bin/bash
# utils.sh - 工具函数库

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 加载配置
load_config() {
    local config_file="${SCRIPT_DIR}/config/guardian.conf"
    if [[ -f "$config_file" ]]; then
        source "$config_file"
    fi
}

# 日志函数
log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 日志级别过滤
    local level_num=0
    case "$level" in
        DEBUG) level_num=0 ;;
        INFO)  level_num=1 ;;
        WARN)  level_num=2 ;;
        ERROR) level_num=3 ;;
    esac
    
    local config_level_num=1
    case "$LOG_LEVEL" in
        DEBUG) config_level_num=0 ;;
        INFO)  config_level_num=1 ;;
        WARN)  config_level_num=2 ;;
        ERROR) config_level_num=3 ;;
    esac
    
    if [[ $level_num -ge $config_level_num ]]; then
        local color=""
        case "$level" in
            DEBUG) color="$BLUE" ;;
            INFO)  color="$GREEN" ;;
            WARN)  color="$YELLOW" ;;
            ERROR) color="$RED" ;;
        esac
        
        echo -e "${timestamp} [${color}${level}${NC}] ${message}" | tee -a "$LOG_FILE"
    fi
}

log_info()  { log "INFO" "$@"; }
log_warn()  { log "WARN" "$@"; }
log_error() { log "ERROR" "$@"; }
log_debug() { 
    if [[ "$DEBUG_MODE" == "true" ]]; then
        log "DEBUG" "$@"
    fi
}

# 状态文件管理
STATE_DIR="${STATE_DIR:-~/openclaw/workspace/gateway-guardian/state}"

ensure_state_dir() {
    mkdir -p "$STATE_DIR"
}

# 获取失败计数
get_failure_count() {
    ensure_state_dir
    local count_file="$STATE_DIR/failure-count"
    if [[ -f "$count_file" ]]; then
        cat "$count_file"
    else
        echo "0"
    fi
}

# 设置失败计数
set_failure_count() {
    ensure_state_dir
    local count="$1"
    echo "$count" > "$STATE_DIR/failure-count"
}

# 重置失败计数
reset_failure_count() {
    set_failure_count 0
}

# 增加失败计数
increment_failure_count() {
    local current=$(get_failure_count)
    set_failure_count $((current + 1))
    echo $((current + 1))
}

# 获取最后失败时间
get_last_failure_time() {
    ensure_state_dir
    local time_file="$STATE_DIR/last-failure-time"
    if [[ -f "$time_file" ]]; then
        cat "$time_file"
    else
        echo "0"
    fi
}

# 设置最后失败时间
set_last_failure_time() {
    ensure_state_dir
    date +%s > "$STATE_DIR/last-failure-time"
}

# 获取最后通知时间
get_last_notify_time() {
    ensure_state_dir
    local time_file="$STATE_DIR/last-notify-time"
    if [[ -f "$time_file" ]]; then
        cat "$time_file"
    else
        echo "0"
    fi
}

# 设置最后通知时间
set_last_notify_time() {
    ensure_state_dir
    date +%s > "$STATE_DIR/last-notify-time"
}

# 检查是否在冷却期
is_in_cooldown() {
    local last_failure=$(get_last_failure_time)
    local current=$(date +%s)
    local elapsed=$((current - last_failure))
    
    if [[ $elapsed -lt $COOLDOWN_PERIOD ]]; then
        echo "true"
        local remaining=$((COOLDOWN_PERIOD - elapsed))
        echo "remaining:$remaining"
    else
        echo "false"
    fi
}

# 计算指数退避时间
calculate_backoff() {
    local attempt="$1"
    local backoff=$((BACKOFF_BASE * (2 ** (attempt - 1))))
    
    if [[ $backoff -gt $MAX_BACKOFF ]]; then
        backoff=$MAX_BACKOFF
    fi
    
    echo $backoff
}

# 记录恢复历史
add_recovery_history() {
    ensure_state_dir
    local action="$1"
    local result="$2"
    local details="$3"
    
    local history_file="$STATE_DIR/recovery-history"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 添加记录
    echo "${timestamp}|${action}|${result}|${details}" >> "$history_file"
    
    # 保留最近 N 条
    if [[ -f "$history_file" ]]; then
        tail -n "$HISTORY_KEEP" "$history_file" > "${history_file}.tmp"
        mv "${history_file}.tmp" "$history_file"
    fi
}

# 记录回滚信息
record_rollback() {
    ensure_state_dir
    local from_commit="$1"
    local to_commit="$2"
    local reason="$3"
    
    local rollback_file="$STATE_DIR/last-rollback"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    cat > "$rollback_file" << EOF
timestamp: $timestamp
from_commit: $from_commit
to_commit: $to_commit
reason: $reason
config_diff:
$(git -C "$WORKSPACE" diff "$from_commit" "$to_commit" -- "*.json" 2>/dev/null | head -100)
EOF
}

# 获取回滚信息
get_rollback_info() {
    ensure_state_dir
    local rollback_file="$STATE_DIR/last-rollback"
    if [[ -f "$rollback_file" ]]; then
        cat "$rollback_file"
    fi
}

# 日志轮转
rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local size=$(du -m "$LOG_FILE" 2>/dev/null | cut -f1)
        if [[ $size -ge $LOG_MAX_SIZE ]]; then
            mv "$LOG_FILE" "${LOG_FILE}.$(date +%Y%m%d%H%M%S)"
            gzip "${LOG_FILE}."* 2>/dev/null &
        fi
    fi
}