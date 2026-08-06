import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showSettings = false
    @State private var showAgents = false
    @State private var presentedTimeline: CardTimelineSection?

    var body: some View {
        Group {
            if !model.hasAccountKey {
                OnboardingView()
            } else {
                NavigationStack {
                    DeckView(
                        openTimeline: { presentedTimeline = $0 },
                        openAgents: { showAgents = true },
                        openSettings: { showSettings = true }
                    )
                }
                .sheet(item: $presentedTimeline) { section in
                    HistoryView(initialSection: section)
                        .environmentObject(model)
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView()
                        .environmentObject(model)
                }
                .sheet(isPresented: $showAgents) {
                    AgentsView()
                        .environmentObject(model)
                }
            }
        }
        .tint(model.themeColor.color)
        .preferredColorScheme(model.appearance.colorScheme)
        .task {
            if model.hasAccountKey {
                await model.loadAgents()
                await model.loadInboxes()
            }
        }
        .onChange(of: model.hasAccountKey) { _, hasAccountKey in
            if !hasAccountKey {
                presentedTimeline = nil
                showAgents = false
                showSettings = false
            }
        }
        .alert(
            "Agent Box",
            isPresented: Binding(
                get: { model.errorMessage != nil },
                set: { if !$0 { model.clearError() } }
            )
        ) {
            Button("OK") { model.clearError() }
        } message: {
            Text(model.errorMessage ?? "Unknown error")
        }
    }
}
