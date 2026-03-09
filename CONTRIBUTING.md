# 贡献指南

感谢你对 Gateway Guardian 的关注！

## 如何贡献

### 报告问题

如果你发现 Bug 或有功能建议：

1. 搜索现有 Issue，避免重复
2. 创建新 Issue，包含：
   - 清晰的问题描述
   - 复现步骤
   - 环境信息
   - 日志 (如有)

### 提交代码

1. Fork 项目
2. 创建特性分支 (`git checkout -b feature/xxx`)
3. 编写代码并测试
4. 提交 Commit (`git commit -m 'Add xxx'`)
5. 推送分支 (`git push origin feature/xxx`)
6. 创建 Pull Request

### 代码规范

- 使用 bash 3.2+ 兼容语法
- 添加注释说明
- 函数命名: `snake_case`
- 变量命名: `UPPER_CASE` (常量) / `lower_case` (变量)

### Commit 消息格式

```
<type>: <简短描述>

<详细说明>

Closes #<issue-number>
```

类型:
- `feat`: 新功能
- `fix`: Bug 修复
- `docs`: 文档更新
- `refactor`: 代码重构
- `test`: 测试
- `chore`: 维护

---

## 开发环境

```bash
# 克隆
git clone https://github.com/your-repo/gateway-guardian.git
cd gateway-guardian

# 安装依赖
chmod +x install.sh

# 测试
./test.sh
```

---

## 许可证

MIT License - 详见 [LICENSE](LICENSE)
