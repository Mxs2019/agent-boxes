import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var baseURL = ""
    @State private var showChangeKey = false
    @State private var showLogOutConfirmation = false
    @State private var showDeleteAccountConfirmation = false
    @State private var isResettingOnboarding = false

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                primaryColorSection
                cardDesignSection
                feedbackSection
                onboardingSection
                serviceSection
                accountSection
            }
            .tint(model.themeColor.color)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: finish)
                        .accessibilityIdentifier("settings-done")
                }
            }
            .onAppear {
                baseURL = model.baseURLString
            }
            .sheet(isPresented: $showChangeKey) {
                ChangeAccountKeyView()
                    .environmentObject(model)
            }
            .confirmationDialog(
                "Log out of Agent Box?",
                isPresented: $showLogOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Log out", role: .destructive) {
                    Task {
                        await model.logOut()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes the account key and local cards from this device. Server cards are not deleted.")
            }
            .confirmationDialog(
                "Delete this account and all its data?",
                isPresented: $showDeleteAccountConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete account", role: .destructive) {
                    Task {
                        if await model.deleteAccount() { dismiss() }
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action permanently deletes all server and device data for this account. You cannot undo it.")
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker(
                "Appearance",
                selection: Binding(
                    get: { model.appearance },
                    set: { model.selectAppearance($0) }
                )
            ) {
                ForEach(AppAppearance.allCases) { option in
                    Text(option.name).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("appearance-picker")
        }
    }

    private var primaryColorSection: some View {
        Section {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 42), spacing: 16)],
                spacing: 16
            ) {
                ForEach(AppThemeColor.allCases) { option in
                    themeButton(option)
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Primary color")
        } footer: {
            Text("This color is used for buttons, links, and controls.")
        }
    }

    private var cardDesignSection: some View {
        Section {
            NavigationLink {
                CardDesignPickerView()
            } label: {
                HStack {
                    Label("Card design", systemImage: "paintpalette")
                    Spacer()
                    Text(model.cardDesign.name)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("card-design-picker-link")
        } header: {
            Text("Card design")
        } footer: {
            Text("Agents follow this design when you copy agent instructions. The card rules stay the same for every design.")
        }
    }

    private var serviceSection: some View {
        Section {
            TextField(AppModel.defaultServiceURLString, text: $baseURL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .accessibilityLabel("Card service URL")
                .accessibilityIdentifier("card-service-url")

        } header: {
            Text("Agent Box service")
        } footer: {
            Text("This is the server that stores and synchronizes your cards.")
        }
    }

    private var feedbackSection: some View {
        Section {
            NavigationLink {
                FeedbackListView()
            } label: {
                Label("Feedback", systemImage: "text.bubble")
            }
            .accessibilityIdentifier("feedback-settings-link")
        } header: {
            Text("Agent feedback")
        } footer: {
            Text("Review the comments that you sent and see which items agents resolved.")
        }
    }

    private var onboardingSection: some View {
        Section {
            Button {
                resetOnboarding()
            } label: {
                HStack {
                    Label("Reset onboarding", systemImage: "arrow.counterclockwise")
                    Spacer()
                    if isResettingOnboarding {
                        ProgressView()
                    }
                }
            }
            .disabled(isResettingOnboarding || !model.hasAccountKey)
            .accessibilityIdentifier("reset-onboarding")
        } header: {
            Text("Onboarding")
        } footer: {
            Text("Add the five introductory cards to your deck again.")
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Label("Account key", systemImage: "key.fill")
                Spacer()
                Text(model.hasAccountKey ? "Connected" : "Not connected")
                    .foregroundStyle(.secondary)
            }

            Button(model.hasAccountKey ? "Change account key" : "Add account key") {
                showChangeKey = true
            }
            .accessibilityIdentifier("change-account-key")

            if model.hasAccountKey {
                Button("Log out", role: .destructive) {
                    showLogOutConfirmation = true
                }
                .accessibilityIdentifier("log-out")

                Button("Delete account", role: .destructive) {
                    showDeleteAccountConfirmation = true
                }
                .accessibilityIdentifier("delete-account")
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Your account key is the only credential for this account. Agent Box cannot show it again.")
        }
    }

    private func finish() {
        let serviceChanged = baseURL != model.baseURLString
        guard model.saveService(baseURL: baseURL) else { return }
        dismiss()
        if serviceChanged {
            Task { await model.sync(showErrors: true) }
        }
    }

    private func resetOnboarding() {
        guard !isResettingOnboarding else { return }
        isResettingOnboarding = true
        Task {
            let succeeded = await model.resetOnboarding()
            isResettingOnboarding = false
            if succeeded { dismiss() }
        }
    }

    private func themeButton(_ option: AppThemeColor) -> some View {
        let isSelected = model.themeColor == option

        return Button {
            model.selectThemeColor(option)
        } label: {
            Circle()
                .fill(option.color.gradient)
                .frame(width: 38, height: 38)
                .overlay {
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.caption.bold())
                            .foregroundStyle(option.foregroundColor)
                    }
                }
                .overlay {
                    if isSelected {
                        Circle()
                            .stroke(option.color.opacity(0.4), lineWidth: 3)
                            .padding(-5)
                    }
                }
                .frame(width: 48, height: 48)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("theme-color-\(option.rawValue)")
    }
}

struct CardDesignPickerView: View {
    @EnvironmentObject private var model: AppModel

    private static let previewSize = CGSize(width: 350, height: 560)
    private static let previewScale: CGFloat = 0.55

    private var tileSize: CGSize {
        CGSize(
            width: Self.previewSize.width * Self.previewScale,
            height: Self.previewSize.height * Self.previewScale
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Every design keeps the same card rules: dense, interactive, and useful offline. The design changes only the look. Each option shows the same weather card.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)

                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 18) {
                        ForEach(CardDesign.allCases) { design in
                            designTile(design)
                        }
                    }
                    .scrollTargetLayout()
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
            }
            .padding(.top, 12)
        }
        .background(model.themeColor.appBackgroundColor.ignoresSafeArea())
        .navigationTitle("Card design")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func designTile(_ design: CardDesign) -> some View {
        let isSelected = model.cardDesign == design

        return Button {
            model.selectCardDesign(design)
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                CardWebView(
                    html: design.previewHTML,
                    contentTrust: .trusted,
                    isScrollEnabled: false
                )
                .frame(width: Self.previewSize.width, height: Self.previewSize.height)
                .background(Color(uiColor: .systemBackground))
                .scaleEffect(Self.previewScale, anchor: .topLeading)
                .frame(
                    width: tileSize.width,
                    height: tileSize.height,
                    alignment: .topLeading
                )
                .compositingGroup()
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            isSelected ? model.themeColor.color : Color.primary.opacity(0.12),
                            lineWidth: isSelected ? 3 : 1
                        )
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
                .allowsHitTesting(false)

                HStack(spacing: 6) {
                    Text(design.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(model.themeColor.color)
                    }
                }

                Text(design.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: tileSize.width, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(design.name)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint(design.summary)
        .accessibilityIdentifier("card-design-\(design.rawValue)")
    }
}

private struct FeedbackListView: View {
    @EnvironmentObject private var model: AppModel
    @State private var isLoading = false
    @State private var editingFeedback: Feedback?
    @State private var feedbackToDelete: Feedback?

    var body: some View {
        List {
            if !unresolvedFeedback.isEmpty {
                Section("Unresolved") {
                    ForEach(unresolvedFeedback) { item in
                        feedbackLink(item)
                    }
                }
            }

            if !resolvedFeedback.isEmpty {
                Section("Resolved") {
                    ForEach(resolvedFeedback) { item in
                        feedbackLink(item)
                    }
                }
            }
        }
        .overlay { emptyState }
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await model.loadFeedback(showErrors: true) }
        .sheet(item: $editingFeedback) { item in
            FeedbackComposerView(feedback: item)
                .environmentObject(model)
        }
        .alert(
            "Delete feedback?",
            isPresented: Binding(
                get: { feedbackToDelete != nil },
                set: { if !$0 { feedbackToDelete = nil } }
            ),
            presenting: feedbackToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                Task { _ = await model.deleteFeedback(item) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The agent will no longer see this feedback.")
        }
    }

    private var unresolvedFeedback: [Feedback] {
        model.feedback.filter { !$0.isResolved }
    }

    private var resolvedFeedback: [Feedback] {
        model.feedback.filter(\.isResolved)
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView("Loading feedback")
        } else if model.feedback.isEmpty {
            ContentUnavailableView(
                "No feedback",
                systemImage: "text.bubble",
                description: Text("Use a card menu to send feedback to its agent.")
            )
        }
    }

    private func feedbackLink(_ item: Feedback) -> some View {
        NavigationLink {
            FeedbackDetailView(feedbackID: item.id)
        } label: {
            FeedbackRowView(feedback: item)
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) {
                feedbackToDelete = item
            }
            Button("Edit") {
                editingFeedback = item
            }
            .tint(model.themeColor.color)
        }
        .accessibilityIdentifier("feedback-row-\(item.id)")
    }

    private func load() async {
        isLoading = true
        await model.loadFeedback(showErrors: true)
        isLoading = false
    }
}

