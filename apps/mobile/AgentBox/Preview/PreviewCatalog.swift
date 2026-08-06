#if DEBUG
import SwiftUI

#Preview("Full app — populated") {
    RootView()
        .environmentObject(PreviewData.model())
}

#Preview("Full app — purple theme") {
    RootView()
        .environmentObject(PreviewData.model(theme: .purple))
}

#Preview("Full app — monochrome dark") {
    RootView()
        .environmentObject(PreviewData.model(theme: .monochrome, appearance: .dark))
}

#Preview("Full app — onboarding") {
    RootView()
        .environmentObject(PreviewData.model(cards: [], configured: false))
}

#Preview("Onboarding") {
    OnboardingView()
        .environmentObject(PreviewData.model(cards: [], configured: false))
}

#Preview("Onboarding — first agent") {
    RootView()
        .environmentObject(PreviewData.model(cards: [], agents: []))
}

#Preview("Deck — interactive swipe") {
    NavigationStack {
        DeckView(openTimeline: { _ in }, openAgents: {}, openSettings: {})
            .environmentObject(PreviewData.model())
    }
}

#Preview("Deck — empty") {
    NavigationStack {
        DeckView(openTimeline: { _ in }, openAgents: {}, openSettings: {})
            .environmentObject(PreviewData.model(cards: [], theme: .purple))
    }
}

#Preview("Deck — reviewed with reset") {
    let reviewedCards = PreviewData.allCards.map { card in
        var reviewedCard = card
        reviewedCard.clearedAt = Date()
        return reviewedCard
    }

    NavigationStack {
        DeckView(openTimeline: { _ in }, openAgents: {}, openSettings: {})
            .environmentObject(PreviewData.model(cards: reviewedCards, theme: .teal))
    }
}

#Preview("Deck — empty monochrome dark") {
    NavigationStack {
        DeckView(openTimeline: { _ in }, openAgents: {}, openSettings: {})
            .environmentObject(
                PreviewData.model(cards: [], theme: .monochrome, appearance: .dark)
            )
    }
}

#Preview("Empty state — photo library") {
    TabView {
        ForEach(EmptyDeckPhotos.names, id: \.self) { photoName in
            EmptyDeckView(photoName: photoName)
                .environmentObject(PreviewData.model(cards: [], theme: .purple))
        }
    }
    .tabViewStyle(.page(indexDisplayMode: .always))
}

#Preview("Deck — dark mode") {
    NavigationStack {
        DeckView(openTimeline: { _ in }, openAgents: {}, openSettings: {})
            .environmentObject(PreviewData.model())
    }
        .preferredColorScheme(.dark)
}

#Preview("Deck — accessibility text") {
    NavigationStack {
        DeckView(openTimeline: { _ in }, openAgents: {}, openSettings: {})
            .environmentObject(PreviewData.model())
    }
        .environment(\.dynamicTypeSize, .accessibility3)
}

#Preview("History — all states") {
    HistoryView()
        .environmentObject(PreviewData.model())
}

#Preview("History — search results") {
    HistoryView(initialQuery: "market")
        .environmentObject(PreviewData.model())
}

#Preview("History — dark mode") {
    HistoryView()
        .environmentObject(PreviewData.model())
        .preferredColorScheme(.dark)
}

#Preview("Upcoming") {
    HistoryView(initialSection: .upcoming)
        .environmentObject(PreviewData.model())
}

#Preview("Card detail — rich HTML") {
    NavigationStack {
        CardDetailView(card: PreviewData.activeMarket)
    }
    .environmentObject(PreviewData.model())
}

#Preview("Card detail — restore action") {
    NavigationStack {
        CardDetailView(card: PreviewData.cleared)
    }
    .environmentObject(PreviewData.model())
}

#Preview("Settings — configured") {
    SettingsView()
        .environmentObject(PreviewData.model(theme: .teal, appearance: .dark))
}

#Preview("Settings — needs token") {
    SettingsView()
        .environmentObject(PreviewData.model(configured: false))
}

#Preview("Agents") {
    AgentsView()
        .environmentObject(PreviewData.model(theme: .teal))
}

#Preview("Agents — no inboxes") {
    AgentsView()
        .environmentObject(PreviewData.model(theme: .orange, inboxes: []))
}

#Preview("Agent Cards") {
    NavigationStack {
        AgentCardsView(
            agent: Agent(
                id: "agent_preview_research",
                name: "Research agent",
                keyHint: "7XK2",
                createdAt: Date().addingTimeInterval(-86_400),
                lastUsedAt: Date().addingTimeInterval(-300),
                revokedAt: nil
            )
        )
        .environmentObject(PreviewData.model(theme: .teal))
    }
}

#Preview("New Agent") {
    NewAgentView()
        .environmentObject(PreviewData.model(theme: .teal))
}

#Preview("New Inbox") {
    NewInboxView()
        .environmentObject(PreviewData.model(theme: .teal))
}

#Preview("Change account key") {
    ChangeAccountKeyView()
        .environmentObject(PreviewData.model(theme: .purple))
}
#endif
