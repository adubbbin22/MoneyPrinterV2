import StoreKit
import SwiftUI

/// Shown after the first successful measurement, never before.
///
/// A paywall during onboarding asks people to pay for something they have not
/// experienced. Letting the first measurement land first means the offer
/// arrives when its value is obvious, and it is dismissible either way.
struct PaywallView: View {
    @EnvironmentObject private var store: SubscriptionStore
    @Environment(\.dismiss) private var dismiss
    @State private var purchasing = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "chart.line.uptrend.xyaxis.circle")
                        .font(.system(size: 54)).foregroundStyle(Theme.accent)

                    Text("PulseLog Plus").font(.title.weight(.bold))
                    Text(FreeTier.paidDescription)
                        .font(.callout).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 12) {
                        FeatureRow(symbol: "infinity", text: "Your complete history, not just the last week")
                        FeatureRow(symbol: "lightbulb", text: "Correlations against sleep, activity and your own tags")
                        FeatureRow(symbol: "doc.richtext", text: "Doctor report PDF")
                        FeatureRow(symbol: "icloud", text: "iCloud sync across your devices")
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                    Text("Always free: \(FreeTier.includedDescription)")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if store.loadFailed {
                        Text("Couldn't reach the App Store. Please try again later.")
                            .font(.callout).foregroundStyle(.orange)
                    }

                    ForEach(store.products, id: \.id) { product in
                        Button {
                            Task { await buy(product) }
                        } label: {
                            VStack(spacing: 2) {
                                Text(product.displayName).fontWeight(.semibold)
                                // Price and renewal terms are shown up front,
                                // not behind a "see details" tap.
                                Text(priceLine(for: product)).font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .tint(product.id == SubscriptionStore.annualID ? Theme.accent : .gray)
                        .disabled(purchasing)
                    }

                    Button("Restore purchases") {
                        Task { try? await store.restore() }
                    }
                    .font(.footnote)

                    Text("Subscriptions renew automatically until cancelled. You can "
                         + "cancel any time in Settings.")
                        .font(.caption2).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .background(Theme.pageBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Always dismissible. A paywall you cannot close is a
                    // support ticket and a one-star review.
                    Button("Not now") { dismiss() }
                }
            }
            .alert("Purchase failed", isPresented: .constant(errorMessage != nil)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .task { await store.load() }
            .onChange(of: store.isSubscribed) { _, subscribed in
                if subscribed { dismiss() }
            }
        }
    }

    private func priceLine(for product: Product) -> String {
        guard let period = product.subscription?.subscriptionPeriod else {
            return product.displayPrice
        }
        let unit: String
        switch period.unit {
        case .month: unit = period.value == 1 ? "month" : "\(period.value) months"
        case .year:  unit = period.value == 1 ? "year" : "\(period.value) years"
        case .week:  unit = "week"
        case .day:   unit = "day"
        @unknown default: unit = "period"
        }
        return "\(product.displayPrice) per \(unit), renews automatically"
    }

    private func buy(_ product: Product) async {
        purchasing = true
        defer { purchasing = false }
        do {
            try await store.purchase(product)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct FeatureRow: View {
    let symbol: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            Text(text).font(.callout)
            Spacer()
        }
    }
}
