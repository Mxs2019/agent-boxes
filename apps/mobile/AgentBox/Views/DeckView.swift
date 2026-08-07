import SwiftUI

struct DeckView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let openTimeline: (CardTimelineSection) -> Void
    let openAgents: () -> Void
    let openSettings: () -> Void
    @State private var dragOffset = CGSize.zero
    @State private var dragStartLocation = CGPoint.zero
    @State private var isClearing = false
    @State private var isManualRefreshRunning = false
    @State private var didCrossDismissThreshold = false
    @State private var swipeIntent = SwipeIntent.undecided
    @State private var undoStack: [Card] = []
    @State private var restoringCard: Card?
    @State private var restoreAnimationID: UUID?
    @State private var departingCards: [DepartingCard] = []
    @State private var stackDepthOffset: CGFloat = 0
    @State private var nextDepartureZIndex: Double = 100
    @State private var showDismissAllConfirmation = false
    @State private var showCustomSnoozePicker = false
    @State private var currentViewSize = CGSize.zero
    @State private var isDismissingAll = false
    @State private var snoozingCardID: String?
    @State private var snoozeProgress: CGFloat = 0
    @State private var snoozeSnapshotCardID: String?
    @State private var snoozeSnapshotRequestID: UUID?
    @State private var snoozeContentSnapshot: UIImage?
    @State private var contentSnapshotCache = ContentSnapshotCache()
    @State private var contentSnapshotRequestIDs: [String: UUID] = [:]
    @State private var pendingSnoozeDate: Date?
    @State private var showsEmptyDeckContent = false
    @State private var didInitializeEmptyDeckContent = false
    @State private var feedbackCard: Card?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            GeometryReader { geometry in
                ZStack(alignment: .bottom) {
                    ZStack {
                        if presentedCards.count <= 1 || isDismissingAll {
                            EmptyDeckView(
                                artworkOpacity: emptyArtworkOpacity(
                                    in: geometry.size.width
                                ),
                                showsContent: showsEmptyDeckContent,
                                openHistory: { openTimeline(.history) }
                            )
                                .allowsHitTesting(presentedCards.isEmpty)
                                .accessibilityHidden(!presentedCards.isEmpty)
                        }

                        if let current = presentedCards.first {
                            deck(current: current)
                        }

                        departingCardLayer
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showsDeckActions {
                        deckActions(in: geometry.size)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(model.themeColor.appBackgroundColor.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    guard !isManualRefreshRunning else { return }
                    isManualRefreshRunning = true
                    Task {
                        _ = await model.sync(showErrors: true)
                        isManualRefreshRunning = false
                    }
                } label: {
                    ZStack {
                        Image(systemName: "arrow.clockwise")
                            .opacity(isManualRefreshRunning ? 0 : 1)
                        ProgressView()
                            .controlSize(.small)
                            .opacity(isManualRefreshRunning ? 1 : 0)
                    }
                    .frame(width: 20, height: 20)
                }
                .disabled(isManualRefreshRunning)
                .accessibilityLabel(
                    isManualRefreshRunning ? "Refreshing cards" : "Refresh cards"
                )

                Button(action: openAgents) {
                    Image(systemName: "key")
                }
                .accessibilityLabel("Agents and inboxes")

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    openTimeline(.history)
                } label: {
                    Image(systemName: CardTimelineSection.history.systemImage)
                }
                .accessibilityLabel("History")
                .accessibilityIdentifier("history-button")
            }
        }
        .alert(
            "Dismiss all cards?",
            isPresented: $showDismissAllConfirmation
        ) {
            Button("Dismiss All", role: .destructive) {
                dismissAll(in: currentViewSize)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every active card will move to History.")
        }
        .sheet(isPresented: $showCustomSnoozePicker) {
            SnoozeDatePickerView(initialDate: defaultSnoozeDate) { date in
                snoozeCurrent(until: date)
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $feedbackCard) { card in
            FeedbackComposerView(card: card)
                .environmentObject(model)
        }
        .onAppear {
            guard !didInitializeEmptyDeckContent else { return }
            didInitializeEmptyDeckContent = true
            showsEmptyDeckContent = presentedCards.isEmpty
        }
        .task(id: presentedCards.isEmpty) {
            guard didInitializeEmptyDeckContent else { return }
            guard presentedCards.isEmpty else {
                showsEmptyDeckContent = false
                return
            }
            guard !showsEmptyDeckContent else { return }

            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, presentedCards.isEmpty else { return }
            if reduceMotion {
                showsEmptyDeckContent = true
            } else {
                withAnimation(.spring(response: 0.44, dampingFraction: 0.72)) {
                    showsEmptyDeckContent = true
                }
            }
        }
        .task(id: snapshotTargetCardIDs) {
            if !departingCards.isEmpty {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
            }
            prepareContentSnapshots()
        }
    }

    private var presentedCards: [Card] {
        guard let restoringCard else { return model.activeCards }
        return [restoringCard] + model.activeCards.filter { $0.id != restoringCard.id }
    }

    private var snapshotTargetCardIDs: [String] {
        let limit = showDismissAllConfirmation ? 6 : 3
        return Array(presentedCards.prefix(limit).map(\.id))
    }

    private var departingCardLayer: some View {
        ZStack {
            ForEach(departingCards) { departure in
                CardChrome(
                    card: departure.card,
                    allowsContentScrolling: false,
                    contentSnapshot: departure.contentSnapshot
                )
                .scaleEffect(departure.scale)
                .offset(
                    x: departure.offset.width,
                    y: departure.stackOffset + departure.offset.height
                )
                .rotationEffect(.degrees(departure.rotation))
                .zIndex(departure.zIndex)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 82)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var showsDeckActions: Bool {
        guard !presentedCards.isEmpty, !isDismissingAll else { return false }

        let isDismissingLastCard = isClearing
            && snoozingCardID == nil
            && restoringCard == nil
            && presentedCards.count == 1
        return !isDismissingLastCard
    }

    private func emptyArtworkOpacity(in width: CGFloat) -> Double {
        guard !presentedCards.isEmpty else { return 1 }
        guard presentedCards.count == 1 else { return 0 }

        let swipeProgress = min(magnitude(of: dragOffset) / max(width * 0.7, 1), 1)
        return Double(max(swipeProgress, snoozeProgress))
    }

    @ViewBuilder
    private func deckActions(in size: CGSize) -> some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 12) {
                actionButtons(in: size, usesLiquidGlass: true)
            }
            .onAppear { currentViewSize = size }
            .onChange(of: size) { _, newSize in currentViewSize = newSize }
        } else {
            actionButtons(in: size, usesLiquidGlass: false)
                .onAppear { currentViewSize = size }
                .onChange(of: size) { _, newSize in currentViewSize = newSize }
        }
    }

    private func actionButtons(in size: CGSize, usesLiquidGlass: Bool) -> some View {
        HStack(spacing: 12) {
            Button {
                guard let card = feedbackTargetCard else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                feedbackCard = card
            } label: {
                Image(systemName: "bubble.left")
                    .font(.body.weight(.semibold))
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(
                DeckActionMaterial(
                    usesLiquidGlass: usesLiquidGlass,
                    tint: nil,
                    foreground: .primary
                )
            )
            .disabled(isClearing || feedbackTargetCard == nil)
            .accessibilityLabel(
                feedbackTargetCard == nil ? "No agent feedback" : "Leave Feedback"
            )
            .accessibilityHint("Opens the feedback form for this card.")
            .accessibilityIdentifier("feedback-card")

            Menu {
                Button("1 day") { snoozeCurrent(days: 1) }
                Button("3 days") { snoozeCurrent(days: 3) }
                Button("1 week") { snoozeCurrent(days: 7) }
                Divider()
                Button("Choose date…") {
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        showCustomSnoozePicker = true
                    }
                }
                Divider()
                Button("View Upcoming", systemImage: "calendar.badge.clock") {
                    openTimeline(.upcoming)
                }
            } label: {
                Image(systemName: "clock")
                    .font(.body.weight(.semibold))
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
                    .scaleEffect(clockScale)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .modifier(
                DeckActionMaterial(
                    usesLiquidGlass: usesLiquidGlass,
                    tint: nil,
                    foreground: .primary
                )
            )
            .disabled(isClearing)
            .accessibilityLabel("Snooze")
            .accessibilityHint("Choose when this card returns to the deck.")
            .accessibilityIdentifier("snooze-card")

            actionLabel("Dismiss", systemImage: "checkmark")
            .modifier(
                DeckActionMaterial(
                    usesLiquidGlass: usesLiquidGlass,
                    tint: model.themeColor.color,
                    foreground: model.themeColor.foregroundColor
                )
            )
            .gesture(dismissGesture(in: size))
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Dismiss")
            .accessibilityHint("Double-tap to dismiss this card.")
            .accessibilityAction {
                requestDismiss(in: size)
            }
            .accessibilityAction(named: "Dismiss all cards") {
                presentDismissAllConfirmation()
            }
            .accessibilityIdentifier("dismiss-card")

            Button {
                undoLastClear(in: size)
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.body.weight(.semibold))
                    .frame(width: 54, height: 54)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(
                DeckActionMaterial(
                    usesLiquidGlass: usesLiquidGlass,
                    tint: nil,
                    foreground: .primary
                )
            )
            .disabled(undoStack.isEmpty || isUndoBlocked)
            .accessibilityLabel("Undo")
            .accessibilityIdentifier("undo-card")
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private var feedbackTargetCard: Card? {
        guard let card = presentedCards.first, card.agentID != nil else { return nil }
        return card
    }

    private func dismissGesture(in size: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.55, maximumDistance: 18)
            .exclusively(before: TapGesture())
            .onEnded { result in
                switch result {
                case .first:
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    presentDismissAllConfirmation()
                case .second:
                    requestDismiss(in: size)
                }
            }
    }

    private func actionLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .contentShape(Capsule())
    }

    private var clockScale: CGFloat {
        let arrival = stagedSnoozeProgress(from: 0.55)
        return 1 + sin(arrival * .pi) * 0.16
    }

    private var snoozeFoldProgress: CGFloat {
        min(snoozeProgress / 0.58, 1)
    }

    private var snoozeCollapseProgress: CGFloat {
        stagedSnoozeProgress(from: 0.3)
    }

    private var snoozeTravelProgress: CGFloat {
        stagedSnoozeProgress(from: 0.24)
    }

    private var snoozeScale: CGSize {
        let width = 1 - snoozeCollapseProgress * 0.95
        let heightReduction = min(
            snoozeFoldProgress * 0.48 + snoozeCollapseProgress * 0.47,
            0.95
        )
        return CGSize(width: width, height: 1 - heightReduction)
    }

    private var snoozeTilt: Double {
        -Double(sin(snoozeFoldProgress * .pi)) * 7
    }

    private func stagedSnoozeProgress(from start: CGFloat) -> CGFloat {
        let linear = min(max((snoozeProgress - start) / (1 - start), 0), 1)
        return linear * linear * (3 - 2 * linear)
    }

    private func deck(current: Card) -> some View {
        GeometryReader { geometry in
            let visibleCardLimit = showDismissAllConfirmation ? 6 : 3
            let visibleCards = Array(presentedCards.prefix(visibleCardLimit))
            let progress = max(stackProgress(in: geometry.size.width), snoozeProgress)
            let cardEffectSize = CGSize(
                width: max(geometry.size.width - 32, 1),
                height: max(geometry.size.height - 82, 1)
            )

            ZStack {
                ForEach(Array(visibleCards.enumerated()).reversed(), id: \.element.id) { item in
                    let index = item.offset
                    let card = item.element
                    let cardSnoozeProgress = card.id == snoozingCardID ? snoozeProgress : 0
                    let snapshotRequestID = card.id == snoozeSnapshotCardID
                        ? snoozeSnapshotRequestID
                        : contentSnapshotRequestIDs[card.id]

                    Group {
                        if cardSnoozeProgress > 0, let snoozeContentSnapshot {
                            CardChrome(
                                card: card,
                                allowsContentScrolling: false,
                                contentSnapshot: snoozeContentSnapshot
                            )
                            .distortionEffect(
                                ShaderLibrary.snoozeCardFold(
                                    .float2(cardEffectSize),
                                    .float(snoozeFoldProgress)
                                ),
                                maxSampleOffset: cardEffectSize
                            )
                            .colorEffect(
                                ShaderLibrary.snoozeCardFoldLight(
                                    .float2(cardEffectSize),
                                    .float(snoozeFoldProgress)
                                )
                            )
                        } else {
                            CardChrome(
                                card: card,
                                allowsContentScrolling: index == 0
                                    && swipeIntent != .swipingCard
                                    && !isClearing,
                                snapshotRequestID: snapshotRequestID,
                                onSnapshot: { requestID, image in
                                    handleContentSnapshot(
                                        image,
                                        for: card,
                                        requestID: requestID
                                    )
                                }
                            )
                        }
                    }
                        .scaleEffect(
                            stackScale(
                                at: index,
                                progress: progress,
                                depthOffset: stackDepthOffset
                            )
                        )
                        .offset(
                            x: index == 0 ? dragOffset.width : 0,
                            y: stackOffset(
                                at: index,
                                progress: progress,
                                depthOffset: stackDepthOffset
                            )
                                + (index == 0 ? dragOffset.height : 0)
                        )
                        .rotationEffect(
                            .degrees(
                                (index == 0
                                    ? rotation(
                                        for: dragOffset,
                                        from: dragStartLocation,
                                        in: geometry.size
                                    ) : 0)
                            )
                        )
                        .scaleEffect(
                            x: cardSnoozeProgress > 0 ? snoozeScale.width : 1,
                            y: cardSnoozeProgress > 0 ? snoozeScale.height : 1,
                            anchor: .bottomLeading
                        )
                        .rotation3DEffect(
                            .degrees(cardSnoozeProgress > 0 ? snoozeTilt : 0),
                            axis: (x: 0, y: 1, z: 0),
                            anchor: .bottomLeading,
                            perspective: 0.55
                        )
                        .offset(
                            x: (cardSnoozeProgress > 0 ? snoozeTravelProgress : 0) * 27,
                            y: (cardSnoozeProgress > 0 ? snoozeTravelProgress : 0) * 43
                        )
                        .opacity(index < 3 ? 1 : 0)
                        .zIndex(Double(visibleCards.count - index))
                        .allowsHitTesting(index == 0)
                        .accessibilityHidden(index != 0)
                        .accessibilityLabel(
                            "Card \(card.title ?? "Untitled"), \(model.activeCards.count) remaining"
                        )
                        .accessibilityAction(named: "Clear card") {
                            clear(
                                card,
                                toward: CGSize(width: 1, height: 0),
                                in: geometry.size
                            )
                        }
                    }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 82)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .simultaneousGesture(swipeGesture(for: current, in: geometry.size))
        }
    }

    private func swipeGesture(for card: Card, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                guard !isClearing else { return }

                if swipeIntent == .undecided {
                    let horizontalDistance = abs(value.translation.width)
                    let verticalDistance = abs(value.translation.height)

                    if horizontalDistance >= 10,
                       horizontalDistance >= verticalDistance * 0.8 {
                        swipeIntent = .swipingCard
                    } else if verticalDistance >= 14,
                              verticalDistance > horizontalDistance * 1.25 {
                        swipeIntent = .scrollingContent
                    } else {
                        return
                    }
                }

                guard swipeIntent == .swipingCard else { return }
                dragStartLocation = value.startLocation
                dragOffset = value.translation

                let distance = magnitude(of: value.translation)
                if distance >= 92, !didCrossDismissThreshold {
                    didCrossDismissThreshold = true
                    UISelectionFeedbackGenerator().selectionChanged()
                } else if distance < 72 {
                    didCrossDismissThreshold = false
                }
            }
            .onEnded { value in
                guard !isClearing else { return }
                guard swipeIntent == .swipingCard else {
                    resetGestureState()
                    return
                }

                let didPlayThresholdHaptic = didCrossDismissThreshold
                swipeIntent = .undecided
                didCrossDismissThreshold = false

                let translationDistance = magnitude(of: value.translation)
                let projectedDistance = magnitude(of: value.predictedEndTranslation)
                if translationDistance >= 92 || projectedDistance >= 170 {
                    let exitVector = projectedDistance > translationDistance
                        ? value.predictedEndTranslation
                        : value.translation
                    clear(
                        card,
                        toward: exitVector,
                        in: size,
                        playsHaptic: !didPlayThresholdHaptic
                    )
                } else {
                    withAnimation(
                        .spring(response: 0.34, dampingFraction: 0.76, blendDuration: 0.08)
                    ) {
                        dragOffset = .zero
                    }
                    dragStartLocation = .zero
                }
            }
    }

    private func requestDismiss(in size: CGSize) {
        guard !isClearing, let current = presentedCards.first else { return }
        clear(current, toward: CGSize(width: 1, height: 0), in: size)
    }

    private func presentDismissAllConfirmation() {
        for card in presentedCards.prefix(6) {
            contentSnapshotRequestIDs[card.id] = UUID()
        }
        showDismissAllConfirmation = true
    }

    private func dismissAll(in size: CGSize) {
        guard !isClearing else { return }
        let cards = model.activeCards
        guard !cards.isEmpty else { return }
        let visibleCards = Array(cards.prefix(6))
        isClearing = true
        isDismissingAll = true
        resetGestureState()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        let distance = max(hypot(size.width, size.height) * 1.35, 700)
        let duration = reduceMotion ? 0.01 : 0.22
        let staggerNanoseconds: UInt64 = reduceMotion ? 0 : 32_000_000
        let zIndexBase = nextDepartureZIndex
        nextDepartureZIndex += Double(visibleCards.count)
        let departures = visibleCards.enumerated().map { index, card in
            DepartingCard(
                card: card,
                contentSnapshot: contentSnapshotCache.images[card.id],
                scale: stackScale(at: index, progress: 0),
                stackOffset: stackOffset(at: index, progress: 0),
                offset: .zero,
                rotation: 0,
                zIndex: zIndexBase + Double(visibleCards.count - index)
            )
        }
        let departureIDs = Set(departures.map(\.id))

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            departingCards.append(contentsOf: departures)
            model.clearAll(cards)
            undoStack.append(contentsOf: cards)
        }

        Task {
            await Task.yield()
            for (index, departure) in departures.enumerated() {
                if index > 0, staggerNanoseconds > 0 {
                    try? await Task.sleep(nanoseconds: staggerNanoseconds)
                }
                let laneOffset = CGFloat((index % 3) - 1) * 6
                let fanRotation = 9 + Double((index % 3) - 1) * 1.2
                animateDeparture(
                    departure.id,
                    to: CGSize(
                        width: distance + CGFloat(index) * 18,
                        height: laneOffset
                    ),
                    rotation: fanRotation,
                    animation: .spring(response: duration, dampingFraction: 0.88)
                )
                UISelectionFeedbackGenerator().selectionChanged()
            }

            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            withTransaction(transaction) {
                departingCards.removeAll { departureIDs.contains($0.id) }
                isDismissingAll = false
                isClearing = false
                resetGestureState()
            }
            discardUnusedContentSnapshots()
        }
    }

    private var defaultSnoozeDate: Date {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: Date())
            ?? Date().addingTimeInterval(86_400)
    }

    private func snoozeCurrent(days: Int) {
        guard let date = Calendar.autoupdatingCurrent.date(
            byAdding: .day,
            value: days,
            to: Date()
        ) else { return }
        snoozeCurrent(until: date)
    }

    private func snoozeCurrent(until date: Date) {
        guard !isClearing, let current = presentedCards.first else { return }
        isClearing = true
        snoozeSnapshotCardID = current.id
        let requestID = UUID()
        snoozeSnapshotRequestID = requestID
        contentSnapshotRequestIDs[current.id] = nil
        snoozeContentSnapshot = nil
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        pendingSnoozeDate = date

        Task {
            try? await Task.sleep(for: .milliseconds(400))
            finishSnoozeSnapshot(nil, for: current, requestID: requestID)
        }
    }

    private func handleContentSnapshot(
        _ image: UIImage?,
        for card: Card,
        requestID: UUID
    ) {
        if snoozeSnapshotCardID == card.id, snoozeSnapshotRequestID == requestID {
            if let image {
                contentSnapshotCache.images[card.id] = image
            }
            finishSnoozeSnapshot(image, for: card, requestID: requestID)
            return
        }

        guard contentSnapshotRequestIDs[card.id] == requestID else { return }
        if let image {
            contentSnapshotCache.images[card.id] = image
        } else {
            contentSnapshotRequestIDs[card.id] = nil
        }
    }

    private func prepareContentSnapshots() {
        for cardID in snapshotTargetCardIDs
        where contentSnapshotCache.images[cardID] == nil
            && contentSnapshotRequestIDs[cardID] == nil {
            contentSnapshotRequestIDs[cardID] = UUID()
        }
        discardUnusedContentSnapshots()
    }

    private func discardUnusedContentSnapshots() {
        var retainedCardIDs = Set(snapshotTargetCardIDs)
        retainedCardIDs.formUnion(departingCards.map { $0.card.id })
        if let snoozeSnapshotCardID {
            retainedCardIDs.insert(snoozeSnapshotCardID)
        }
        contentSnapshotCache.images = contentSnapshotCache.images.filter {
            retainedCardIDs.contains($0.key)
        }
        contentSnapshotRequestIDs = contentSnapshotRequestIDs.filter {
            retainedCardIDs.contains($0.key)
        }
    }

    private func finishSnoozeSnapshot(
        _ image: UIImage?,
        for card: Card,
        requestID: UUID
    ) {
        guard isClearing,
              snoozeSnapshotCardID == card.id,
              snoozeSnapshotRequestID == requestID,
              let date = pendingSnoozeDate
        else { return }

        snoozeSnapshotRequestID = nil
        snoozeContentSnapshot = image
        snoozingCardID = card.id
        snoozeProgress = 0

        let duration = reduceMotion ? 0.01 : 0.3
        withAnimation(.linear(duration: duration)) {
            snoozeProgress = 1
        }

        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                model.snooze(card, until: date)
                snoozingCardID = nil
                snoozeProgress = 0
                snoozeSnapshotCardID = nil
                snoozeContentSnapshot = nil
                pendingSnoozeDate = nil
                resetGestureState()
                isClearing = false
            }
        }
    }

    private func clear(
        _ card: Card,
        toward vector: CGSize,
        in size: CGSize,
        playsHaptic: Bool = true
    ) {
        guard !isClearing else { return }
        if playsHaptic {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.55)
        }

        let stackProgress = stackProgress(in: size.width)
        let distance = max(hypot(size.width, size.height) * 1.25, 600)
        let direction = normalized(vector)
        let destination = CGSize(
            width: direction.width * distance,
            height: direction.height * distance
        )
        let duration = reduceMotion ? 0.01 : 0.42
        let departure = DepartingCard(
            card: card,
            contentSnapshot: contentSnapshotCache.images[card.id],
            scale: 1,
            stackOffset: 0,
            offset: dragOffset,
            rotation: rotation(
                for: dragOffset,
                from: dragStartLocation,
                in: size
            ),
            zIndex: nextDepartureZIndex
        )
        nextDepartureZIndex += 1
        let destinationRotation = rotation(
            for: destination,
            from: dragStartLocation,
            in: size
        )

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            stackDepthOffset = max(1 - stackProgress, 0)
            departingCards.append(departure)
            model.clear(card)
            undoStack.append(card)
            resetGestureState()
        }

        Task {
            await Task.yield()
            withAnimation(.spring(response: duration, dampingFraction: 0.82)) {
                stackDepthOffset = 0
            }
            animateDeparture(
                departure.id,
                to: destination,
                rotation: destinationRotation,
                animation: .spring(response: duration, dampingFraction: 0.82)
            )
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            withTransaction(transaction) {
                departingCards.removeAll { $0.id == departure.id }
            }
            discardUnusedContentSnapshots()
        }
    }

    private func animateDeparture(
        _ id: UUID,
        to offset: CGSize,
        rotation: Double,
        animation: Animation
    ) {
        guard let index = departingCards.firstIndex(where: { $0.id == id }) else { return }
        withAnimation(animation) {
            departingCards[index].offset = offset
            departingCards[index].rotation = rotation
        }
    }

    private func undoLastClear(in size: CGSize) {
        guard !isUndoBlocked else { return }

        if let restoringCard {
            finishRestore(restoringCard)
        }

        guard let card = undoStack.popLast() else { return }
        let animationID = UUID()
        isClearing = true
        restoringCard = card
        restoreAnimationID = animationID
        dragStartLocation = CGPoint(x: size.width / 2, y: size.height / 2)
        dragOffset = CGSize(width: max(size.width * 1.25, 520), height: 0)
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()

        let duration = reduceMotion ? 0.01 : 0.42
        Task {
            await Task.yield()
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                departingCards.removeAll { $0.card.id == card.id }
            }
            withAnimation(.spring(response: duration, dampingFraction: 0.82)) {
                dragOffset = .zero
            }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

            guard restoreAnimationID == animationID else { return }
            finishRestore(card)
            discardUnusedContentSnapshots()
        }
    }

    private var isUndoBlocked: Bool {
        isClearing && restoringCard == nil
    }

    private func finishRestore(_ card: Card) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            model.restore(card)
            restoringCard = nil
            restoreAnimationID = nil
            resetGestureState()
            isClearing = false
        }
    }

    private func rotation(for offset: CGSize, from start: CGPoint, in size: CGSize) -> Double {
        guard size.width > 0, size.height > 0 else { return 0 }

        let leverX = (start.x - size.width / 2) / size.width
        let leverY = (start.y - size.height / 2) / size.height
        let motionX = offset.width / size.width
        let motionY = offset.height / size.height
        let torque = leverX * motionY - leverY * motionX
        let horizontalProgress = min(max(offset.width / 110, -1), 1)
        let directionalTilt = horizontalProgress * 8
        let touchAdjustment = min(max(torque * 16, -2.5), 2.5)
        let angle = directionalTilt + touchAdjustment
        return Double(min(max(angle, -12), 12))
    }

    private func stackProgress(in width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return min(magnitude(of: dragOffset) / (width * 0.7), 1)
    }

    private func stackScale(
        at index: Int,
        progress: CGFloat,
        depthOffset: CGFloat = 0
    ) -> CGFloat {
        let level = max(CGFloat(index) + depthOffset - progress, 0)
        return 1 - level * 0.035
    }

    private func stackOffset(
        at index: Int,
        progress: CGFloat,
        depthOffset: CGFloat = 0
    ) -> CGFloat {
        let level = max(CGFloat(index) + depthOffset - progress, 0)
        return level * 10
    }

    private func magnitude(of vector: CGSize) -> CGFloat {
        hypot(vector.width, vector.height)
    }

    private func normalized(_ vector: CGSize) -> CGSize {
        let length = magnitude(of: vector)
        guard length > 0 else { return CGSize(width: 1, height: 0) }
        return CGSize(width: vector.width / length, height: vector.height / length)
    }

    private func resetGestureState() {
        dragOffset = .zero
        dragStartLocation = .zero
        didCrossDismissThreshold = false
        swipeIntent = .undecided
    }
}

