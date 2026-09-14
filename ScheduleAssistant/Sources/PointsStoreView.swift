import SwiftUI
import StoreKit

/// 积分商店：积分包购买（消耗型）、恢复购买与客服入口（苹果审核要求可见）。
/// 余额只展示后端数据，客户端不做本地记账。
struct PointsStoreView: View {
    @ObservedObject private var account = AccountStore.shared
    @ObservedObject private var iap = IAPService.shared
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        List {
            Section {
                HStack {
                    Label("当前积分", systemImage: "sparkles")
                        .foregroundStyle(orbitAccent())
                    Spacer()
                    if account.isFetchingPoints {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(account.points.map { "\($0)" } ?? "—")
                            .font(.title3.bold().monospacedDigit())
                    }
                }
            } header: {
                Text("余额")
            } footer: {
                Text("积分由服务端按 AI 用量自动扣减，余额以本页显示为准；积分仅支持在 iOS 端使用。")
            }

            Section {
                if iap.isLoadingProducts && iap.products.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在获取积分包…")
                            .foregroundStyle(.secondary)
                    }
                } else if iap.products.isEmpty {
                    Button("重新获取积分包") { iap.loadProducts() }
                    Text("暂时加载不出积分包；请检查网络，或确认商品已在 App Store Connect 通过审核。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(iap.products, id: \.productIdentifier) { product in
                        purchaseRow(product)
                    }
                }
            } header: {
                Text("积分包")
            }

        }
        .navigationTitle("积分商店")
        .navigationBarTitleDisplayMode(.inline)
        .tint(orbitAccent())
        .onAppear {
            iap.loadProducts()
            Task { await account.refreshPoints() }
        }
        .alert("积分商店",
               isPresented: Binding(
                get: { iap.storeNotice != nil },
                set: { if !$0 { iap.storeNotice = nil } }
               )) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text(iap.storeNotice ?? "")
        }
    }

    private func purchaseRow(_ product: SKProduct) -> some View {
        Button {
            iap.purchase(product)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(iap.pointsLabel(for: product))
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !product.localizedTitle.isEmpty,
                       product.localizedTitle != product.productIdentifier {
                        Text(product.localizedTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if iap.purchasingProductID == product.productIdentifier {
                    ProgressView().controlSize(.small)
                } else {
                    Text(iap.price(for: product))
                        .font(.subheadline.bold())
                        .foregroundStyle(orbitAccent())
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(orbitAccent())
                }
            }
        }
        .disabled(iap.purchasingProductID != nil)
    }
}
