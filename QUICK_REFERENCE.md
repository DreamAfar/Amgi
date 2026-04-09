# 快速参考 - Sprint 1 + Sprint 2 功能指南

**版本**: 2026-04-09  
**范围**: Amgi iOS App 功能快速参考

---

## 🎯 新增功能概览

### Sprint 1: 卡片操作菜单 ✅

**位置**: ReviewView → 卡片上方右侧菜单

**可用操作**:
- 🔴 **Suspend** - 暂停卡片，稍后复习
- 📚 **Bury** - 埋藏卡片，今天隐藏
- 🚩 **Flag** - 标记卡片为重要
- ↩️ **Undo** - 撤销上一个操作

**使用流程**:
```
显示卡片 → 点击 "..." 菜单 → 选择操作 → 自动刷新队列 → 显示下一张
```

**文件**:
- `AnkiApp/Sources/Shared/CardContextMenu.swift` - 菜单 UI
- `AnkiApp/Sources/Review/ReviewSession.swift` - 会话管理
- `Sources/AnkiClients/CardClient.swift` - API

---

### Sprint 2: 卡组设置 ✅

**位置**: Decks Tab → 选择卡组 → 右上角齿轮⚙️

**可配置项**:
- 📅 **每日新卡数** (1-1000)
- 📅 **每日复习卡** (1-10000)
- 📝 **学习步骤** (e.g., "1m 10m")
- 📝 **复习步骤** (e.g., "10m")
- 🔍 **启用 FSRS** (开关)
- ⚖️ **FSRS 权重** (文本输入)

**使用流程**:
```
DeckDetailView → 点击 ⚙️ Settings → 编辑参数 → Save → 自动保存
```

**文件**:
- `AnkiApp/Sources/Decks/DeckConfigView.swift` - 配置 UI
- `AnkiApp/Sources/Decks/DeckDetailView.swift` - 集成
- `Sources/AnkiClients/DeckClient.swift` - API

---

### Sprint 2: 笔记删除 ✅

**位置**: Browse Tab → 搜索结果列表

**使用流程**:
```
搜索笔记 → 左滑笔记行 → 红色 Delete 按钮 → 点击 
→ 确认 Alert ("Are you sure?") → Delete → 列表自动更新
```

**特点**:
- 左滑手势删除 (swipeActions)
- 删除前确认提示
- 删除后自动刷新列表

**文件**:
- `AnkiApp/Sources/Browse/BrowseView.swift` - UI 集成
- `Sources/AnkiClients/NoteClient.swift` - API

---

### Sprint 2: 卡片搜索 ✅

**位置**: 可用于任何需要搜索卡片的地方

**查询语法**:
```
is:new           # 新卡片
is:due           # 待复习卡片  
is:review        # 复习卡片
is:suspended     # 暂缓卡片
deck:DeckName    # 按卡组筛选
tag:TagName      # 按标签筛选
"text here"      # 精确短语搜索
nid:12345        # 特定笔记
cid:67890        # 特定卡片
```

**组合示例**:
```
deck:German is:due tag:important
is:new deck:"Biology Prep"
"irregular verb" tag:review
```

**文件**:
- `Sources/AnkiClients/CardClient.swift` - API
- `Sources/AnkiClients/CardClient+Live.swift` - RPC 实现

---

## 🔧 API 参考

### DeckClient (新增方法)

```swift
// 获取卡组配置
let config = try deckClient.getDeckConfig(deckId: 123)

// 更新卡组配置
var config = try deckClient.getDeckConfig(deckId: 123)
config.newPerDay = 25
config.reviewsPerDay = 300
try deckClient.updateDeckConfig(config)
```

### CardClient (新增方法)

```swift
// 搜索卡片
let cards = try cardClient.search("deck:German is:due")

// 现有方法继续工作
try cardClient.suspend(cardId: 456)
try cardClient.bury(cardId: 456) 
try cardClient.flag(cardId: 456, flag: 1)
try cardClient.undo()
```

### NoteClient (改进)

```swift
// 删除笔记（改进了 RPC method 映射）
try noteClient.delete(noteId: 789)
```

---

## 📱 UI 界面快速导航

### DeckConfigView

```
Form {
  Section("Daily Limits") {
    Stepper: New cards per day
    Stepper: Reviews per day
  }
  
  Section("Learning Steps") {
    TextField: 学习步骤
  }
  
  Section("Relearning Steps") {
    TextField: 复习步骤
  }
  
  Section("FSRS") {
    Toggle: Enable FSRS
    TextField: FSRS Weights (if enabled)
  }
}
```

### BrowseView 删除

