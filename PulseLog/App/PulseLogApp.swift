import SwiftData
import SwiftUI

@main
struct PulseLogApp: App {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @StateObject private var subscriptions = SubscriptionStore()
    @State private var container: ModelContainer?

    var body: some Scene {
        WindowGroup {
            Group {
                if !hasCompletedOnboarding {
                    OnboardingView()
                } else if let container {
                    RootView()
                        .modelContainer(container)
                        .environmentObject(subscriptions)
                } else {
                    ProgressView()
                }
            }
            .task {
                await subscriptions.load()
                rebuildContainer()
                Haptics.prepare()
            }
            .onChange(of: subscriptions.isSubscribed) { _, _ in
                // iCloud sync is a paid feature, so the container is rebuilt
                // when entitlement changes.
                rebuildContainer()
            }
        }
    }

    private func rebuildContainer() {
        // Falling back to a local container keeps the app usable if CloudKit
        // is unavailable; losing sync is not a reason to lose the app.
        container = (try? ModelStack.container(cloudSyncEnabled: subscriptions.isSubscribed))
            ?? (try? ModelStack.container(cloudSyncEnabled: false))
    }
}

struct RootView: View {
    @EnvironmentObject private var subscriptions: SubscriptionStore
    @AppStorage("hasSeenPaywall") private var hasSeenPaywall = false
    @State private var showingPaywall = false

    var body: some View {
        TabView {
            HomeView(onFirstMeasurementSaved: offerPaywallOnce)
                .tabItem { Label("Measure", systemImage: "heart.fill") }

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet") }

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
        }
        .tint(Theme.accent)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    private func offerPaywallOnce() {
        guard !hasSeenPaywall, !subscriptions.isSubscribed else { return }
        hasSeenPaywall = true
        showingPaywall = true
    }
}
