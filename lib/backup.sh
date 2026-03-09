#!/bin/bash
# backup.sh - v3.0 备份模块
# 功能：本地备份、远程备份、加密、脱敏

# 加载配置
source "${GUARDIAN_DIR:-~/openclaw/workspace/gateway-guardian}/config/guardian.conf"

# ============================================================
# 敏感数据处理
# ============================================================

# 脱敏处理 JSON 文件
sanitize_config() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        echo "错误: 文件不存在 $input_file"
        return 1
    fi
    
    # 使用 jq 脱敏敏感字段
    local temp_file=$(mktemp)
    cp "$input_file" "$temp_file"
    
    for field in "${SENSITIVE_FIELDS[@]}"; do
        # 替换敏感字段值为 [REDACTED]
        jq --arg field "$field" '
            walk(if type == "object" and has($field) then .[$field] = "[REDACTED]" else . end)
        ' "$temp_file" > "${temp_file}.sanitized" 2>/dev/null && mv "${temp_file}.sanitized" "$temp_file"
    done
    
    mv "$temp_file" "$output_file"
    echo "✅ 配置已脱敏: $output_file"
}

# ============================================================
# 本地备份
# ============================================================

# 创建本地备份
create_local_backup() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S).json.gz.enc"
    local backup_path="$LOCAL_BACKUP_DIR/$backup_name"
    
    # 创建备份目录
    mkdir -p "$LOCAL_BACKUP_DIR"
    
    # 脱敏并压缩
    local temp_config=$(mktemp)
    sanitize_config "$HOME/.config/openclaw/openclaw.json" "$temp_config"
    
    # 压缩
    gzip -c "$temp_config" > "${temp_config}.gz"
    
    # 加密 (如果密钥存在)
    if [ -f "$ENCRYPTION_KEY_FILE" ]; then
        openssl enc -aes-256-cbc -salt -pbkdf2 -in "${temp_config}.gz" -out "$backup_path" -pass file:"$ENCRYPTION_KEY_FILE" 2>/dev/null
        rm -f "${temp_config}.gz" "$temp_config"
        echo "✅ 加密备份已创建: $backup_path"
    else
        # 无密钥则不加密
        mv "${temp_config}.gz" "${backup_path%.enc}"
        rm -f "$temp_config"
        echo "⚠️ 未加密备份已创建: ${backup_path%.enc}"
    fi
    
    # 清理旧备份
    cleanup_old_backups
    
    # 记录审计日志
    log_audit "BACKUP_CREATED" "$backup_path"
    
    echo "$backup_path"
}

# 清理旧备份
cleanup_old_backups() {
    local count=$(ls -1 "$LOCAL_BACKUP_DIR" 2>/dev/null | wc -l)
    
    if [ "$count" -gt "$MAX_BACKUPS" ]; then
        local to_delete=$((count - MAX_BACKUPS))
        ls -1t "$LOCAL_BACKUP_DIR" | tail -$to_delete | while read file; do
            rm -f "$LOCAL_BACKUP_DIR/$file"
            echo "🗑️ 清理旧备份: $file"
        done
    fi
}

# 恢复备份
restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo "错误: 备份文件不存在"
        return 1
    fi
    
    local temp_file=$(mktemp)
    
    # 解密 (如果是加密文件)
    if [[ "$backup_file" == *.enc ]]; then
        if [ -f "$ENCRYPTION_KEY_FILE" ]; then
            openssl enc -aes-256-cbc -d -pbkdf2 -in "$backup_file" -out "${temp_file}.gz" -pass file:"$ENCRYPTION_KEY_FILE" 2>/dev/null
            gunzip -c "${temp_file}.gz" > "$temp_file"
            rm -f "${temp_file}.gz"
        else
            echo "错误: 需要解密密钥"
            return 1
        fi
    elif [[ "$backup_file" == *.gz ]]; then
        gunzip -c "$backup_file" > "$temp_file"
    else
        cp "$backup_file" "$temp_file"
    fi
    
    # 验证 JSON
    if jq empty "$temp_file" 2>/dev/null; then
        cp "$temp_file" "$HOME/.config/openclaw/openclaw.json"
        echo "✅ 配置已恢复: $backup_file"
        log_audit "BACKUP_RESTORED" "$backup_file"
    else
        echo "错误: 备份文件格式无效"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
}

# ============================================================
# 远程备份 (GitHub)
# ============================================================

# 推送到远程仓库
push_to_remote() {
    if [ "$ENABLE_REMOTE_BACKUP" != "true" ] || [ -z "$REMOTE_REPO" ]; then
        echo "远程备份未启用"
        return 0
    fi
    
    local backup_dir="$LOCAL_BACKUP_DIR/remote"
    mkdir -p "$backup_dir"
    
    # 创建当前备份
    local timestamp=$(date +%Y%m%d-%H%M%S)
    local backup_file="config-$timestamp.json.enc"
    
    # 脱敏加密
    local temp_file=$(mktemp)
    sanitize_config "$HOME/.config/openclaw/openclaw.json" "$temp_file"
    
    if [ -f "$ENCRYPTION_KEY_FILE" ]; then
        openssl enc -aes-256-cbc -salt -pbkdf2 -in "$temp_file" -out "$backup_dir/$backup_file" -pass file:"$ENCRYPTION_KEY_FILE"
    else
        echo "错误: 需要加密密钥才能远程备份"
        rm -f "$temp_file"
        return 1
    fi
    
    rm -f "$temp_file"
    
    # Git 操作
    cd "$backup_dir"
    git init -q 2>/dev/null || true
    git remote remove origin 2>/dev/null || true
    git remote add origin "$REMOTE_REPO"
    
    git add .
    git commit -m "backup: $timestamp" -q
    git push -f origin main 2>/dev/null || git push -f origin master 2>/dev/null
    
    echo "✅ 远程备份已推送"
    log_audit "REMOTE_BACKUP_PUSHED" "$backup_file"
}

# ============================================================
# 审计日志
# ============================================================

log_audit() {
    local action="$1"
    local detail="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$timestamp] $action: $detail" >> "$AUDIT_LOG"
}

# ============================================================
# 主入口
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        create)
            create_local_backup
            ;;
        restore)
            restore_backup "${2:-}"
            ;;
        remote)
            push_to_remote
            ;;
        list)
            ls -la "$LOCAL_BACKUP_DIR"
            ;;
        sanitize)
            sanitize_config "${2:-$HOME/.config/openclaw/openclaw.json}" "${3:-/tmp/sanitized.json}"
            cat "${3:-/tmp/sanitized.json}"
            ;;
        *)
            echo "用法: $0 {create|restore <file>|remote|list|sanitize [input] [output]}"
            ;;
    esac
fi