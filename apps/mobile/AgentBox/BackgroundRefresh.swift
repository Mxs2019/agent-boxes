import BackgroundTasks
import UIKit
import UserNotifications

enum BackgroundSyncResult {
    case newData
    case noData
    case failed

    var taskSucceeded: Bool {
        self != .failed
    }

    var fetchResult: UIBackgroundFetchResult {
        switch self {
        case .newData: .newData
        case .noData: .noData
        case .failed: .failed
        }
    }
}

@MainActor
final class AppBadgeCoordinator {
    static let shared = AppBadgeCoordinator()

    private static let requestPrefix = "cc.agentboxes.badge."
    private let notificationCenter = UNUserNotificationCenter.current()
    private var updateGeneration = 0

    func requestAuthorizationAndUpdate(cards: [Card]) async {
        _ = try? await notificationCenter.requestAuthorization(options: [.alert, .badge])
        await update(cards: cards)
    }

    func update(cards: [Card], now: Date = Date()) async {
        updateGeneration += 1
        let generation = updateGeneration
        let settings = await notificationCenter.notificationSettings()
        guard generation == updateGeneration, settings.badgeSetting == .enabled else { return }

        let currentCount = activeCount(in: cards, at: now)
        try? await notificationCenter.setBadgeCount(currentCount)
        guard generation == updateGeneration else { return }

        let pendingRequests = await notificationCenter.pendingNotificationRequests()
        let oldIdentifiers = pendingRequests
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.requestPrefix) }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: oldIdentifiers)

        var previousCount = currentCount
        let eventDates = Set(
            cards.flatMap { card in
                [card.showAt, card.expiresAt, card.snoozedUntil].compactMap { $0 }
            }
            .filter { $0 > now.addingTimeInterval(1) }
        )
        .sorted()

        var requestIndex = 0
        for eventDate in eventDates {
            guard generation == updateGeneration, requestIndex < 60 else { return }
            let nextCount = activeCount(
                in: cards,
                at: eventDate.addingTimeInterval(0.1)
            )
            guard nextCount != previousCount else { continue }
            previousCount = nextCount

            let content = UNMutableNotificationContent()
            content.badge = NSNumber(value: nextCount)
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(eventDate.timeIntervalSince(now), 1),
                repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "\(Self.requestPrefix)\(requestIndex)",
                content: content,
                trigger: trigger
            )
            try? await notificationCenter.add(request)
            requestIndex += 1
        }
    }

    func setCount(_ count: Int) async {
        let settings = await notificationCenter.notificationSettings()
        guard settings.badgeSetting == .enabled else { return }
        try? await notificationCenter.setBadgeCount(max(count, 0))
    }

    private func activeCount(in cards: [Card], at date: Date) -> Int {
        cards.count { $0.status(at: date) == .active }
    }
}

@MainActor
final class BackgroundRefreshCoordinator {
    static let shared = BackgroundRefreshCoordinator()
    static let identifier = "cc.agentboxes.refresh"

    var syncHandler: (() async -> BackgroundSyncResult)?
    var deviceTokenHandler: ((String) async -> Void)? {
        didSet { deliverPendingDeviceToken() }
    }
    var notificationTapHandler: ((String) async -> Void)? {
        didSet { deliverPendingNotificationCard() }
    }

    private var pendingDeviceToken: String?
    private var pendingNotificationCardID: String?

    func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.identifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                self.handle(refreshTask)
            }
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 60 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // iOS can reject a request when another refresh is already pending.
        }
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        let operation = Task {
            let result = await syncHandler?() ?? .failed
            task.setTaskCompleted(success: result.taskSucceeded)
        }
        task.expirationHandler = {
            operation.cancel()
        }
    }

    func receiveDeviceToken(_ token: String) {
        pendingDeviceToken = token
        deliverPendingDeviceToken()
    }

    func receiveNotificationCardID(_ cardID: String) {
        pendingNotificationCardID = cardID
        deliverPendingNotificationCard()
    }

    private func deliverPendingDeviceToken() {
        guard let token = pendingDeviceToken, let deviceTokenHandler else { return }
        pendingDeviceToken = nil
        Task { await deviceTokenHandler(token) }
    }

    private func deliverPendingNotificationCard() {
        guard let cardID = pendingNotificationCardID, let notificationTapHandler else { return }
        pendingNotificationCardID = nil
        Task { await notificationTapHandler(cardID) }
    }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        BackgroundRefreshCoordinator.shared.register()
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .badge])
        Task { @MainActor in
            _ = await BackgroundRefreshCoordinator.shared.syncHandler?()
        }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let cardID = Self.notificationCardID(
            from: response.notification.request.content.userInfo
        ) {
            BackgroundRefreshCoordinator.shared.receiveNotificationCardID(cardID)
        }
        completionHandler()
    }

    static func notificationCardID(from userInfo: [AnyHashable: Any]) -> String? {
        guard let cardID = userInfo["card_id"] as? String,
              cardID.hasPrefix("card_"),
              !cardID.dropFirst(5).isEmpty
        else { return nil }
        return cardID
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { @MainActor in
            BackgroundRefreshCoordinator.shared.receiveDeviceToken(token)
        }
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            let result = await BackgroundRefreshCoordinator.shared.syncHandler?() ?? .failed
            completionHandler(result.fetchResult)
        }
    }
}
