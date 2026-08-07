import XCTest

final class HistoryNavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testHistoryCardOpensItsDetailScreen() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let historyButton = app.buttons["history-button"]
        XCTAssertTrue(historyButton.waitForExistence(timeout: 5))
        historyButton.tap()

        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        let cardLink = app.buttons["history-card-card_preview_market"]
        XCTAssertTrue(cardLink.waitForExistence(timeout: 5))
        cardLink.tap()

        XCTAssertTrue(app.navigationBars["Morning market update"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
    }

    func testHistoryOverviewShowsSnapshotsAndReturnsToTheFullCard() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.buttons["history-card-card_preview_market"].tap()

        let overviewToggle = app.buttons["history-overview-toggle"]
        XCTAssertTrue(overviewToggle.waitForExistence(timeout: 5))
        overviewToggle.tap()

        XCTAssertTrue(app.staticTexts["history-overview-day-0"].waitForExistence(timeout: 5))
        let card = app.buttons["history-overview-card-card_preview_market"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        let compactCard = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                card.frame.width <= app.frame.width * 0.55
                    && card.frame.height <= app.frame.height * 0.55
            },
            object: card
        )
        wait(for: [compactCard], timeout: 4)
        XCTAssertLessThanOrEqual(card.frame.width, app.frame.width * 0.55)
        XCTAssertLessThanOrEqual(card.frame.height, app.frame.height * 0.55)

        let previousCard = app.buttons["history-overview-card-card_preview_review"]
        XCTAssertTrue(previousCard.exists)
        XCTAssertFalse(previousCard.frame.intersects(card.frame))
        card.tap()

        let action = app.buttons["add-back-to-deck"]
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        let completedZoom = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == YES"),
            object: action
        )
        wait(for: [completedZoom], timeout: 5)
        XCTAssertTrue(app.webViews.firstMatch.exists)
    }

    func testHistoryOverviewUsesNormalHorizontalScrolling() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.buttons["history-card-card_preview_market"].tap()
        app.buttons["history-overview-toggle"].tap()

        let card = app.buttons["history-overview-card-card_preview_market"]
        let dayHeader = app.staticTexts["history-overview-day-0"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(dayHeader.waitForExistence(timeout: 5))
        XCTAssertFalse(app.otherElements["history-timeline"].exists)
        XCTAssertLessThan(dayHeader.frame.maxY, card.frame.minY)
        XCTAssertLessThan(card.frame.minY - dayHeader.frame.maxY, 16)

        let firstPosition = card.frame.minX
        app.swipeLeft()

        let movedFreely = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                card.frame.minX < firstPosition - 20
            },
            object: card
        )
        wait(for: [movedFreely], timeout: 2)
    }

    func testHistoryCardSwipeMovesWithoutRemovingTheCard() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.buttons["history-card-card_preview_market"].tap()
        XCTAssertTrue(app.navigationBars["Morning market update"].waitForExistence(timeout: 5))

        app.swipeRight()

        XCTAssertTrue(app.navigationBars["Things to review"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.exists)
    }

    func testHistoryCardCanBeAddedBackFromTheBottomAction() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let timelineButton = app.buttons["history-button"]
        XCTAssertTrue(timelineButton.waitForExistence(timeout: 5))
        timelineButton.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        let cardLink = app.buttons["history-card-card_preview_cleared"]
        XCTAssertTrue(cardLink.waitForExistence(timeout: 5))
        cardLink.tap()
        XCTAssertTrue(app.navigationBars["Commute reading list"].waitForExistence(timeout: 5))

        let restore = app.buttons["add-back-to-deck"]
        XCTAssertTrue(restore.waitForExistence(timeout: 5))
        XCTAssertEqual(restore.label, "Add back to Deck")
        restore.tap()

        XCTAssertEqual(restore.label, "In Deck")
        XCTAssertFalse(restore.isEnabled)
    }

    func testDeckCardCanOpenTheFeedbackComposer() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let feedback = app.buttons["feedback-card"]
        XCTAssertTrue(feedback.waitForExistence(timeout: 5))
        XCTAssertEqual(feedback.label, "Leave Feedback")
        XCTAssertLessThan(feedback.frame.midX, app.buttons["snooze-card"].frame.midX)
        feedback.tap()

        XCTAssertTrue(app.navigationBars["Leave Feedback"].waitForExistence(timeout: 5))
        let continueButton = app.buttons["Continue"]
        if continueButton.waitForExistence(timeout: 1) {
            continueButton.tap()
        }

        let comment = app.textViews["feedback-comment"]
        XCTAssertTrue(comment.waitForExistence(timeout: 5))
        app.buttons["Make concise"].tap()
        XCTAssertTrue((comment.value as? String)?.contains("Make this card more concise") == true)
    }

    func testHistoryCardStaysAboveItsActions() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.buttons["history-card-card_preview_market"].tap()

        let card = app.webViews["history-browser-card-card_preview_market"]
        let moreActions = app.buttons["history-more-card-actions"]
        let deckAction = app.buttons["add-back-to-deck"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(moreActions.waitForExistence(timeout: 5))
        XCTAssertLessThanOrEqual(card.frame.maxY, moreActions.frame.minY)
        XCTAssertLessThan(moreActions.frame.midX, deckAction.frame.midX)
    }

    func testPrimaryColorCanBeSelected() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let settingsButton = app.buttons["Settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        settingsButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["settings-done"].exists)
        XCTAssertFalse(app.buttons["Save"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)

        let purpleSwatch = app.buttons["theme-color-purple"]
        XCTAssertTrue(purpleSwatch.waitForExistence(timeout: 5))
        purpleSwatch.tap()

        XCTAssertEqual(purpleSwatch.value as? String, "Selected")

        let monochromeSwatch = app.buttons["theme-color-monochrome"]
        XCTAssertTrue(scrollToElement(monochromeSwatch, in: app))
        monochromeSwatch.tap()
        XCTAssertEqual(monochromeSwatch.value as? String, "Selected")

        let appearancePicker = app.segmentedControls["appearance-picker"]
        XCTAssertTrue(appearancePicker.waitForExistence(timeout: 5))
        let darkAppearance = appearancePicker.buttons["Dark"]
        darkAppearance.tap()
        XCTAssertTrue(darkAppearance.isSelected)
    }

    func testSearchOpensHistoryWithoutPresentingTheInput() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let searchButton = app.buttons["history-button"]
        XCTAssertTrue(searchButton.waitForExistence(timeout: 5))
        searchButton.tap()

        let historyTitle = app.navigationBars["History"]
        XCTAssertTrue(historyTitle.waitForExistence(timeout: 5))
        XCTAssertFalse(app.keyboards.firstMatch.exists)
        XCTAssertTrue(historyTitle.exists)
    }

    func testSearchResultOpensOnlyTheCardsInTheResultList() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        let searchField = app.searchFields["Title, content, or source"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("Commute reading list")

        let result = app.buttons["history-card-card_preview_cleared"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["history-card-card_preview_market"].exists)
        result.tap()

        let resultTitle = app.navigationBars["Commute reading list"]
        XCTAssertTrue(resultTitle.waitForExistence(timeout: 5))
        app.swipeLeft()
        XCTAssertTrue(resultTitle.exists)
        app.swipeRight()
        XCTAssertTrue(resultTitle.exists)
    }

    func testViewUpcomingOpensSnoozedAndScheduledCards() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let snooze = app.buttons["snooze-card"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 5))
        snooze.tap()

        let viewUpcoming = app.buttons["View Upcoming"]
        XCTAssertTrue(viewUpcoming.waitForExistence(timeout: 5))
        viewUpcoming.tap()

        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["upcoming-card-card_preview_snoozed"].waitForExistence(timeout: 5)
        )
        XCTAssertTrue(app.buttons["upcoming-card-card_preview_scheduled"].exists)
        XCTAssertFalse(app.buttons["upcoming-card-card_preview_market"].exists)
    }

    func testScheduledCardCanBeAddedToTheDeckNow() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.segmentedControls["card-timeline-section"].buttons["Upcoming"].tap()
        XCTAssertTrue(app.navigationBars["Upcoming"].waitForExistence(timeout: 5))

        let scheduledCard = app.buttons["upcoming-card-card_preview_scheduled"]
        XCTAssertTrue(scheduledCard.waitForExistence(timeout: 5))
        scheduledCard.tap()
        XCTAssertTrue(app.navigationBars["Friday launch checklist"].waitForExistence(timeout: 5))

        let addNow = app.buttons["add-back-to-deck"]
        XCTAssertTrue(addNow.waitForExistence(timeout: 5))
        XCTAssertEqual(addNow.label, "Add to Deck Now")
        addNow.tap()

        XCTAssertEqual(addNow.label, "In Deck")
        XCTAssertFalse(addNow.isEnabled)
    }

    func testEmptyDeckShowsTheInteractiveEmptyState() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--ui-testing", "--ui-testing-empty"])
        app.launch()

        let emptyDeck = app.descendants(matching: .any)["empty-deck"]
        XCTAssertTrue(emptyDeck.waitForExistence(timeout: 5))
        XCTAssertEqual(emptyDeck.label, "All clear. Everything is reviewed.")
        XCTAssertFalse(app.buttons["dismiss-card"].exists)
        XCTAssertFalse(app.buttons["undo-card"].exists)

        let history = app.buttons["empty-history-button"]
        XCTAssertTrue(history.exists)
        XCTAssertEqual(history.label, "View history")
        history.tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))
        app.buttons["history-done"].tap()

        let start = emptyDeck.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.4))
        let end = emptyDeck.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.65))
        start.press(forDuration: 0.2, thenDragTo: end)
        XCTAssertTrue(emptyDeck.exists)
    }

    func testDismissQueuesFastTapsAndHidesControlsOnTheEmptyState() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let dismiss = app.buttons["dismiss-card"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertTrue(dismiss.isEnabled)
        dismiss.tap()
        dismiss.tap()

        let emptyDeck = app.descendants(matching: .any)["empty-deck"]
        XCTAssertTrue(emptyDeck.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["dismiss-card"].exists)
        XCTAssertFalse(app.buttons["undo-card"].exists)
    }

    func testUndoAcceptsRepeatedTapsDuringTheRestoreAnimation() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["history-button"].tap()
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 5))

        let clearedCard = app.buttons["history-card-card_preview_cleared"]
        XCTAssertTrue(clearedCard.waitForExistence(timeout: 5))
        clearedCard.tap()

        let addBack = app.buttons["add-back-to-deck"]
        XCTAssertTrue(addBack.waitForExistence(timeout: 5))
        addBack.tap()

        app.navigationBars["Commute reading list"].buttons.firstMatch.tap()
        app.buttons["history-done"].tap()

        let dismiss = app.buttons["dismiss-card"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()
        dismiss.tap()

        let undo = app.buttons["undo-card"]
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        undo.tap()
        undo.tap()

        let firstCard = app.staticTexts["Card Morning market update, 3 remaining"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 2))
    }

    func testNextCardAcceptsSwipeBeforePreviousExitCompletes() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let firstCard = app.staticTexts["Card Morning market update, 2 remaining"]
        XCTAssertTrue(firstCard.waitForExistence(timeout: 5))

        app.swipeRight(velocity: .fast)
        app.swipeRight(velocity: .fast)

        let emptyDeck = app.descendants(matching: .any)["empty-deck"]
        XCTAssertTrue(emptyDeck.waitForExistence(timeout: 2))
    }

    func testDismissHidesControlsWhileTheLastCardLeaves() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let dismiss = app.buttons["dismiss-card"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.tap()

        let lastCard = app.staticTexts["Card Things to review, 1 remaining"]
        XCTAssertTrue(lastCard.waitForExistence(timeout: 2))
        dismiss.tap()

        XCTAssertTrue(dismiss.waitForNonExistence(timeout: 0.2))
        XCTAssertFalse(app.buttons["undo-card"].exists)

        let emptyDeck = app.descendants(matching: .any)["empty-deck"]
        XCTAssertTrue(emptyDeck.waitForExistence(timeout: 2))
    }

    func testLongPressDismissAsksBeforeDismissingAllCards() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let dismiss = app.buttons["dismiss-card"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.press(forDuration: 0.8)

        XCTAssertTrue(app.buttons["Cancel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Dismiss All"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(dismiss.exists)
    }

    func testDismissAllClearsTheDeckInOneBurst() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let dismiss = app.buttons["dismiss-card"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        dismiss.press(forDuration: 0.8)

        let dismissAll = app.buttons["Dismiss All"]
        XCTAssertTrue(dismissAll.waitForExistence(timeout: 5))
        dismissAll.tap()

        let emptyDeck = app.descendants(matching: .any)["empty-deck"]
        XCTAssertTrue(emptyDeck.waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["dismiss-card"].exists)
        XCTAssertFalse(app.buttons["undo-card"].exists)
    }

    func testSnoozeOffersQuickActionsAndMovesToTheNextCard() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        let snooze = app.buttons["snooze-card"]
        XCTAssertTrue(snooze.waitForExistence(timeout: 5))
        XCTAssertLessThan(snooze.frame.midX, app.buttons["dismiss-card"].frame.midX)
        snooze.tap()

        XCTAssertTrue(app.buttons["1 day"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["3 days"].exists)
        XCTAssertTrue(app.buttons["1 week"].exists)
        XCTAssertTrue(app.buttons["Choose date…"].exists)
        XCTAssertTrue(app.buttons["View Upcoming"].exists)
        app.buttons["Choose date…"].tap()

        XCTAssertTrue(app.navigationBars["Custom snooze"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["confirm-custom-snooze"].exists)
        app.buttons["Cancel"].tap()

        XCTAssertTrue(snooze.waitForExistence(timeout: 5))
        snooze.tap()
        XCTAssertTrue(app.buttons["1 day"].waitForExistence(timeout: 5))
        app.buttons["1 day"].tap()

        let nextCard = app.staticTexts["Card Things to review, 1 remaining"]
        XCTAssertTrue(nextCard.waitForExistence(timeout: 5))
    }

    func testAccountKeyUsesASeparateReplacementFlow() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.secureTextFields.firstMatch.exists)

        let changeKey = app.buttons["change-account-key"]
        XCTAssertTrue(scrollToElement(changeKey, in: app))
        changeKey.tap()

        XCTAssertTrue(app.navigationBars["Change account key"].waitForExistence(timeout: 5))
        let keyField = app.secureTextFields["new-account-key"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5))

        let updateKey = app.buttons["update-account-key"]
        XCTAssertFalse(updateKey.isEnabled)
        keyField.typeText("ab_account_replacement_key")
        XCTAssertTrue(updateKey.isEnabled)
        updateKey.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Change account key"].exists)
    }

    func testSettingsOffersOnboardingReset() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))

        let reset = app.buttons["reset-onboarding"]
        XCTAssertTrue(scrollToElement(reset, in: app))
        XCTAssertTrue(reset.isEnabled)
    }

    func testAgentsOpenFromTheDeckToolbar() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--ui-testing", "--ui-testing-first-agent"])
        app.launch()

        let agents = app.buttons["Agents and inboxes"]
        XCTAssertTrue(agents.waitForExistence(timeout: 5))
        agents.tap()

        XCTAssertTrue(app.navigationBars["Agents & Inboxes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-agent"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["new-inbox"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["Create an agent to connect it through MCP and send cards."]
                .waitForExistence(timeout: 5)
        )
    }

    func testAgentCanBeCreatedAndItsKeyCanBeCopied() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["Agents and inboxes"].tap()
        XCTAssertTrue(app.navigationBars["Agents & Inboxes"].waitForExistence(timeout: 5))

        let newAgent = app.buttons["new-agent"]
        XCTAssertTrue(newAgent.waitForExistence(timeout: 5))
        newAgent.tap()

        XCTAssertTrue(app.navigationBars["New Agent"].waitForExistence(timeout: 5))
        let name = app.textFields["agent-name"]
        XCTAssertTrue(waitForHittable(name))
        name.tap()
        name.typeText("Coding agent")
        app.buttons["Create"].tap()

        XCTAssertTrue(app.navigationBars["Agent Created"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["agent-api-key"].waitForExistence(timeout: 5))

        let copyKey = app.buttons["copy-agent-api-key"]
        XCTAssertTrue(copyKey.waitForExistence(timeout: 5))
        copyKey.tap()
        XCTAssertEqual(copyKey.label, "Agent key copied")

        let copyMCPConnection = app.buttons["copy-new-agent-mcp-connection"]
        XCTAssertTrue(scrollToElement(copyMCPConnection, in: app))
        copyMCPConnection.tap()
        XCTAssertEqual(copyMCPConnection.label, "MCP connection copied")

        let copyInstructions = app.buttons["copy-new-agent-instructions"]
        XCTAssertTrue(scrollToElement(copyInstructions, in: app))
        copyInstructions.tap()
        XCTAssertEqual(copyInstructions.label, "Instructions copied")
    }

    func testAgentOpensOnlyItsAssociatedCards() {
        let app = XCUIApplication()
        app.launchArguments.append("--ui-testing")
        app.launch()

        app.buttons["Agents and inboxes"].tap()
        XCTAssertTrue(app.navigationBars["Agents & Inboxes"].waitForExistence(timeout: 5))

        let researchAgent = app.buttons["agent-row-agent_preview_research"]
        XCTAssertTrue(researchAgent.waitForExistence(timeout: 5))
        researchAgent.tap()

        XCTAssertTrue(app.navigationBars["Research agent"].waitForExistence(timeout: 5))
        let revealKey = app.buttons["View agent key"]
        XCTAssertTrue(revealKey.waitForExistence(timeout: 5))
        revealKey.tap()

        let copyInstructions = app.buttons["copy-agent-instructions"]
        XCTAssertTrue(copyInstructions.waitForExistence(timeout: 5))
        copyInstructions.tap()
        XCTAssertEqual(copyInstructions.label, "Instructions copied")

        let marketCard = app.buttons["agent-card-card_preview_market"]
        XCTAssertTrue(marketCard.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["agent-card-card_preview_review"].exists)

        marketCard.tap()
        XCTAssertTrue(app.navigationBars["Morning market update"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
    }

    func testAccountWithNoAgentsOpensTheClient() {
        let app = XCUIApplication()
        app.launchArguments.append(contentsOf: ["--ui-testing", "--ui-testing-first-agent"])
        app.launch()

        XCTAssertTrue(app.buttons["history-button"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Agents and inboxes"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.navigationBars["Create your first agent"].exists)
    }

    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<4 {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func waitForHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