```
List {
  ForEach(notes) { note in
    NoteRowView(note)
      .swipeActions {
        Button("Delete", role: .destructive) {
          delete note
        }
      }
  }
}
```

### CardContextMenu

```
Menu {
  Button("Suspend", systemImage: "pause.circle")
  Button("Bury", systemImage: "books.vertical")
  Button("Flag", systemImage: "flag.fill")
  Button("Undo", systemImage: "arrow.uturn.backward")
}
```

---

## 🔄 状态流程

### 卡片操作流程

```
当前卡片显示
    ↓
用户点击菜单
    ↓
显示 4 个选项
    ↓
用户选择操作 (suspend/bury/flag/undo)
    ↓
cardClient.perform(operation)
    ↓
Rust 后端处理
    ↓
reviewSession.refreshAndAdvance()
    ↓
重新获取待做队列
    ↓
更新卡片计数
    ↓
显示下一张卡片或完成
```

### 卡组配置流程

```
选择卡组
    ↓
点击设置按钮
    ↓
DeckConfigView Sheet 打开
    ↓
deckClient.getDeckConfig(deckId) 
    ↓
显示当前配置
    ↓
用户修改参数
    ↓
点击 Save
    ↓
deckClient.updateDeckConfig(config)
    ↓
Rust 往数据库保存
    ↓
Sheet 关闭
    ↓
返回 DeckDetailView
```

---

## 🐛 常见问题

### Q: 菜单在哪里？
A: ReviewView 中，卡片上方右侧有 "..." 按钮。只在显示卡片时可见。

### Q: 设置在哪里保存？
A: 点击 Save 后立即保存到本地 SQLite 数据库。同步时会上传到服务器。

### Q: 删除能恢复吗？
A: 否。删除操作会从数据库中永久移除笔记及其所有卡片。建议先导出备份。

### Q: 搜索支持哪些查询？
A: 支持完整的 Anki 查询语法（见上面的"查询语法"部分）。

### Q: Undo 能撤销哪些操作？
A: 可以撤销最后一个操作（包括卡片回答、suspend/bury/flag 等）。但只能撤销一步。

---

## 📝 使用示例

### 示例 1: 学习时管理困难卡片

```
1. 显示卡片
2. 读一遍，点击 "..." 
3. 如果太难，选择 "Bury" 隐藏今天
4. 继续下一张卡片
5. 明天学习时会看到这张卡片
```

### 示例 2: 配置每日复习限制

```
1. 进入 Decks
2. 点击 "German Vocabulary"
3. 点击右上角齿轮 ⚙️
4. 修改 "Reviews per day" 从 200 改为 100
5. 点击 "Save Configuration"
6. 配置已保存
```

### 示例 3: 搜索并删除特定笔记

```
1. 进入 Browse Tab
2. 输入搜索: "deck:German tag:old is:review"
3. 看到筛选结果
4. 左滑笔记行
5. 点击 Delete
6. 确认删除
7. 笔记被删除，列表刷新
```

### 示例 4: 搜索所有待复习卡片

```
1. 使用 CardClient.search
2. 查询: "is:due"
3. 返回所有待复习的卡片
4. 可以批量操作或逐个查看
```

---

## 🎓 最佳实践

### 卡片操作
- ✅ 使用 Suspend 处理当前有问题的卡片，等待修正
- ✅ 使用 Bury 隐藏类似卡片一天
- ✅ 使用 Flag 标记容易出错的卡片
- ❌ 不要频繁 Undo，它只能回退一步

### 卡组设置
- ✅ 新手建议: 每天 20 新卡片 + 200 复习卡片
- ✅ 根据学习进度调整限制
- ✅ 启用 FSRS 获得更智能的复习计划
- ❌ 不要突然大幅改变限制

### 笔记管理
- ✅ 定期搜索并清理过时笔记
- ✅ 使用标签分类笔记便于管理
- ✅ 删除前确认无需要
- ❌ 不要误删重要笔记(无法恢复)

### 搜索查询
- ✅ 使用组合查询精确筛选
- ✅ 保存常用查询以备重用
- ✅ 利用标签和卡组组织卡片
- ❌ 不要创建过于复杂的查询

---

## 📚 详细文档

更多信息请查看:
- **SPRINT_1_SUMMARY.md** - Sprint 1 详细总结
- **SPRINT_2_SUMMARY.md** - Sprint 2 详细总结  
- **VERIFICATION_GUIDE.md** - 功能验证指南
- **COMPLETION_REPORT.md** - 完整功能报告
- **ARCHITECTURE.md** - 架构设计文档
- **CLAUDE.md** - 项目说明书

---

**最后更新**: 2026-04-09  
**维护者**: Amgi 团队  
**版本**: 1.0
