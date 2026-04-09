# 🐛 代码审查报告 - 潜在 Bug 和问题

**审查日期**: 2026-04-09  
**审查范围**: AnkiApp/Sources/ 所有 Swift 文件  
**严重程度**: 🔴 Critical | 🟠 High | 🟡 Medium | 🟢 Low

---

## 总体评分: **B+** (75/100)

主要问题集中在**缺失功能**而非**代码 Bug**  
整体代码质量良好，架构合理

---

## 🔴 严重问题（立即修复）

### 1. ReviewSession - 卡片队列耗尽处理不完善

**文件**: `Sources/Review/ReviewSession.swift`  
**问题**: 当卡片队列为空时，行为不确定
**代码位置**: `advanceToNextCard()` 方法

```swift
private func advanceToNextCard() {
    if cardQueue.isEmpty {
        isFinished = true
        return
    }
    currentQueuedCard = cardQueue.removeFirst()
    // ...
}
```

**问题**:
- ❌ 如果中途调用 `start()` 时网络失败，cardQueue 为空但 isFinished 未正确设置
- ❌ 没有处理 "只有 1 张卡片" 的情况
- ❌ 没有日志记录卡片队列状态

**建议修复**:
```swift
private func advanceToNextCard() {
    guard !cardQueue.isEmpty else {
        print("[ReviewSession] Card queue exhausted at \\(cardQueue.count) cards")
        isFinished = true
        return
    }
    
    currentQueuedCard = cardQueue.removeFirst()
    showAnswer = false
    reviewStartTime = .now
    
    // 计算下一张卡片的间隔
    computeNextIntervals()
    
    print("[ReviewSession] Advanced to card \\(currentQueuedCard?.card.id ?? -1)")
}
```

**严重程度**: 🔴 **Critical** - 影响用户体验

---

### 2. DeckDetailView - 缺失错误处理

**文件**: `Sources/Decks/DeckDetailView.swift`  
**问题**: 异步方法没有错误提示

```swift
private func loadCounts() async {
    do {
        counts = try deckClient.countsForDeck(deck.id)
    } catch {
        print("[DeckDetail] Error loading counts: \\(error)")
        counts = .zero  // ← 静默失败
    }
}
```

**问题**:
- ❌ 错误被吞掉，用户不知道加载失败
- ❌ 显示零卡数可能误导用户
- ❌ 没有重试机制

**建议修复**:
```swift
@State private var loadError: Error?

private func loadCounts() async {
    do {
        counts = try deckClient.countsForDeck(deck.id)
        loadError = nil
    } catch {
        loadError = error
        print("[DeckDetail] Error loading counts: \\(error)")
        // 保留之前的 counts 或显示占位符
    }
}

// 在 body 中显示错误
if let error = loadError {
    HStack {
        Image(systemName: "exclamationmark.triangle")
            .foregroundStyle(.orange)
        Text(error.localizedDescription)
            .font(.caption)
    }
    Button("Retry") {
        Task { await loadCounts() }
    }
}
```

**严重程度**: 🟠 **High** - 影响数据完整性感知

---

### 3. BrowseView - 分页加载时的数据竞态

**文件**: `Sources/Browse/BrowseView.swift`  
**问题**: 快速滚动时可能加载重复数据

```swift
private func loadNextPage() async {
    if !hasMorePages || isLoading { return }
    isLoading = true
    
    try await Task.sleep(nanoseconds: 500_000_000)  // 延迟½秒
    // ...
    
    let newResults = try noteClient.search(query, limit: pageSize)
    notes.append(contentsOf: newResults)  // ← 可能重复
    
    isLoading = false
}
```

**问题**:
- ❌ 没有防抖（debounce）机制，快速滚动会多次触发
- ❌ 没有检查是否已经加载过该页
- ❌ 搜索条件改变时没有重置状态

