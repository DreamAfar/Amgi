# AnkiApp SwiftUI Views 架构文档

## 📁 Views 文件树结构

```
AnkiApp/Sources/
│
├── 🎬 AnkiAppApp.swift               [主应用入口]
├── 📄 ContentView.swift              [标签栏容器]
├── 📄 DebugView.swift                [调试工具]
│
├── 📂 Review/                        [复习模块]
│   ├── ReviewView.swift              [👁️ 主复习界面]
│   ├── ReviewSession.swift           [🧠 复习会话管理]
│   └── CardWebView.swift             [🌐 HTML 卡片渲染]
│
├── 📂 Decks/                         [牌组模块]
│   ├── DeckListView.swift            [👁️ 牌组列表]
│   └── DeckDetailView.swift          [👁️ 牌组详情]
│
├── 📂 Browse/                        [浏览/编辑模块]
│   ├── BrowseView.swift              [👁️ 笔记搜索浏览]
│   ├── AddNoteView.swift             [👁️ 新建笔记表单]
│   └── NoteEditorView.swift          [👁️ 编辑笔记]
│
├── 📂 Stats/                         [统计仪表板模块]
│   ├── StatsDashboardView.swift      [👁️ 统计主容器]
│   ├── TodayStatsCard.swift          [📊 今日统计卡片]
│   │
│   ├── 📈 图表组件：
│   ├── AddedChart.swift              [新增卡片数]
│   ├── ButtonsChart.swift            [按钮分布]
│   ├── CardCountsChart.swift         [卡片类型分布]
│   ├── CardStateChart.swift          [卡片状态]
│   ├── EaseChart.swift               [简易度分布]
│   ├── ForecastChart.swift           [未来预测]
│   ├── FutureDueChart.swift          [未来待复习]
│   ├── HeatmapChart.swift            [学习热力图]
│   ├── HourlyChart.swift             [按小时分布]
│   ├── IntervalsChart.swift          [间隔分布]
│   ├── RetentionChart.swift          [保留率]
│   ├── ReviewsChart.swift            [复习数量]
│   │
│   └── 🎛️ 辅助组件：
│       └── PeriodPicker.swift        [时间周期选择器]
│
├── 📂 Sync/                          [同步模块]
│   ├── OnboardingView.swift          [👁️ 首次启动向导]
│   ├── SyncSheet.swift               [👁️ 同步界面]
│   └── LoginSheet.swift              [👁️ 登录表单]
│
└── 📂 Shared/                        [共享组件]
    ├── DeckCountsView.swift          [牌组卡数徽章]
    ├── ShareSheet.swift              [原生分享菜单]
    └── ImportHelper.swift            [导入助手函数]
```

## 🔗 快速导航

### 按功能模块
- **复习流程** → `Review/` (3 个文件)
- **牌组管理** → `Decks/` (2 个文件)
- **笔记管理** → `Browse/` (3 个文件)  
- **数据分析** → `Stats/` (15 个文件)
- **账户同步** → `Sync/` (3 个文件)
- **UI 基础** → `Shared/` (3 个文件)

### 按实现完成度
- ✅ **完全实现** (14个)：ReviewView, DeckListView, BrowseView, AddNoteView, NoteEditorView, StatsDashboardView, SyncSheet, LoginSheet, AnkiAppApp, DebugView 等
- ⏳ **框架/演示** (5个)：大部分图表组件
- 🧩 **辅助/非View** (12个)：Observable classes, UIViewRepresentable, 枚举等

## 📊 统计信息

| 类别 | 数量 |
|-----|-----|
| 总文件 | 31 |
| SwiftUI Views | 19 |
| 其他类型 | 12 |
| 完全实现 | 14 |
| 框架状态 | 5 |
| 需要 @Dependency | 10 |

## 🏗️ 架构分层

```
层级结构：

┌─────────────────────────────────────────────┐
│ 🎭 表现层 (Presentation)                     │
│ ├─ ContentView (标签栏路由)                 │
│ ├─ 模块Views (ReviewView, DeckListView等) │
│ └─ 图表/组件 (各类Chart, DeckCountsView)  │
├─────────────────────────────────────────────┤
│ 🔌 依赖注入层 (Dependency Container)         │  
│ ├─ @Dependency(\.deckClient)               │
│ ├─ @Dependency(\.ankiBackend)              │
│ ├─ @Dependency(\.noteClient)               │
│ └─ @Dependency(\.statsClient) 等           │
├─────────────────────────────────────────────┤
│ 📦 业务层 (Business Logic)                  │
│ ├─ ReviewSession (复习状态管理)            │
│ ├─ DependencyClients (AnkiClients模块)    │
│ └─ SyncClient (同步逻辑)                   │
├─────────────────────────────────────────────┤
│ 🌉 后端桥接层 (FFI Bridge)                 │
│ ├─ AnkiBackend (Swift -> Rust 包装)       │
│ ├─ AnkiProto (Protobuf 类型)              │
│ └─ C FFI (4个函数: invoke/callVoid等)     │
├─────────────────────────────────────────────┤
│ 🦀 Rust 后端 (anki-bridge-rs XCFramework)  │
│ └─ Rust rslib + SQLite + Sync 协议        │
└─────────────────────────────────────────────┘
```

## 🚀 启动流程

```
1. AnkiAppApp.main()
   ├─ init() { prepareDependencies { ... } }
   │   └─ 初始化 AnkiBackend (连接 Rust)
   │   └─ 打开 SQLite 数据库
   │   └─ 注册所有 @DependencyClient
   │
   ├─ var body: some Scene
   │   ├─ if onboardingCompleted
   │   │   └─ ContentView()  ← 主应用入口
   │   └─ else
   │       └─ OnboardingView()  ← 首次启动向导
   │
   └─ ContentView().body
       └─ TabView {
           Tab("Decks") → NavigationStack { DeckListView() }
           Tab(role: .search) → NavigationStack { BrowseView() }
           Tab("Stats") → NavigationStack { StatsDashboardView() }
           Tab("Debug") → NavigationStack { DebugView() }
       }
```

## 💾 数据流向

```
用户交互 → SwiftUI Views
           ↓
        @Dependency Client
           ↓
      AnkiBackend (Swift)
           ↓
    C FFI (4个导出函数)
           ↓
  Rust rslib (anki-bridge-rs)
           ↓
  SQLite Database + Sync API
           ↓
   Response Protobuf → Swift View Update
```

