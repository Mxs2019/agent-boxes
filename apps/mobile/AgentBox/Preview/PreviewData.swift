#if DEBUG
import Foundation

enum PreviewData {
    private static let now = Date()

    static let activeMarket = Card(
        id: "card_preview_market",
        accountID: "account_preview",
        sequence: 1,
        title: "Morning market update",
        html: """
        <style>
          .positive { color: #16803c; font-weight: 700; }
          .note { background-color: #eef5ff; border-radius: 10px; padding: 12px; }
        </style>
        <h2>Markets opened higher</h2>
        <p>Rail and semiconductor stocks led the morning move.</p>
        <div class="note">
          <strong>Watch:</strong> Treasury yields after the 10:00 AM release.
        </div>
        <h3>Quick view</h3>
        <table>
          <thead><tr><th>Index</th><th>Move</th></tr></thead>
          <tbody>
            <tr><td>S&amp;P 500</td><td class="positive">+0.7%</td></tr>
            <tr><td>Nasdaq</td><td class="positive">+1.1%</td></tr>
          </tbody>
        </table>
        """,
        plainText: "Markets opened higher. Rail and semiconductor stocks led the morning move.",
        createdAt: now.addingTimeInterval(-18 * 60),
        expiresAt: now.addingTimeInterval(23 * 60 * 60),
        clearedAt: nil,
        source: "api",
        sourceName: "research-agent",
        agentID: "agent_preview_research",
        contentTrust: .trusted,
        metadata: ["topic": .string("markets")]
    )

    static let activeReview = Card(
        id: "card_preview_review",
        accountID: "account_preview",
        sequence: 2,
        title: "Things to review",
        html: """
        <h2>Today</h2>
        <ol>
          <li>Review the new onboarding flow.</li>
          <li>Approve the launch copy.</li>
          <li>Check the TestFlight notes.</li>
        </ol>
        <blockquote>Focus on changes that remove work for the user.</blockquote>
        """,
        plainText: "Review the new onboarding flow, approve the launch copy, and check TestFlight notes.",
        createdAt: now.addingTimeInterval(-7 * 60),
        expiresAt: now.addingTimeInterval(24 * 60 * 60),
        clearedAt: nil,
        source: "api",
        sourceName: "product-agent",
        agentID: "agent_preview_product",
        contentTrust: .trusted,
        metadata: [:]
    )

    static let cleared = Card(
        id: "card_preview_cleared",
        accountID: "account_preview",
        sequence: 3,
        title: "Commute reading list",
        html: "<h2>Saved for the train</h2><p>A short product strategy memo and two design notes.</p>",
        plainText: "A short product strategy memo and two design notes.",
        createdAt: now.addingTimeInterval(-5 * 60 * 60),
        expiresAt: now.addingTimeInterval(19 * 60 * 60),
        clearedAt: now.addingTimeInterval(-4 * 60 * 60),
        source: "email",
        sourceName: "max@example.com",
        metadata: [:]
    )

    static let expired = Card(
        id: "card_preview_expired",
        accountID: "account_preview",
        sequence: 4,
        title: "Yesterday’s weather window",
        html: "<h2>Dry until 8 PM</h2><p>This forecast is now out of date.</p>",
        plainText: "Dry until 8 PM. This forecast is now out of date.",
        createdAt: now.addingTimeInterval(-28 * 60 * 60),
        expiresAt: now.addingTimeInterval(-4 * 60 * 60),
        clearedAt: nil,
        source: "api",
        sourceName: "weather-agent",
        agentID: "agent_preview_weather",
        contentTrust: .trusted,
        metadata: [:]
    )

    static let snoozed = Card(
        id: "card_preview_snoozed",
        accountID: "account_preview",
        sequence: 5,
        title: "Quarterly planning notes",
        html: "<h2>Planning notes</h2><p>Review these notes before the next planning session.</p>",
        plainText: "Review these notes before the next planning session.",
        createdAt: now.addingTimeInterval(-2 * 60 * 60),
        expiresAt: now.addingTimeInterval(8 * 86_400),
        clearedAt: nil,
        snoozedUntil: now.addingTimeInterval(2 * 86_400),
        source: "api",
        sourceName: "planning-agent",
        metadata: [:]
    )

    static let scheduled = Card(
        id: "card_preview_scheduled",
        accountID: "account_preview",
        sequence: 6,
        title: "Friday launch checklist",
        html: "<h2>Launch checklist</h2><p>Complete the final release checks.</p>",
        plainText: "Complete the final release checks.",
        createdAt: now.addingTimeInterval(-60 * 60),
        showAt: now.addingTimeInterval(3 * 86_400),
        expiresAt: now.addingTimeInterval(4 * 86_400),
        clearedAt: nil,
        source: "api",
        sourceName: "release-agent",
        metadata: [:]
    )

    static let allCards = [activeMarket, activeReview, cleared, expired, snoozed, scheduled]

    @MainActor
    static func model(
        cards: [Card] = allCards,
        configured: Bool = true,
        theme: AppThemeColor = .blue,
        appearance: AppAppearance = .system,
        agents: [Agent]? = nil,
        inboxes: [Inbox]? = nil
    ) -> AppModel {
        AppModel(
            previewCards: cards,
            previewConfigured: configured,
            previewTheme: theme,
            previewAppearance: appearance,
            previewAgents: agents,
            previewInboxes: inboxes
        )
    }
}
#endif
