import Foundation
import Combine
import StoreKit
import Supabase
import UIKit

@MainActor
final class PurchaseManager: ObservableObject {
    static let monthlyProductID = "com.girokiq.pro.monthly"
    static let annualProductID = "com.girokiq.pro.annual"
    static let productIDs = [monthlyProductID, annualProductID]

    enum PurchaseCycle {
        case monthly
        case annual

        var productID: String {
            switch self {
            case .monthly:
                return PurchaseManager.monthlyProductID
            case .annual:
                return PurchaseManager.annualProductID
            }
        }
    }

    @Published private(set) var productsByID: [String: Product] = [:]
    @Published private(set) var subscriptionTier: AppSubscriptionTier = .free
    @Published private(set) var activeProductID: String?
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var isRefreshingEntitlements = false
    @Published private(set) var purchaseInProgressProductID: String?
    @Published var purchaseErrorMessage: String?
    @Published var purchaseInfoMessage: String?

    private let supabaseService = SupabaseService.shared
    private let quotaService = CloudStorageQuotaService.shared
    private var authViewModel: AuthViewModel?
    private var updatesTask: Task<Void, Never>?
    private var lastSyncedUserID: UUID?
    private var lastSyncedTier: AppSubscriptionTier?

    private var verifySubscriptionEndpoint: URL {
        Configuration.supabaseFunctionsBaseURL.appendingPathComponent("verify-subscription")
    }

    init() {
        updatesTask = observeTransactionUpdates()
        Task {
            await refreshProducts()
            await refreshEntitlementsAndSync()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    var monthlyProduct: Product? { productsByID[Self.monthlyProductID] }
    var annualProduct: Product? { productsByID[Self.annualProductID] }

    var assistantPlanSubtitle: String {
        switch subscriptionTier {
        case .free:
            return "Free plan · Faster AI · 10 requests/day"
        case .pro:
            return "Pro plan · Best AI · Higher limits"
        }
    }

    var hasProAccess: Bool { subscriptionTier == .pro }

    func bind(authViewModel: AuthViewModel) {
        self.authViewModel = authViewModel
    }

    func handleAuthenticationStateChanged() {
        guard authViewModel?.currentUserId != nil else {
            subscriptionTier = .free
            activeProductID = nil
            purchaseErrorMessage = nil
            purchaseInfoMessage = nil
            AppSubscriptionTier.persisted = .free
            Task {
                await quotaService.invalidateCache()
            }
            lastSyncedUserID = nil
            lastSyncedTier = nil
            return
        }

        Task {
            await refreshProducts()
            await refreshEntitlementsAndSync()
        }
    }

    func refreshProducts() async {
        guard !isLoadingProducts else { return }
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            let products = try await Product.products(for: Self.productIDs)
            productsByID = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        } catch {
            purchaseErrorMessage = "Couldn't load App Store products right now."
        }
    }

    func purchase(cycle: PurchaseCycle) async -> Bool {
        purchaseErrorMessage = nil
        purchaseInfoMessage = nil

        // Bind purchases to the currently signed-in GirokIQ account to prevent
        // replaying a valid subscription across multiple Supabase accounts.
        guard let accountToken = authViewModel?.currentUserId else {
            purchaseErrorMessage = "Sign in before purchasing GirokIQ Pro."
            return false
        }

        if productsByID[cycle.productID] == nil {
            await refreshProducts()
        }

        guard let product = productsByID[cycle.productID] else {
            purchaseErrorMessage = "The App Store product isn't available yet. Check your StoreKit configuration or App Store Connect setup."
            return false
        }

        purchaseInProgressProductID = product.id
        defer { purchaseInProgressProductID = nil }

        do {
            let result = try await product.purchase(options: [.appAccountToken(accountToken)])

            switch result {
            case .success(let verificationResult):
                let transaction = try checkVerified(verificationResult)
                await transaction.finish()
                await refreshEntitlementsAndSync()
                if hasProAccess {
                    purchaseInfoMessage = "GirokIQ Pro is now active."
                } else {
                    purchaseInfoMessage = "Purchase succeeded, but server verification has not granted Pro yet. If this doesn't resolve in a minute, try Restore Purchases."
                }
                return true
            case .userCancelled:
                return false
            case .pending:
                purchaseInfoMessage = "This purchase is pending approval."
                return false
            @unknown default:
                purchaseErrorMessage = "The purchase couldn't be completed."
                return false
            }
        } catch {
            purchaseErrorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        purchaseErrorMessage = nil
        purchaseInfoMessage = nil

        do {
            try await AppStore.sync()
            await refreshEntitlementsAndSync()
            purchaseInfoMessage = hasProAccess
                ? "Purchases restored. GirokIQ Pro is active."
                : "No active GirokIQ Pro subscription was found to restore."
        } catch {
            purchaseErrorMessage = error.localizedDescription
        }
    }

    func openManageSubscriptions() async {
        purchaseErrorMessage = nil

        guard let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene else {
            purchaseErrorMessage = "Couldn't open App Store subscription settings right now."
            return
        }

        do {
            try await AppStore.showManageSubscriptions(in: windowScene)
        } catch {
            purchaseErrorMessage = "Couldn't open App Store subscription settings right now."
        }
    }

    func refreshEntitlementsAndSync() async {
        guard !isRefreshingEntitlements else { return }
        isRefreshingEntitlements = true
        defer { isRefreshingEntitlements = false }

        typealias VerifiedEntitlement = (transaction: Transaction, jwsRepresentation: String)
        var matchedTransactions: [VerifiedEntitlement] = []

        for await entitlement in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(entitlement)
                guard Self.productIDs.contains(transaction.productID) else { continue }
                guard transaction.revocationDate == nil else { continue }
                if let expirationDate = transaction.expirationDate, expirationDate <= Date() {
                    continue
                }
                matchedTransactions.append((transaction: transaction, jwsRepresentation: entitlement.jwsRepresentation))
            } catch {
                continue
            }
        }

        let bestEntitlement = matchedTransactions
            .sorted { entitlementSort(lhs: $0.transaction, rhs: $1.transaction) }
            .first
        activeProductID = bestEntitlement?.transaction.productID
        let localTier: AppSubscriptionTier = bestEntitlement == nil ? .free : .pro
        let serverTier = await syncSubscriptionTierToServer(localTier, transactionJWS: bestEntitlement?.jwsRepresentation)
        subscriptionTier = serverTier
        AppSubscriptionTier.persisted = serverTier
        await quotaService.invalidateCache()
        authViewModel?.updateLocalSubscriptionTier(serverTier)
    }

