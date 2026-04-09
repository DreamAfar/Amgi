# 🛠️ iOS Anki 开发者简明手册

**版本**: 1.0  
**目标**: 快速上手、添加新功能的完整指南

---

## 🚀 快速启动（5 分钟）

### 1. 项目结构
```
AnkiApp/                          # iOS 应用源代码
├── Sources/
│   ├── AnkiApp/                  # SwiftUI Views（用户界面）
│   ├── AnkiClients/              # @DependencyClient（业务逻辑）
│   ├── AnkiKit/                  # 数据模型
│   ├── AnkiProto/                # Protobuf 类型（自动生成）
│   └── AnkiSync/                 # 同步相关
│
anki-bridge-rs/                  # Rust 📦 包装
├── src/lib.rs                   # FFI 导出点（4个函数）
└── include/anki_bridge.h        # C 头文件

anki-upstream/                   # 上游 Anki 项目
├── rslib/src/                   # Rust 核心逻辑（SQLite、FSRS、Sync）
└── proto/                       # Protobuf 定义（.proto 文件）
```

### 2. 重要文件速查

| 文件 | 用途 | 何时编辑 |
|-----|------|---------|
| `Sources/AnkiClients/*.swift` | 定义业务 API | 新增功能时** |
| `Sources/AnkiClients/*+Live.swift` | 实现业务逻辑 | 连接 Rust 后端 |
| `AnkiApp/Sources/*.swift` | UI 视图 | 用户界面调整 |
| `CLAUDE.md` | 架构文档 | 参考和学习 |
| `anki-upstream/proto/anki/*.proto` | API 定义 | 查看后端接口 |

### 3. 核心工作流

```
User Action (UI)
    ↓
SwiftUI View (React to State)
    ↓
@Dependency(\.xxxClient) method call
    ↓
DependencyClient implementation (+Live.swift)
    ↓
AnkiBackend.invoke() → Rust FFI
    ↓
Protobuf encoding/decoding
    ↓
Rust rslib → SQLite
    ↓
Response back to Swift View
    ↓
@State update → UI refresh
```

---

## 📝 添加新功能的步骤（以"暂停卡片"为例）

### Step 1: 定义 Client API

**文件**: `Sources/AnkiClients/CardClient.swift`

```swift
@DependencyClient
public struct CardClient: Sendable {
    // 现有... 
    public var suspend: @Sendable (_ cardId: Int64) throws -> Void  // ← 新增
}
```

### Step 2: 实现 Client 逻辑

**文件**: `Sources/AnkiClients/CardClient+Live.swift`

```swift
extension CardClient: DependencyKey {
    public static let liveValue = Self(
        // 现有实现...
        
        suspend: { cardId in
            @Dependency(\.ankiBackend) var backend
            
            // 1. 构建请求
            var cardIds = Anki_Scheduler_CardIdArray()
            cardIds.ids = [cardId]
            
            // 2. 调用后端
            let response: Anki_Collection_OpChangesWithCount = try backend.invoke(
                service: 13,  // BackendSchedulerService（参考 CLAUDE.md）
                method: ?,    // 需要查 proto 文件找到 suspend 的方法 ID
                request: cardIds
            )
            
            // 3. 返回结果或处理错误
            // response.changes 包含操作变化信息
        }
    )
}
```

### Step 3: 在 View 中调用

**文件**: `AnkiApp/Sources/Review/ReviewView.swift` 或其他

```swift
struct ReviewView: View {
    @Dependency(\.cardClient) var cardClient  // ← 注入
    
    var body: some View {
        VStack {
            // ... 卡片显示
            
            .contextMenu {
                Button("Suspend") {
                    Task {
                        try await cardClient.suspend(cardId)
                        // UI 更新逻辑
                    }
                }
            }
        }
    }
}
```

### Step 4: 编译并测试

```bash
# Build
cd AnkiApp && xcodegen generate && cd ..
xcodebuild build -project AnkiApp/AnkiApp.xcodeproj \
    -scheme AnkiApp \
    -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'

# Run tests  
swift test
```

---

## 🔗 如何找到 Protobuf 方法 ID

**场景**: 想要在 CardClient 中添加 suspend() 功能

**步骤**:

1. 打开 `anki-upstream/proto/anki/scheduler.proto`

```protobuf
service BackendSchedulerService {
    rpc GetQueuedCards(GetQueuedCardsRequest) returns (QueuedCards) = 3;
    rpc AnswerCard(CardAnswer) returns (OpChangesWithCount) = 4;
    rpc CountsForDeckToday(DeckId) returns (DeckCounts) = 7;
    rpc SuspendCards(CardIdArray) returns (OpChangesWithCount) = 10;  // ← 方法 ID = 10
    rpc BuryCards(CardIdArray) returns (OpChangesWithCount) = 11;   // ← 方法 ID = 11
}
```

2. 查 CLAUDE.md 找对应的 Service ID:

```
| Service ID | Name | Key Methods |
|---|---|---|
| 13 | BackendSchedulerService | 3=GetQueuedCards, 4=AnswerCard, ... |
```

3. 在 Swift 中使用:

```swift
try backend.invoke(
    service: 13,        // BackendSchedulerService
    method: 10,         // SuspendCards RPC 方法
    request: cardIds
)
```

---

## 📚 关键代码模板库

### 模板 1️⃣: 编写一个新的 Client

