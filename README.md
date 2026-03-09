# 🚀 Gateway Guardian

<p align="center">
  <img src="https://img.shields.io/badge/version-3.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="License">
  <img src="https://img.shields.io/badge/bash-3.2+-orange" alt="Bash">
</p>

> 🛡️ OpenClaw Gateway 的智能守护系统 - 自动检测、恢复与配置回滚

Gateway Guardian 是专为 Gateway 类服务设计的智能守护进程，提供多层健康检测、自动故障恢复、配置回滚和实时告警通知功能。

## ✨ 特性

| 特性 | 说明 |
|------|------|
| 🏥 多层健康检测 | HTTP → 进程 → 服务状态，三层检测确保准确 |
| 🔄 智能恢复 | 自动重启、配置回滚，一键修复 |
| 💾 Git 备份 | 本地/远程 Git 备份，支持加密脱敏 |
| 🔔 实时告警 | Discord/Webhook 实时通知 |
| ⚙️ 完全配置化 | 所有参数可通过配置文件调整 |
| 📊 状态持久化 | 失败计数持久化，重启不丢失 |

## 📊 与其他方案对比

| 方案 | 检测方式 | 自动回滚 | 通知 | 状态持久化 |
|------|----------|----------|------|------------|
| systemd restart | 仅进程 | ❌ | ❌ | ❌ |
| Prometheus + Alertmanager | 指标检测 | ❌ | ✅ | ✅ |
| **Gateway Guardian** | 多层检测 | ✅ | ✅ | ✅ |

## 🚀 快速开始

### 1. 安装

```bash
# 克隆项目
git clone https://github.com/your-repo/gateway-guardian.git
cd gateway-guardian

# 安装
chmod +x install.sh
./install.sh
```

### 2. 配置

```bash
# 复制配置模板
cp config/guardian.conf config/guardian.conf.example

# 编辑配置
vim config/guardian.conf
```

必需配置项：

```bash
# Discord 通知 (必需)
DISCORD_CHANNEL_ID="your-channel-id"

# Gateway 端口 (默认 18789)
GATEWAY_PORT=18789
```

### 3. 启动

```bash
# 启动守护进程
systemctl --user start openclaw-guardian

# 查看状态
systemctl --user status openclaw-guardian

# 查看日志
journalctl --user -u openclaw-guardian -f
```

## ⚙️ 配置说明

### 检测参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `CHECK_INTERVAL` | 60 | 检测间隔 (秒) |
| `HTTP_TIMEOUT` | 10 | HTTP 检测超时 (秒) |
| `MAX_RETRIES` | 3 | 最大重试次数 |
| `COOLDOWN_PERIOD` | 90 | 冷却期 (秒) |

### 恢复参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `ENABLE_ROLLBACK` | true | 启用自动回滚 |
| `ROLLBACK_DEPTH` | 1 | 回滚深度 |
| `BACKUP_INTERVAL` | 3600 | 备份间隔 (秒) |

### 通知参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `ENABLE_DISCORD_NOTIFY` | true | 启用 Discord 通知 |
| `NOTIFY_MIN_INTERVAL` | 300 | 通知最小间隔 (秒) |

## 📁 项目结构

```
gateway-guardian/
├── guardian.sh              # 主入口脚本
├── install.sh              # 安装脚本
├── LICENSE                 # MIT 许可证
├── README.md               # 本文档
├── config/
│   └── guardian.conf       # 配置文件
└── lib/
    ├── detection.sh        # 检测模块
    ├── recovery.sh         # 恢复模块
    ├── backup.sh          # 备份模块
    ├── notification.sh     # 通知模块
    ├── security.sh         # 安全模块
    └── utils.sh           # 工具函数
```

## 🔧 检测逻辑

```
┌─────────────────┐
│  L1: HTTP 检测  │  ← /health 端点
└────────┬────────┘
         ↓ 失败
┌─────────────────┐
│ L2: 进程检测    │  ← pgrep 检查
└────────┬────────┘
         ↓ 失败
┌─────────────────┐
│ L3: 服务检测    │  ← systemctl 检查
└────────┬────────┘
         ↓ 全部失败
    ┌────────┐
    │ 触发修复 │
    └────────┘
```

### 智能判断逻辑

- ✅ **systemd 正常** → 直接判定为正常 (最可靠)
- ⚠️ **HTTP + 进程都失败** → 才触发报警
- 🔄 **连续失败 3 次** → 执行自动修复
- 🔙 **修复失败** → 自动回滚配置

## 💾 备份与回滚

### 本地备份

自动备份到 `~/.openclaw/backups/`，保留 30 天。

### 远程备份 (可选)

支持 GitHub 私有仓库备份，保留完整配置文件用于故障恢复。

```bash
# 配置环境变量
export GITHUB_BACKUP_TOKEN="your-token"
export BACKUP_ENCRYPTION_KEY="your-key"

# 启用远程备份
ENABLE_GITHUB_BACKUP=true
GITHUB_REPO="https://github.com/user/repo"
```

## 🔔 通知示例

### 启动通知
```
🛡️ Gateway Guardian 已启动
检测间隔: 60s
最大重试: 3 次
```

### 故障告警
```
⚠️ Gateway 异常
连续失败: 2/3
正在尝试修复...
```

### 恢复成功
```
✅ Gateway 已恢复
修复耗时: 23秒
```

### 回滚通知
```
🔄 配置已回滚
原因: 连续修复失败
变更: gateway.bind (lan → localhost)
```

## 🛠️ 常见问题

### Q: 如何手动测试检测？
```bash
./lib/detection.sh check
```

### Q: 如何禁用自动回滚？
```bash
# 编辑配置
vim config/guardian.conf

# 设置
ENABLE_ROLLBACK=false

# 重启服务
systemctl --user restart openclaw-guardian
```

### Q: 如何查看详细日志？
```bash
# 实时日志
journalctl --user -u openclaw-guardian -f

# 只看错误
journalctl --user -u openclaw-guardian -p err
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

MIT License - 查看 [LICENSE](LICENSE) 了解更多

---

<p align="center">
  <sub>Built with ❤️ for OpenClaw</sub>
</p>
