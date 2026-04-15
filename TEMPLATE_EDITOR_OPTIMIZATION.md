# 卡片模板编辑UI优化方案

## 需求1: 代码编辑器字体大小调整

### 当前问题
- HTML/CSS代码编辑框的字体太大
- 一行显示不了太多内容
- 不便于查看和编辑

### 优化方案

#### 方案A: 设置面板中添加字体大小滑块（推荐）
```swift
// 在Settings/SettingsView中添加
Section("Code Editor") {
    @AppStorage("templateEditorFontSize") var fontSize: Double = 14
    
    HStack {
        Text("Font Size")
        Slider(value: $fontSize, in: 10...24, step: 1)
        Text("\(Int(fontSize))pt")
    }
}

// 在TextEditor中使用
TextEditor(text: $templateHTML)
    .font(.system(size: fontSize, design: .monospaced))
```

#### 方案B: 编辑器中添加快速调整按钮
```swift
HStack {
    Button(action: { fontSize -= 1 }) {
        Image(systemName: "minus.circle")
    }
    
    Slider(value: $fontSize, in: 10...24)
    
    Button(action: { fontSize += 1 }) {
        Image(systemName: "plus.circle")
    }
}
.padding(.horizontal)
```

---

## 需求2: 键盘工具栏按钮优化

### 当前问题
- 工具栏按钮文字只显示一个字
- 按钮太拥挤
- 难以理解每个按钮的功能

### 问题根源分析
按钮可能使用了 `Label()` 显示过多内容但空间有限。

### 优化方案

#### 方案A: 改为竖向滚动工具栏（推荐）
```swift
ScrollView(.horizontal) {
    HStack(spacing: 8) {
        ToolbarButton(icon: "curly­brackets", 
                     tooltip: "{}",
                     action: { insertText("{{}}") })
        
        ToolbarButton(icon: "number",
                     tooltip: "#{}",
                     action: { insertText("{{#}}") })
        
        ToolbarButton(icon: "number.slash",
                     tooltip: "^{}",
                     action: { insertText("{{^}}") })
        
        ToolbarButton(icon: "document.richtext",
                     tooltip: "FrontSide",
                     action: { insertText("{{FrontSide}}") })
        
        // 更多按钮...
    }
    .padding(.horizontal, 8)
}
.frame(height: 44)
```

#### 方案B: 按钮分组 + 菜单
```swift
HStack(spacing: 4) {
    // 基础按钮
    ToolbarButton(icon: "{}", action: { insertText("{{}}") })
    
    // 下拉菜单
    Menu {
        Button("{{#field}}") { insertText("{{#field}}") }
        Button("{{^field}}") { insertText("{{^field}}") }
        Button("{{field:filter}}") { insertText("{{field:filter}}") }
    } label: {
        Image(systemName: "ellipsis.circle")
    }
    
    ToolbarButton(icon: "FrontSide", 
                 action: { insertText("{{FrontSide}}") })
}
```

#### 方案C: 轻浮窗（Context Menu）
长按字段时显示格式化选项：
```swift
TextEditor(text: $templateHTML)
    .contextMenu {
        Button("Wrap in {{}}") { /* wrap selected text */ }
        Button("Add Filter") { /* apply filter */ }
        Button("Add Conditional") { /* wrap in #{}  */ }
    }
```

#### 方案D: 标签栏 + 分页
```swift
VStack {
    Picker("Tool Category", selection: $selectedCategory) {
        Text("Basics").tag("basics")
        Text("Filters").tag("filters")
        Text("Logic").tag("logic")
    }
    .pickerStyle(.segmented)
    
    ScrollView(.horizontal) {
        HStack {
            Group {
                // 根据 selectedCategory 显示不同按钮
                switch selectedCategory {
                case "basics":
                    BasicToolButtons()
                case "filters":
                    FilterToolButtons()
                case "logic":
                    LogicToolButtons()
                default:
                    EmptyView()
                }
            }
        }
    }
}
```

---

## ToolbarButton 辅助组件定义

```swift
struct ToolbarButton: View {
    let icon: String
    let tooltip: String?
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 18))
        }
        .help(tooltip ?? "")
        .frame(width: 44, height: 44)
    }
}
```

---

## 实施优先级建议

| 优先级 | 功能 | 实施时间 | 复杂度 |
|------|------|--------|------|
| 🔴 高 | 字体大小调整 | 30分钟 | 低 |
| 🟡 中 | 工具栏优化（方案A或B） | 1小时 | 中 |
| 🟢 低 | Context Menu | 1.5小时 | 中 |

---

## 推荐实施顺序

1. **立即实施**
   - ✅ 方案A: 设置中添加字体大小滑块
   - ✅ 方案B: 工具栏改为水平滚动

2. **后续优化**
   - 🔄 添加搜索功能 (Ctrl+F in editor)
   - 🔄 代码高亮 (Syntax highlighting)
   - 🔄 自动缩进

3. **进阶功能**
   - 📋 模板预设库
   - 📋 实时预览
   - 📋 验证检查