private struct FeedbackRowView: View {
    let feedback: Feedback

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(feedback.comment)
                .font(.body)
                .lineLimit(3)
            HStack(spacing: 6) {
                Text(feedback.cardTitle ?? "Untitled card")
                Text("·")
                Text(feedback.agentName)
                Spacer(minLength: 4)
                Text(feedback.createdAt, format: .relative(presentation: .named))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}

private struct FeedbackDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let feedbackID: String
    @State private var editingFeedback: Feedback?
    @State private var showDeleteConfirmation = false

    var body: some View {
        Group {
            if let feedback {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 10) {
                            Label(
                                feedback.isResolved ? "Resolved" : "Unresolved",
                                systemImage: feedback.isResolved
                                    ? "checkmark.circle.fill"
                                    : "circle"
                            )
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(feedback.isResolved ? .green : model.themeColor.color)

                            Text(feedback.comment)
                                .font(.title3)
                                .textSelection(.enabled)

                            Text(feedbackDateLine(feedback))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        VStack(alignment: .leading, spacing: 10) {
                            Text("Card sent")
                                .font(.headline)
                            CardChrome(card: feedback.snapshotCard)
                                .frame(height: 480)
                        }
                    }
                    .padding(16)
                }
            } else {
                ContentUnavailableView("Feedback not found", systemImage: "text.bubble")
            }
        }
        .background(model.themeColor.appBackgroundColor.ignoresSafeArea())
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let feedback {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Edit", systemImage: "pencil") {
                            editingFeedback = feedback
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Feedback actions")
                }
            }
        }
        .sheet(item: $editingFeedback) { item in
            FeedbackComposerView(feedback: item)
                .environmentObject(model)
        }
        .alert("Delete feedback?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                guard let feedback else { return }
                Task {
                    if await model.deleteFeedback(feedback) { dismiss() }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The agent will no longer see this feedback.")
        }
    }

    private var feedback: Feedback? {
        model.feedback.first { $0.id == feedbackID }
    }

    private func feedbackDateLine(_ feedback: Feedback) -> String {
        let created = feedback.createdAt.formatted(
            .dateTime.month(.abbreviated).day().year().hour().minute()
        )
        if let resolvedAt = feedback.resolvedAt {
            let resolved = resolvedAt.formatted(
                .dateTime.month(.abbreviated).day().year().hour().minute()
            )
            return "Sent to \(feedback.agentName) on \(created). Resolved on \(resolved)."
        }
        return "Sent to \(feedback.agentName) on \(created)."
    }
}