    func displayPrice(for cycle: PurchaseCycle, fallback: String) -> String {
        productsByID[cycle.productID]?.displayPrice ?? fallback
    }

    private func observeTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await update in Transaction.updates {
                do {
                    let transaction = try self.checkVerified(update)
                    await transaction.finish()
                    await self.refreshEntitlementsAndSync()
                } catch {
                    await MainActor.run {
                        self.purchaseErrorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private func syncSubscriptionTierToServer(_ tier: AppSubscriptionTier, transactionJWS: String?) async -> AppSubscriptionTier {
        guard Configuration.cloudAppStateEnabled else { return tier }
        guard let authViewModel, let userId = authViewModel.currentUserId else { return tier }

        if lastSyncedUserID == userId, lastSyncedTier == tier {
            return tier
        }

        do {
            let session = try await supabase.auth.session
            guard !session.isExpired else { return tier }

            var request = URLRequest(url: verifySubscriptionEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")

            // When Pro is active, we send the StoreKit 2 transaction JWS for server-side
            // signature verification. When Pro is not active, we send `null` so the server
            // safely sets the tier back to free.
            var body: [String: Any] = [:]
            if let jws = transactionJWS {
                body["transaction_jws"] = jws
            } else {
                body["transaction_jws"] = NSNull()
            }
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError("Failed to verify subscription tier.")
            }
            lastSyncedUserID = userId
            // Trust the server's verdict (it may downgrade even if StoreKit says Pro).
            let serverTier = parseSubscriptionTier(from: data) ?? tier
            lastSyncedTier = serverTier
            return serverTier
        } catch {
            let nsError = error as NSError
            let description = nsError.localizedDescription.lowercased()
            if description.contains("subscription_tier") || description.contains("column") {
                purchaseErrorMessage = "GirokIQ Pro is active locally, but your Supabase database still needs the latest migration for `subscription_tier`."
            } else {
                purchaseErrorMessage = "Your plan changed locally, but syncing it to the account state failed."
            }
            return tier
        }
    }

    private func parseSubscriptionTier(from data: Data) -> AppSubscriptionTier? {
        guard
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let raw = obj["subscription_tier"] as? String
        else { return nil }

        return raw.lowercased() == "pro" ? .pro : .free
    }

    private nonisolated func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let safe):
            return safe
        case .unverified(_, let error):
            throw error
        }
    }

    private nonisolated func entitlementSort(lhs: Transaction, rhs: Transaction) -> Bool {
        let lhsDate = lhs.expirationDate ?? .distantFuture
        let rhsDate = rhs.expirationDate ?? .distantFuture
        if lhsDate == rhsDate {
            return lhs.purchaseDate > rhs.purchaseDate
        }
        return lhsDate > rhsDate
    }
}
