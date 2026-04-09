# Sprint 3 集成测试指南

## 📋 概述

本指南介绍 Sprint 3 新增的全面集成测试套件，涵盖标签管理、卡组管理、卡片操作及跨系统集成。

---

## 🧪 测试套件结构

### 1. **TagClientIntegrationTests** (`TagClientIntegrationTests.swift`)
**位置**: `AnkiApp/Sources/Browse/`

#### 测试覆盖范围
- ✅ `getAllTags()` - 获取所有标签
- ✅ `addTag(tag)` - 添加标签
- ✅ `removeTag(tag)` - 删除标签
- ✅ `renameTag(oldName, newName)` - 重命名标签
- ✅ `findNotesByTag(tag)` - 按标签查找笔记

#### 主要测试场景
| 测试名 | 目的 | 验证点 |
|--------|------|--------|
| `testGetAllTagsReturnsEmptyArrayInitially` | 初始状态 | 空数组 |
| `testGetAllTagsReturnsMultipleTags` | 多标签检索 | 所有标签返回 |
| `testAddTagSucceedsWithValidName` | 有效标签添加 | 标签可用 |
| `testAddTagWithEmptyNameThrows` | 空名验证 | 抛出异常 |
| `testRemoveTagSucceedsWithExistingTag` | 标签删除 | 不再存在 |
| `testRenameTagSucceedsWithValidNames` | 标签重命名 | 旧名消失，新名出现 |
| `testCompleteTagLifecycle` | 完整生命周期 | 创建→重命名→查询→删除 |
| `testMultipleConcurrentOperations` | 并发操作 | 无错误执行 |

#### 运行测试
```bash
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -testClassPattern="TagClientIntegrationTests"
```

---

### 2. **DeckClientIntegrationTests** (`DeckClientIntegrationTests.swift`)
**位置**: `AnkiApp/Sources/Decks/`

#### 测试覆盖范围
- ✅ `getDeckTree(now)` - 获取卡组树
- ✅ `create(name)` - 创建卡组
- ✅ `rename(id, name)` - 重命名卡组
- ✅ `delete(id)` - 删除卡组
- ✅ `getDeckConfig(id)` - 获取卡组配置

#### 主要测试场景
| 测试名 | 目的 | 验证点 |
|--------|------|--------|
| `testGetDeckTreeReturnsValidStructure` | 树结构获取 | 树结构有效 |
| `testCreateDeckReturnsPositiveId` | 卡组创建 | 返回正数ID |
| `testCreateMultipleDecksReturnsDifferentIds` | 多卡组创建 | ID不同 |
| `testCreateDeckWithEmptyNameThrows` | 空名验证 | 抛出异常 |
| `testRenameDeckSucceedsWithNewName` | 卡组重命名 | 名称更新 |
| `testDeleteDeckRemovesAllChildren` | 级联删除 | 子卡组删除 |
| `testCompleteDeckLifecycle` | 完整生命周期 | 创建→重命名→配置→删除 |
| `testDeckHierarchyOperations` | 层级操作 | 多卡组结构 |

#### 运行测试
```bash
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -testClassPattern="DeckClientIntegrationTests"
```

---

### 3. **CrossSystemIntegrationTests** (`CrossSystemIntegrationTests.swift`)
**位置**: `AnkiApp/Sources/Shared/`

#### 测试覆盖范围
- ✅ 卡组 + 卡片工作流
- ✅ 标签 + 笔记工作流
- ✅ 全系统学习工作流
- ✅ 搜索集成
- ✅ 错误恢复
- ✅ 状态一致性
- ✅ 性能测试

#### 主要测试场景
| 测试类别 | 测试数量 | 目的 |
|---------|---------|------|
| **系统集成** | 8 | 验证多系统协作 |
| **工作流** | 3 | 真实用户场景 |
| **错误处理** | 1 | 恢复能力 |
| **一致性** | 1 | 状态同步 |
| **性能** | 2 | 大规模操作 |

#### 重要测试场景详解

##### 📍 Deck + Cards 工作流
```swift
// 流程：创建卡组 → 获取卡片 → 本身作答
1. 创建学习卡组 (StudyDeck)
2. 获取待复习卡片
3. 验证卡组存在于树中
4. 清理卡组
```

##### 📍 Complete Study Workflow (完整学习工作流)
```swift
// 完整用户场景
1. 创建学习卡组
2. 创建组织标签 (优先级、难度)
3. 获取待复习卡片
4. 查询笔记并关联标签
5. 作答卡片
6. 搜索标签卡片
7. 清理所有资源
```

##### 📍 Performance Tests (性能测试)
```swift
// 50个标签创建 < 10秒
// 20个卡组创建 < 10秒
// 树检索 < 1秒
```

