import AppKit
import Foundation
import Observation
import StoreKit

enum RemoteFeature: String {
    case browse
    case clone
    case pull
    case push
    case pushCommit
    case refresh

    var title: String {
        switch self {
        case .browse:
            "Browse Remote Repositories"
        case .clone:
            "Clone Remote Repositories"
        case .pull:
            "Pull From Remote"
        case .push:
            "Push To Remote"
        case .pushCommit:
            "Push Commits To Remote"
        case .refresh:
            "Refresh Remote History"
        }
    }

    var summary: String {
        switch self {
        case .browse:
            "Open a remote Git URL and inspect history without cloning."
        case .clone:
            "Clone a hosted repository into a local folder."
        case .pull:
            "Pull the current branch from its configured remote."
        case .push:
            "Push the current branch to its configured remote."
        case .pushCommit:
            "Push a selected commit to a branch on the remote."
        case .refresh:
            "Fetch the latest remote branches, commits, and tags."
        }
    }
}

@MainActor
@Observable
final class SubscriptionManager {
    static let remoteSubscriptionProductIDs = [
        "de.holgerkrupp.gitMenu.remote.monthly"
    ]
    static let trialDuration: TimeInterval = 7 * 24 * 60 * 60

    private enum StorageKey {
        static let trialStartDate = "remoteFeaturesTrialStartDate"
    }

    private let userDefaults: UserDefaults
    @ObservationIgnored private var updatesTask: Task<Void, Never>?
    @ObservationIgnored private var pendingUnlockAction: (@MainActor () -> Void)?

    private(set) var products: [Product] = []
    private(set) var hasActiveSubscription = false
    private(set) var trialStartDate: Date?
    private(set) var isLoadingProducts = false
    private(set) var isProcessingPurchase = false
    var isPaywallPresented = false
    var paywallFeature: RemoteFeature?
    var purchaseErrorMessage: String?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.trialStartDate = userDefaults.object(forKey: StorageKey.trialStartDate) as? Date
    }

    var hasStartedTrial: Bool {
        trialStartDate != nil
    }

    var isTrialActive: Bool {
        guard let trialExpiresAt else {
            return false
        }

        return trialExpiresAt > Date()
    }

    var canUseRemoteFeatures: Bool {
        hasActiveSubscription || isTrialActive
    }

    var trialExpiresAt: Date? {
        guard let trialStartDate else {
            return nil
        }

        return trialStartDate.addingTimeInterval(Self.trialDuration)
    }

    var remainingTrialDays: Int? {
        guard let trialExpiresAt else {
            return nil
        }

        let remaining = trialExpiresAt.timeIntervalSinceNow
        guard remaining > 0 else {
            return 0
        }

        return max(1, Int(ceil(remaining / 86_400)))
    }

    var accessDescription: String {
        if hasActiveSubscription {
            return "Remote Git Pro is active."
        }

        if let remainingTrialDays, remainingTrialDays > 0 {
            let unit = remainingTrialDays == 1 ? "day" : "days"
            return "Free trial active: \(remainingTrialDays) \(unit) left."
        }

        if hasStartedTrial {
            return "Free trial ended. Subscribe to keep using remote Git features."
        }

        let trialDays = Int(Self.trialDuration / 86_400)
        return "Start a \(trialDays)-day free trial for remote Git features."
    }

    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            guard let self else { return }

            await refreshProducts()
            await refreshEntitlements()

            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else {
                    continue
                }

                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    func requestAccess(
        to feature: RemoteFeature,
        onUnlock: (@MainActor () -> Void)? = nil
    ) -> Bool {
        guard canUseRemoteFeatures else {
            paywallFeature = feature
            pendingUnlockAction = onUnlock
            purchaseErrorMessage = nil
            isPaywallPresented = true
            return false
        }

        return true
    }

    func dismissPaywall() {
        isPaywallPresented = false
        paywallFeature = nil
        pendingUnlockAction = nil
        purchaseErrorMessage = nil
    }

    func startTrial() {
        if trialStartDate == nil {
            let now = Date()
            trialStartDate = now
            userDefaults.set(now, forKey: StorageKey.trialStartDate)
        }

        completeUnlockFlow()
    }

    func refreshProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let loadedProducts = try await Product.products(for: Self.remoteSubscriptionProductIDs)
            products = loadedProducts.sorted { $0.price < $1.price }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    purchaseErrorMessage = "The App Store could not verify the purchase."
                    return
                }

                await transaction.finish()
                await refreshEntitlements()

                if canUseRemoteFeatures {
                    completeUnlockFlow()
                }
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func restorePurchases() async {
        isProcessingPurchase = true
        defer { isProcessingPurchase = false }

        do {
            try await AppStore.sync()
            await refreshEntitlements()

            if canUseRemoteFeatures {
                completeUnlockFlow()
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func openManageSubscriptions() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private func completeUnlockFlow() {
        let action = pendingUnlockAction
        isPaywallPresented = false
        paywallFeature = nil
        pendingUnlockAction = nil
        purchaseErrorMessage = nil

        guard let action else {
            return
        }

        // Let the sheet dismiss before continuing with the remote action.
        Task { @MainActor in
            await Task.yield()
            action()
        }
    }

    private func refreshEntitlements() async {
        var activeSubscription = false

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }

            guard Self.remoteSubscriptionProductIDs.contains(transaction.productID) else {
                continue
            }

            if transaction.revocationDate != nil {
                continue
            }

            if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                continue
            }

            activeSubscription = true
            break
        }

        hasActiveSubscription = activeSubscription
    }
}
