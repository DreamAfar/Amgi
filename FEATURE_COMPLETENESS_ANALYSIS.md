# 🔍 iOS Anki 功能完整性分析报告

**生成日期**: 2026-04-09  
**分析范围**: AnkiApp 前端 UI vs AnkiClients 后端 API

---

## 📊 功能实现概览

### 总体完成度：**45%** 🟠

| 按模块 | 已实现 | 计划中 | 未实现 | 完成度 |
|-------|--------|--------|---------|--------|
| **Deck 牌组** | 60% | 20% | 20% | 🟠 |
| **Card 卡片** | 10% | 40% | 50% | 🔴 |
| **Note 笔记** | 70% | 10% | 20% | 🟢 |
| **Stats 统计** | 100% | 0% | 0% | 🟢 |
| **Sync 同步** | 90% | 5% | 5% | 🟢 |
| **Media 媒体** | 0% | 50% | 50% | 🔴 |

---

## ✅/❌ API 使用情况

### DeckClient (😊 部分实现)

```
✅ fetchAll       → DeckListView, BrowseView, StatsDashboardView
✅ fetchTree      → DeckListView, DeckDetailView
✅ countsForDeck  → DeckDetailView
❌ create         → 【未实现】无创建牌组 UI
❌ rename         → 【未实现】无重命名牌组功能
❌ delete         → 【未实现】无删除牌组功能
```

**缺失的 UI 集合**:
- 长按牌组 → 菜单（重命名/删除）
- 新建牌组按钮
- 牌组设置页面

---

### CardClient (😢 完全未实现 - **最优先！**)

```
❌ fetchDue      → 【未使用】ReviewSession 直接调用 Rust backend
❌ fetchByNote   → 【未实现】无按笔记查询卡片
❌ save          → 【未实现】无编辑卡片功能
❌ answer        → 【未使用】ReviewSession 直接调用 Rust backend
❌ undo          → 【未实现】无撤销复习答案
❌ suspend       → 【未实现】无暂停卡片功能
❌ bury          → 【未实现】无搁置卡片功能
```

**严重缺失的功能**:
1. **在复习和浏览中无卡片操作菜单**
   - ❌ 暂停卡片 (Suspend)
   - ❌ 搁置卡片 (Bury)
   - ❌ 撤销上一个答案 (Undo)
   - ❌ 标记卡片 (Flag)
   - ❌ 查看卡片信息 (Card Info)

2. **在浏览中无卡片编辑**
   - ❌ 编辑卡片内容（在复习时快速编辑）
   - ❌ 重置卡片进度
   - ❌ 从复习卡片进入编辑笔记

3. **无卡片多选操作**
   - ❌ BrowseView 中没有卡片多选
   - ❌ 批量标记卡片
   - ❌ 批量暂停/搁置

---

### NoteClient (🟢 部分实现)

```
✅ fetch         → BrowseView, NoteEditorView
✅ search        → BrowseView (带分页)
✅ save          → NoteEditorView, AddNoteView
❌ delete        → 【未实现】无删除笔记功能
```

**缺失的功能**:
- ❌ BrowseView 中右滑/长按删除笔记
- ❌ 笔记详情页的删除按钮
- ❌ 批量删除笔记

---

### DeckClient - 创建/编辑 (🔴 未实现)

```
❌ create  → 【无 UI】无新建牌组界面
❌ rename  → 【无 UI】无重命名界面
❌ delete  → 【无 UI】无删除确认界面
```

### StatsClient (✅ 完全实现)

```
✅ fetchGraphs   → StatsDashboardView
```

### SyncClient (✅ 基本完整)

```
✅ sync          → SyncSheet  
✅ fullSync      → SyncSheet
✅ syncMedia     → SyncSheet
✅ login         → LoginSheet (via SyncClient.login)
✅ lastSyncDate  → 【未使用】可用于显示上次同步时间
```

### MediaClient (🔴 完全未实现)

```
❌ localURL   → 【未实现】无媒体查看功能
❌ save       → 【未实现】无媒体上传
❌ delete     → 【未实现】无媒体删除
```

---