struct AgentsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var showNewAgent = false
    @State private var showNewInbox = false
    @State private var agentToRevoke: Agent?
    @State private var inboxToRevoke: Inbox?
    @State private var copiedInboxID: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if model.agents.isEmpty {
                        Label(
                            "Create an agent to connect it through MCP and send cards.",
                            systemImage: "key.fill"
                        )
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeAgents) { agent in
                            agentRow(agent)
                        }
                        ForEach(revokedAgents) { agent in
                            agentRow(agent)
                                .opacity(0.55)
                        }
                    }
                } header: {
                    sectionHeader(
                        "Agents",
                        actionLabel: "New agent",
                        actionIdentifier: "new-agent"
                    ) {
                        showNewAgent = true
                    }
                }

                Section {
                    if model.inboxes.isEmpty {
                        Label(
                            "Create a new email address to turn incoming email into cards.",
                            systemImage: "envelope"
                        )
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(activeInboxes) { inbox in
                            inboxRow(inbox)
                        }
                        ForEach(revokedInboxes) { inbox in
                            inboxRow(inbox)
                                .opacity(0.55)
                        }
                    }
                } header: {
                    sectionHeader(
                        "Inboxes",
                        actionLabel: "New inbox",
                        actionIdentifier: "new-inbox"
                    ) {
                        showNewInbox = true
                    }
                } footer: {
                    Text("Email cards use restricted mode. Attachments are not included.")
                }
            }
            .navigationTitle("Agents & Inboxes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await model.loadAgents(showErrors: true)
                await model.loadInboxes(showErrors: true)
            }
            .refreshable {
                await model.loadAgents(showErrors: true)
                await model.loadInboxes(showErrors: true)
            }
            .sheet(isPresented: $showNewAgent) {
                NewAgentView()
                    .environmentObject(model)
            }
            .sheet(isPresented: $showNewInbox) {
                NewInboxView()
                    .environmentObject(model)
            }
            .alert(
                "Revoke agent?",
                isPresented: Binding(
                    get: { agentToRevoke != nil },
                    set: { if !$0 { agentToRevoke = nil } }
                ),
                presenting: agentToRevoke
            ) { agent in
                Button("Revoke \(agent.name)", role: .destructive) {
                    Task { await model.revokeAgent(agent) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This key will stop working now. Existing cards will use restricted mode after the next sync.")
            }
            .alert(
                "Revoke inbox?",
                isPresented: Binding(
                    get: { inboxToRevoke != nil },
                    set: { if !$0 { inboxToRevoke = nil } }
                ),
                presenting: inboxToRevoke
            ) { inbox in
                Button("Revoke \(inbox.name)", role: .destructive) {
                    Task { await model.revokeInbox(inbox) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("New email will be rejected. Cards that are already in Agent Box will stay in history.")
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var activeAgents: [Agent] {
        model.agents.filter { !$0.isRevoked }
    }

    private var revokedAgents: [Agent] {
        model.agents.filter(\.isRevoked)
    }

    private var activeInboxes: [Inbox] {
        model.inboxes.filter { !$0.isRevoked }
    }

    private var revokedInboxes: [Inbox] {
        model.inboxes.filter(\.isRevoked)
    }

    private func sectionHeader(
        _ title: String,
        actionLabel: String,
        actionIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.body.weight(.semibold))
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(actionLabel)
            .accessibilityIdentifier(actionIdentifier)
        }
    }

    private func agentRow(_ agent: Agent) -> some View {
        HStack(spacing: 12) {
            NavigationLink {
                AgentCardsView(agent: agent)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: agent.isRevoked ? "xmark.shield" : "checkmark.shield.fill")
                        .foregroundStyle(agent.isRevoked ? .secondary : model.themeColor.color)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(agent.name)
                        Text(agentStatus(agent))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("agent-row-\(agent.id)")

            if !agent.isRevoked {
                Menu {
                    Button("Revoke agent", role: .destructive) {
                        agentToRevoke = agent
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Actions for \(agent.name)")
            }
        }
    }

    private func agentStatus(_ agent: Agent) -> String {
        let count = model.cards(sentBy: agent).count
        let cardCount = "\(count) \(count == 1 ? "card" : "cards")"
        if agent.isRevoked { return "\(cardCount) · Revoked" }
        if let lastUsedAt = agent.lastUsedAt {
            return "\(cardCount) · Used \(lastUsedAt.formatted(.relative(presentation: .named)))"
        }
        return "\(cardCount) · Not used"
    }

    private func inboxRow(_ inbox: Inbox) -> some View {
        HStack(spacing: 12) {
            Image(systemName: inbox.isRevoked ? "envelope.badge.fill" : "envelope.fill")
                .foregroundStyle(inbox.isRevoked ? .secondary : model.themeColor.color)

            VStack(alignment: .leading, spacing: 3) {
                Text(inbox.name)
                Text(inbox.emailAddress)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 4)

            if !inbox.isRevoked {
                Menu {
                    Button {
                        UIPasteboard.general.string = inbox.emailAddress
                        copiedInboxID = inbox.id
                    } label: {
                        Label("Copy address", systemImage: "doc.on.doc")
                    }
                    Button("Revoke inbox", role: .destructive) {
                        inboxToRevoke = inbox
                    }
                } label: {
                    Image(systemName: copiedInboxID == inbox.id ? "checkmark" : "ellipsis")
                        .frame(width: 36, height: 36)
                }
                .accessibilityLabel("Actions for \(inbox.name)")
            } else {
                Text("Revoked")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("inbox-row-\(inbox.id)")
    }
}

struct AgentCardsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var query = ""
    @State private var agentKey: String?
    @State private var isLoadingKey = false
    @State private var copiedMCPConnection = false
    @State private var copiedInstructions = false
    @State private var showReplaceConfirmation = false
    @State private var searchIndex = CardSearchIndex()
    @State private var searchResults: [CardSearchResult] = []
    let agent: Agent

    var body: some View {
        List {
            if !agent.isRevoked {
                Section {
                    if let agentKey {
                        Text(agentKey)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("agent-api-key")
                        Button {
                            UIPasteboard.general.string = agentKey
                        } label: {
                            Label("Copy agent key", systemImage: "doc.on.doc")
                        }
                        Button {
                            UIPasteboard.general.string = model.agentMCPConnection(agentKey: agentKey)
                            copiedMCPConnection = true
                        } label: {
                            Label(
                                copiedMCPConnection ? "MCP connection copied" : "Copy MCP connection",
                                systemImage: copiedMCPConnection ? "checkmark" : "point.3.connected.trianglepath.dotted"
                            )
                        }
                        .accessibilityIdentifier("copy-agent-mcp-connection")
                        Button {
                            UIPasteboard.general.string = model.agentInstructions(agentKey: agentKey)
                            copiedInstructions = true
                        } label: {
                            Label(
                                copiedInstructions ? "Instructions copied" : "Copy agent instructions",
                                systemImage: copiedInstructions ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .accessibilityIdentifier("copy-agent-instructions")
                    } else {
                        Button {
                            Task { await revealKey() }
                        } label: {
                            Label(isLoadingKey ? "Loading…" : "View agent key", systemImage: "key")
                        }
                        .disabled(isLoadingKey)
                    }
                    Button("Replace agent key", role: .destructive) {
                        showReplaceConfirmation = true
                    }
                } header: {
                    Text("Agent key · ends in \(agent.keyHint)")
                } footer: {
                    Text("The account key can view and replace this key at any time.")
                }
            }

            if isSearching {
                ForEach(searchResults) { result in
                    NavigationLink {
                        CardDetailView(card: result.card)
                    } label: {
                        CardRow(card: result.card, searchMatch: result.match)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .accessibilityIdentifier("agent-card-\(result.card.id)")
                    .listRowInsets(
                        EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 16)
                    )
                }
            } else {
                ForEach(dayGroups) { group in
                    Section {
                        ForEach(group.cards) { card in
                            NavigationLink {
                                CardDetailView(card: card)
                            } label: {
                                CardRow(card: card)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("agent-card-\(card.id)")
                            .listRowInsets(
                                EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 16)
                            )
                        }
                    } header: {
                        HistoryDayHeader(date: group.day)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.plain)
        .listSectionSpacing(8)
        .overlay { emptyState }
        .navigationTitle(agent.name)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Search this agent")
        .task(id: searchCorpusID) {
            await searchIndex.prepare(agentCards)
        }
        .task(id: searchTaskID) {
            guard isSearching else {
                searchResults = []
                return
            }
            try? await Task.sleep(nanoseconds: 90_000_000)
            guard !Task.isCancelled else { return }
            let results = await searchIndex.search(query, in: agentCards)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
        .refreshable { await model.sync() }
        .accessibilityIdentifier("agent-cards-\(agent.id)")
        .confirmationDialog(
            "Replace this agent key?",
            isPresented: $showReplaceConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace key", role: .destructive) {
                Task { await replaceKey() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The current key will stop working now.")
        }
    }

    private var displayedCards: [Card] {
        isSearching ? searchResults.map(\.card) : agentCards
    }

    private var agentCards: [Card] {
        model.cards(sentBy: agent)
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchTaskID: CardSearchTaskID {
        CardSearchTaskID(
            scope: agent.id,
            query: query,
            cardIDs: agentCards.map(\.id)
        )
    }

    private var searchCorpusID: CardSearchTaskID {
        CardSearchTaskID(scope: agent.id, query: "", cardIDs: agentCards.map(\.id))
    }

    private var dayGroups: [HistoryDayGroup] {
        let calendar = Calendar.autoupdatingCurrent
        return Dictionary(grouping: displayedCards) { card in
            calendar.startOfDay(for: card.createdAt)
        }
        .map { day, cards in
            HistoryDayGroup(day: day, cards: cards.sorted { $0.createdAt > $1.createdAt })
        }
        .sorted { $0.day > $1.day }
    }

    private func revealKey() async {
        isLoadingKey = true
        defer { isLoadingKey = false }
        copiedInstructions = false
        copiedMCPConnection = false
        agentKey = await model.revealAgentKey(agent)
    }

    private func replaceKey() async {
        isLoadingKey = true
        defer { isLoadingKey = false }
        copiedInstructions = false
        copiedMCPConnection = false
        agentKey = await model.replaceAgentKey(agent)
    }

    @ViewBuilder
    private var emptyState: some View {
        if displayedCards.isEmpty {
            if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ContentUnavailableView(
                    "No cards from \(agent.name)",
                    systemImage: "rectangle.stack"
                )
            } else {
                ContentUnavailableView.search(text: query)
            }
        }
    }
}

struct NewAgentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var credential: AgentCredential?
    @State private var copiedKey = false
    @State private var copiedMCPConnection = false
    @State private var copiedInstructions = false
    @State private var isCreating = false
    var body: some View {
        NavigationStack {
            Form {
                if let credential {
                    createdSections(credential)
                } else {
                    Section {
                        TextField("For example, Research agent", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("agent-name")
                    } header: {
                        Text("Agent name")
                    } footer: {
                        Text("Use one key for each agent or service. Agent Box records this name on every card.")
                    }

                    if let error = model.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(credential == nil ? "Cancel" : "Done") { dismiss() }
                        .accessibilityIdentifier(credential == nil ? "cancel-agent" : "finish-agent-setup")
                }
                if credential == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                    }
                }
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var navigationTitle: String {
        if credential != nil { return "Agent Created" }
        return "New Agent"
    }

    @ViewBuilder
    private func createdSections(_ credential: AgentCredential) -> some View {
        Section {
            Label("\(credential.agent.name) can now send trusted cards.", systemImage: "checkmark.shield.fill")
                .foregroundStyle(model.themeColor.color)
        }

        Section {
            Text(credential.agentKey)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .accessibilityIdentifier("agent-api-key")

            Button {
                UIPasteboard.general.string = credential.agentKey
                copiedKey = true
            } label: {
                Label(copiedKey ? "Agent key copied" : "Copy agent key", systemImage: copiedKey ? "checkmark" : "key")
            }
            .accessibilityIdentifier("copy-agent-api-key")
        } header: {
            Text("Private agent key")
        } footer: {
            Text("You can view or replace this key later from the agent page.")
        }

        Section {
            Text(model.mcpURLString)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
            Button {
                UIPasteboard.general.string = model.agentMCPConnection(agentKey: credential.agentKey)
                copiedMCPConnection = true
            } label: {
                Label(
                    copiedMCPConnection ? "MCP connection copied" : "Copy MCP connection",
                    systemImage: copiedMCPConnection ? "checkmark" : "point.3.connected.trianglepath.dotted"
                )
            }
            .accessibilityIdentifier("copy-new-agent-mcp-connection")
        } header: {
            Text("MCP connection")
        } footer: {
            Text("Add this Streamable HTTP connection to an MCP client. It gives this agent card and feedback tools.")
        }

        Section {
            Button {
                UIPasteboard.general.string = model.agentInstructions(agentKey: credential.agentKey)
                copiedInstructions = true
            } label: {
                Label(
                    copiedInstructions ? "Instructions copied" : "Copy agent instructions",
                    systemImage: copiedInstructions ? "checkmark" : "doc.on.doc"
                )
            }
            .accessibilityIdentifier("copy-new-agent-instructions")
        } header: {
            Text("Agent instructions")
        } footer: {
            Text("These ready-to-paste instructions include this agent's key.")
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        credential = await model.createAgent(name: name)
    }
}

struct NewInboxView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var inbox: Inbox?
    @State private var copied = false
    @State private var isCreating = false

    var body: some View {
        NavigationStack {
            Form {
                if let inbox {
                    Section {
                        Label("Your inbox is ready.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(model.themeColor.color)
                    }

                    Section {
                        Text(inbox.emailAddress)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                            .accessibilityIdentifier("inbox-email-address")

                        Button {
                            UIPasteboard.general.string = inbox.emailAddress
                            copied = true
                        } label: {
                            Label(
                                copied ? "Address copied" : "Copy address",
                                systemImage: copied ? "checkmark" : "doc.on.doc"
                            )
                        }
                        .accessibilityIdentifier("copy-inbox-address")
                    } header: {
                        Text(inbox.name)
                    } footer: {
                        Text("Use this address in a newsletter form. New messages will become restricted cards.")
                    }
                } else {
                    Section {
                        TextField("For example, Newsletters", text: $name)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("inbox-name")
                    } header: {
                        Text("Inbox name")
                    } footer: {
                        Text("Agent Box will make a private, random email address for this inbox.")
                    }

                    if let error = model.errorMessage {
                        Section {
                            Text(error)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .navigationTitle(inbox == nil ? "New Inbox" : "Inbox Created")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(inbox == nil ? "Cancel" : "Done") { dismiss() }
                }
                if inbox == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            Task { await create() }
                        }
                        .disabled(
                            name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || isCreating
                        )
                        .accessibilityIdentifier("create-inbox")
                    }
                }
            }
        }
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        inbox = await model.createInbox(name: name)
    }
}
