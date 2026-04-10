import SwiftUI

struct SettingsView: View {
    @State private var followSystem = true
    @State private var forceDarkMode = false

    var body: some View {
        List {
            Section("基础") {
                settingsRow("账户", icon: "person.crop.circle")
                settingsRow("编辑", icon: "pencil.and.scribble")
                settingsRow("复习", icon: "rectangle.on.rectangle")
            }

            Section("主题") {
                Toggle("与系统保持一致", isOn: $followSystem)
                Toggle("夜间模式", isOn: $forceDarkMode)
                    .disabled(followSystem)
            }

            Section("维护") {
                settingsRow("备份", icon: "externaldrive")
                settingsRow("检查数据库", icon: "checkmark.seal")
                settingsRow("检查媒体文件", icon: "photo.on.rectangle")
                settingsRow("空卡片", icon: "rectangle.stack.badge.minus")
            }

            Section("其他") {
                settingsRow("关于", icon: "info.circle")
            }
        }
        .navigationTitle("Settings")
    }

    private func settingsRow(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
