import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @State private var baseURL = AppModel.defaultServiceURLString
    @State private var accountKey = ""
    @State private var createdKey: String?
    @State private var isWorking = false
    @State private var copied = false
    @State private var showExistingKey = false
    @State private var showServiceURL = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    Spacer(minLength: 32)
                    brand
                    if let createdKey {
                        saveKey(createdKey)
                    } else if showExistingKey {
                        existingAccount
                    } else {
                        createAccount
                    }
                    serviceSettings
                    Label(
                        "Agent Box stores your account key in Keychain on this device.",
                        systemImage: "lock.fill"
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    Spacer(minLength: 20)
                }
                .frame(maxWidth: 520)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
        .tint(model.themeColor.color)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var brand: some View {
        VStack(spacing: 18) {
            AgentBoxMark(color: model.themeColor.foregroundColor)
                .frame(width: 54, height: 54)
                .frame(width: 88, height: 88)
                .background(model.themeColor.color.gradient, in: RoundedRectangle(cornerRadius: 24))
            VStack(spacing: 8) {
                Text("Agent Box")
                    .font(.largeTitle.bold())
                Text("One key. No username. No password.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var createAccount: some View {
        VStack(spacing: 16) {
            Text("Create an account to receive cards from agents and email inboxes.")
                .multilineTextAlignment(.center)
            Button {
                create()
            } label: {
                buttonLabel(isWorking ? "Creating…" : "Create account")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
            .accessibilityIdentifier("create-account")
            Button("I already have an account key") {
                showExistingKey = true
            }
        }
        .onboardingCard()
    }

    private func saveKey(_ key: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Save your account key", systemImage: "key.fill")
                .font(.title2.bold())
            Text("This is the only time Agent Box will show this key. It is how you sign in on every client.")
                .foregroundStyle(.secondary)
            Text(key)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("account-key")
            Button {
                UIPasteboard.general.string = key
                copied = true
            } label: {
                Label(copied ? "Account key copied" : "Copy account key", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            Button {
                connect(key)
            } label: {
                buttonLabel(isWorking ? "Connecting…" : "I saved it — continue")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking)
        }
        .onboardingCard()
    }

    private var existingAccount: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Use an account key")
                .font(.title2.bold())
            SecureField("ab_account_…", text: $accountKey)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.oneTimeCode)
                .onSubmit { connect(accountKey) }
                .accessibilityIdentifier("account-key-input")
            Button {
                connect(accountKey)
            } label: {
                buttonLabel(isWorking ? "Connecting…" : "Connect")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isWorking || accountKey.isEmpty)
            Button("Create a new account") {
                showExistingKey = false
            }
            .frame(maxWidth: .infinity)
        }
        .onboardingCard()
    }

    private var serviceSettings: some View {
        DisclosureGroup("Use a different Agent Box service", isExpanded: $showServiceURL) {
            TextField(AppModel.defaultServiceURLString, text: $baseURL)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .padding(.top, 10)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }

    private func buttonLabel(_ title: String) -> some View {
        HStack {
            if isWorking { ProgressView() }
            Text(title)
        }
        .frame(maxWidth: .infinity)
    }

    private func create() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            createdKey = await model.createAccountKey(baseURL: baseURL)
            isWorking = false
        }
    }

    private func connect(_ key: String) {
        guard !isWorking else { return }
        isWorking = true
        Task {
            _ = await model.connect(baseURL: baseURL, accountKey: key)
            isWorking = false
        }
    }
}

private extension View {
    func onboardingCard() -> some View {
        padding(20)
            .background(.background, in: RoundedRectangle(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(.quaternary) }
    }
}

private struct AgentBoxMark: View {
    let color: Color

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                card(0.48).frame(width: width * 0.64, height: height * 0.35).offset(y: -height * 0.23)
                card(0.72).frame(width: width * 0.72, height: height * 0.35)
                card(1).frame(width: width * 0.8, height: height * 0.35).offset(y: height * 0.23)
            }
            .frame(width: width, height: height)
        }
        .accessibilityHidden(true)
    }

    private func card(_ opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(opacity))
    }
}
