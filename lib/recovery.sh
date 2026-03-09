#!/bin/bash
# recovery.sh - 恢复与回滚模块

# ============================================================
# 日志函数备用定义 (如果主脚本未定义)
# ============================================================
if ! type log_info >/dev/null 2>&1; then
    log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
    log_info() { log "[INFO] $*"; }
    log_warn() { log "[WARN] $*"; }
    log_error() { log "[ERROR] $*"; }
    log_debug() { [[ "${DEBUG:-false}" == "true" ]] && log "[DEBUG] $*"; }
fi

# 配置默认值
GATEWAY_SERVICE="${GATEWAY_SERVICE:-openclaw-gateway}"
GATEWAY_STARTUP_WAIT="${GATEWAY_STARTUP_WAIT:-15}"
OPENCLAW_CMD="${OPENCLAW_CMD:-openclaw}"
WORKSPACE="${WORKSPACE:-~/workspace}"

# ============================================================
# 重启策略
# ============================================================

# 安全重启 Gateway
restart_gateway() {
    log_info "正在重启 Gateway..."
    
    # 先尝试优雅停止
    systemctl --user stop "${GATEWAY_SERVICE:-openclaw-gateway}" 2>/dev/null || true
    sleep 2
    
    # 强制杀死残留进程 (排除 guardian 自己!)
    # 注意: 只匹配 openclaw-gateway，不匹配 openclaw-guardian
    local pids=$(pgrep -f "openclaw-gateway" 2>/dev/null)
    if [[ -n "$pids" ]]; then
        for pid in $pids; do
            # 再次确认不是 guardian 进程
            local cmd=$(ps -p "$pid" -o comm= 2>/dev/null)
            if [[ "$cmd" != *"guardian"* ]]; then
                log_warn "发现残留进程 $pid ($cmd)，强制终止"
                kill -9 "$pid" 2>/dev/null || true
            fi
        done
        sleep 1
    fi
    
    # 启动
    systemctl --user start "${GATEWAY_SERVICE:-openclaw-gateway}"
    
    # 等待启动
    if wait_for_gateway "$GATEWAY_STARTUP_WAIT"; then
        log_info "✓ Gateway 重启成功"
        return 0
    else
        log_error "✗ Gateway 重启失败"
        return 1
    fi
}

# 智能重启 (带指数退避)
smart_restart() {
    local attempt="$1"
    local backoff=$(calculate_backoff "$attempt")
    
    log_info "智能重启 (第 ${attempt} 次，退避 ${backoff}s)"
    
    # 等待退避时间
    sleep "$backoff"
    
    # 执行重启
    if restart_gateway; then
        return 0
    fi
    
    return 1
}

# ============================================================
# 诊断修复
# ============================================================

# 运行 doctor 诊断
run_doctor() {
    log_info "运行 openclaw doctor..."
    
    local output
    output=$($OPENCLAW_CMD doctor 2>&1)
    local exit_code=$?
    
    log_debug "doctor 输出:\n$output"
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "✓ doctor 诊断通过"
        return 0
    else
        log_warn "✗ doctor 发现问题"
        return 1
    fi
}

# 运行 doctor --fix 修复
run_doctor_fix() {
    log_warn "尝试 doctor --fix 修复..."
    
    local output
    output=$($OPENCLAW_CMD doctor --fix 2>&1)
    local exit_code=$?
    
    log_debug "doctor --fix 输出:\n$output"
    
    if [[ $exit_code -eq 0 ]]; then
        log_info "✓ doctor --fix 执行完成"
        echo "$output"
        return 0
    else
        log_error "✗ doctor --fix 执行失败"
        return 1
    fi
}

# ============================================================
# Git 配置回滚
# ============================================================

# 获取当前 commit
get_current_commit() {
    git -C "$WORKSPACE" rev-parse HEAD 2>/dev/null
}

# 获取 commit 简短信息
get_commit_info() {
    local commit="$1"
    git -C "$WORKSPACE" log -1 --format="%h %s" "$commit" 2>/dev/null
}

# 查找稳定 commit (排除回滚/自动备份)
find_stable_commit() {
    local depth="${1:-$ROLLBACK_DEPTH}"
    
    log_debug "查找稳定 commit (深度: $depth)..."
    
    # 排除这些类型的 commit:
    # - rollback
    # - daily-backup
    # - auto-backup
    # - guardian
    
    local stable_commit=$(git -C "$WORKSPACE" log --oneline -50 | \
        grep -v -E "rollback|daily-backup|auto-backup|guardian" | \
        sed -n "$((depth + 1))p" | \
        awk '{print $1}')
    
    if [[ -n "$stable_commit" ]]; then
        log_debug "找到稳定 commit: $stable_commit"
        echo "$stable_commit"
        return 0
    else
        log_error "无法找到稳定 commit"
        return 1
    fi
}

