# 🗺️ AnkiApp Views 导航关系完全保存

**生成日期**: 2026-04-09  
**工具**: 静态分析 + grep 搜索

---

## 📐 导航流程图

```
┌─────────────────────────────────────────────────────────────────────┐
│                          AnkiAppApp                                  │
│                    (@main Application)                              │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
                    ┌──────▼──────┐
                    │ onboarding? │
                    └──────┬──────┘
           ┌────────────────┼────────────────┐
           │                                 │
        Yes │                                │ No
           │                                 │
    ┌──────▼────────┐            ┌──────────▼──────┐
    │OnboardingView │            │ ContentView     │
    │  (初次启动)   │            │ (主应用标签栏)  │
    └──────┬────────┘            └──┬───┬───┬───┬─┘
           │                        │   │   │   │
           │ onboarded() →          │   │   │   │
           │ ContentView 로        │   │   │   │
           │                       │   │   │   │
                ┌──────────────────┴───┴───┼───┤
                │                          │   │
         ┌──────▼─────────┐  ┌────────────┤   │
         │ DeckListView │ │  │BrowseView  │   │
         │ (Tab 0)      │ │  │(Tab Search)│   │
         └──────┬────────┘  └──────┬──────┘    │
                │                  │           │
         ┌──────▼────────────┐ ┌──▼──────────┐  │
         │DeckDetailView     │ │NoteRecord ──┤  │
         │ (stack flow)      │ │destination  │  │
         └──────┬────────────┘ └──────┬──────┘  │
                │                     │         │
         ┌──────▼───────┐    ┌────────▼──────┐  │
         │ReviewView    │    │NoteEditorView │  │
         │(fullScreen)  │    │ (edit/save)   │  │
         └──────────────┘    └───────────────┘  │
                                                 │
                ┌─────────────────┬──────────────┤
                │                 │              │
         ┌──────▼──────┐   ┌──────▼──────┐ ┌───▼───┐
         │StatsDashb   │   │DebugView    │ │Sync   │
         │(Tab 2)      │   │(Tab 3)      │ │Sheet  │
         └─────────────┘   └─────────────┘ │(Modal)│
                                            └───────┘
```

---

## 🔀 详细导航流（按启动顺序）

### 1️⃣ 应用启动路径

```
AnkiAppApp.main()
  ↓
  ├─ [首次启动]
  │   └─ OnboardingView
  │       ├─ [选择本地模式]
  │       │   └─ isCompleted = true → ContentView
  │       └─ [选择自定义服务器]
  │           └─ KeychainHelper.saveEndpoint() → ContentView
  │
  └─ [已有保存状态]
      └─ ContentView (tabView)
```

### 2️⃣ 标签栏结构（ContentView）

```
ContentView: TabView {
    ├─ Tab(0) "Decks" → NavigationStack { DeckListView() }
    ├─ Tab(1, role: .search) → NavigationStack { BrowseView() }  
    ├─ Tab(2) "Stats" → NavigationStack { StatsDashboardView() }
    └─ Tab(3) "Debug" → NavigationStack { DebugView() }
    
    底层 Sheet:
    ├─ .sheet(showSync) → SyncSheet
    └─ .fileImporter(showImport) → ImportHelper
}
```

---

## 🧭 各标签页导航详解

### Tab 0: Decks（牌组浏览）

```
DeckListView (列表根)
  │
  ├─ if isLoading → ProgressView
  ├─ if empty → ContentUnavailableView
  └─ if has decks
      │
      └─ List(tree) → DeckRowView (递归)
          │
          ├─ if no children
          │   └─ NavigationLink(value: deckInfo)
          │       └─ DeckDetailView
          │           │
          │           ├─ 显示: 卡数、子牌组列表
          │           │
          │           ├─ 按钮: "Study Now"
          │           │   └─ .fullScreenCover → ReviewView
          │           │       │
          │           │       ├─ ReviewSession (Observable)
          │           │       │   ├─ start() → 获取队列
          │           │       │   ├─ revealAnswer()
          │           │       │   └─ answer(rating)
          │           │       │
          │           │       └─ if finished
          │           │           └─ finishedView (统计)
          │           │
          │           └─ 子牌组列表
          │               └─ NavigationLink(value: child)
          │                   └─ DeckDetailView (嵌套)
          │
          └─ if has children
              └─ DisclosureGroup (展开/折叠)
                  └─ ForEach children → DeckRowView (递归)

[刷新]: NavigationStack.refreshable → loadDecks()
[导出]: ContentView.fileImporter → ImportHelper.importPackage()
```

