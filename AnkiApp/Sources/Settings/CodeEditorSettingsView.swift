import SwiftUI

/// 编辑器设置视图（HTML/CSS代码编辑器）
struct CodeEditorSettingsView: View {
    @AppStorage("codeEditor_fontSize") private var fontSize: Double = 14.0
    @AppStorage("codeEditor_fontFamily") private var fontFamilyRaw: String = "monospace"

    private let minFontSize: Double = 10
    private let maxFontSize: Double = 32

    private var fontFamily: CodeFontFamily {
        CodeFontFamily(rawValue: fontFamilyRaw) ?? .menlo
    }

    var body: some View {
        List {
            Section(header: Text(L("code_editor_section_font"))) {
                // 字体大小 — 左标签、右数字 + - / +
                HStack(spacing: 12) {
                    Label(L("code_editor_font_size"), systemImage: "textformat.size")
                    Spacer()
                    Button {
                        fontSize = max(minFontSize, fontSize - 1)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 28, height: 28)
                            .background(Color(UIColor.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(fontSize <= minFontSize)

                    Text("\(Int(fontSize))")
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .frame(minWidth: 32, alignment: .center)

                    Button {
                        fontSize = min(maxFontSize, fontSize + 1)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 28, height: 28)
                            .background(Color(UIColor.systemGray5))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(fontSize >= maxFontSize)
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
                .padding(.vertical, 4)

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
