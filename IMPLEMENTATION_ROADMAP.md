# 🛠️ iOS Anki 功能实现建议与优先级规划

**生成日期**: 2026-04-09  
**分析**: 前端 UI 功能缺失 vs Rust 后端 API 现状

---

## 📌 关键发现

✅ **Rust 后端已支持** 的核心功能:
- Suspend / Bury / Flag 卡片
- Undo 操作 
- 重置卡片进度
- 笔记删除
- 牌组创建/编辑/删除
- 学习选项配置

❌ **前端 Swift UI 完全未实现** 的功能:
- 卡片操作菜单 UI
- 学习选项编辑界面
- 账户管理界面
- 媒体预览和上传

💡 **可立即实现** 的功能:
- CardClient.suspend/bury/flag（后端就绪，仅需 Swift 包装）
- CardClient.undo（后端就绪，仅需 Swift 包装）
- NoteClient.delete（已定义，未使用）
- DeckClient.rename/delete（已定义，未使用）

---

## 🎯 三阶段实现计划

### **阶段 1: 实现卡片操作** ⭐ WHO SHOULD START NOW
**预计用时**: 10-12 小时  
**目标完成度**: 55% → 68%

#### 1.1 CardClient 完整实现
**文件**: `Sources/AnkiClients/CardClient+Live.swift`

```swift
// 需要实现的 API 调用（Rust 后端已支持）
extension CardClient: DependencyKey {
    public static let liveValue = Self(
        fetchDue: { deckId in
            // ✅ Rust: scheduler.getQueuedCards()
            // 已在 ReviewSession 中使用
        },
        
        answer: { cardId, rating, timeSpent in
            // ✅ Rust: scheduler.answerCard()
            // 已在 ReviewSession 中使用
        },
        
        suspend: { cardId in
            // ✅ Rust: scheduler.suspendCards([cardId])
            let resp: Anki_Collection_OpChangesWithCount = try backend.invoke(
                service: 13, // BackendSchedulerService
                method: ?, // suspendCards method
                request: Anki_Scheduler_CardIdArray() { ids = [cardId] }
            )
            return resp.changes
        },
        
        bury: { cardId in
            // ✅ Rust: scheduler.buryCards([cardId])
            let resp: Anki_Collection_OpChangesWithCount = try backend.invoke(
                service: 13,
                method: ?, // buryCards method
                request: Anki_Scheduler_CardIdArray() { ids = [cardId] }
            )
            return resp.changes
        },
        
        flag: { cardId, flagValue in
            // ✅ Rust: collection.setCardFlag(cardId, flag)
            // flagValue: 0-7 (no flag, red, orange, green, blue, pink, turquoise, purple)
        },
        
        undo: { _ in
            // ✅ Rust: collection.undo()
            // 会撤销上一次的操作（包括答题）
        },
        
        resetProgress: { cardId in
            // ✅ Rust: scheduler.resetCards([cardId])
        }
    )
}
```

**Rust 后端 protobuf 查询需要**:
- 查找 `BackendSchedulerService` 中的方法 ID
  - `suspendCards()` → method ID?
  - `buryCards()` → method ID?
  - 参考: CLAUDE.md 的 Service Index Reference

#### 1.2 ReviewView 卡片菜单
**文件**: `AnkiApp/Sources/Review/ReviewView.swift`

```swift
// 在 cardView 中添加长按菜单
private var cardView: some View {
    VStack(spacing: 0) {
        CardWebView(html: session.showAnswer ? session.backHTML : session.frontHTML)
            .onLongPressGesture {
                showCardMenu = true  // 触发菜单
            }
        
        // 菜单样式
        if showCardMenu && session.showAnswer {
            CardContextMenu(
                onSuspend: { session.suspend() },
                onBury: { session.bury() },
                onUndo: { session.undo() },
                onEdit: { showNoteEditor = true }
            )
        }
        
        Spacer()
        // ... 现有的答题按钮
    }
}

// 在 ReviewSession 中添加方法
func suspend() {
    guard let queued = currentQueuedCard else { return }
    do {
        try cardClient.suspend(queued.card.id)
        // 移到下张卡片
        advanceToNextCard()
    } catch {
        print("[ReviewSession] Suspend failed: \(error)")
    }
}

func bury() {
    guard let queued = currentQueuedCard else { return }
    do {
        try cardClient.bury(queued.card.id)
        advanceToNextCard()
    } catch {
        print("[ReviewSession] Bury failed: \(error)")
    }
}

func undo() {
    // ⚠️ 注意: undo() 影响整个 collection，需要重新加载会话
    do {
        try cardClient.undo(currentQueuedCard?.card.id ?? 0)
        // 重新加载卡片队列
        start()
    } catch {
        print("[ReviewSession] Undo failed: \(error)")
    }
}
```

