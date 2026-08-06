import SwiftUI

@main
struct AgentBoxApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .task {
                    BackgroundRefreshCoordinator.shared.syncHandler = { [weak model] in
                        guard let model else { return .failed }
                        return await model.backgroundSync()
                    }
                    BackgroundRefreshCoordinator.shared.deviceTokenHandler = { [weak model] token in
                        await model?.registerDeviceToken(token)
                    }
                    await model.start()
                    await model.enableBadge()
                    BackgroundRefreshCoordinator.shared.schedule()
                }
                .task {
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(30))
                        guard !Task.isCancelled else { return }
                        await model.refreshBadgeCount()
                    }
                }
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(60))
                        guard !Task.isCancelled, scenePhase == .active else { return }
                        await model.sync()
                    }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await model.sync() }
            case .background:
                BackgroundRefreshCoordinator.shared.schedule()
            default:
                break
            }
        }
    }
}
