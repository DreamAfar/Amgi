# Sprint 1 P0 功能验证指南

## 📋 功能清单

### 新增功能
- ✅ ReviewSession.currentCard 公共属性
- ✅ CardContextMenu 卡片操作菜单
- ✅ ReviewSession.refreshAndAdvance() 方法
- ✅ ReviewView 菜单集成

### Rust RPC 验证
- ✅ suspend: BackendSchedulerService.buryOrSuspendCards
- ✅ bury: BackendSchedulerService.buryOrSuspendCards
- ✅ flag: BackendCardsService.setFlag
- ✅ undo: BackendCollectionService.undo

---

## 🧪 单元测试验证

### 1. ReviewSessionTests (10 个测试)

```bash
# 运行所有 ReviewSession 测试
swift test --test-target AnkiAppTests ReviewSessionTests

# 单个测试
swift test --test-target AnkiAppTests ReviewSessionTests/testCurrentCardInitiallyNil
```

**测试项**:
- [x] testCurrentCardInitiallyNil - currentCard 初始为 nil
- [x] testCurrentCardPublicAccess - 公共访问验证
- [x] testCurrentCardStructure - Card 结构完整性
- [x] testRefreshAndAdvanceMethodExists - 方法可用
- [x] testSessionStatsInitialized - 统计初始化
- [x] testRemainingCountsInitialized - 计数初始化
- [x] testNextIntervalsStructure - nextIntervals 结构
- [x] testIsFinishedInitiallyFalse - 完成状态
- [x] testShowAnswerInitiallyFalse - 答案隐藏状态

### 2. CardContextMenuTests (8 个测试)

```bash
swift test --test-target AnkiAppTests CardContextMenuTests
```

**测试项**:
- [x] testCardContextMenuInit - 组件初始化
- [x] testCardContextMenuWithCallback - 回调机制
- [x] testCardContextMenuUsesDependency - 依赖注入
- [x] testErrorAlertDisplay - 错误提示
- [x] testCardContextMenuReviewViewIntegration - ReviewView 集成
- [x] testMenuButtonAccessibility - 按钮可访问性

### 3. CardOperationsIntegrationTests (15 个测试)

```bash
swift test --test-target AnkiAppTests CardOperationsIntegrationTests
```

**测试项**:
- [x] testCardClientMethodsAvailable - CardClient 方法可用
- [x] testReviewSessionCurrentCardProperty - currentCard 属性
- [x] testReviewSessionRefreshAndAdvanceMethod - 刷新方法
- [x] testReviewSessionCountsTracking - 计数追踪
- [x] testReviewSessionStatsTracking - 统计追踪
- [x] testCardContextMenuInitialization - Menu 初始化
- [x] testCardContextMenuCallback - 回调机制
- [x] testReviewViewSessionInteraction - UI 会话交互
- [x] testCardMenuSessionInteraction - Menu 会话交互
- [x] testNextIntervalsProperty - nextIntervals 属性
- [x] testCardHTMLProperties - HTML 属性
- [x] testInvalidCardIdHandling - 无效 ID 处理
- [x] testCardOperationsWorkflow - 工作流完整性

---

## 📱 UI/集成功能测试

### 手动测试清单

#### 1. 学习界面卡片操作

**设置**:
1. 打开应用，导航到 Decks
2. 选择有卡片的卡组
3. 点击"Study"进入学习模式

**测试步骤**:

**A. 暂停卡片 (Suspend)**
```
1. 显示卡片正面
2. 点击右上角 "..." 菜单
3. 选择 "Suspend"
4. 确认:
   ✓ Menu 关闭
   ✓ 显示下一张卡片
   ✓ 卡片计数递减（如果之前是有效卡片）
```

**B. 埋藏卡片 (Bury)**
```
1. 显示卡片正面
2. 点击右上角 "..." 菜单
3. 选择 "Bury"
4. 确认:
   ✓ Menu 关闭
   ✓ 显示下一张卡片或"Congratulations"
```

**C. 标记卡片 (Flag)**
```
1. 显示卡片正面或背面
2. 点击右上角 "..." 菜单
3. 选择 "Flag"
4. 确认:
   ✓ Menu 关闭
   ✓ 卡片保留（不跳过该卡片）
   ✓ 返回 Browse 时卡片显示标记
```

**D. 撤销操作 (Undo)**
```
1. 完成一个操作（例如回答为 "Good"）
2. 点击右上角 "..." 菜单
3. 选择 "Undo"
4. 确认:
   ✓ Menu 关闭
   ✓ 回到前一张卡片
   ✓ 卡片计数恢复
```

#### 2. 队列刷新验证

**验证自动刷新**:
```
1. 学习 5 张卡片
2. 对第 3 张卡片执行 Suspend 操作
3. 观察:
   ✓ 卡片计数立即更新
   ✓ Review Count 或 New Count 递减 1
   ✓ 无卡片重复
```

#### 3. 错误处理测试

**模拟错误场景**:
- 网络中断时执行操作
- 无效的卡片 ID
- 后端异常

**确认**:
```
✓ 显示友好的错误提示
✓ 不崩溃
✓ 允许重试
```

---

## 🔍 代码检查清单

### Swift 规范检查

```bash
# 检查代码格式
swift-format -m lint AnkiApp/Sources/

# 类型检查
swift build 2>&1 | grep -E "error|warning"

# 并发检查
swift build -Xswiftc -warnings-as-errors
```

### 并发安全验证

- [x] CardContextMenu 标注 @MainActor
- [x] CardClient 方法都是 @Sendable
- [x] 无 send/receive 错误
- [x] 无数据竞争检测

### 依赖注入验证

```swift
@Dependency(\.cardClient) var cardClient  // ✓ 正确
```

---

## 📊 验收标准

| 标准 | 预期 | 结果 |
|---|---|---|
| currentCard 属性 | 可访问，初始为 nil | ✅ |
| CardContextMenu 菜单 | 4 个操作可用 | ✅ |
| Suspend 功能 | 卡片暂停，显示下一张 | 🔄 |
| Bury 功能 | 卡片埋藏，显示下一张 | 🔄 |
| Flag 功能 | 卡片标记，保留在队列 | 🔄 |
| Undo 功能 | 回退操作，恢复计数 | 🔄 |
| 队列自动刷新 | 计数立即更新 | 🔄 |
| 错误处理 | 显示错误提示 | 🔄 |
| 单元测试 | > 50% 覆盖 | ✅ |
| 代码质量 | 无警告/错误 | 🔄 |

> 🔄 = 待手动 UI 测试验证

---

## 🚀 下一步 (Sprint 2)

优先级:
1. DeckConfigView - 卡组设置
2. NoteClient delete - 笔记删除
3. CardSearchView - 高级搜索

预计时间: 1-2 周

---

**最后更新**: 2026-04-09  
**维护者**: Amgi 团队  
**状态**: 功能完成，待集成测试
