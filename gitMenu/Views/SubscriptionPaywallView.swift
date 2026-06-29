import StoreKit
import SwiftUI

struct SubscriptionPaywallView: View {
    @Bindable var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss

    private var trialDays: Int {
        Int(SubscriptionManager.trialDuration / 86_400)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Remote Git Pro")
                    .font(.system(size: 26, weight: .bold))

                Text(subscriptionManager.paywallFeature?.title ?? "Unlock Remote Git Features")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text(subscriptionManager.accessDescription)
                    .font(.system(size: 13.5))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                paywallFeatureRow(
                    title: "Browse remote repos",
                    detail: "Inspect hosted repositories without cloning."
                )
                paywallFeatureRow(
                    title: "Clone and sync",
                    detail: "Clone repositories, then pull and push from the menu bar."
                )
                paywallFeatureRow(
                    title: "Local stays free",
                    detail: "Opening, refreshing, committing, branching, and local history stay unlocked."
                )
            }

            if let feature = subscriptionManager.paywallFeature {
                Text(feature.summary)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
            }

            if let message = subscriptionManager.purchaseErrorMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.red)
            }

            VStack(alignment: .leading, spacing: 10) {
                if !subscriptionManager.hasStartedTrial {
                    Button("Accept \(trialDays) Days Free") {
                        subscriptionManager.startTrial()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                if subscriptionManager.isLoadingProducts {
                    ProgressView("Loading subscription options…")
                        .controlSize(.small)
                } else if subscriptionManager.products.isEmpty {
                    Text("No App Store subscription products are available yet. Add your remote subscription product ID in `SubscriptionManager` and configure it in App Store Connect.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(subscriptionManager.products, id: \.id) { product in
                        Button {
                            Task {
                                await subscriptionManager.purchase(product)
                            }
                        } label: {
                            HStack {
                                
                                Text("\(trialDays) days free, then \(product.displayPrice)/month")
                                    .font(.system(size: 9, weight: .ultraLight))
                                 //   .font(.caption)
                             
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(subscriptionManager.isProcessingPurchase)
                    }
                }
            }

            HStack {
                /*
                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }
                .buttonStyle(.plain)
                .disabled(subscriptionManager.isProcessingPurchase)

                Button("Manage Subscriptions") {
                    subscriptionManager.openManageSubscriptions()
                }
                .buttonStyle(.plain)
*/
                Spacer()

                Button("Not Now") {
                    subscriptionManager.dismissPaywall()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .font(.system(size: 12.5, weight: .medium))
        }
        .padding(22)
        .frame(width: 430)
    }

    private func paywallFeatureRow(title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(GitLaneColor.main.color)
                .font(.system(size: 14, weight: .semibold))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))

                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
