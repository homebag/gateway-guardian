#!/bin/bash
# security.sh - v3.0 安全模块
# 功能：加密、解密、密钥管理、安全检查

# ============================================================
# 密钥管理
# ============================================================

# 生成加密密钥
generate_encryption_key() {
    local key_file="${1:-$HOME/.openclaw/.backup-key}"
    
    if [ -f "$key_file" ]; then
        echo "密钥文件已存在: $key_file"
        read -p "是否覆盖? (y/N): " confirm
        [ "$confirm" != "y" ] && return 1
    fi
    
    # 生成 32 字节随机密钥
    openssl rand -base64 32 > "$key_file"
    chmod 600 "$key_file"
    
    echo "✅ 加密密钥已生成: $key_file"
    echo "⚠️ 请妥善保管此密钥，丢失将无法恢复备份！"
}

# 验证密钥
verify_encryption_key() {
    local key_file="${1:-$HOME/.openclaw/.backup-key}"
    
    if [ ! -f "$key_file" ]; then
        echo "❌ 密钥文件不存在"
        return 1
    fi
    
    # 检查权限
    local perms=$(stat -c %a "$key_file" 2>/dev/null)
    if [ "$perms" != "600" ]; then
        echo "⚠️ 密钥文件权限不安全: $perms (应为 600)"
        chmod 600 "$key_file"
        echo "已自动修复权限"
    fi
    
    echo "✅ 密钥文件有效"
    return 0
}

# ============================================================
# 加密/解密
# ============================================================

# 加密文件
encrypt_file() {
    local input_file="$1"
    local output_file="${2:-${input_file}.enc}"
    local key_file="${3:-$HOME/.openclaw/.backup-key}"
    
    if [ ! -f "$input_file" ]; then
        echo "错误: 输入文件不存在"
        return 1
    fi
    
    if [ ! -f "$key_file" ]; then
        echo "错误: 密钥文件不存在"
        return 1
    fi
    
    openssl enc -aes-256-cbc -salt -pbkdf2 \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$key_file"
    
    echo "✅ 文件已加密: $output_file"
}

# 解密文件
decrypt_file() {
    local input_file="$1"
    local output_file="$2"
    local key_file="${3:-$HOME/.openclaw/.backup-key}"
    
    if [ ! -f "$key_file" ]; then
        echo "错误: 密钥文件不存在"
        return 1
    fi
    
    openssl enc -aes-256-cbc -d -pbkdf2 \
        -in "$input_file" \
        -out "$output_file" \
        -pass file:"$key_file" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✅ 文件已解密: $output_file"
    else
        echo "❌ 解密失败 (密钥错误或文件损坏)"
        return 1
    fi
}

# ============================================================
# 安全检查
# ============================================================

# 运行安全检查
run_security_audit() {
    local issues=0
    
    echo "=== Guardian 安全审计 ==="
    echo ""
    
    # 1. 检查密钥文件
    echo "1. 加密密钥检查..."
    if [ -f "$HOME/.openclaw/.backup-key" ]; then
        local perms=$(stat -c %a "$HOME/.openclaw/.backup-key" 2>/dev/null)
        if [ "$perms" = "600" ]; then
            echo "   ✅ 密钥文件权限正确"
        else
            echo "   ⚠️ 密钥文件权限不安全: $perms"
            ((issues++))
        fi
    else
        echo "   ⚠️ 未找到加密密钥"
        ((issues++))
    fi
    
    # 2. 检查配置文件权限
    echo ""
    echo "2. 配置文件权限检查..."
    local config_perms=$(stat -c %a "$HOME/.openclaw/openclaw.json" 2>/dev/null)
    if [ -n "$config_perms" ] && [ "$config_perms" -le "640" ]; then
        echo "   ✅ 配置文件权限安全: $config_perms"
    else
        echo "   ⚠️ 配置文件权限可能不安全: $config_perms"
        ((issues++))
    fi
    
    # 3. 检查敏感数据暴露
    echo ""
    echo "3. 敏感数据暴露检查..."
    if grep -r "token" "$HOME/.openclaw/workspace/gateway-guardian/logs/" 2>/dev/null | grep -v "\[REDACTED\]" | head -3; then
        echo "   ⚠️ 日志中可能存在未脱敏的敏感数据"
        ((issues++))
    else
        echo "   ✅ 未发现敏感数据泄露"
    fi
    
    # 4. 检查备份目录
    echo ""
    echo "4. 备份目录检查..."
    local backup_dir="$HOME/.openclaw/backups/gateway-config"
    if [ -d "$backup_dir" ]; then
        local backup_count=$(ls -1 "$backup_dir" 2>/dev/null | wc -l)
        echo "   ✅ 备份目录存在，共 $backup_count 个备份"
    else
        echo "   ⚠️ 备份目录不存在"
        ((issues++))
    fi
    
    # 5. 检查 systemd 服务
    echo ""
    echo "5. 服务状态检查..."
    if systemctl --user is-active openclaw-guardian &>/dev/null; then
        echo "   ✅ Guardian 服务运行中"
    else
        echo "   ⚠️ Guardian 服务未运行"
        ((issues++))
    fi
    
    echo ""
    echo "=== 审计完成 ==="
    echo "发现问题: $issues 个"
    
    return $issues
}

# ============================================================
# 敏感数据扫描
# ============================================================

# 扫描配置文件中的敏感数据
scan_sensitive_data() {
    local file="${1:-$HOME/.openclaw/openclaw.json}"
    
    echo "=== 敏感数据扫描: $file ==="
    echo ""
    
    local found=0
    
    # 扫描 token
    if grep -o '"token"[[:space:]]*:[[:space:]]*"[^"]\{20,\}"' "$file" 2>/dev/null; then
        echo "⚠️ 发现 token 字段"
        ((found++))
    fi
    
    # 扫描 password
    if grep -oi '"password"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null; then
        echo "⚠️ 发现 password 字段"
        ((found++))
    fi
    
    # 扫描 apiKey
    if grep -oi '"apiKey"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" 2>/dev/null; then
        echo "⚠️ 发现 apiKey 字段"
        ((found++))
    fi
    
    echo ""
    echo "共发现 $found 个敏感字段"
    
    if [ $found -gt 0 ]; then
        echo ""
        echo "⚠️ 备份前将自动脱敏这些字段"
    fi
}

# ============================================================
# 主入口
# ============================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-}" in
        gen-key)
            generate_encryption_key "${2:-}"
            ;;
        verify-key)
            verify_encryption_key "${2:-}"
            ;;
        encrypt)
            encrypt_file "${2:-}" "${3:-}" "${4:-}"
            ;;
        decrypt)
            decrypt_file "${2:-}" "${3:-}" "${4:-}"
            ;;
        audit)
            run_security_audit
            ;;
        scan)
            scan_sensitive_data "${2:-}"
            ;;
        *)
            echo "用法: $0 {gen-key|verify-key|encrypt|decrypt|audit|scan}"
            echo ""
            echo "命令说明:"
            echo "  gen-key [file]    - 生成加密密钥"
            echo "  verify-key [file] - 验证密钥文件"
            echo "  encrypt in [out]  - 加密文件"
            echo "  decrypt in out    - 解密文件"
            echo "  audit             - 运行安全审计"
            echo "  scan [file]       - 扫描敏感数据"
            ;;
    esac
fi