**关键链接**:
- DeckListView ---(列表项)--> DeckDetailView
- DeckDetailView ---(Study Now)--> ReviewView (fullScreenCover)
- DeckDetailView ---(--(子牌组)--> DeckDetailView (嵌套)

---

### Tab 1: Search/Browse（笔记浏览）

```
BrowseView (搜索&列表根)
  │
  ├─ if empty && no search
  │   └─ ContentUnavailableView("Browse Notes")
  ├─ if empty && has search
  │   └─ ContentUnavailableView.search()
  └─ if has notes
      │
      └─ List(notes, pagination)
          │
          └─ ForEach notes
              │
              ├─ NoteRowView
              │   │
              │   └─ NavigationLink(value: note)
              │       └─ NoteEditorView
              │           │
              │           ├─ loadNote() → 获取字段名
              │           ├─ fieldValues (编辑)
              │           └─ save() → 保存修改
              │
              └─ onAppear
                  ├─ if stub → fetchNoteDetails(id)
                  └─ if last → loadNextPage()
  
  工具栏:
  └─ 按钮 "+" (Add Note)
      └─ .sheet(showAddNote) → AddNoteView
          │
          ├─ 选择 Deck
          ├─ 选择 NoteType → loadFields()
          ├─ 填写字段
          └─ Add → save() → 返回 BrowseView

[筛选]: 上方 Deck Filter Bar
        └─ Picker → parentDeck, activeDeck → performSearch()

[搜索]: searchable(text) → onChange → performSearch()
```

**关键链接**:
- BrowseView ---(列表项)--> NoteEditorView (navigationDestination)
- BrowseView ---(+ 按钮)--> AddNoteView (sheet)
- AddNoteView ---(Add)--> BrowseView
- NoteEditorView ---(Save)--> BrowseView

---

### Tab 2: Stats（统计仪表板）

```
StatsDashboardView (容器)
  │
  ├─ 顶部筛选行
  │   ├─ deckMenu (选择牌组)
  │   │   └─ Menu { selectedDeck = deck } → onChange → loadStats()
  │   └─ periodMenu (选择时间)
  │       └─ Menu { period = p } → onChange → loadStats()
  │
  └─ ScrollView
      └─ LazyVStack(spacing: 16) {
          ├─ ProgressView (loading)
          ├─ ContentUnavailableView (error)
          └─ if graphs loaded
              │
              ├─ TodayStatsCard
              │   ├─ 显示: Reviewed, Time, Correct%, Mature%
              │   └─ 纯展示组件
              │
              ├─ FutureDueChart
              │   └─ 柱状图 (Cards.Charts)
              │
              ├─ HeatmapChart
              │   └─ 热力图 (reviews 时间序列)
              │
              ├─ ReviewsChart
              │   └─ 时间序列 (reviews/day)
              │
              ├─ CardCountsChart
              │   └─ 饼图 (New/Learning/Mature等)
              │
              ├─ IntervalsChart
              │   └─ 条形图 (interval distribution)
              │
              ├─ EaseChart
              │   └─ 柱状图 (ease factors)
              │
              ├─ HourlyChart
              │   └─ 按小时分布
              │
              ├─ ButtonsChart
              │   └─ 按钮分布 (Again/Hard/Good/Easy)
              │
              ├─ AddedChart
              │   └─ 新增卡片 (time series)
              │
              └─ RetentionChart
                  └─ 保留率分析

[所有图表]: 纯展示，无导航链接
[刷新]: NavigationStack.refreshable → loadStats()
```

**关键链接**:
- 无链接跳转，所有组件为展示型
- 筛选器影响数据，重新加载图表

---

### Tab 3: Debug（调试工具）

```
DebugView (工具集)
  │
  ├─ Account Section
  │   ├─ Username (显示)
  │   └─ Host Key (显示)
  │
  ├─ Actions Section
  │   ├─ "Check Database"
  │   │   └─ backend.call(service: 2, method: 0)
  │   ├─ "Export Collection"
  │   │   └─ ImportHelper.exportCollection()
  │   │       └─ .sheet → ShareSheet (分享 .colpkg)
  │   │
  │   └─ "Reset Collection"
  │       └─ showResetConfirm
  │           └─ [删除数据库]
  │
  └─ .sheet(showShareSheet)
      └─ ShareSheet (UIActivityViewController)
          └─ 系统分享菜单 (AirDrop/邮件等)

[导出流]: DebugView → ExportCollection → ShareSheet → 系统分享
```

**关键链接**:
- DebugView ---(Export)--> ShareSheet (sheet)

---

### 底部 Sheet 和 Modal（ContentView 层）

```
ContentView
  │
  ├─ .sheet(showSync)
  │   └─ SyncSheet
  │       │
  │       ├─ NavigationStack {
  │       │   ├─ 服务器配置显示
  │       │   │   ├─ 已配置 → 显示端点 + 用户名
  │       │   │   │   └─ Menu
  │       │   │   │       ├─ "Change Server" 
  │       │   │   │       │   └─ .sheet → ServerSetupSheet (modal)
  │       │   │   │       └─ "Logout"
  │       │   │   │
  │       │   │   └─ 未配置 → Button "Configure Server"
  │       │   │       └─ showServerSetup = true
  │       │   │
  │       │   └─ 同步状态显示
  │       │       ├─ .idle → ProgressView
  │       │       ├─ .syncing(msg) → ProgressView(msg)
  │       │       ├─ .success(summary) → successView
  │       │       ├─ .error(msg) → errorView
  │       │       ├─ .needsFullSync → fullSyncChoiceView
  │       │       └─ .noServer → noServerView
  │       │
  │       └─ .sheet(showLogin)
  │           └─ LoginSheet
  │               │
  │               ├─ NavigationStack {
  │               │   ├─ Form { username, password }
  │               │   └─ Button "Sign In"
  │               │       └─ SyncClient.login()
  │               │
  │               └─ onSuccess → Task { startSync() }
  │
  │       └─ .sheet(showServerSetup)
  │           └─ ServerSetupSheet (未导出)
  │               ├─ TextField (url)
  │               └─ Button "Continue"
  │                   └─ KeychainHelper.saveEndpoint()
  │
  └─ .fileImporter(showImport)
      └─ 选择 .apkg / .colpkg
          └─ ImportHelper.importPackage(url)
              └─ 显示导入结果
              │   └─ onComplete → refreshID = UUID()
              │       └─ 触发所有标签页刷新
```

**关键链接**:
- ContentView ---(Sync 按钮)--> SyncSheet (sheet)
- SyncSheet ---(登录)--> LoginSheet (sheet)
- SyncSheet ---(服务器设置)--> ServerSetupSheet (sheet)
- ContentView ---(导入)--> ImportHelper (fileImporter)

---

## 🔄 数据流与刷新机制

### 应用刷新机制
```
refreshID (UUID) → .id(refreshID)
  ↓
ContentView 中的所有标签页都使用 .id(refreshID)
  ↓
刷新触发时点：
  1. 完成同步 → refreshID = UUID()
  2. 完成导入 → refreshID = UUID()
  3. 完成复习 → 返回时调用 await loadCounts()

结果：
  所有列表重新加载，显示最新数据
```

### 各 View 的刷新机制
```
DeckListView
  ├─ .task { await loadDecks() }
  └─ .refreshable { await loadDecks() }

DeckDetailView
  ├─ .task { await loadCounts(); await loadChildren() }
  └─ ReviewView 完成后 → Task { await loadCounts() }

BrowseView
  ├─ .searchable → onChange → performSearch()
  ├─ 牌组筛选 → performSearch()
  └─ AddNoteView 完成 → Task { await performSearch() }

StatsDashboardView
  ├─ .task { await loadDecks(); await loadStats() }
  ├─ .refreshable { await loadStats() }
  └─ .onChange(of: selectedDeck) { await loadStats() }

ReviewView
  └─ 完成后回调 onDismiss()
      └─ showReview = false
      └─ Task { await loadCounts() }
```

---

## 📍 导航堆栈总结

### NavigationStack 数量及位置
| 位置 | 启用 NavigationStack | 目的 |
|------|------------------|------|
| ContentView | 4个 (每个标签页一个) | 隔离各标签页的导航状态 |
| AddNoteView | 1个 | 表单容器 |
| LoginSheet | 1个 | 登录表单容器 |
| SyncSheet | 1个 | 同步界面容器 |
| ReviewView | 1个 | 复习界面容器 |
| ServerSetupSheet | 1个 | 服务器设置容器 |

### 导航方式统计
```
navigationDestination (type: T.self)  → 4个
  - DeckInfo → DeckDetailView
  - DeckInfo → DeckDetailView (递归)
  - NoteRecord → NoteEditorView
  
NavigationLink                        → 5个
  - 牌组行 → DeckInfo 值
  - 笔记行 → NoteRecord 值
  - 子牌组行 → DeckInfo 值

fullScreenCover                      → 1个
  - DeckDetailView "Study Now" → ReviewView

sheet                                → 6个
  - ContentView (Sync)
  - SyncSheet (Login)
  - SyncSheet (ServerSetup)
  - BrowseView (AddNote)
  - DebugView (ShareSheet)
  - SyncSheet (Login)

fileImporter                         → 1个
  - ContentView (导入 .apkg/.colpkg)
```

---

## 🔗 关键路径（用户流）

### 新手入门路径
```
1. app 启动
2. OnboardingView
3. 选择 "Custom Server" 或 "Use Locally"
4. ContentView (Decks 标签自动打开)
5. 点击 "Sync" 按钮
6. SyncSheet → 需要登录 → LoginSheet
7. 登录成功 → 自动同步 → 返回 Decks 列表
```

### 复习卡片路径
```
1. ContentView (Decks 标签)
2. 点击牌组 → DeckDetailView
3. 点击 "Study Now" → ReviewView (fullScreenCover)
4. 学习卡片、点击评分 → 下一张卡片
5. 完成所有卡片 → "Done" → 返回 DeckDetailView
6. 返回时自动更新卡数
```

### 添加笔记路径
```
1. ContentView (Search 标签 → BrowseView)
2. 点击 "+" 按钮 → AddNoteView (sheet)
3. 选择牌组、笔记类型、填写字段
4. 点击 "Add" → 保存到数据库
5. 自动返回 BrowseView → 显示新笔记
```

### 查看统计路径
```
1. ContentView (Stats 标签 → StatsDashboardView)
2. 选择牌组 (menu) / 时间周期 (menu)
3. 图表自动更新
4. 下拉刷新 (pull-to-refresh) 重新加载
```

### 同步数据路径
```
1. ContentView (顶部 Sync 按钮)
2. SyncSheet (弹出)
3. 如未登录 → LoginSheet
4. 输入用户名密码 → SyncClient.login()
5. 同步开始 → 显示进度
6. 同步完成 → 所有标签页刷新
```

---

## ⚖️ 导航复杂度评分

| 模块 | 导航链接数 | 深度 | 复杂度 | 代码质量 |
|-----|---------|-----|--------|---------|
| Decks | 3 | 3 级 (递归) | 🟠 中 | ✅ 良 |
| Browse | 2 | 2 级 | 🟢 低 | ✅ 很好 |
| Stats | 1 | 1 级 | 🟢 低 | ✅ 很好 |
| Sync | 3 | 2 级 | 🟡 中 | ✅ 良 |
| Debug | 1 | 1 级 | 🟢 低 | ✅ 良 |
| Review | 1 | 1 级 | 🟢 低 | ✅ 很好 |

**总体复杂度**: 🟡 **中等** (设计清晰、分类得当)

---

## ✅ 导航最佳实践遵循

- ✅ 使用 type-safe 的 navigationDestination
- ✅ 使用 @State 管理 sheet 显示/隐藏
- ✅ 各标签页独立的 NavigationStack
- ✅ 合理使用 fullScreenCover (ReviewView)
- ✅ 避免循环导航
- ✅ 使用 UUID 刷新机制实现全局更新

---

**✅ 导航关系分析完成** - 已生成完整的用户流程和跳转规则

