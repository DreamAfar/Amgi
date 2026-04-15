import SwiftUI

/// 编辑器设置视图（HTML/CSS代码编辑器）
struct CodeEditorSettingsView: View {
    @AppStorage("codeEditor_fontSize") private var fontSize: Double = 14.0
    @AppStorage("codeEditor_fontFamily") private var fontFamilyRaw: String = "monospace"

    private var fontFamily: CodeFontFamily {
        CodeFontFamily(rawValue: fontFamilyRaw) ?? .menlo
    }

    var body: some View {
        List {
            Section(header: Text(L("code_editor_section_font"))) {
                // 字体大小调节
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(L("code_editor_font_size"), systemImage: "textformat.size")
                        Spacer()
                        Text(L("code_editor_font_size_pt", Int(fontSize)))
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
                        Text(L("code_editor_preview_label"))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text("{{Front}}")
                            .font(.system(size: fontSize, design: .monospaced))
                            .padding(8)
                            .background(Color(UIColor.systemGray6))
                            .cornerRadius(4)
                    }
                    .padding(.top, 8)
                }
                .padding(.vertical, 8)

                // 字体选择
                Picker(L("code_editor_font_family"), selection: Binding(
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
        }
        .navigationTitle(L("settings_row_editing"))
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

#Preview {
    NavigationStack {
        CodeEditorSettingsView()
    }
}
