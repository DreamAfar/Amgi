import SwiftUI
import AnkiClients
import AnkiSync

struct LoginSheet: View {
    @Binding var isPresented: Bool
    let onSuccess: () -> Void

    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(L("login_field_username"), text: $username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField(L("login_field_password"), text: $password)
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
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
                    .disabled(username.isEmpty || password.isEmpty || isLoading)
                }
            }
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