private final class ContentSnapshotCache {
    var images: [String: UIImage] = [:]
}

private struct DepartingCard: Identifiable {
    let id = UUID()
    let card: Card
    let contentSnapshot: UIImage?
    let scale: CGFloat
    let stackOffset: CGFloat
    var offset: CGSize
    var rotation: Double
    let zIndex: Double
}

private enum SwipeIntent: Equatable {
    case undecided
    case scrollingContent
    case swipingCard
}

private struct DeckActionMaterial: ViewModifier {
    let usesLiquidGlass: Bool
    let tint: Color?
    let foreground: Color

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), usesLiquidGlass {
            content
                .foregroundStyle(foreground)
                .glassEffect(.regular.tint(tint).interactive(), in: Capsule())
        } else {
            content
                .foregroundStyle(foreground)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(.white.opacity(0.28), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.12), radius: 12, y: 5)
        }
    }
}

private struct SnoozeDatePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedDate: Date
    private let minimumDate: Date
    let onSave: (Date) -> Void

    init(initialDate: Date, onSave: @escaping (Date) -> Void) {
        let minimumDate = Date().addingTimeInterval(60)
        self.minimumDate = minimumDate
        _selectedDate = State(initialValue: max(initialDate, minimumDate))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Show again",
                    selection: $selectedDate,
                    in: minimumDate...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle("Custom snooze")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Snooze") {
                        onSave(selectedDate)
                        dismiss()
                    }
                    .accessibilityIdentifier("confirm-custom-snooze")
                }
            }
        }
    }
}

#if DEBUG
#Preview("Custom snooze") {
    SnoozeDatePickerView(
        initialDate: Date().addingTimeInterval(86_400),
        onSave: { _ in }
    )
}
#endif
