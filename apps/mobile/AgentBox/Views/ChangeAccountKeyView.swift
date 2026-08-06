import SwiftUI

struct ChangeAccountKeyView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var keyIsFocused: Bool
    @State private var key = ""
    @State private var isUpdating = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("New account key", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.oneTimeCode)
                        .submitLabel(.done)
                        .focused($keyIsFocused)
                        .onSubmit { updateKey() }
                        .accessibilityIdentifier("new-account-key")
                } header: {
                    Text(model.hasAccountKey ? "Replacement key" : "Account key")
                } footer: {
                    if model.hasAccountKey {
                        Text("Your current key stays active until the new key is verified.")
                    } else {
                        Text("Agent Box will verify this key before it stores it on this device.")
                    }
                }
            }
            .navigationTitle(model.hasAccountKey ? "Change account key" : "Add account key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isUpdating)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(isUpdating ? "Verifying…" : "Update key") {
                        updateKey()
                    }
                    .disabled(isUpdating || normalizedToken.isEmpty)
                    .accessibilityIdentifier("update-account-key")
                }
            }
            .onAppear { keyIsFocused = true }
        }
        .tint(model.themeColor.color)
        .preferredColorScheme(model.appearance.colorScheme)
        .interactiveDismissDisabled(isUpdating)
    }

    private var normalizedToken: String {
        key.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateKey() {
        guard !isUpdating, !normalizedToken.isEmpty else { return }
        isUpdating = true
        Task {
            if await model.replaceAccountKey(normalizedToken) {
                dismiss()
            }
            isUpdating = false
        }
    }
}
