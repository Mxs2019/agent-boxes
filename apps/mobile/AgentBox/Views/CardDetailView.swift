import SwiftUI

struct CardDetailView: View {
    @EnvironmentObject private var model: AppModel
    let card: Card
    @State private var feedbackCard: Card?

    var body: some View {
        CardChrome(card: currentCard)
            .padding([.horizontal, .bottom], 12)
            .background(model.themeColor.appBackgroundColor.ignoresSafeArea())
            .accessibilityIdentifier("card-detail-\(card.id)")
            .navigationTitle(currentCard.title ?? "Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if canAddToDeckNow {
                            Button("Add to Deck Now", systemImage: "rectangle.stack.badge.plus") {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                model.restoreToDeck(currentCard)
                            }
                            .accessibilityIdentifier("add-card-to-deck-now")
                        } else if canRestore {
                            Button("Restore to Deck", systemImage: "arrow.uturn.backward") {
                                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                model.restoreToDeck(currentCard)
                            }
                            .accessibilityIdentifier("restore-card-to-deck")
                        } else {
                            Button("In Deck", systemImage: "rectangle.stack.fill") {}
                                .disabled(true)
                        }
                        Divider()
                        if currentCard.agentID != nil {
                            Button("Leave Feedback", systemImage: "text.bubble") {
                                presentFeedback(for: currentCard)
                            }
                        } else {
                            Button("No agent feedback", systemImage: "text.bubble") {}
                                .disabled(true)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("Card actions")
                    .accessibilityIdentifier("card-actions")
                }
            }
            .sheet(item: $feedbackCard) { card in
                FeedbackComposerView(card: card)
                    .environmentObject(model)
            }
    }

    private var currentCard: Card {
        model.cards.first(where: { $0.id == card.id }) ?? card
    }

    private var canRestore: Bool {
        [.cleared, .expired].contains(currentCard.status())
    }

    private var canAddToDeckNow: Bool {
        [.scheduled, .snoozed].contains(currentCard.status())
    }

    private func presentFeedback(for card: Card) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            feedbackCard = card
        }
    }
}