**建议修复**:
```swift
@State private var currentPage = 1
@State private var lastSearchQuery = ""

private func loadNextPage() async {
    guard !isLoading && hasMorePages else { return }
    
    // 检查搜索条件是否改变
    if searchText != lastSearchQuery {
        currentPage = 1
        notes = []
        hasMorePages = true
        lastSearchQuery = searchText
    }
    
    isLoading = true
    defer { isLoading = false }
    
    do {
        let offset = (currentPage - 1) * pageSize
        let newResults = try noteClient.search(
            searchText,
            limit: pageSize,
            offset: offset  // 需要扩展 API
        )
        
        if newResults.isEmpty {
            hasMorePages = false
        } else {
            notes.append(contentsOf: newResults)
            currentPage += 1
        }
    } catch {
        print("[BrowseView] Load next page failed: \\(error)")
    }
}
```

**严重程度**: 🟠 **High** - 数据重复/混乱

---

## 🟠 高优先级问题

### 4. SyncSheet - 同步中断恢复不足

**文件**: `Sources/Sync/SyncSheet.swift`  
**问题**: 网络中断时缺少恢复策略

```swift
private func startSync() async {
    syncState = .syncing("Synchronizing...")
    do {
        let summary = try await syncClient.sync()  // ← 可能超时
        syncState = .success(summary)
    } catch {
        syncState = .error("Sync failed: \\(error)")
    }
}
```

**缺陷**:
- ❌ 没有超时设置（可能永垂直挂起）
- ❌ 没有重试逻辑
- ❌ 没有部分同步的恢复

**建议**:
```swift
private func startSync() async {
    syncState = .syncing("Synchronizing...")
    
    for attempt in 1...3 {
        do {
            let summary = try await withTimeoutInterval(
                TimeInterval(30),  // 30秒超时
                operation: { try await syncClient.sync() }
            )
            syncState = .success(summary)
            return
        } catch {
            if attempt < 3 {
                syncState = .syncing("Retrying (\\(attempt)/3)...")
                try? await Task.sleep(nanoseconds: UInt64(attempt * 1_000_000_000))
            } else {
                syncState = .error(error.localizedDescription)
            }
        }
    }
}

func withTimeoutInterval<T>(
    _ interval: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            throw TimeoutError()
        }
        
        let result = try await group.nextElement()!
        group.cancelAll()
        return result
    }
}
```

**严重程度**: 🟠 **High** - 用户体验恶化

---

### 5. ReviewView - 内存泄漏风险

**文件**: `Sources/Review/ReviewView.swift`  
**问题**: ReviewSession 可能持有循环引用

```swift
@State private var session: ReviewSession

init(...) {
    self._session = State(initialValue: ReviewSession(deckId: deckId))
}
```

**风险**:
- ⚠️ ReviewSession 是 @Observable class，包含 @Dependency
- ⚠️ 如果 @Dependency 包含 self 引用，可能造成循环

**检查建议**:
```
✓ 确认 ReviewSession 中 @Dependency 没有持有 self
✓ 确认 dismiss 时正确清理状态
✓ 使用 Instruments (Allocations) 监控内存
```

**严重程度**: 🟠 **High** - 潜在内存泄漏

---

## 🟡 中等优先级问题

### 6. ContentView - Tab 刷新机制过激

**文件**: `Sources/ContentView.swift`  
**问题**: 每次完成操作都刷新所有标签页

```swift
@State private var refreshID = UUID()

// 在 sync/import 完成时
refreshID = UUID()  // 刷新所有标签页
```

**影响**:
- ⚠️ 破坏滚动位置
- ⚠️ 破坏用户在标签页中的输入状态  
- ⚠️ 不必要的 API 重新加载

**建议**:
```swift
// 只刷新相关标签页
private func refreshDecks() {
    // 使用标识符刷新，而非整个 refreshID
    deckListRefreshID = UUID()
}

.onChange(of: syncComplete) {
    refreshDecks()
    // ...
}
```

**严重程度**: 🟡 **Medium** - UX 问题

---

### 7. AddNoteView - 字段值同步不当

**文件**: `Sources/Browse/AddNoteView.swift`  
**问题**: 字段值数组可能长度不匹配

```swift
private func fieldBinding(for index: Int) -> Binding<String> {
    Binding(
        get: { index < fieldValues.count ? fieldValues[index] : "" },
        set: { newValue in
            if index < fieldValues.count {
                fieldValues[index] = newValue
            }
        }
    )
}
```

**问题**:
- ❌ 如果笔记类型改变，fieldValues 可能为空
- ❌ 新字段无法设置值（set 中忽略了）

