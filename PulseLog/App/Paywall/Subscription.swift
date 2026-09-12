import Foundation
import StoreKit

/// Subscription state.
///
/// Pricing is monthly and annual only. Weekly pricing is the single largest
/// driver of one-star reviews in this category: it reads as cheap and bills as
/// roughly $260 a year, and people discover the difference after the fact.
/// Declining to use it is a product decision, not an oversight.
@MainActor
final class SubscriptionStore: ObservableObject {

    static let monthlyID = "com.pulselog.plus.monthly"
    static let annualID = "com.pulselog.plus.annual"

    @Published private(set) var products: [Product] = []
    @Published private(set) var isSubscribed = false
    @Published private(set) var loadFailed = false

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            // Transactions can arrive at any time — renewals, refunds, Ask to
            // Buy approvals, purchases made on another device.
            for await update in Transaction.updates {
                guard let self, case .verified(let transaction) = update else { continue }
                await transaction.finish()
                await self.refresh()
            }
        }
    }

    deinit { updatesTask?.cancel() }

    func load() async {
        do {
            products = try await Product.products(for: [Self.monthlyID, Self.annualID])
                .sorted { $0.price < $1.price }
            loadFailed = false
        } catch {
            loadFailed = true
        }
        await refresh()
    }

    func refresh() async {
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.revocationDate == nil,
               [Self.monthlyID, Self.annualID].contains(transaction.productID) {
                isSubscribed = true
                return
            }
        }
        isSubscribed = false
    }

    func purchase(_ product: Product) async throws {
        let result = try await product.purchase()
        switch result {
        case .success(let verification):
            if case .verified(let transaction) = verification {
                await transaction.finish()
                await refresh()
            }
        case .userCancelled, .pending:
            break
        @unknown default:
            break
        }
    }

    func restore() async throws {
        try await AppStore.sync()
        await refresh()
    }
}

/// What the free tier includes.
///
/// Measuring and logging stay unlimited and free forever. Charging for the
/// measurement itself would make the app useless to anyone who does not pay,
/// and a health record you cannot add to is not a health record. The paid
/// tier sells the analysis built on top.
enum FreeTier {
    static let historyDays = 7

    static let includedDescription = "Unlimited measurements and unlimited blood "
        + "pressure logging, always free. The last \(historyDays) days of history."

    static let paidDescription = "Full history, trends and correlations, the doctor "
        + "report PDF, and iCloud sync across your devices."
}