# 执行回滚
do_rollback() {
    log_warn "========== 开始配置回滚 =========="
    
    local current_commit=$(get_current_commit)
    local stable_commit=$(find_stable_commit)
    
    if [[ -z "$stable_commit" ]]; then
        log_error "回滚失败: 无法找到稳定版本"
        return 1
    fi
    
    log_warn "当前: $(get_commit_info "$current_commit")"
    log_warn "目标: $(get_commit_info "$stable_commit")"
    
    # 记录回滚前的配置差异
    local diff_output
    diff_output=$(git -C "$WORKSPACE" diff "$current_commit" "$stable_commit" -- "*.json" 2>/dev/null)
    
    # 执行回滚
    if ! git -C "$WORKSPACE" reset --hard "$stable_commit" 2>&1 | tee -a "$LOG_FILE"; then
        log_error "git reset 失败"
        return 1
    fi
    
    # 创建回滚标记 commit
    git -C "$WORKSPACE" commit --allow-empty -m "rollback: auto from $(git rev-parse --short $current_commit) by guardian" 2>&1 | tee -a "$LOG_FILE"
    
    # 记录回滚信息
    record_rollback "$current_commit" "$stable_commit" "自动回滚"
    
    log_info "✓ 配置回滚完成"
    
    # 返回回滚详情 (供通知使用)
    echo "ROLLBACK_FROM=$current_commit"
    echo "ROLLBACK_TO=$stable_commit"
    echo "ROLLBACK_DIFF<<EOF"
    echo "$diff_output"
    echo "EOF"
    
    return 0
}

# ============================================================
# 完整恢复流程
# ============================================================

# 完整恢复流程
# 返回: 0=成功, 1=失败
full_recovery() {
    local attempt=$(get_failure_count)
    
    log_warn "========== 开始完整恢复流程 (第 ${attempt} 次) =========="
    
    add_recovery_history "recovery_start" "attempt" "第 ${attempt} 次"
    
    # 步骤 1: 诊断
    log_info "步骤 1/4: 诊断问题"
    run_doctor
    
    # 步骤 2: 尝试 doctor --fix
    log_info "步骤 2/4: 尝试自动修复"
    if run_doctor_fix; then
        # 等待并检测
        sleep 3
        if check_gateway; then
            log_info "✓ 自动修复成功"
            add_recovery_history "doctor_fix" "success" ""
            return 0
        fi
    fi
    
    # 步骤 3: 尝试重启
    log_info "步骤 3/4: 尝试重启"
    if restart_gateway; then
        # 检测是否恢复
        sleep 3
        if check_gateway; then
            log_info "✓ 重启修复成功"
            add_recovery_history "restart" "success" ""
            return 0
        fi
    fi
    
    # 步骤 4: 回滚配置
    log_info "步骤 4/4: 尝试配置回滚"
    
    if [[ "$ENABLE_ROLLBACK" != "true" ]]; then
        log_warn "回滚已禁用，跳过"
        add_recovery_history "rollback" "skipped" "回滚已禁用"
        return 1
    fi
    
    local rollback_result
    rollback_result=$(do_rollback)
    local rollback_exit=$?
    
    if [[ $rollback_exit -eq 0 ]]; then
        add_recovery_history "rollback" "success" "$rollback_result"
        
        # 重启 Gateway
        if [[ "$RESTART_AFTER_ROLLBACK" == "true" ]]; then
            if restart_gateway; then
                # 最终检测
                sleep 3
                if check_gateway; then
                    log_info "✓ 回滚修复成功"
                    return 0
                fi
            fi
        fi
    else
        add_recovery_history "rollback" "failed" ""
    fi
    
    log_error "✗ 所有恢复尝试均失败"
    return 1
}

# ============================================================
# 状态重置
# ============================================================

# 恢复成功后重置状态
reset_on_success() {
    reset_failure_count
    set_last_failure_time 0
    log_info "状态已重置"
}

# 记录失败
record_failure() {
    local new_count=$(increment_failure_count)
    set_last_failure_time
    log_warn "记录失败 (累计 ${new_count} 次)"
    echo "$new_count"
}
# ============================================================
# 别名函数 (兼容主脚本调用)
# ============================================================

# attempt_recovery - 综合恢复尝试
attempt_recovery() {
    log "开始恢复尝试..."
    
    # 先尝试 doctor --fix
    if run_doctor_fix 2>/dev/null; then
        log "doctor --fix 成功"
    fi
    
    # 重启 Gateway
    if restart_gateway; then
        log "✅ 恢复成功"
        return 0
    fi
    
    # 如果重启失败，尝试回滚
    if do_rollback; then
        if restart_gateway; then
            log "✅ 回滚后恢复成功"
            return 0
        fi
    fi
    
    log "❌ 恢复失败"
    return 1
}

# log 函数 (如果不存在)
if ! type log >/dev/null 2>&1; then
    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
    }
fi