## 🎯 用户功能缺失清单（按优先级）

### 🔴 **P0 - 关键功能缺失**（应立即实现）

#### 1. 卡片操作菜单
**影响**: 复习效率、学习体验  
**位置**: ReviewView 中卡片显示区域  
**需求功能**:
```
右滑卡片或长按 → 菜单显示
├─ [ ] Suspend (暂停到明天)
├─ [ ] Bury (搁置直到下一时段)
├─ [ ] Flag (标记/取消标记)
├─ [ ] Edit (进入编辑笔记)
├─ [ ] Card Info (显示卡片详情)
└─ [ ] Undo (撤销上一个答案)
```
**关键 API**: cardClient.suspend, bury, undo（需实现）  
**预计工作量**: 2-3 小时（UI + 后端）

#### 2. 暂停/搁置/标记卡片
**影响**: 日常学习管理  
**位置**: BrowseView 中卡片行上下文菜单  
**需求功能**:
```
BrowseView 中长按卡片 → 菜单
├─ [ ] Suspend
├─ [ ] Bury
├─ [ ] Reset Progress
├─ [ ] Mark/Unmark
└─ [ ] Delete

对应的 Rust API:
└─ scheduler.suspendCards()
└─ scheduler.buryCards()
└─ scheduler.buryNotesForToday()
└─ notesService.updateNote() with flags
```
**关键 API**: cardClient.suspend, bury（需实现）  
**预计工作量**: 2-3 小时

#### 3. 复习界面快速编辑
**影响**: 学习效率  
**位置**: ReviewView 答案显示时，右上角按钮  
**需求功能**:
```
复习时显示笔记 → "Edit" 按钮
└─ 打开 NoteEditorView
└─ 修改后自动保存
└─ 返回继续复习
```
**关键 API**: noteClient.fetch, save（已有）  
**预计工作量**: 1-2 小时

---

### 🟠 **P1 - 高优先级功能**（本周完成）

#### 4. 牌组创建/编辑/删除
**影响**: 笔记库管理  
**缺失 UI**:
```
DeckListView 中长按牌组 → 菜单
├─ [ ] Rename
├─ [ ] Delete
└─ [ ] Options (学习设置)

顶部按钮
└─ [ ] "+" 新建牌组

DeckDetailView
└─ [ ] "Settings" 按钮 (设置每日新卡数、学习间隔等)
```
**关键 API**:
- deckClient.create() ✅ API 就绪
- deckClient.rename() ✅ API 就绪
- deckClient.delete() ✅ API 就绪
- 需要新增: getDeckOptions(), setDeckOptions()

**预计工作量**: 3-4 小时

#### 5. 撤销复习答案 (Undo)
**影响**: 用户体验  
**位置**: ReviewView 或 DeckDetailView 顶部  
**需求功能**:
```
答题后按 "Undo" 按钮 → 回到上个卡片
└─ 调用 cardClient.undo(cardId)
```
**关键 API**: cardClient.undo()（需实现）  
**预计工作量**: 1-2 小时

#### 6. 笔记删除功能
**影响**: 笔记管理  
**位置**: BrowseView 和 NoteEditorView  
**需求功能**:
```
BrowseView 中滑动/长按 → "Delete" 选项
NoteEditorView 右上 → "Delete" 按钮 → 确认框
```
**关键 API**: noteClient.delete()（已有，未使用）  
**预计工作量**: 1-2 小时

#### 7. 账户管理
**影响**: 多用户支持  
**缺失 UI**:
```
Settings 界面 (new)
├─ [ ] 已登录账户显示
├─ [ ] 账户切换
├─ [ ] 添加本地账户
├─ [ ] 删除账户
└─ [ ] 重命名设备

需要
└─ Keychain 管理多个账户
└─ UserDefaults 记录账户列表
```
**预计工作量**: 3-4 小时

---

### 🟡 **P2 - 中等优先级**（计划中）

