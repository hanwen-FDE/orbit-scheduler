import SwiftUI
import StoreKit

/// 左侧「我的」中唯一的积分入口。账本来自服务端 quota_ops，而非客户端余额推断。
struct MyPointsCenterView: View {
    @ObservedObject private var account = AccountStore.shared

    var body: some View {
        List {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("当前积分余额").font(.subheadline).foregroundStyle(.secondary)
                        Text(account.points.map { "\($0) 积分" } ?? "—")
                            .font(.largeTitle.bold().monospacedDigit())
                            .foregroundStyle(orbitAccent())
                    }
                    Spacer()
                    Image(systemName: "sparkles").font(.title).foregroundStyle(orbitAccent())
                }
                NavigationLink(destination: PointsStoreView()) {
                    Label("充值 · 积分商店", systemImage: "cart.circle.fill")
                        .foregroundStyle(orbitAccent())
                }
            }

            Section("积分明细") {
                if account.isFetchingLedger {
                    HStack { Spacer(); ProgressView(); Spacer() }
                } else if account.pointsLedger.isEmpty {
                    Text("暂无积分明细")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(account.pointsLedger) { entry in
                        ledgerRow(entry)
                    }
                }
            } footer: {
                Text("积分流水由 Orbit 云端账本记录，按时间倒序展示。")
            }
        }
        .navigationTitle("我的积分")
        .navigationBarTitleDisplayMode(.inline)
        .tint(orbitAccent())
        .task {
            await account.refreshPoints()
            await account.refreshPointsLedger()
        }
    }

    private func ledgerRow(_ entry: OrbitAPIClient.PointsLedgerEntry) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.delta_points >= 0 ? "plus.circle.fill" : "minus.circle.fill")
                .foregroundStyle(entry.delta_points >= 0 ? orbitAccent() : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(ledgerReason(entry)).font(.body)
                Text(entry.created_at.replacingOccurrences(of: "T", with: " "))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(entry.delta_points >= 0 ? "+\(entry.delta_points)" : "\(entry.delta_points)")
                    .font(.headline.monospacedDigit()).foregroundStyle(entry.delta_points >= 0 ? orbitAccent() : .primary)
                Text("余额 \(entry.balance_after)").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func ledgerReason(_ entry: OrbitAPIClient.PointsLedgerEntry) -> String {
        if entry.reason.hasPrefix("iap:") { return "购买积分包" }
        if entry.reason.hasPrefix("refund:") { return "积分包退款" }
        if entry.reason.contains("admin:grant") { return "系统赠送 / 调整" }
        if entry.reason.contains("usage:") { return "Orbit 云端 AI 使用" }
        return entry.reason
    }
}

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
