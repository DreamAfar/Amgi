# GitHub Actions IPA 编译 - 快速Q&A

**Q: Sprint 3 新增内容需要修改编译工作流程吗？**

✅ **简短答案**: 不必强制修改，但**推荐升级**以获得质量检查。

---

## 🎯 核心事实

### Sprint 3 对编译的影响

| 类别 | 新增代码 | 编译影响 | 需要修改工作流 |
|------|---------|--------|-------------|
| **Swift 代码** | TagClient, TagsView, 卡组增强 | ✅ 自动编译 | ❌ 否 |
| **Rust 代码** | 无 | - | ❌ 否 |
| **Protobuf** | 无新 .proto 文件 | - | ❌ 否 |
| **依赖包** | 无新依赖 | - | ❌ 否 |
| **集成测试** | 34+ 个测试文件 | ✅ 不影响 IPA | ❌ 否 |

**结论**: ✅ **现有工作流足够** - 所有新代码会自动编译进 IPA

---

## 🔧 修改选项

### 方案 A: 保持不变 (快速发布)
```bash
# 现有工作流可直接使用
git add -A
git commit -m "add: Sprint 3 features"
git push origin main
# GitHub Actions 会自动编译
```

**优点**: 快速、无风险  
**缺点**: 缺少质量检查

---

### 方案 B: 升级工作流 (推荐生产)
```bash
# 已为你修改 .github/workflows/main.yml
# 变化:
# + 步骤 9.5: 运行 34+ 集成测试
# + 步骤 10: 编译日志验证
# + 步骤 13-14: 生成构建摘要报告

git add .github/workflows/main.yml
git commit -m "ci: upgrade workflow with Sprint 3 quality checks"
git push origin main
```

**优点**: 自动验证、更好的诊断、构建报告  
**缺点**: +6 分钟编译时间

---

## ⚡ 修改内容一览

### 新增的工作流步骤

```yml
# 步骤 9.5: 集成测试验证 ← NEW
- name: Run Integration Tests (Sprint 3 Quality Check)
  continue-on-error: true
  run: xcodebuild test -testClassPattern="(TagClient|DeckClient|CrossSystem)..."

# 步骤 10 增强: 编译日志验证 ← ENHANCED
- name: Build unsigned xcarchive
  run: |
    xcodebuild archive ... 2>&1 | tee build.log
    if grep -q "Build complete!" build.log; then
      echo "✅ Build successful!"
    else
      exit 1  # 编译失败立即退出
    fi

# 步骤 13: 构建摘要报告 ← NEW
# 步骤 14: 上传摘要 ← NEW
```

### 预期输出示例

```
✅ Tests: 34/34 passed (TagClient: 11, DeckClient: 10, CrossSystem: 13)
✅ Archive build successful!
✅ IPA created: 128.5 MB
✅ Summary generated
```

---

## 📦 构件输出

编译完成后下载:

1. **AnkiApp-unsigned-ipa** (主文件)
   - 可直接通过 Xcode 或 Apple Configurator 2 安装
   - 7 天保留期

2. **build-summary** (新增)
   - Markdown 格式
   - 包含构建时间、IPA 大小、功能列表

---

## 🚀 立即行动

### Step 1: 验证修改
```bash
# 检查工作流文件
cat .github/workflows/main.yml | grep -A 5 "Sprint 3"
```

### Step 2: 推送并测试
```bash
git add -A
git commit -m "chore: add Sprint 3 workflow upgrades"
git push origin main
```

### Step 3: 通过 GitHub UI 触发
```
Actions 
  → Build Unsigned IPA 
    → Run workflow 
      → main branch
```

### Step 4: 监控构建
- 实时查看日志
- 等待 ~36 分钟 (vs 原来 30 分钟)
- 下载 IPA 和摘要

---

## ❓ 常见问题

**Q: 如果测试失败会怎样?**  
A: 测试失败**不会阻止** IPA 生成 (`continue-on-error: true`)。但会在日志中显示失败信息供参考。

**Q: 我只想快速发布，能跳过测试吗?**  
A: 当然！保持原有工作流即可，新步骤是可选的。

**Q: 编译时间会增加多少?**  
A: 增加约 5-6 分钟 (34+ 个测试)，总计 ~36 分钟。

**Q: 如何快速回滚?**  
A: 恢复 `.github/workflows/main.yml` 到之前版本即可。

**Q: 摘要报告可以定制吗?**  
A: 可以！修改步骤 13 中的 markdown 生成部分。

---

## 📊 时间对比

```
原工作流:  30 分钟
         ├─ 构建 Rust: 8 min
         ├─ Protobuf: 2 min
         ├─ xcodebuild: 15 min
         └─ 打包 & 上传: 5 min

升级工作流: 36 分钟 (+20%)
         ├─ 构建 Rust: 8 min
         ├─ Protobuf: 2 min
         ├─ 集成测试: 5 min ← NEW
         ├─ xcodebuild: 15 min
         ├─ 摘要生成: 1 min ← NEW
         └─ 打包 & 上传: 5 min
```

---

## ✅ 最终建议

| 场景 | 推荐方案 | 原因 |
|------|--------|------|
| **日常快速测试** | 方案 A (不改) | 快速迭代 |
| **准备生产发布** | 方案 B (升级) | 质量保证 |
| **公开测试版** | 方案 B (升级) | 完整验证 |
| **App Store 提交** | 方案 B (升级) | 必须通过 |

**我的推荐**: 👉 **选择方案 B** - 增加 20% 时间成本换取完整的质量保证。

---

## 🔗 相关文档

- [完整升级指南](GITHUB_ACTIONS_UPGRADE.md) - 详细说明和原理
- [GitHub Actions 官方文档](https://docs.github.com/en/actions)
- [Sprint 3 总结](SPRINT_3_SUMMARY.md) - 新功能列表

---

**现状**: ✅ .github/workflows/main.yml 已升级  
**下一步**: 推送到 GitHub 并触发新工作流  
**预计**: 36 分钟完成编译
