import SwiftUI
import AnkiClients
import AnkiSync
import AmgiTheme

struct LoginSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.palette) private var palette
    let onSuccess: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("login_field_username"), text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    HStack(spacing: 8) {
                        Group {
                            if isPasswordVisible {
                                TextField(L("login_field_password"), text: $password)
                            } else {
                                SecureField(L("login_field_password"), text: $password)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            isPasswordVisible.toggle()
                        } label: {
                            Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                .foregroundStyle(palette.textSecondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L(isPasswordVisible ? "login_hide_password" : "login_show_password"))
                    }
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .amgiStatusText(.danger, font: .caption)
                    }
                }
                Section {
                    Button {
                        Task { await login() }
                    } label: {
                        if isLoading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text(L("login_btn_sign_in")).frame(maxWidth: .infinity)
                        }
                    }
                    .tint(palette.accent)
                    .disabled(username.isEmpty || password.isEmpty || isLoading)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle(L("login_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("btn_cancel")) { isPresented = false }
                }
            }
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        do {
            _ = try await SyncClient.login(username: username, password: password)
            isPresented = false
            onSuccess()
        } catch {
            errorMessage = L("login_failed")
        }
        isLoading = false
    }
}