**UI 设计建议**:
```
长按卡片 → 浮动菜单显示
┌─────────────────────┐
│ ⏸ Suspend (明天)    │
│ 💤 Bury (本周)      │
│ ↩️ Undo            │
│ ✏️ Edit Note       │
│ ℹ️ Card Info       │
└─────────────────────┘
```

**预计工作量**:
- CardClient 实现: 2 小时
- ReviewView UI: 2 小时
- 测试: 1 小时

---

#### 1.3 NoteEditorView 快速编辑
**文件**: `AnkiApp/Sources/Review/ReviewView.swift`

```swift
// 在答题菜单中添加 "Edit" 按钮
// 点击后转到 NoteEditorView，完成后返回复习

@State private var showNoteEditor = false
@State private var editingNote: NoteRecord?

// 在 body 中
.sheet(isPresented: $showNoteEditor) {
    if let note = editingNote {
        NavigationStack {
            NoteEditorView(note: note) {
                // 编辑完成回调
                showNoteEditor = false
                Task {
                    // 重新加载当前卡片的笔记内容
                    session.reloadCurrentCard()
                }
            }
        }
    }
}

// 在 ReviewSession 中
func editCurrentNote() {
    guard let queued = currentQueuedCard else { return }
    do {
        if let note = try noteClient.fetch(queued.note.id) {
            reviewViewDelegate?.presentNoteEditor(note)
        }
    } catch {
        print("[ReviewSession] Failed to fetch note: \(error)")
    }
}

func reloadCurrentCard() {
    // 重新获取当前卡片的 HTML
    // 实现卡片内容更新
}
```

**预计工作量**: 1-2 小时

---

### **阶段 2: 卡片/笔记管理** 📋
**预计用时**: 8-10 小时  
**目标完成度**: 68% → 78%

#### 2.1 BrowseView 卡片操作
**文件**: `AnkiApp/Sources/Browse/BrowseView.swift`

```swift
// 为每个卡片行添加上下文菜单
List(notes, id: \.id) { note in
    NavigationLink(value: note) {
        NoteRowView(note: note)
            .contextMenu {
                // Suspend 此笔记的所有卡片
                Button(role: .destructive) {
                    Task { await suspendNoteCards(note.id) }
                } label: {
                    Label("Suspend", systemImage: "pause")
                }
                
                // Bury 此笔记的所有卡片
                Button(role: .destructive) {
                    Task { await buryNoteCards(note.id) }
                } label: {
                    Label("Bury", systemImage: "moon")
                }
                
                // Delete 笔记
                Button(role: .destructive) {
                    Task {
                        try await noteClient.delete(note.id)
                        await performSearch()
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
}

// 辅助函数
private func suspendNoteCards(_ noteId: Int64) async {
    do {
        let cards = try cardClient.fetchByNote(noteId)
        for card in cards {
            try cardClient.suspend(card.id)
        }
        await performSearch()
    } catch {
        print("[BrowseView] Suspend failed: \(error)")
    }
}

private func buryNoteCards(_ noteId: Int64) async {
    do {
        let cards = try cardClient.fetchByNote(noteId)
        for card in cards {
            try cardClient.bury(card.id)
        }
        await performSearch()
    } catch {
        print("[BrowseView] Bury failed: \(error)")
    }
}
```

**预计工作量**: 2-3 小时

#### 2.2 笔记删除功能
**文件**: `AnkiApp/Sources/Browse/NoteEditorView.swift`

