import SwiftUI

enum CardTimelineSection: String, CaseIterable, Identifiable {
    case history = "History"
    case upcoming = "Upcoming"

    var id: Self { self }

    var systemImage: String {
        switch self {
        case .history: "list.bullet.rectangle.portrait"
        case .upcoming: "calendar.badge.clock"
        }
    }
}

struct HistoryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var selectedSection: CardTimelineSection
    @State private var searchIndex: CardSearchIndex
    @State private var searchResults: [CardSearchResult] = []

    init(
        initialSection: CardTimelineSection = .history,
        initialQuery: String = ""
    ) {
        _query = State(initialValue: initialQuery)
        _selectedSection = State(initialValue: initialSection)
        _searchIndex = State(initialValue: CardSearchIndex())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Card timeline", selection: $selectedSection) {
                    ForEach(CardTimelineSection.allCases) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .accessibilityIdentifier("card-timeline-section")

                Divider()

                List {
                    if isSearching {
                        ForEach(searchResults) { result in
                            cardLink(result.card, searchMatch: result.match)
                        }
                    } else {
                        ForEach(browsingCards) { card in
                            cardLink(card)
                        }
                    }
                }
                .listStyle(.plain)
                .overlay { emptyState }
            }
            .navigationTitle(selectedSection.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("history-done")
                }
            }
            .searchable(text: $query, prompt: "Title, content, or source")
            .task(id: searchCorpusID) {
                await searchIndex.prepare(searchCandidates)
            }
            .task(id: searchTaskID) {
                guard isSearching else {
                    searchResults = []
                    return
                }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled else { return }
                let results = await searchIndex.search(query, in: searchCandidates)
                guard !Task.isCancelled else { return }
                searchResults = results.sorted { first, second in
                    cardSort(first.card, second.card)
                }
            }
            .refreshable { await model.sync() }
        }
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var browsingCards: [Card] {
        searchCandidates.sorted(by: cardSort)
    }

    private var listedCards: [Card] {
        isSearching ? searchResults.map(\.card) : browsingCards
    }

    private var searchCandidates: [Card] {
        switch selectedSection {
        case .history: model.historyCards
        case .upcoming: model.upcomingCards
        }
    }

    private var isSearching: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var searchTaskID: CardSearchTaskID {
        CardSearchTaskID(
            scope: selectedSection.rawValue,
            query: query,
            cardIDs: searchCandidates.map(\.id)
        )
    }

    private var searchCorpusID: CardSearchTaskID {
        CardSearchTaskID(
            scope: selectedSection.rawValue,
            query: "",
            cardIDs: searchCandidates.map(\.id)
        )
    }

    @ViewBuilder
    private func cardLink(_ card: Card, searchMatch: CardSearchMatch? = nil) -> some View {
        NavigationLink {
            HistoryBrowserView(
                cards: listedCards,
                initialCardID: card.id,
                section: selectedSection
            )
        } label: {
            historyRow(card, searchMatch: searchMatch)
        }
        .accessibilityIdentifier(cardIdentifier(for: card))
        .listRowInsets(
            EdgeInsets(top: 11, leading: 20, bottom: 11, trailing: 16)
        )
    }

    @ViewBuilder
    private func historyRow(_ card: Card, searchMatch: CardSearchMatch?) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(displayDate(for: card), format: rowDateFormat)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            CardRow(card: card, searchMatch: searchMatch, showsBody: false)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rowAccessibilityLabel(for: card))
    }

    @ViewBuilder
    private var emptyState: some View {
        if !isSearching {
            if selectedSection == .upcoming, model.upcomingCards.isEmpty {
                ContentUnavailableView(
                    "Nothing upcoming",
                    systemImage: "calendar.badge.clock",
                    description: Text("Snoozed and scheduled cards will appear here.")
                )
            } else if selectedSection == .history, model.historyCards.isEmpty {
                ContentUnavailableView("No history", systemImage: "rectangle.stack")
            }
        } else if searchResults.isEmpty {
            ContentUnavailableView.search(text: query)
        }
    }

    private var rowDateFormat: Date.FormatStyle {
        .dateTime.month(.abbreviated).day().year().hour().minute()
    }

    private func displayDate(for card: Card) -> Date {
        selectedSection == .upcoming ? card.upcomingDate() ?? card.createdAt : card.createdAt
    }

    private func cardSort(_ first: Card, _ second: Card) -> Bool {
        if selectedSection == .upcoming {
            return displayDate(for: first) < displayDate(for: second)
        }
        return first.createdAt > second.createdAt
    }

    private func cardIdentifier(for card: Card) -> String {
        "\(selectedSection == .upcoming ? "upcoming" : "history")-card-\(card.id)"
    }

    private func rowAccessibilityLabel(for card: Card) -> String {
        let source = card.sourceName ?? card.source.capitalized
        let date = displayDate(for: card).formatted(rowDateFormat)
        return "\(card.title ?? "Untitled"), \(source), \(date)"
    }
}