#### 运行测试
```bash
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -testClassPattern="CrossSystemIntegrationTests"
```

---

## 🚀 完整测试运行

### 一次性运行所有 Sprint 3 集成测试
```bash
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -testClassPattern="(TagClientIntegrationTests|DeckClientIntegrationTests|CrossSystemIntegrationTests)"
```

### 运行带详细输出
```bash
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -testClassPattern="TagClientIntegrationTests" \
  -verbose
```

### 在模拟器上运行
```bash
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -testClassPattern="DeckClientIntegrationTests"
```

---

## ✅ 测试成功标准

### 全部测试通过条件
- ✅ 所有 **26+ 个测试用例** 通过
- ✅ 无编译警告
- ✅ 覆盖率 ≥ 80%（关键路径）
- ✅ 性能测试完成时间 < 阈值

### 预期结果统计
```
总测试数: 26+
├── TagClient: 11 tests
├── DeckClient: 10 tests
├── CrossSystem: 13 tests
└── 预期通过率: 100%
```

---

## 🔧 Mock 实现

### 测试依赖注入
所有客户端均有 `testValue` 实现：

```swift
// TagClient 模拟
extension TagClient {
    static var testValue: TagClient { 
        TagClient(
            getAllTags: { [] },
            addTag: { _ in },
            removeTag: { _ in },
            renameTag: { _, _ in },
            findNotesByTag: { _ in [] }
        )
    }
}
```

### 使用模拟值
```swift
@Dependency(\.tagClient) var tagClient  // 自动注入模拟
```

---

## 🐛 调试技巧

### 单个测试调试
```swift
// Xcode 中：
1. 点击测试方法名左侧的钻石图标
2. 选择 "Run [TestName]"
3. 添加断点进行步进调试
```

### 查看完整测试日志
```bash
// 启用详细日志输出
xcodebuild test \
  -scheme AnkiApp \
  -testClassPattern="TagClientIntegrationTests" \
  -verbose 2>&1 | tee test.log
```

### 快速失败识别
```swift
// 重新运行最后失败的测试
xcodebuild test -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -only-testing="AnkiApp/TagClientIntegrationTests/testAddTagWithEmptyNameThrows"
```

---

## 📊 测试覆盖率报告

### 生成覆盖率报告
```bash
xcodebuild test \
  -project AnkiApp/AnkiApp.xcodeproj \
  -scheme AnkiApp \
  -enableCodeCoverage YES \
  -resultBundlePath BuildArtifacts.xcresult

xcrun xccov view BuildArtifacts.xcresult --report
```

### 预期覆盖范围
| 组件 | 覆盖率 | 关键路径 |
|------|--------|---------|
| TagClient | 95% | ✅ getAllTags, addTag, removeTag |
| DeckClient | 93% | ✅ create, rename, delete |
| SearchClient | 85% | ✅ search, searchNotes |
| Integration | 90% | ✅ 完整工作流 |

---

## 🔄 持续集成 (CI)

### 测试在 CI 中自动运行
```yaml
# 示例 GitHub Actions 配置
- name: Run Integration Tests
  run: |
    xcodebuild test \
      -project AnkiApp/AnkiApp.xcodeproj \
      -scheme AnkiApp \
      -testClassPattern="(Tags|Decks|CrossSystem)ClientIntegrationTests"
  timeout-minutes: 15
```

---

## 📝 已知问题 & 解决方案

### 问题 1: 模拟器启动缓慢
**症状**: 测试超时
**解决**: 预先启动模拟器
```bash
xcrun simctl boot "iPhone 17 Pro Max"
```

### 问题 2: 测试数据不一致
**症状**: 测试间隔状态污染
**解决**: 每个测试都有独立的 setUp/tearDown

### 问题 3: 并发测试失败
**症状**: 多并发操作时顺序不定
**解决**: 使用 XCTestExpectation 同步

---

## 🎯 下一步行动

1. **验证所有测试通过**
   ```bash
   xcodebuild test -scheme AnkiApp
   ```

2. **检查覆盖率指标**
   - 目标：≥ 80%

3. **正式集成到 CI 流程**
   - `.github/workflows/test.yml`

4. **文档更新**
   - 更新 TESTING.md
   - 创建测试最佳实践指南

---

## 📚 参考链接

- [XCTest 文档](https://developer.apple.com/documentation/xctest)
- [Dependencies 库](https://github.com/pointfreeco/swift-dependencies)
- [Swift Testing (新框架)](https://developer.apple.com/documentation/testing)

---

**最后更新**: 2024
**维护者**: iOS-Anki 开发团队