```swift
// 在 NoteEditorView 中添加删除按钮
var body: some View {
    Form { ... }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
            }
            
            ToolbarItem(placement: .destructiveAction) {
                Menu {
                    Button("Delete Note", role: .destructive) {
                        showDeleteConfirm = true
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .alert("Delete Note?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) {
                Task { await delete() }
            }
        }
}

private func delete() async {
    do {
        try await noteClient.delete(note.id)
        dismiss()
        onSave()  // 触发列表刷新
    } catch {
        print("[NoteEditorView] Delete failed: \(error)")
    }
}
```

**预计工作量**: 1-2 小时

#### 2.3 牌组 CRUD 操作
**文件**: `AnkiApp/Sources/Decks/DeckListView.swift`

```swift
// 添加菜单到牌组行
private struct DeckRowView: View {
    let node: DeckTreeNode
    @Dependency(\.deckClient) var deckClient
    @State private var showRenameDialog = false
    @State private var newName = ""
    
    var body: some View {
        if node.children.isEmpty {
            NavigationLink(value: deckInfo) { rowContent }
                .contextMenu {
                    Button { showRenameDialog = true } label: {
                        Label("Rename", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        Task { await deleteDeck() }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
        } else {
            // ... 现有代码
        }
    }
    
    private func deleteDeck() async {
        do {
            try deckClient.delete(node.id)
            // 触发列表刷新 (通过 parent 回调)
        } catch {
            print("[DeckRowView] Delete failed: \(error)")
        }
    }
}

// 顶部添加新建按钮
.toolbar {
    ToolbarItem(placement: .topBarTrailing) {
        Button(action: { showCreateDialog = true }) {
            Image(systemName: "plus")
        }
    }
}

.sheet(isPresented: $showCreateDialog) {
    CreateDeckView { newName in
        Task {
            try await deckClient.create(newName)
            await loadDecks()
        }
    }
}
```

**预计工作量**: 2-3 小时

---

### **阶段 3: 学习定制化** ⚙️
**预计用时**: 10-12 小时  
**目标完成度**: 78% → 90%

#### 3.1 学习选项界面
**文件**: `AnkiApp/Sources/Decks/DeckOptionsView.swift` (新文件)

```swift
struct DeckOptionsView: View {
    let deckId: Int64
    @Dependency(\.deckClient) var deckClient
    @State private var options: DeckOptions?
    
    var body: some View {
        Form {
            Section("New Cards") {
                Stepper("Per day", value: $options?.newPerDay, in: 1...1000)
                Picker("Order", selection: $options?.newOrder) {
                    Text("Due").tag(0)
                    Text("Random").tag(1)
                }
            }
            
            Section("Learning") {
                TextField("Steps (min, separated)", text: $options?.learningSteps)
                Stepper("Per day", value: $options?.learnPerDay)
            }
            
            Section("Review") {
                Stepper("Per day", value: $options?.reviewPerDay)
                Stepper("Ease %", value: $options?.easyBonus)
                Stepper("Hard penalty", value: $options?.hardPenalty)
            }
            
            Section("Advanced") {
                Toggle("Use FSRS", isOn: $options?.useFsrs)
                if options?.useFsrs == true {
                    // FSRS 参数调整
                }
            }
        }
        .navigationTitle("Deck Options")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { Task { await save() } }
            }
        }
        .task { await loadOptions() }
    }
    
    private func loadOptions() async {
        // 需要实现 deckClient.getDeckOptions(deckId)
    }
}
```

**需要扩展**:
```swift
// 在 DeckClient 中添加
public var getDeckOptions: @Sendable (_ deckId: Int64) throws -> DeckOptions
public var setDeckOptions: @Sendable (_ deckId: Int64, _ options: DeckOptions) throws -> Void
```

**预计工作量**: 3-4 小时

#### 3.2 卡片信息面板
**文件**: `AnkiApp/Sources/Review/CardInfoView.swift` (新文件)

```swift
struct CardInfoView: View {
    let cardId: Int64
    let cardDetail: CardDetail?  // 从 Rust backend 获取
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 卡片状态
            HStack {
                Text("Status").font(.caption)
                Spacer()
                Text(cardDetail?.cardsStatus ?? "").foregroundStyle(.secondary)
            }
            
            Divider()
            
            // 复习统计
            HStack {
                Text("Reviews")
                Spacer()
                Text("\(cardDetail?.reviewsCount ?? 0)")
            }
            
            HStack {
                Text("Ease")
                Spacer()
                Text("\(Int((cardDetail?.ease ?? 0.0) * 100))%")
            }
            
            HStack {
                Text("Interval")
                Spacer()
                Text(formatInterval(cardDetail?.interval ?? 0))
            }
            
            HStack {
                Text("Next Review")
                Spacer()
                Text(formatDate(cardDetail?.nextReview))
            }
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(8)
    }
}
```

