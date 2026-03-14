import SwiftUI

/// Login sheet for 4chan Pass authentication.
struct LoginView: View {
    var onSuccess: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var pin = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Token", text: $token)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    SecureField("PIN", text: $pin)
                        .textContentType(.password)
                } header: {
                    Text("4chan Pass")
                } footer: {
                    Text("Enter your 4chan Pass token and PIN to post.")
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Login")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Login") {
                        Task { await login() }
                    }
                    .disabled(token.isEmpty || pin.isEmpty || isLoading)
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
            .disabled(isLoading)
            .onAppear {
                // Pre-fill from Keychain if available
                if let saved = KeychainHelper.passToken { token = saved }
                if let saved = KeychainHelper.passPIN { pin = saved }
            }
        }
    }

    private func login() async {
        isLoading = true
        errorMessage = nil
        do {
            try await ChanPostAPI.shared.authenticate(token: token, pin: pin)
            onSuccess()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}
