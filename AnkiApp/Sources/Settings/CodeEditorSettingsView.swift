import SwiftUI

/// 编辑器设置视图（HTML/CSS代码编辑器）
struct CodeEditorSettingsView: View {
    @AppStorage("codeEditor_fontSize") private var fontSize: Double = 14.0
    @AppStorage("codeEditor_fontFamily") private var fontFamilyRaw: String = "monospace"
    @AppStorage("codeEditor_lineNumbers") private var showLineNumbers = true
    @AppStorage("codeEditor_syntaxHighlight") private var enableSyntaxHighlight = false
    
    private var fontFamily: CodeFontFamily {
        CodeFontFamily(rawValue: fontFamilyRaw) ?? .menlo
    }
    
    var body: some View {
        List {
            Section(header: Text("Font Settings")) {
                // 字体大小调节
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label("Font Size", systemImage: "textformat.size")
                        Spacer()
                        Text("\(Int(fontSize))pt")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    
                    Slider(value: $fontSize, in: 10...24, step: 1)
                        .padding(.vertical, 4)
                    
                    HStack(spacing: 12) {
                        Button(action: { fontSize = max(10, fontSize - 1) }) {
                            Image(systemName: "minus.circle.fill")
                        }
                        .disabled(fontSize <= 10)
                        
                        Spacer()
                        
                        // 快速预设
                        ForEach([12.0, 14.0, 16.0, 18.0] as [Double], id: \.self) { size in
                            Button { fontSize = size } label: {
                                Text("\(Int(size))")
                                    .font(.system(size: 12))
                                    .frame(width: 40, height: 32)
                                    .background(fontSize == size ? Color.blue : Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                    .foregroundStyle(fontSize == size ? .white : .primary)
                            }
                        }
                        
                        Spacer()
                        
                        Button(action: { fontSize = min(24, fontSize + 1) }) {
                            Image(systemName: "plus.circle.fill")
                        }
                        .disabled(fontSize >= 24)
                    }
                    
                    // 代码预览
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preview:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        Text("{{field:filter}}")
                            .font(.system(size: fontSize, design: .monospaced))
                            .padding(8)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(4)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 8)
                
                // 字体选择
                Picker("Font Family", selection: Binding(
                    get: { fontFamilyRaw },
                    set: { fontFamilyRaw = $0 }
                )) {
                    ForEach(CodeFontFamily.allCases) { family in
                        Text(family.displayName)
                            .font(.system(size: fontSize, design: .monospaced))
                            .tag(family.rawValue)
                    }
                }
            }
            
            Section(header: Text("Display Options")) {
                // 行号
                Toggle("Show Line Numbers", isOn: $showLineNumbers)
                
                // 语法高亮（将来功能）
                Toggle("Syntax Highlighting", isOn: $enableSyntaxHighlight)
                    .disabled(true) // 暂未实现
                    .opacity(0.5)
            }
            
            Section(header: Text("Info")) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Keyboard Shortcuts", systemImage: "command")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        ShortcutRow(key: "Cmd + B", desc: "Bold: **text**")
                        ShortcutRow(key: "Cmd + I", desc: "Italic: *text*")
                        ShortcutRow(key: "Cmd + {", desc: "Mustache: {{field}}")
                        ShortcutRow(key: "Cmd + K", desc: "Link: [text](url)")
                    }
                }
            }
        }
        .navigationTitle("Code Editor")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 字体家族枚举
enum CodeFontFamily: String, CaseIterable, Identifiable {
    case menlo = "Menlo"
    case courier = "Courier New"
    case monaco = "Monaco"
    case monospace = "Monospace"
    
    var id: String { rawValue }
    var displayName: String { rawValue }
}

// 快捷键行
private struct ShortcutRow: View {
    let key: String
    let desc: String
    
    var body: some View {
        HStack {
            Text(key)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.blue)
                .frame(width: 60, alignment: .leading)
            Text(desc)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        CodeEditorSettingsView()
    }
}