#### 8. 卡片信息面板
**影响**: 学习分析  
**需求**:
```
CardInfoView(cardId: Int64)
├─ 卡片状态 (New/Learning/Review)
├─ 最后复习时间
├─ 间隔 (Interval)
├─ 易度 (Ease)
├─ 复习计数
└─ 下次复习时间
```
**关键 API**: 需要 cardClient.info() 或查询 AnkiProto  
**预计工作量**: 2-3 小时

#### 9. 学习选项 (Deck Options)
**影响**: 个性化学习  
**需求**:
```
DeckDetailView → "Settings" 按钮
└─ DeckOptionsView
    ├─ [ ] 新卡片每天限制
    ├─ [ ] 复习卡片每天限制
    ├─ [ ] 学习卡片每天限制
    ├─ [ ] 学习步长 (Learning steps)
    ├─ [ ] 间隔修饰符 (Interval modifiers)
    ├─ [ ] FSRS 参数调整
    └─ [ ] 重新计算 FSRS 参数

Rust 后端 API:
└─ decksService.getDeckOptions()
└─ decksService.updateDeckOptions()
```
**预计工作量**: 4-5 小时

#### 10. 媒体管理
**影响**: 笔记内容表现  
**需求**:
```
在图片卡片上点击 → 显示全屏预览
在 NoteEditorView 中 → 添加媒体按钮
└─ 拍照或从相册选择
└─ 上传到媒体库

需要的 Rust API:
└─ mediaService.addMedia()
└─ mediaService.getMediaPath()
└─ mediaService.deleteMedia()
```
**预计工作量**: 3-4 小时

---

### 🟢 **P3 - 低优先级**（后续优化）

#### 11. 卡片多选与批量操作
**需求**:
```
BrowseView → "Select" 模式
├─ [ ] 多选卡片
├─ [ ] 批量标记
├─ [ ] 批量暂停
├─ [ ] 批量删除
└─ [ ] 批量改标签
```
**预计工作量**: 4-5 小时

#### 12. 高级搜索语法
**需求**: BrowseView 搜索框支持 Anki 搜索语法  
```
"deck:Spanish"
"tag:review"
"is:suspended"
"prop:ease>250"
"added:1"
```
**预计工作量**: 2-3 小时

#### 13. 标签管理
**需求**:
```
Tags 管理页面
├─ [ ] 列出所有标签
├─ [ ] 编辑标签名
├─ [ ] 批量标记/取消标记
└─ [ ] 删除标签
```
**预计工作量**: 2-3 小时

---

## 📋 实现路线图

### **第 1 阶段（本周）** - 核心卡片操作

```
Week 1:
├─ Day 1-2: 《 卡片操作菜单 (Suspend/Bury)
│   ├─ 后端: cardClient.suspend(), .bury() 实现
│   ├─ 前端: ReviewView 长按/右滑菜单
│   └─ 测试: 验证数据库状态变化
│
├─ Day 2-3: 撤销答案 (Undo)
│   ├─ 后端: cardClient.undo() 实现
│   ├─ 前端: 按钮 + 确认框
│   └─ 测试: 验证卡片回到上个状态
│
└─ Day 3: 快速编辑笔记
    ├─ 前端: ReviewView "Edit" 按钮
    ├─ 导航: ReviewView → NoteEditorView
    └─ 测试: 编辑后卡片内容更新
```

**交付**: 核心卡片操作完成，可以在复习时管理卡片

---

### **第 2 阶段（第二周）** - 牌组管理 & 浏览增强

```
Week 2:
├─ Day 1-2: 牌组 CRUD
│   ├─ 后端: deckClient.create/rename/delete 接入
│   ├─ 前端: DeckListView 上下文菜单 + 新建对话框
│   └─ 测试: 创建/编辑/删除牌组
│
├─ Day 2-3: 笔记删除 & BrowseView 增强
│   ├─ 前端: BrowseView 长按 → 删除选项
│   ├─ 前端: NoteEditorView "Delete" 按钮
│   └─ 测试: 删除笔记后列表更新
│
└─ Day 3: 账户管理基础
    ├─ 前端: Settings 页面框架
    ├─ 逻辑: 多账户 Keychain 存储
    └─ 测试: 账户切换
```

**交付**: 笔记库完全可管理，支持多账户管理

---

