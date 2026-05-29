import SwiftUI

enum CodeEditorPreferences {
    static let fontSizeKey = "codeEditor_fontSize"
    static let fontFamilyKey = "codeEditor_fontFamily"
    static let templateInsertTokensKey = "codeEditor_cardTemplateInsertTokens"

    static func parsedTemplateInsertTokens(from rawValue: String) -> [String] {
        uniqueTokens(
            rawValue
                .components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
    }

    static func resolvedTemplateInsertTokens(from rawValue: String, fallback: [String]) -> [String] {
        let customTokens = parsedTemplateInsertTokens(from: rawValue)
        return customTokens.isEmpty ? fallback : customTokens
    }

    private static func uniqueTokens(_ tokens: [String]) -> [String] {
        var seen = Set<String>()
        return tokens.filter { seen.insert($0).inserted }
    }
}

/// 编辑器设置视图（HTML/CSS代码编辑器）
struct CodeEditorSettingsView: View {
    @AppStorage(CodeEditorPreferences.fontSizeKey) private var fontSize: Double = 14.0
    @AppStorage(CodeEditorPreferences.fontFamilyKey) private var fontFamilyRaw: String = "monospace"
    @AppStorage(CodeEditorPreferences.templateInsertTokensKey) private var templateInsertTokensRaw = ""
    @Environment(\.palette) private var palette

    private let minFontSize: Double = 10
    private let maxFontSize: Double = 32

    private var fontFamily: CodeFontFamily {
        CodeFontFamily(rawValue: fontFamilyRaw) ?? .menlo
    }

    private var customTemplateInsertTokens: [String] {
        CodeEditorPreferences.parsedTemplateInsertTokens(from: templateInsertTokensRaw)
    }

    private var templateInsertSummary: String {
        if customTemplateInsertTokens.isEmpty {
            return L("code_editor_template_insert_default_summary")
        }
        return L("code_editor_template_insert_custom_summary", customTemplateInsertTokens.count)
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
                            .background(palette.surface)
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
                            .background(palette.surface)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(fontSize >= maxFontSize)
                }
                .listRowBackground(palette.surfaceElevated)

                // 代码预览
                VStack(alignment: .leading, spacing: 4) {
                    Text(L("code_editor_preview_label"))
                        .amgiFont(.caption)
                        .foregroundStyle(palette.textSecondary)

                    Text("{{Front}}")
                        .font(.system(size: fontSize, design: .monospaced))
                        .padding(8)
                        .background(palette.surface)
                        .cornerRadius(4)
                }
                .padding(.vertical, 4)
                    .listRowBackground(palette.surfaceElevated)

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
                .listRowBackground(palette.surfaceElevated)
            }

            Section(header: Text(L("code_editor_section_keyboard_toolbar"))) {
                NavigationLink {
                    CardTemplateInsertToolbarSettingsView()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(
                            L("code_editor_template_insert_settings"),
                            systemImage: "keyboard"
                        )
                        Text(templateInsertSummary)
                            .amgiFont(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .listRowBackground(palette.surfaceElevated)
            }
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
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

private struct CardTemplateInsertToolbarSettingsView: View {
    @AppStorage(CodeEditorPreferences.templateInsertTokensKey) private var templateInsertTokensRaw = ""
    @Environment(\.palette) private var palette

    private var parsedTokens: [String] {
        CodeEditorPreferences.parsedTemplateInsertTokens(from: templateInsertTokensRaw)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text(L("code_editor_template_insert_description"))
                        .amgiFont(.body)
                        .foregroundStyle(palette.textSecondary)

                    ZStack(alignment: .topLeading) {
                        if templateInsertTokensRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text(L("code_editor_template_insert_placeholder"))
                                .amgiFont(.body)
                                .foregroundStyle(palette.textTertiary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 10)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $templateInsertTokensRaw)
                            .frame(minHeight: 180)
                            .scrollContentBackground(.hidden)
                            .background(Color.clear)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(size: 15, design: .monospaced))
                    }
                    .padding(8)
                    .background(palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.vertical, 4)
            } footer: {
                Text(L("code_editor_template_insert_hint"))
            }
            .listRowBackground(palette.surfaceElevated)

            Section(L("code_editor_template_insert_preview")) {
                if parsedTokens.isEmpty {
                    Text(L("code_editor_template_insert_default_summary"))
                        .foregroundStyle(palette.textSecondary)
                } else {
                    ForEach(parsedTokens, id: \.self) { token in
                        Text(token)
                            .font(.system(.body, design: .monospaced))
                    }
                }
            }
            .listRowBackground(palette.surfaceElevated)
        }
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .navigationTitle(L("code_editor_template_insert_settings"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(L("code_editor_template_insert_reset_default")) {
                    templateInsertTokensRaw = ""
                }
                .amgiToolbarTextButton(tone: .neutral)
                .disabled(templateInsertTokensRaw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }
}

#Preview {
    NavigationStack {
        CodeEditorSettingsView()
    }
}