**预计工作量**: 2 小时

#### 3.3 媒体管理
**需要的工作**:
- 实现 MediaClient 的 localURL/save/delete
- 在笔记编辑中添加媒体上传
- 在卡片显示中添加媒体预览

**预计工作量**: 4-5 小时

---

## 📈 实现时间线

```
Week 1:
├─ Mon-Tue:  CardClient suspend/bury/undo 实现 + UI
│            (4-5 小时)
│
├─ Wed:      快速编辑笔记功能
│            (1-2 小时)
│
├─ Thu-Fri:  BrowseView 卡片操作 + 笔记删除
│            (3-4 小时)
│
└─ Fri PM:   测试 + Bug 修复
             (1-2 小时)

Result after Week 1:
✅ 功能完成度: 45% → 68%
✅ 卡片操作完全可用
✅ 笔记管理功能完整

---

Week 2:
├─ Mon-Tue:  牌组 CRUD 操作
│            (2-3 小时)
│
├─ Wed-Thu:  学习选项界面
│            (3-4 小时)
│
├─ Fri:      卡片信息 + 媒体基础
│            (2-3 小时)
│
└─ 测试 + 优化

Result after Week 2:
✅ 功能完成度: 68% → 85%
✅ 用户可完全定制学习
✅ 媒体支持基础完成
```

---

## 🚀 立即可做的任务

### TODAY - 优先级排序

```
【立即开始】
1. 查阅 anki-upstream/proto/ 中的 .proto 文件
   找到：
   - suspendCards() 方法 ID
   - buryCards() 方法 ID
   - setCardFlag() 方法 ID
   参考: CLAUDE.md 的 Service Index Reference

2. 实现 CardClient+Live.swift
   复制后端 API 调用到 Swift 侧

3. 添加 ReviewView 长按菜单
   使用 .contextMenu 或自定义 GestureRecognizer
```

---

## 📚 参考资源

### Rust 后端功能位置
```
anki-upstream/rslib/src/
├─ scheduler/
│   ├─ suspend_cards()
│   ├─ bury_cards()
│   ├─ undo()
│   └─ reset_cards()
│
├─ cards/
│   ├─ set_flag()
│   └─ card_info()
│
└─ collection/
    ├─ remove_notes()
    └─ undo()
```

### Protobuf 定义位置
```
anki-upstream/proto/anki/
├─ scheduler.proto (schedler API)
├─ collection.proto (通用操作)
└─ cards.proto (卡片数据)
```

### Swift 代码模板
- ReviewSession.swift - 参考 answer() 实现
- DeckListView.swift - 参考 loadDecks() 模式
- NoteEditorView.swift - 参考 save() 实现

---

## ✅ 成功标准

### Phase 1 完成标准
- [ ] cardClient.suspend/bury/undo 可调用
- [ ] ReviewView 显示菜单
- [ ] 暂停/搁置卡片后列表更新
- [ ] 撤销功能可恢复状态
- [ ] 单元测试通过

### Phase 2 完成标准
- [ ] BrowseView 卡片可操作
- [ ] 笔记可删除
- [ ] 牌组可创建/编辑/删除
- [ ] 所有操作撤销就绪
- [ ] 无内存泄漏或崩溃

### Phase 3 完成标准
- [ ] 学习选项可编辑并保存
- [ ] 卡片信息面板完整
- [ ] 媒体上传和预览就绪
- [ ] 整体功能完成度 ≥ 85%

---

## 💡 最后建议

1. **优先顺序**: 卡片操作 > 笔记管理 > 牌组管理 > 学习定制
2. **平衡点**: 80% 功能完成度就可发布 MVP
3. **用户优先**: 专注于复习体验（卡片操作），其次是编辑（笔记、牌组）
4. **测试策略**: 每完成一个功能立即测试，避免积累 bug

**预计发布 MVP 时间**: 4-5 周（包括测试和优化）

