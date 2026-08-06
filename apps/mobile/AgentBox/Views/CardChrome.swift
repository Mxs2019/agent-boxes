import SwiftUI

struct CardChrome: View {
    let card: Card
    var allowsContentScrolling = true
    var contentSnapshot: UIImage? = nil
    var snapshotRequestID: UUID? = nil
    var onSnapshot: ((UUID, UIImage?) -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(card.title ?? "Untitled")
                        .font(.headline)
                        .lineLimit(2)
                    Text(sourceLine)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(card.createdAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(16)

            Divider()
            if let contentSnapshot {
                Image(uiImage: contentSnapshot)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                CardWebView(
                    html: card.html,
                    contentTrust: card.contentTrust,
                    isScrollEnabled: allowsContentScrolling,
                    snapshotRequestID: snapshotRequestID,
                    onSnapshot: onSnapshot
                )
                .equatable()
            }
        }
        .background(AppThemeColor.cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }

    private var sourceLine: String {
        card.sourceName ?? card.source.capitalized
    }
}

struct FeedbackComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("hasSeenAgentFeedbackIntroduction") private var hasSeenIntroduction = false
    private let card: Card?
    private let feedback: Feedback?
    @State private var comment: String
    @State private var isSaving = false

    init(card: Card) {
        self.card = card
        feedback = nil
        _comment = State(initialValue: "")
    }

    init(feedback: Feedback) {
        card = nil
        self.feedback = feedback
        _comment = State(initialValue: feedback.comment)
    }

    var body: some View {
        NavigationStack {
            Group {
                if showsIntroduction {
                    introduction
                } else {
                    composer
                }
            }
            .navigationTitle(feedback == nil ? "Leave Feedback" : "Edit Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if !showsIntroduction {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(feedback == nil ? "Send" : "Save") {
                            save()
                        }
                        .disabled(cleanComment.isEmpty || cleanComment.count > 5_000 || isSaving)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSaving)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var showsIntroduction: Bool {
        feedback == nil && !hasSeenIntroduction
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "text.bubble.fill")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(model.themeColor.color)

            VStack(alignment: .leading, spacing: 10) {
                Text("Help your agent improve")
                    .font(.title2.bold())
                Text(
                    "Your feedback and a copy of this card are shared only with the agent that sent it."
                )
                .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                introductionRow(
                    "Private to the agent",
                    detail: "Other agents cannot read this feedback.",
                    systemImage: "lock.fill"
                )
                introductionRow(
                    "The card stays attached",
                    detail: "The feedback includes the HTML that you received.",
                    systemImage: "doc.richtext"
                )
                introductionRow(
                    "Give the agent its instructions",
                    detail: "The current Agent Box instructions tell the agent how to check and resolve feedback.",
                    systemImage: "checklist"
                )
            }

            Spacer()

            Button {
                hasSeenIntroduction = true
            } label: {
                Text("Continue")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(model.themeColor.color)
        }
        .padding(24)
    }

    private var composer: some View {
        Form {
            if feedback == nil {
                Section("Quick feedback") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(FeedbackPrompt.allCases) { prompt in
                                Button(prompt.title) {
                                    comment = prompt.comment
                                }
                                .buttonStyle(.bordered)
                                .buttonBorderShape(.capsule)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            Section {
                TextEditor(text: $comment)
                    .frame(minHeight: 180)
                    .accessibilityLabel("Feedback comment")
                    .accessibilityIdentifier("feedback-comment")

                HStack {
                    Text("Shared with \(agentName)")
                    Spacer()
                    Text("\(comment.count) / 5,000")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(comment.count > 5_000 ? .red : .secondary)
            } header: {
                Text("Comment")
            } footer: {
                Text("A snapshot of the card HTML is included automatically.")
            }
        }
        .tint(model.themeColor.color)
    }

    private var cleanComment: String {
        comment.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var agentName: String {
        feedback?.agentName ?? card?.sourceName ?? "this agent"
    }

    private func introductionRow(
        _ title: String,
        detail: String,
        systemImage: String
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(model.themeColor.color)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func save() {
        guard !isSaving, !cleanComment.isEmpty, cleanComment.count <= 5_000 else { return }
        isSaving = true
        Task {
            let succeeded: Bool
            if let feedback {
                succeeded = await model.updateFeedback(feedback, comment: cleanComment)
            } else if let card {
                succeeded = await model.createFeedback(for: card, comment: cleanComment)
            } else {
                succeeded = false
            }
            isSaving = false
            if succeeded { dismiss() }
        }
    }
}

private enum FeedbackPrompt: String, CaseIterable, Identifiable {
    case stopSending
    case improveDesign
    case makeConcise
    case addInteraction

    var id: Self { self }

    var title: String {
        switch self {
        case .stopSending: "Stop sending"
        case .improveDesign: "Improve design"
        case .makeConcise: "Make concise"
        case .addInteraction: "Add interaction"
        }
    }

    var comment: String {
        switch self {
        case .stopSending: "Stop sending this card."
        case .improveDesign: "Improve the design of this card."
        case .makeConcise: "Make this card more concise."
        case .addInteraction: "Include more interactive details in this card."
        }
    }
}