```swift
// DefitionQA.swift - 定义新的业务功能
@DependencyClient
public struct ExampleClient: Sendable {
    public var fetchData: @Sendable (_ id: Int64) throws -> String
    public var saveData: @Sendable (_ id: Int64, _ value: String) throws -> Void
}

// ExampleClient+Live.swift - 实现
extension ExampleClient: DependencyKey {
    public static let liveValue = Self(
        fetchData: { id in
            @Dependency(\.ankiBackend) var backend
            
            var req = Anki_Example_FetchRequest()
            req.id = id
            
            let resp: Anki_Example_Data = try backend.invoke(
                service: X, method: Y, request: req
            )
            
            return resp.value
        },
        
        saveData: { id, value in
            @Dependency(\.ankiBackend) var backend
            
            var req = Anki_Example_SaveRequest()
            req.id = id
            req.value = value
            
            try backend.callVoid(
                service: X, method: Y, request: req
            )
        }
    )
}

// 注册依赖
extension DependencyValues {
    public var exampleClient: ExampleClient {
        get { self[ExampleClient.self] }
        set { self[ExampleClient.self] = newValue }
    }
}
```

### 模板 2️⃣: 在 View 中处理异步操作

```swift
struct MyView: View {
    @Dependency(\.myClient) var myClient
    @State private var data: String?
    @State private var isLoading = false
    @State private var error: Error?
    
    var body: some View {
        ZStack {
            if isLoading {
                ProgressView()
            } else if let error = error {
                Text("Error: \(error.localizedDescription)")
                    .foregroundStyle(.red)
            } else if let data = data {
                Text(data)
            } else {
                ContentUnavailableView("No data")
            }
        }
        .task {
            await loadData()
        }
    }
    
    private func loadData() async {
        isLoading = true
        error = nil
        
        do {
            data = try myClient.fetchData(123)
        } catch {
            self.error = error
        }
        
        isLoading = false
    }
}
```

### 模板 3️⃣: 上下文菜单（Context Menu）

```swift
List(items) { item in
    NavigationLink(value: item) {
        HStack {
            Text(item.title)
            Spacer()
            Text(item.subtitle).foregroundStyle(.secondary)
        }
    }
    .contextMenu {
        Button {
            Task { await performAction1(item) }
        } label: {
            Label("Action 1", systemImage: "star")
        }
        
        Button(role: .destructive) {
            Task { await performAction2(item) }
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}
```

---

## 🔍 调试技巧

### 打印日志
```swift
print("[FeatureName] Action: \(param1), \(param2)")
print("[Error] \(error) in fetchData")
```

### 在 Xcode 中设置断点

1. 点击行号左侧设置断点
2. 右键 → Edit Breakpoint
3. 添加条件：`cardId == 123`

### 查看网络日志（Sync）

观察 `SyncSheet` 中的 `syncState` 变化

### 查看数据库状态

运行 SQL 查询（通过 DebugView 中的数据库检查功能）

---

## 🎯 常见问题

### Q1: 如何添加新的状态变量？
```swift
@State private var newVar = defaultValue
```

### Q2: 如何在 View 间传递数据？
```swift
NavigationLink(value: data) { ... }  // 类型安全传递
.navigationDestination(for: DataType.self) { data in ... }
```

### Q3: 如何处理长时间运行的操作？
```swift
.task {
    await operation()  // 自动任务
}

// 或手动
Button {
    Task {
        isLoading = true
        defer { isLoading = false }
        try await operation()
    }
}
```

### Q4: Dependencies 框架如何工作？
```swift
@DependencyClient  // 定义接口
struct MyClient { ... }

extension MyClient: DependencyKey {  // 注册
    static let liveValue = Self(...)  // 生产环境
    static let testValue = Self(...)  // 测试环境
}

// 使用
@Dependency(\.myClient) var myClient
```

### Q5: Swift 6 并发规则？
- 所有 UI 更新必须在 `@MainActor` 上
- 使用 `async/await` 而非回调
- `@Sendable` 确保线程安全

---

## 📋 添加新功能检查清单

```
□ 1. 定义 @DependencyClient API
□ 2. 查找 Rust 后端对应的 proto 方法 ID
□ 3. 实现 Client+Live.swift with backend.invoke()
□ 4. 注册 DependencyValues extension
□ 5. 在 View 中注入 @Dependency
□ 6. 添加菜单/按钮触发逻辑
□ 7. 处理 async/await 和错误
□ 8. @State 更新 UI
□ 9. 编译并验证
□ 10. 添加测试用例
□ 11. 更新 README/文档
```

---

## 🚀 推荐阅读顺序

1. **CLAUDE.md** - 项目架构和模块图
2. **Import 规则部分** - Swift 导入规范
3. **本文档** - 功能开发流程
4. **原有代码** - DeckListView, ReviewSession 等作为范例
5. **proto 文件** - 理解后端 API

---

## 💼 代码审查检查清单

在提交 PR 时，确保：

- [ ] 所有 @Dependency 正确导入了 `Dependencies` 框架
- [ ] `@DependencyClient` 标注正确
- [ ] API 方法签名使用 `@Sendable`
- [ ] 错误使用 `throws` 不是 `try?`
- [ ] 视图使用 `@MainActor` @State 更新
- [ ] 没有内存泄漏（使用 weak self 或 @Sendable）
- [ ] 所有异步操作都使用 `async/await`
- [ ] 文件命名 `FeatureName.swift` 和 `FeatureName+Live.swift`
- [ ] 导入符合规范（public import vs import）

---

## 📞 获取帮助

- **项目文档**: 查看根目录的 `*.md` 文件
- **Protocol 查询**: 在 `anki-upstream/proto/` 中搜索
- **编译问题**: 使用 `xcodebuild` 提示的完整错误信息
- **设计讨论**: 创建 Issue 或 Discussion

---

**祝编码愉快！🎉**