private struct HistoryBrowserView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let cards: [Card]
    let section: CardTimelineSection
    private let initialCardID: String
    private let cardsByID: [String: Card]
    @State private var selectedCardID: String?
    @State private var isOverview = false
    @State private var snapshots: [String: UIImage] = [:]
    @State private var snapshotOrder: [String] = []
    @State private var addedCardIDs: Set<String> = []
    @State private var transitionCardID: String?
    @State private var zoomAnimationID: UUID?
    @State private var zoomProgress: CGFloat = 0
    @State private var overviewContentOpacity: Double = 1
    @State private var snapshotRequestCardID: String?
    @State private var snapshotRequestID: UUID?
    @State private var pendingOverviewChange: Bool?
    @State private var feedbackCard: Card?
    @State private var overviewScrollOffset: CGFloat = 0

    init(
        cards: [Card],
        initialCardID: String,
        section: CardTimelineSection,
        startsInOverview: Bool = false
    ) {
        self.cards = cards
        self.section = section
        self.initialCardID = initialCardID
        cardsByID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        _selectedCardID = State(initialValue: initialCardID)
        _isOverview = State(initialValue: startsInOverview)
        _transitionCardID = State(initialValue: initialCardID)
        _zoomProgress = State(initialValue: startsInOverview ? 1 : 0)
        _snapshotRequestCardID = State(initialValue: initialCardID)
        _snapshotRequestID = State(initialValue: UUID())
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                if isOverview {
                    overview(in: geometry.size)
                } else {
                    focusedCards(in: geometry.size)

                    historyAction
                }

                zoomCard(in: geometry.size)
            }
        }
        .background(model.themeColor.appBackgroundColor.ignoresSafeArea())
        .navigationTitle(currentCard?.title ?? section.rawValue)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    setOverview(!isOverview)
                } label: {
                    Image(systemName: isOverview ? "rectangle.fill" : "rectangle.grid.2x2")
                }
                .accessibilityLabel(isOverview ? "Show full card" : "Show card overview")
                .accessibilityIdentifier("history-overview-toggle")
            }
        }
        .onChange(of: selectedCardID) { oldValue, newValue in
            guard oldValue != nil, newValue != nil, oldValue != newValue else { return }
            if zoomAnimationID == nil {
                transitionCardID = newValue
                requestSnapshotIfNeeded(for: newValue)
            }
            UISelectionFeedbackGenerator().selectionChanged()
        }
        .sheet(item: $feedbackCard) { card in
            FeedbackComposerView(card: card)
                .environmentObject(model)
        }
    }

    private var currentCard: Card? {
        guard let selectedCardID else { return cards.first }
        return cardsByID[selectedCardID]
    }

    private func focusedCards(in size: CGSize) -> some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(cards) { card in
                        CardChrome(
                            card: card,
                            allowsContentScrolling: true,
                            snapshotRequestID: snapshotRequestCardID == card.id
                                ? snapshotRequestID
                                : nil,
                            onSnapshot: { requestID, image in
                                receiveSnapshot(requestID, image: image, for: card.id)
                            }
                        )
                        .frame(
                            width: max(size.width - 24, 1),
                            height: max(size.height - 94, 1)
                        )
                        .frame(width: size.width, height: size.height, alignment: .top)
                        .offset(y: 12)
                        .scrollTransition(.interactive, axis: .horizontal) { content, phase in
                            content
                                .scaleEffect(1 - abs(phase.value) * 0.035)
                                .rotationEffect(.degrees(phase.value * 2.5))
                        }
                        .zIndex(card.id == transitionCardID ? 10 : 0)
                        .opacity(
                            zoomAnimationID != nil && card.id == transitionCardID ? 0 : 1
                        )
                        .id(card.id)
                        .accessibilityIdentifier("history-browser-card-\(card.id)")
                    }
                }
                .scrollTargetLayout()
            }
            .scrollIndicators(.hidden)
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $selectedCardID, anchor: .center)
            .onAppear {
                proxy.scrollTo(initialCardID, anchor: .center)
            }
        }
    }

    private func overview(in size: CGSize) -> some View {
        let overviewScale: CGFloat = 0.5
        let fullCardWidth = max(size.width - 24, 1)
        let fullCardHeight = max(size.height - 94, 1)
        let cardWidth = fullCardWidth * overviewScale
        let cardHeight = fullCardHeight * overviewScale
        let overviewContentHeight = max(size.height, cardHeight)
        let dayHeaderHeight: CGFloat = 32
        let dayHeaderTop = max(
            (overviewContentHeight - cardHeight) / 2 - dayHeaderHeight - 8,
            8
        )
        let contentInset = max((size.width - cardWidth) / 2, 0)

        return ZStack(alignment: .topLeading) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 20) {
                        ForEach(cards) { card in
                            Button {
                                selectedCardID = card.id
                                setOverview(false)
                            } label: {
                                HistoryCardThumbnail(
                                    card: card,
                                    snapshot: snapshots[card.id],
                                    onSnapshot: { image in
                                        storeSnapshot(image, for: card.id)
                                    }
                                )
                                .frame(width: fullCardWidth, height: fullCardHeight)
                                .scaleEffect(overviewScale)
                                .frame(width: cardWidth, height: cardHeight)
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .frame(width: cardWidth, height: cardHeight)
                            .zIndex(card.id == transitionCardID ? 10 : 0)
                            .opacity(
                                zoomAnimationID != nil && card.id == transitionCardID
                                    ? 0
                                    : overviewContentOpacity
                            )
                            .id(card.id)
                            .accessibilityLabel(card.title ?? "Untitled")
                            .accessibilityHint("Show the full card.")
                            .accessibilityIdentifier("history-overview-card-\(card.id)")
                        }
                    }
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(
                                key: HistoryOverviewScrollOffsetKey.self,
                                value: contentInset
                                    - geometry.frame(
                                        in: .named("history-overview-scroll")
                                    ).minX
                            )
                        }
                    }
                    .padding(.horizontal, contentInset)
                    .frame(minHeight: overviewContentHeight)
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "history-overview-scroll")
                .onAppear {
                    guard let selectedCardID else { return }
                    proxy.scrollTo(selectedCardID, anchor: .center)
                }
                .onPreferenceChange(HistoryOverviewScrollOffsetKey.self) { newOffset in
                    overviewScrollOffset = max(newOffset, 0)
                    updateOverviewSelection(from: newOffset, cardWidth: cardWidth)
                }
            }

            overviewDayHeaders(cardWidth: cardWidth, viewportWidth: size.width)
                .padding(.top, dayHeaderTop)
                .opacity(zoomAnimationID == nil ? 1 : overviewContentOpacity)
        }
    }

    @ViewBuilder
    private var historyAction: some View {
        if let currentCard {
            HStack(spacing: 12) {
                Menu {
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
                        .font(.body.weight(.semibold))
                        .frame(width: 54, height: 54)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 10, y: 4)
                .accessibilityLabel("More card actions")
                .accessibilityIdentifier("history-more-card-actions")

                Button {
                    guard !isInDeck(currentCard) else { return }
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    addedCardIDs.insert(currentCard.id)
                    model.restoreToDeck(currentCard)
                } label: {
                    Label(
                        actionTitle(for: currentCard),
                        systemImage: isInDeck(currentCard)
                            ? "rectangle.stack.fill"
                            : "rectangle.stack.badge.plus"
                    )
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(model.themeColor.foregroundColor)
                .background(model.themeColor.color, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
                .disabled(isInDeck(currentCard))
                .opacity(isInDeck(currentCard) ? 0.58 : 1)
                .accessibilityIdentifier("add-back-to-deck")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .opacity(zoomAnimationID == nil ? 1 : 0)
            .transition(.opacity)
        }
    }

    private func actionTitle(for card: Card) -> String {
        if isInDeck(card) { return "In Deck" }
        return section == .history ? "Add back to Deck" : "Add to Deck Now"
    }

    private func isInDeck(_ card: Card) -> Bool {
        card.status() == .active || addedCardIDs.contains(card.id)
    }

    private func presentFeedback(for card: Card) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            feedbackCard = card
        }
    }

    private func setOverview(_ value: Bool) {
        guard value != isOverview, zoomAnimationID == nil else { return }
        guard !reduceMotion else {
            isOverview = value
            zoomProgress = value ? 1 : 0
            return
        }

        if value, let selectedCardID {
            pendingOverviewChange = value
            requestSnapshot(for: selectedCardID)
            return
        }

        startZoom(toOverview: value)
    }

    private func startZoom(toOverview value: Bool) {
        let animationID = UUID()
        transitionCardID = selectedCardID
        zoomAnimationID = animationID
        zoomProgress = value ? 0 : 1
        overviewContentOpacity = value ? 0 : 1

        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            isOverview = value
        }

        Task { @MainActor in
            await Task.yield()
            withAnimation(zoomAnimation(toOverview: value)) {
                zoomProgress = value ? 1 : 0
                overviewContentOpacity = value ? 1 : 0
            }

            try? await Task.sleep(for: zoomCleanupDelay(toOverview: value))
            guard zoomAnimationID == animationID else { return }
            zoomAnimationID = nil
            transitionCardID = selectedCardID
            overviewContentOpacity = 1
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    @ViewBuilder
    private func zoomCard(in size: CGSize) -> some View {
        if zoomAnimationID != nil,
           let transitionCardID,
           let card = cardsByID[transitionCardID]
        {
            let fullCardWidth = max(size.width - 24, 1)
            let fullCardHeight = max(size.height - 94, 1)
            let scale = 1 - (zoomProgress * 0.5)
            let fullCenterY = 12 + (fullCardHeight / 2)
            let overviewCenterY = size.height / 2
            let centerY = fullCenterY + ((overviewCenterY - fullCenterY) * zoomProgress)

            HistoryCardThumbnail(
                card: card,
                snapshot: snapshots[transitionCardID],
                onSnapshot: { image in
                    storeSnapshot(image, for: transitionCardID)
                }
            )
            .frame(width: fullCardWidth, height: fullCardHeight)
            .scaleEffect(scale, anchor: .center)
            .position(x: size.width / 2, y: centerY)
            .allowsHitTesting(false)
            .zIndex(100)
        }
    }

    private func requestSnapshotIfNeeded(for cardID: String?) {
        guard let cardID, snapshots[cardID] == nil else { return }
        requestSnapshot(for: cardID)
    }

    private func requestSnapshot(for cardID: String) {
        snapshotRequestCardID = cardID
        snapshotRequestID = UUID()
    }

    private func receiveSnapshot(_ requestID: UUID, image: UIImage?, for cardID: String) {
        guard snapshotRequestID == requestID, snapshotRequestCardID == cardID else { return }
        snapshotRequestID = nil
        if let image {
            storeSnapshot(image, for: cardID)
        }

        guard let pendingOverviewChange else { return }
        self.pendingOverviewChange = nil
        startZoom(toOverview: pendingOverviewChange)
    }

    private var usesSlowZoomAnimation: Bool {
        ProcessInfo.processInfo.arguments.contains("--ui-testing-slow-history-zoom")
    }

    private func zoomAnimation(toOverview: Bool) -> Animation {
        if usesSlowZoomAnimation {
            return .spring(response: 2.2, dampingFraction: 0.92)
        }
        let response = toOverview ? 0.35 : 0.52
        return .spring(response: response, dampingFraction: 0.9)
    }

    private func zoomCleanupDelay(toOverview: Bool) -> Duration {
        if usesSlowZoomAnimation { return .milliseconds(2_500) }
        return toOverview ? .milliseconds(440) : .milliseconds(650)
    }

    private func updateOverviewSelection(from offset: CGFloat, cardWidth: CGFloat) {
        guard !cards.isEmpty else { return }
        let cardStep = cardWidth + 20
        let index = min(max(Int((offset / cardStep).rounded()), 0), cards.count - 1)
        let cardID = cards[index].id
        if selectedCardID != cardID {
            selectedCardID = cardID
        }
    }

    private func overviewDayHeaders(cardWidth: CGFloat, viewportWidth: CGFloat) -> some View {
        let sections = overviewDaySections
        let layout = HistoryOverviewDayHeaderLayout(
            cardWidth: cardWidth,
            viewportWidth: viewportWidth,
            scrollOffset: overviewScrollOffset
        )

        return ZStack(alignment: .topLeading) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                Text(section.day, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .frame(width: layout.headerWidth, height: 32, alignment: .leading)
                    .background(.regularMaterial, in: Capsule())
                    .offset(x: layout.xPosition(for: index, in: sections))
                    .accessibilityLabel(
                        section.day.formatted(.dateTime.weekday(.wide).month(.wide).day())
                    )
                    .accessibilityIdentifier("history-overview-day-\(index)")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    private var overviewDaySections: [HistoryOverviewDaySection] {
        let calendar = Calendar.autoupdatingCurrent
        var sections: [HistoryOverviewDaySection] = []
        for (index, card) in cards.enumerated() {
            let date = section == .upcoming
                ? card.upcomingDate() ?? card.createdAt
                : card.createdAt
            let day = calendar.startOfDay(for: date)
            if sections.last?.day != day {
                sections.append(HistoryOverviewDaySection(day: day, firstCardIndex: index))
            }
        }
        return sections
    }

    private func storeSnapshot(_ image: UIImage?, for cardID: String) {
        guard let image else { return }
        snapshots[cardID] = image
        snapshotOrder.removeAll { $0 == cardID }
        snapshotOrder.append(cardID)

        let cacheLimit = 28
        while snapshotOrder.count > cacheLimit {
            let removedID = snapshotOrder.removeFirst()
            snapshots[removedID] = nil
        }
    }
}

private struct HistoryOverviewScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct HistoryOverviewDaySection: Identifiable {
    let day: Date
    let firstCardIndex: Int

    var id: Date { day }
}

struct HistoryOverviewDayHeaderLayout {
    let cardWidth: CGFloat
    let viewportWidth: CGFloat
    let scrollOffset: CGFloat
    let headerWidth: CGFloat = 156
    let pinnedLeading: CGFloat = 16
    let pushSpacing: CGFloat = 8
    let cardSpacing: CGFloat = 20

    func xPosition(
        for sectionIndex: Int,
        in sections: [HistoryOverviewDaySection]
    ) -> CGFloat {
        guard sections.indices.contains(sectionIndex) else { return pinnedLeading }
        let naturalPosition = xPosition(for: sections[sectionIndex])
        let activeIndex = sections.lastIndex {
            xPosition(for: $0) <= pinnedLeading
        }
        guard activeIndex == sectionIndex else { return naturalPosition }

        let nextPosition = sections.indices.contains(sectionIndex + 1)
            ? xPosition(for: sections[sectionIndex + 1])
            : .greatestFiniteMagnitude
        return min(pinnedLeading, nextPosition - headerWidth - pushSpacing)
    }

    private func xPosition(for section: HistoryOverviewDaySection) -> CGFloat {
        let contentInset = max((viewportWidth - cardWidth) / 2, 0)
        let cardStep = cardWidth + cardSpacing
        return contentInset + (CGFloat(section.firstCardIndex) * cardStep) - scrollOffset
    }
}

private struct HistoryCardThumbnail: View {
    let card: Card
    let snapshot: UIImage?
    let onSnapshot: (UIImage?) -> Void
    @State private var snapshotRequestID = UUID()

    var body: some View {
        CardChrome(
            card: card,
            allowsContentScrolling: false,
            contentSnapshot: snapshot,
            snapshotRequestID: snapshot == nil ? snapshotRequestID : nil,
            onSnapshot: { requestID, image in
                guard requestID == snapshotRequestID else { return }
                onSnapshot(image)
            }
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct HistoryDayGroup: Identifiable {
    let day: Date
    let cards: [Card]

    var id: Date { day }
}

struct HistoryDayHeader: View {
    let date: Date

    var body: some View {
        HStack(spacing: 12) {
            Text(date, format: .dateTime.day())
                .font(.title2.bold())
                .fontDesign(.rounded)
                .monospacedDigit()
                .frame(minWidth: 30)

            VStack(alignment: .leading, spacing: 1) {
                Text(dayName)
                    .font(.subheadline.weight(.semibold))
                Text(date, format: .dateTime.month(.wide).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .foregroundStyle(.primary)
        .padding(.top, 10)
        .padding(.bottom, 3)
    }

    private var dayName: String {
        let calendar = Calendar.autoupdatingCurrent
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInTomorrow(date) { return "Tomorrow" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide))
    }
}

#if DEBUG
#Preview("History — zoomed-out timeline") {
    let model = PreviewData.model()

    NavigationStack {
        HistoryBrowserView(
            cards: model.historyCards,
            initialCardID: PreviewData.activeMarket.id,
            section: .history,
            startsInOverview: true
        )
    }
    .environmentObject(model)
}
#endif
