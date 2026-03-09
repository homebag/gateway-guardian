#!/bin/bash
# notification.sh - 通知模块

# ============================================================
# Discord 通知
# ============================================================

# 从配置文件获取 Discord Token
# 缺失函数定义
get_last_notify_time() { local file="${STATE_DIR:-/tmp}/last_notify"; [[ -f "$file" ]] && cat "$file" || echo 0; }
set_last_notify_time() { local file="${STATE_DIR:-/tmp}/last_notify"; mkdir -p "$(dirname "$file")" 2>/dev/null; date +%s > "$file"; }
log_debug() { [[ "${DEBUG:-false}" == "true" ]] && echo "[DEBUG] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }

get_discord_token() {
    local token=""
    
    # 方法1: 从环境变量
    if [[ -n "$DISCORD_BOT_TOKEN" ]]; then
        echo "$DISCORD_BOT_TOKEN"
        return 0
    fi
    
    # 方法2: 从 OpenClaw 配置
    if [[ -f "${OPENCLAW_DIR:-$HOME/.config/openclaw}/openclaw.json" ]]; then
        # 尝试多个可能的位置
        token=$(cat "${OPENCLAW_DIR:-$HOME/.config/openclaw}/openclaw.json" | \
            grep -oP '"token"\s*:\s*"\K[^"]+' 2>/dev/null | head -1)
        
        if [[ -n "$token" ]]; then
            echo "$token"
            return 0
        fi
    fi
    
    return 1
}

# 发送 Discord 消息
send_discord_message() {
    local message="$1"
    
    if [[ "$ENABLE_DISCORD_NOTIFY" != "true" ]]; then
        log_debug "Discord 通知已禁用"
        return 0
    fi
    
    # 检查通知频率限制
    local last_notify=$(get_last_notify_time)
    local current=$(date +%s)
    local elapsed=$((current - last_notify))
    
    if [[ $elapsed -lt $NOTIFY_MIN_INTERVAL ]] && [[ $last_notify -gt 0 ]]; then
        log_debug "通知频率限制 (距上次 ${elapsed}s < ${NOTIFY_MIN_INTERVAL}s)"
        return 0
    fi
    
    local token=$(get_discord_token)
    if [[ -z "$token" ]]; then
        log_error "无法获取 Discord Token"
        return 1
    fi
    
    local payload=$(cat << EOF
{
    "content": "$message"
}
EOF
)
    
    local http_code=$(curl -s --connect-timeout 10 -m 15 -w "%{http_code}" -o /dev/null \
        --connect-timeout 10 \
        --max-time 15 \
        --retry 2 \
        -X POST \
        -H "Authorization: Bot $token" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://discord.com/api/v10/channels/$DISCORD_CHANNEL_ID/messages" 2>/dev/null)
    
    if [[ "$http_code" == "200" ]] || [[ "$http_code" == "201" ]]; then
        log_debug "Discord 消息发送成功"
        set_last_notify_time
        return 0
    else
        log_error "Discord 消息发送失败 (HTTP $http_code)"
        return 1
    fi
}

# 发送嵌入消息 (支持更丰富的格式)
send_discord_embed() {
    local title="$1"
    local description="$2"
    local color="${3:-15105570}"  # 默认橙色
    local fields="${4:-}"
    
    if [[ "$ENABLE_DISCORD_NOTIFY" != "true" ]]; then
        return 0
    fi
    
    local token=$(get_discord_token)
    if [[ -z "$token" ]]; then
        return 1
    fi
    
    local payload=$(cat << EOF
{
    "embeds": [{
        "title": "$title",
        "description": "$description",
        "color": $color,
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    }]
}
EOF
)
    
    curl -s -o /dev/null \
        --connect-timeout 10 \
        --max-time 15 \
        --retry 2 \
        -X POST \
        -H "Authorization: Bot $token" \
        -H "Content-Type: application/json" \
        -d "$payload" \
        "https://discord.com/api/v10/channels/$DISCORD_CHANNEL_ID/messages"
}

# ============================================================
# 预定义通知模板
# ============================================================

# 告警通知
notify_alert() {
    local reason="$1"
    local attempt="$2"
    
    send_discord_embed \
        "⚠️ Gateway 告警" \
        "**原因**: $reason\n**重试次数**: 第 ${attempt} 次\n**时间**: $(date '+%Y-%m-%d %H:%M:%S')" \
        "15105570"  # 橙色
}

# 恢复通知
notify_recovered() {
    local method="$1"
    local duration="$2"
    
    send_discord_embed \
        "✅ Gateway 已恢复" \
        "**恢复方式**: $method\n**耗时**: ${duration}s\n**时间**: $(date '+%Y-%m-%d %H:%M:%S')" \
        "3066993"  # 绿色
}

# 回滚通知 (详细报告)
notify_rollback() {
    local from_commit="$1"
    local to_commit="$2"
    local diff="${3:-}"
    
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # 获取变更文件列表
    local changed_files=$(git -C "$WORKSPACE" diff --name-only "$from_commit".."$to_commit" 2>/dev/null | grep "\.json$" || echo "")
    local file_count=$(echo "$changed_files" | grep -v "^$" | wc -l)
    
    local description="**时间**: $timestamp\n"
    description+="**回滚前**: \`${from_commit:0:8}\`\n"
    description+="**回滚后**: \`${to_commit:0:8}\`\n"
    description+="**变更文件**: ${file_count} 个\n\n"
    
    if [[ "$file_count" -gt 0 ]] && [[ -n "$changed_files" ]]; then
        description+="**变更文件列表**:\n\`\`\`\n$changed_files\n\`\`\`\n"
    fi
    
    if [[ -n "$diff" ]]; then
        # 截断 diff，避免消息过长
        local truncated_diff=$(echo "$diff" | head -25)
        description+="\n**配置差异**:\n\`\`\`diff\n${truncated_diff}\n\`\`\`"
    fi
    
    send_discord_embed \
        "🔄 Gateway 配置已回滚" \
        "$description" \
        "3447003"  # 蓝色
}

# 严重错误通知
notify_critical() {
    local message="$1"
    local details="${2:-}"
    
    local description="**问题**: $message\n**时间**: $(date '+%Y-%m-%d %H:%M:%S')"
    
    if [[ -n "$details" ]]; then
        description="${description}\n\n**详情**:\n\`\`\`\n${details}\n\`\`\`"
    fi
    
    send_discord_embed \
        "🚨 严重错误 - 需人工介入" \
        "$description" \
        "15158332"  # 红色
}

# ============================================================
# 启动通知
# ============================================================

notify_startup() {
    send_discord_embed \
        "🛡️ Guardian 已启动" \
        "**检测间隔**: ${CHECK_INTERVAL}s\n**最大重试**: ${MAX_RETRIES} 次\n**时间**: $(date '+%Y-%m-%d %H:%M:%S')" \
        "3447003"
}

notify_shutdown() {
    send_discord_embed \
        "🔴 Guardian 已停止" \
        "**时间**: $(date '+%Y-%m-%d %H:%M:%S')" \
        "10070709"
}
# ============================================================
# 通用通知包装函数
# ============================================================

send_notification() {
    local message="$1"
    local level="${2:-info}"
    
    case "$level" in
        "info")
            send_discord_message "$message"
            ;;
        "warning"|"warn")
            send_discord_message "⚠️ $message"
            ;;
        "error"|"critical")
            send_discord_message "🚨 $message"
            ;;
        *)
            send_discord_message "$message"
            ;;
    esac
}

# ============================================================
# 别名函数 (兼容主脚本调用)
# ============================================================

# send_notification 别名
