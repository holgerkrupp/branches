import StoreKit
import SwiftUI

struct SettingsView: View {
    @Bindable var credentialsStore: HostCredentialsStore
    @Bindable var subscriptionManager: SubscriptionManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                subscriptionCard

                ForEach($credentialsStore.accounts) { $account in
                    accountCard(account: $account)
                }

                Button(action: credentialsStore.addCustomHost) {
                    Label("Add Custom Host", systemImage: "plus.circle")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(20)
        }
        .frame(minWidth: 620, minHeight: 540)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            subscriptionManager.start()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remote Git")
                .font(.system(size: 22, weight: .semibold))

            Text("Local repositories stay free. Remote browsing, clone, pull, and push use a subscription with a free trial.")
                .font(.system(size: 13.5))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 520, alignment: .leading)
        }
    }

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Remote Git Pro")
                        .font(.system(size: 15, weight: .semibold))

                    Text(subscriptionManager.accessDescription)
                        .font(.system(size: 12.5))
                        .foregroundStyle(subscriptionManager.canUseRemoteFeatures ? .green : .secondary)
                }

                Spacer()
            }

            HStack(spacing: 12) {
                if !subscriptionManager.hasStartedTrial {
                    Button("Start Free Trial") {
                        subscriptionManager.startTrial()
                    }
                    .buttonStyle(.borderedProminent)
                }

                if let product = subscriptionManager.products.first {
                    Button("Subscribe for \(product.displayPrice)") {
                        Task {
                            await subscriptionManager.purchase(product)
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(subscriptionManager.isProcessingPurchase)
                }

                Button("Restore Purchases") {
                    Task {
                        await subscriptionManager.restorePurchases()
                    }
                }
                .buttonStyle(.plain)

                Button("Manage") {
                    subscriptionManager.openManageSubscriptions()
                }
                .buttonStyle(.plain)
            }

            if let message = subscriptionManager.purchaseErrorMessage, !message.isEmpty {
                Text(message)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    @ViewBuilder
    private func accountCard(account: Binding<GitHostAccount>) -> some View {
        let isCustom = account.wrappedValue.kind == .custom

        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: account.wrappedValue.kind.symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.wrappedValue.displayTitle)
                        .font(.system(size: 15, weight: .semibold))

                    Text(account.wrappedValue.statusText)
                        .font(.system(size: 12.5))
                        .foregroundStyle(account.wrappedValue.isEnabled && !account.wrappedValue.token.isEmpty ? .green : .secondary)
                }

                Spacer()

                Toggle("Enabled", isOn: account.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()

                if isCustom {
                    Button(role: .destructive) {
                        credentialsStore.remove(account.wrappedValue.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                settingsField("Host URL", text: account.hostURL, placeholder: isCustom ? "https://git.example.com" : account.wrappedValue.kind.defaultURL)
                settingsField("Username", text: account.username, placeholder: "Optional account name")
                secureSettingsField("Access Token", text: account.token, placeholder: "Paste a personal access token")
                settingsField("Notes", text: account.note, placeholder: "Optional notes for this host")
            }

            if !account.wrappedValue.note.isEmpty {
                Text(account.wrappedValue.note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func settingsField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func secureSettingsField(
        _ title: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.secondary)

            SecureField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }
}
