# Gateway Guardian

Gateway 守护神 - 自动检测、自动修复、自动回滚

## 功能

- 🔍 自动检测 - 三层检测 (HTTP → 进程 → Systemd)
- 🔄 自动修复 - doctor --fix + 自动重启
- ⏪ 自动回滚 - Git 一键还原
- 💾 本地备份 - 保留 10 个版本
- 🔔 Discord 通知 - 实时推送

## 快速上手

```bash
# 克隆
git clone https://github.com/homebag/gateway-guardian.git
cd gateway-guardian

# 安装
./install.sh

# 配置
vim config/guardian.conf

# 启动
systemctl --user enable --now openclaw-guardian
```

## 检测逻辑

1. HTTP 检测 - 访问 /health
2. 进程检测 - pgrep
3. Systemd 检测 - systemctl is-active

判断: Systemd 正常 + HTTP 正常 = 正常

## 配置

| 参数 | 默认值 | 说明 |
|------|--------|------|
| CHECK_INTERVAL | 60 | 检测间隔(秒) |
| MAX_RETRIES | 3 | 失败次数阈值 |
| COOLDOWN_PERIOD | 90 | 冷却期(秒) |
| GATEWAY_PORT | 18789 | Gateway 端口 |

## 备份

- 本地: ~/.openclaw/backups/gateway-config/
- 保留: 最近 10 个版本

## LICENSE

MIT
