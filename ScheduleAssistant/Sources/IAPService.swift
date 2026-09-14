import Foundation
import StoreKit
import SwiftUI

/// StoreKit 1 内购：支付成功后先把收据交给后端 /api/iap/verify 校验，
/// 收到成功响应（含 duplicate 幂等结果）才 finishTransaction；
/// 失败不 finish，下次启动 SKPaymentQueue 会重新下发待处理交易。
/// 收据只发给自家后端，不发给任何第三方；日志中不打印收据内容。
final class IAPService: NSObject, ObservableObject {
    static let shared = IAPService()

    @Published private(set) var products: [SKProduct] = []
    @Published private(set) var isLoadingProducts = false
    @Published private(set) var purchasingProductID: String?
    @Published private(set) var isRestoring = false
    /// 一次性结果提示（积分商店页以 alert 展示）。
    @Published var storeNotice: String?

    private var productsRequest: SKProductsRequest?

    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }

    // MARK: - 商品

    func loadProducts() {
        let ids = Set(OrbitBackendConfig.productIDs)
        guard !ids.isEmpty else { return }
        DispatchQueue.main.async {
            self.isLoadingProducts = true
        }
        let request = SKProductsRequest(productIdentifiers: ids)
        request.delegate = self
        productsRequest = request
        request.start()
    }

    func price(for product: SKProduct) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = product.priceLocale
        return formatter.string(from: product.price) ?? "¥\(product.price)"
    }

    func pointsLabel(for product: SKProduct) -> String {
        if let points = OrbitBackendConfig.points(forProductID: product.productIdentifier) {
            return "\(points) 积分"
        }
        return product.localizedTitle.isEmpty ? product.productIdentifier : product.localizedTitle
    }

    // MARK: - 购买 / 恢复

    func purchase(_ product: SKProduct) {
        guard SKPaymentQueue.canMakePayments() else {
            storeNotice = "此设备不允许应用内购买，请检查系统「屏幕使用时间」限制。"
            return
        }
        purchasingProductID = product.productIdentifier
        SKPaymentQueue.default().add(SKPayment(product: product))
    }

    func restore() {
        isRestoring = true
        SKPaymentQueue.default().restoreCompletedTransactions()
    }

    // MARK: - 交易处理

    @MainActor
    private func handle(_ transaction: SKPaymentTransaction) async {
        switch transaction.transactionState {
        case .purchased, .restored:
            guard let receiptURL = Bundle.main.appStoreReceiptURL,
                  let receiptData = try? Data(contentsOf: receiptURL) else {
                // 没读到收据无法校验：保留交易，下次启动自动重试。
                purchasingProductID = nil
                storeNotice = "读取 App Store 收据失败，稍后将自动重试；请勿删除 App。"
                return
            }
            do {
                let response = try await AccountStore.shared.verifyReceipt(
                    base64: receiptData.base64EncodedString())
                // 后端确认入账（或确认重复收据）之后才允许 finish。
                SKPaymentQueue.default().finishTransaction(transaction)
                purchasingProductID = nil
                if let added = response.points_added, added > 0 {
                    storeNotice = "充值成功，积分 +\(added)，当前余额 \(response.points ?? 0)。"
                } else if transaction.transactionState == .restored {
                    storeNotice = "恢复购买完成；已入账的积分不会重复添加。"
                } else {
                    storeNotice = "收据已确认，本次无新增积分（重复收据不重复入账）。"
                }
            } catch {
                // 网络/后端暂不可用或登录过期：不 finish，下次启动重试。
                purchasingProductID = nil
                storeNotice = "积分入账暂时失败（将自动重试）。请确认网络与登录状态后重新打开 App。"
            }
        case .failed:
            SKPaymentQueue.default().finishTransaction(transaction)
            purchasingProductID = nil
            if let error = transaction.error as? SKError, error.code == .paymentCancelled {
                break
            }
            storeNotice = "购买未完成：\(transaction.error?.localizedDescription ?? "未知错误")"
        case .deferred, .purchasing:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - SKProductsRequestDelegate

extension IAPService: SKProductsRequestDelegate {
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        let received = response.products.sorted { $0.price.decimalValue < $1.price.decimalValue }
        let invalid = response.invalidProductIdentifiers
        DispatchQueue.main.async {
            self.products = received
            self.isLoadingProducts = false
            if received.isEmpty, !invalid.isEmpty {
                self.storeNotice = "积分包暂不可用：商品尚未在 App Store Connect 通过审核。"
            }
        }
    }

    func request(_ request: SKRequest, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.isLoadingProducts = false
            self.storeNotice = "无法获取积分包：\(error.localizedDescription)"
        }
    }
}

// MARK: - SKPaymentTransactionObserver

extension IAPService: SKPaymentTransactionObserver {
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            Task { @MainActor in
                await self.handle(transaction)
            }
        }
    }

    func paymentQueueRestoreCompletedTransactionsFinished(_ queue: SKPaymentQueue) {
        DispatchQueue.main.async {
            self.isRestoring = false
            self.storeNotice = "恢复购买完成；已入账的积分不会重复添加。"
        }
    }

    func paymentQueue(_ queue: SKPaymentQueue, restoreCompletedTransactionsFailedWithError error: Error) {
        DispatchQueue.main.async {
            self.isRestoring = false
            self.storeNotice = "恢复购买失败：\(error.localizedDescription)"
        }
    }
}
