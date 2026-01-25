//
//  StoreManager.swift
//  TilesRemake
//

import StoreKit

/// Manages in-app purchases for the app
@MainActor
class StoreManager {

    static let shared = StoreManager()

    // MARK: - Product IDs

    /// Product ID for unlocking the import feature
    static let importFeatureProductID = "com.tilesremake.import"

    // MARK: - State

    /// Whether the import feature has been purchased
    private(set) var isImportUnlocked: Bool = false

    /// Available products from the App Store
    private(set) var products: [Product] = []

    /// Whether a purchase is currently in progress
    private(set) var isPurchasing: Bool = false

    /// Last error message (if any)
    private(set) var errorMessage: String?

    // MARK: - Private

    private var updateListenerTask: Task<Void, Error>?

    // MARK: - Initialization

    private init() {
        // Load persisted purchase state
        isImportUnlocked = UserDefaults.standard.bool(forKey: "importFeatureUnlocked")

        // Start listening for transaction updates
        updateListenerTask = listenForTransactions()

        // Load products
        Task {
            await loadProducts()
            await updatePurchasedProducts()
        }
    }

    deinit {
        updateListenerTask?.cancel()
    }

    // MARK: - Product Loading

    /// Loads available products from the App Store
    func loadProducts() async {
        do {
            let productIDs = [StoreManager.importFeatureProductID]
            products = try await Product.products(for: productIDs)

            #if DEBUG
            print("StoreManager: Loaded \(products.count) products")
            for product in products {
                print("  - \(product.id): \(product.displayName) - \(product.displayPrice)")
            }
            #endif
        } catch {
            #if DEBUG
            print("StoreManager: Failed to load products: \(error)")
            #endif
            errorMessage = "Failed to load products"
        }
    }

    // MARK: - Purchasing

    /// Purchases the import feature
    /// - Returns: True if purchase was successful
    func purchaseImportFeature() async -> Bool {
        guard let product = products.first(where: { $0.id == StoreManager.importFeatureProductID }) else {
            #if DEBUG
            print("StoreManager: Import product not found")
            #endif
            errorMessage = "Product not available"
            return false
        }

        return await purchase(product)
    }

    /// Purchases a product
    /// - Parameter product: The product to purchase
    /// - Returns: True if purchase was successful
    func purchase(_ product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil

        defer {
            isPurchasing = false
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                // Check if the transaction is verified
                let transaction = try checkVerified(verification)

                // Update purchase state
                await updatePurchasedProducts()

                // Finish the transaction
                await transaction.finish()

                #if DEBUG
                print("StoreManager: Purchase successful for \(product.id)")
                #endif

                return true

            case .userCancelled:
                #if DEBUG
                print("StoreManager: User cancelled purchase")
                #endif
                return false

            case .pending:
                #if DEBUG
                print("StoreManager: Purchase pending (Ask to Buy or other)")
                #endif
                errorMessage = "Purchase pending approval"
                return false

            @unknown default:
                #if DEBUG
                print("StoreManager: Unknown purchase result")
                #endif
                return false
            }
        } catch {
            #if DEBUG
            print("StoreManager: Purchase failed: \(error)")
            #endif
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }

    // MARK: - Restore Purchases

    /// Restores previously purchased products
    func restorePurchases() async {
        #if DEBUG
        print("StoreManager: Restoring purchases...")
        #endif

        // Sync with App Store
        do {
            try await AppStore.sync()
        } catch {
            #if DEBUG
            print("StoreManager: Sync failed: \(error)")
            #endif
        }

        // Update purchase state
        await updatePurchasedProducts()

        #if DEBUG
        print("StoreManager: Restore complete. Import unlocked: \(isImportUnlocked)")
        #endif
    }

    // MARK: - Transaction Handling

    /// Listens for transaction updates (purchases made on other devices, etc.)
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached {
            for await result in Transaction.updates {
                do {
                    let transaction = try await self.checkVerified(result)
                    await self.updatePurchasedProducts()
                    await transaction.finish()
                } catch {
                    #if DEBUG
                    print("StoreManager: Transaction verification failed: \(error)")
                    #endif
                }
            }
        }
    }

    /// Updates the purchased products state by checking current entitlements
    func updatePurchasedProducts() async {
        var importUnlocked = false

        // Check for the import feature entitlement
        for await result in Transaction.currentEntitlements {
            do {
                let transaction = try checkVerified(result)

                if transaction.productID == StoreManager.importFeatureProductID {
                    importUnlocked = true
                }
            } catch {
                #if DEBUG
                print("StoreManager: Entitlement verification failed: \(error)")
                #endif
            }
        }

        // Update state
        isImportUnlocked = importUnlocked

        // Persist state
        UserDefaults.standard.set(importUnlocked, forKey: "importFeatureUnlocked")

        #if DEBUG
        print("StoreManager: Import feature unlocked: \(isImportUnlocked)")
        #endif
    }

    /// Verifies a transaction
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified(_, let error):
            throw error
        case .verified(let safe):
            return safe
        }
    }

    // MARK: - Helpers

    /// Gets the import feature product (if loaded)
    var importProduct: Product? {
        products.first { $0.id == StoreManager.importFeatureProductID }
    }

    /// Gets the formatted price for the import feature
    var importFeaturePrice: String {
        importProduct?.displayPrice ?? "$0.99"
    }
}
