#!/bin/bash
# backup.sh - v3.2 简化备份模块
# 功能：本地备份 (不脱敏、不加密，保留完整配置用于恢复)

source "${GUARDIAN_DIR:-$HOME/.openclaw/workspace/gateway-guardian}/config/guardian.conf"

# ============================================================
# 本地备份 (简化版 - 不脱敏不加密)
# ============================================================

create_local_backup() {
    local backup_name="backup-$(date +%Y%m%d-%H%M%S).json.gz"
    local backup_path="$LOCAL_BACKUP_DIR/$backup_name"
    
    mkdir -p "$LOCAL_BACKUP_DIR"
    
    # 直接备份原始配置 (不脱敏，用于恢复)
    local config_source="$HOME/.openclaw/openclaw.json"
    
    # 压缩
    gzip -c "$config_source" > "$backup_path"
    
    echo "✅ 备份已创建: $backup_path"
    
    # 清理旧备份
    cleanup_old_backups
    
    echo "$backup_path"
}

cleanup_old_backups() {
    local count=$(ls -1 "$LOCAL_BACKUP_DIR"/*.json.gz 2>/dev/null | wc -l)
    
    if [ "$count" -gt "$MAX_BACKUPS" ]; then
        local to_delete=$((count - MAX_BACKUPS))
        ls -1t "$LOCAL_BACKUP_DIR"/*.json.gz | tail -n "$to_delete" | xargs rm -f 2>/dev/null
        echo "已清理 $to_delete 个旧备份"
    fi
}

restore_backup() {
    local backup_file="$1"
    
    if [ ! -f "$backup_file" ]; then
        echo "错误: 备份文件不存在"
        return 1
    fi
    
    # 解压
    local config_dest="$HOME/.openclaw/openclaw.json"
    gunzip -c "$backup_file" > "$config_dest"
    
    echo "✅ 配置已恢复: $config_dest"
}

list_backups() {
    ls -1t "$LOCAL_BACKUP_DIR"/*.json.gz 2>/dev/null || echo "无备份"
}

# 命令行入口
case "${1:-}" in
    create) create_local_backup ;;
    restore) restore_backup "$2" ;;
    list) list_backups ;;
esac