**修复**:
```swift
private func fieldBinding(for index: Int) -> Binding<String> {
    Binding(
        get: {
            // 确保数组足够长
            while fieldValues.count <= index {
                fieldValues.append("")
            }
            return fieldValues[index]
        },
        set: { newValue in
            while fieldValues.count <= index {
                fieldValues.append("")
            }
            fieldValues[index] = newValue
        }
    )
}
```

**严重程度**: 🟡 **Medium** - 数据丢失风险

---

### 8. CardWebView - 没有错误处理

**文件**: `Sources/Review/CardWebView.swift`  
**问题**: 不稳定的 HTML 可能导致白屏

```swift
func updateUIView(_ webView: WKWebView, context: Context) {
    let styledHTML = """
    <!DOCTYPE html>
    ...
    """
    webView.loadHTMLString(styledHTML, baseURL: nil)  // ← 可能失败
}
```

**建议**:
```swift
func updateUIView(_ webView: WKWebView, context: Context) {
    // 检查 HTML 有效性
    guard !html.isEmpty else {
        webView.loadHTMLString("<p>No content</p>", baseURL: nil)
        return
    }
    
    let styledHTML = """
    <!DOCTYPE html>
    <html>
    ...
    """
    
    do {
        webView.loadHTMLString(styledHTML, baseURL: nil)
    } catch {
        print("[CardWebView] Failed to load HTML: \\(error)")
    }
}
```

**严重程度**: 🟡 **Medium** - UI 崩溃风险

---

## 🟢 低优先级建议

### 9. 日志记录不统一

**问题**: 日志格式和日志级别不一致

**现状**:
```swift
print("[ReviewSession] ...")
print("[DeckDetail] Error loading: \\(error)")
// 无法过滤或控制日志级别
```

**建议**:
```swift
enum LogLevel {
    case debug, info, warning, error
}

func log(_ level: LogLevel, _ module: String, _ message: String) {
    #if DEBUG
    let emoji = level == .error ? "❌" : "✓"
    print("\\(emoji) [\\(module)] \\(message)")
    #endif
}

// 使用
log(.info, "ReviewSession", "Started with \\(cardQueue.count) cards")
log(.error, "DeckDetail", "Error loading: \\(error)")
```

**严重程度**: 🟢 **Low** - 开发便利性

---

### 10. Magic Numbers 应该提取为常量

**现状**:
```swift
req.fetchLimit = 200
let response: Anki_Scheduler_QueuedCards = try backend.invoke(
    service: 13,  // ← Magic number!
    method: AnkiBackend.SchedulerMethod.getQueuedCards.rawValue,
    request: req
)
```

**建议**:
```swift
enum BackendService: Int {
    case scheduler = 13
    case collection = 3
    case decks = 7
    // ...
}

const let QUEUE_FETCH_LIMIT = 200

let response: Anki_Scheduler_QueuedCards = try backend.invoke(
    service: BackendService.scheduler.rawValue,
    method: AnkiBackend.SchedulerMethod.getQueuedCards.rawValue,
    request: req
)
```

**严重程度**: 🟢 **Low** - 可维护性

---

## 📋 Bug 修复优先级

| 优先级 | Issue | 工作量 | 影响 |
|-------|-------|--------|------|
| P0 | 卡片队列耗尽处理 | 1h | Critical |
| P0 | 数据竞态 (BrowseView) | 2h | High |
| P1 | 错误处理 (DeckDetailView) | 1h | High |
| P1 | Sync 中断恢复 | 1.5h | High |
| P1 | 内存泄漏风险 | 1h | High |
| P2 | Tab 刷新机制 | 0.5h | Medium |
| P2 | 字段同步 | 0.5h | Medium |
| P2 | CardWebView 错误处理 | 0.5h | Medium |
| P3 | 日志等 | 可选 | Low |

**总工作量**: 8-10 小时

---

## ✅ 代码优点

- ✅ 清晰的模块划分
- ✅ 正确使用 async/await
- ✅ 良好的状态管理
- ✅ 合理的依赖注入
- ✅ 整体架构设计优秀

---

## 🎯 下一步行动

1. **本周**: 修复 P0 和 P1 问题
2. **下周**: 系统性错误处理改进
3. **月底**: 性能优化和日志记录

---

**审查完成** ✅

