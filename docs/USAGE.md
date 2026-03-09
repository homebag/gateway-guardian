# Gateway Guardian 使用指南

本文档提供 Gateway Guardian 的详细使用说明。

## 目录

1. [安装](#安装)
2. [配置](#配置)
3. [运维](#运维)
4. [故障排查](#故障排查)
5. [高级功能](#高级功能)

---

## 安装

### 环境要求

- Linux 系统 (Ubuntu 20.04+)
- systemd
- bash 3.2+
- curl

### 安装步骤

#### 1. 克隆项目

```bash
git clone https://github.com/your-repo/gateway-guardian.git
cd gateway-guardian
```

#### 2. 配置权限

```bash
chmod +x install.sh guardian.sh
```

#### 3. 编辑配置

```bash
vim config/guardian.conf
```

必需配置：

```bash
# Discord 频道 ID (必需)
DISCORD_CHANNEL_ID="your-discord-channel-id"

# Discord Bot Token (可选，从环境变量读取)
# DISCORD_BOT_TOKEN="${DISCORD_BOT_TOKEN}"
```

#### 4. 执行安装

```bash
./install.sh
```

安装脚本会：
- 创建 systemd 服务
- 启动 Guardian
- 配置开机自启

---

## 配置

### 配置文件位置

- 主配置: `config/guardian.conf`
- 状态目录: `~/.openclaw/gateway-guardian/state/`
- 日志文件: `~/.openclaw/gateway-guardian/logs/`

### 核心参数

```bash
# ========== 检测参数 ==========
CHECK_INTERVAL=60          # 检测间隔 (秒)
HTTP_TIMEOUT=10           # HTTP 超时 (秒)
MAX_RETRIES=3             # 最大重试次数
COOLDOWN_PERIOD=90        # 冷却期 (秒)

# ========== 回滚参数 ==========
ENABLE_ROLLBACK=true      # 启用自动回滚
ROLLBACK_DEPTH=1          # 回滚深度

# ========== 通知参数 ==========
ENABLE_DISCORD_NOTIFY=true
DISCORD_CHANNEL_ID=""
NOTIFY_MIN_INTERVAL=300

# ========== 备份参数 ==========
ENABLE_GIT_BACKUP=true
LOCAL_BACKUP_DIR="$HOME/.openclaw/config-backup"
BACKUP_RETENTION_DAYS=30
```

### Discord 配置

1. 创建 Discord 应用：https://discord.com/developers/applications
2. 创建 Bot，获取 Token
3. 将 Bot 邀请到服务器
4. 获取频道 ID (启用开发者模式，右键频道 → 复制 ID)

---

## 运维

### 基本操作

```bash
# 启动
systemctl --user start openclaw-guardian

# 停止
systemctl --user stop openclaw-guardian

# 重启
systemctl --user restart openclaw-guardian

# 查看状态
systemctl --user status openclaw-guardian

# 查看日志
journalctl --user -u openclaw-guardian -f
```

### 手动操作

```bash
# 手动检测
./lib/detection.sh check

# 手动备份
./lib/backup.sh backup

# 手动回滚
./lib/recovery.sh rollback
```

### 监控

```bash
# 查看资源使用
systemctl --user status openclaw-guardian

# 查看内存
ps aux | grep guardian

# 查看日志大小
ls -lh ~/.openclaw/gateway-guardian/logs/
```

---

## 故障排查

### 问题：服务启动失败

```bash
# 检查日志
journalctl --user -u openclaw-guardian -e

# 检查配置语法
bash -n guardian.sh

# 手动运行测试
./lib/detection.sh check
```

### 问题：Discord 通知不工作

```bash
# 测试通知
./lib/notification.sh test

# 检查 Token
echo $DISCORD_BOT_TOKEN
```

### 问题：频繁误报

调整检测参数：

```bash
# 编辑配置
vim config/guardian.conf

# 增加检测间隔
CHECK_INTERVAL=120

# 增加最大重试
MAX_RETRIES=5

# 增加冷却期
COOLDOWN_PERIOD=300

# 重启生效
systemctl --user restart openclaw-guardian
```

### 问题：磁盘空间不足

清理备份：

```bash
# 手动清理旧备份
rm -rf ~/.openclaw/config-backup/*

# 减少保留天数
BACKUP_RETENTION_DAYS=7
```

---

## 高级功能

### GitHub 远程备份

```bash
# 1. 创建 GitHub 仓库

# 2. 生成 Personal Access Token
# Settings → Developer settings → Personal access tokens
# 权限: repo

# 3. 配置环境变量
export GITHUB_BACKUP_TOKEN="ghp_xxxxx"
export BACKUP_ENCRYPTION_KEY="your-secret-key"

# 4. 编辑配置
vim config/guardian.conf

ENABLE_GITHUB_BACKUP=true
GITHUB_REPO="https://github.com/username/repo"
GITHUB_BRANCH="config-backup"

# 5. 重启
systemctl --user restart openclaw-guardian
```

### 自定义检测脚本

编辑 `lib/detection.sh` 添加自定义检测：

```bash
# 例如：添加数据库检测
check_database() {
    mysql -h localhost -u root -p -e "SELECT 1" >/dev/null 2>&1
    return $?
}
```

### 集成其他通知渠道

编辑 `lib/notification.sh` 添加 Webhook：

```bash
# 添加 Webhook 通知
send_webhook() {
    local message="$1"
    curl -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "{\"content\": \"$message\"}"
}
```

---

## 性能优化

### 推荐配置

| 场景 | 检测间隔 | 最大重试 | 冷却期 |
|------|----------|----------|--------|
| 生产环境 | 60s | 3 | 90s |
| 测试环境 | 30s | 2 | 30s |
| 高可用 | 120s | 5 | 300s |

### 内存优化

Guardian 本身占用很小 (<10MB)，主要资源消耗在 Gateway。

```bash
# 限制 Guardian 内存
MemoryMax=100M

# 限制 CPU
CPUQuota=50%
```

---

## 卸载

```bash
# 停止服务
systemctl --user stop openclaw-guardian

# 禁用自启
systemctl --user disable openclaw-guardian

# 删除文件
rm -rf ~/gateway-guardian

# 删除服务
rm ~/.config/systemd/user/openclaw-guardian.service
```

---

## 常见问题 FAQ

**Q: Guardian 和 Gateway 是什么关系？**
A: Guardian 是守护进程，监测 Gateway。Gateway 负责处理实际业务。

**Q: 什么情况下会回滚？**
A: 连续 `MAX_RETRIES` 次修复失败后会自动回滚配置。

**Q: 如何禁用通知？**
A: 设置 `ENABLE_DISCORD_NOTIFY=false`

**Q: 回滚会回滚什么？**
A: 只回滚 `~/.openclaw/openclaw.json` 配置文件。

**Q: 支持哪些 Linux 发行版？**
A: 任何使用 systemd 的 Linux 发行版 (Ubuntu, Debian, CentOS, Fedora 等)

---

## 获取帮助

- 提交 Issue: https://github.com/your-repo/gateway-guardian/issues
- 查看日志: `journalctl --user -u openclaw-guardian -f`