### **第 3 阶段（第三周）** - 学习定制化

```
Week 3:
├─ Day 1-2: 学习选项设置
│   ├─ 后端: getDeckOptions/setDeckOptions API 实现
│   ├─ 前端: DeckOptionsView UI
│   └─ 测试: 验证设置持久化
│
├─ Day 2-3: 卡片信息面板
│   ├─ 后端: 提供卡片详细信息 API
│   ├─ 前端: CardInfoView 展示统计
│   └─ 集成: 复习中点击查看
│
└─ Day 3: 媒体支持
    ├─ 后端: media API 完善
    ├─ 前端: 图片预览 + 上传
    └─ 测试: 媒体文件管理
```

**交付**: 用户可完全定制学习参数，支持媒体

---

## 💻 代码结构需要的改进

### CardClient 实现

**文件**: `Sources/AnkiClients/CardClient+Live.swift`

```swift
// 现在只有占位符，需要完整实现
extension CardClient: DependencyKey {
    public static let liveValue: Self = {
        @Dependency(\.ankiBackend) var backend
        
        return Self(
            fetchDue: { deckId in
                // 从 Rust backend 获取待复习卡片
                var req = Anki_Scheduler_GetQueuedCardsRequest()
                req.deckID = deckId
                let resp: Anki_Scheduler_QueuedCards = try backend.invoke(...)
                return resp.cards.map { CardRecord(...) }
            },
            
            suspend: { cardId in
                // scheduler.shouldSuspend(cardId)
            },
            
            bury: { cardId in
                // scheduler.shouldBury(cardId)
            },
            
            undo: { cardId in
                // collection.undo()
            },
            // ... 等
        )
    }()
}
```

### DeckClient 增强

**文件**: `Sources/AnkiClients/DeckClient.swift`

```swift
@DependencyClient
public struct DeckClient: Sendable {
    public var fetchAll: @Sendable () throws -> [DeckInfo]
    public var fetchTree: @Sendable () throws -> [DeckTreeNode]
    public var countsForDeck: @Sendable (_ deckId: Int64) throws -> DeckCounts
    public var create: @Sendable (_ name: String) throws -> Int64
    public var rename: @Sendable (_ deckId: Int64, _ name: String) throws -> Void
    public var delete: @Sendable (_ deckId: Int64) throws -> Void
    
    // 新增：学习选项
    public var getDeckOptions: @Sendable (_ deckId: Int64) throws -> DeckOptions
    public var setDeckOptions: @Sendable (_ deckId: Int64, _ options: DeckOptions) throws -> Void
}
```

---

## 🚀 快速启动建议

### **立即开始（优先级最高）**

1. **修复 CardClient 的 suspend/bury/undo**
   - 检查 Rust backend 是否有对应 API
   - 实现 CardClient+Live.swift
   - 添加 UI 菜单到 ReviewView

2. **添加删除笔记功能**
   - 实现 noteClient.delete()（已定义，未使用）
   - BrowseView 中添加滑动删除
   - 添加确认对话框

3. **启用 DeckClient.create/rename/delete**
   - 检查后端 API 现状
   - DeckListView 中添加上下文菜单
   - 实现创建/编辑对话框

### **本周目标**

完成 **P0 和 P1** 功能，使 App 达到 **70% 功能完整度**

```
当前: 45% → 目标: 70%
缺口: 25% 功能点

预计投入: 12-16 小时开发
```

---

## 📌 总结

| 方面 | 状态 | 优先级 |
|-----|------|--------|
| ✅ 复习流程 | 基本完整 | - |
| ✅ 笔记管理 | 部分完整（缺 delete） | P1 |
| ✅ 统计分析 | 完全完整 | - |
| ❌ 卡片操作 | 完全缺失 | **P0** |
| ❌ 牌组管理 | 部分缺失 | P1 |
| ❌ 账户管理 | 完全缺失 | P1 |
| ❌ 媒体支持 | 完全缺失 | P2 |
| ❌ 学习设置 | 完全缺失 | P2 |

**关键瓶颈**: CardClient API 未实现 → 推荐 **优先实现卡片操作**

