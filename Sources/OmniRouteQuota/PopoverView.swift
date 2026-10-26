#if os(macOS)
import AppKit
import QuotaCore
import SwiftUI

/// Matches OmniRouteTray's dark 320-point popover and four-column quota grid.
/// See DESIGN.md for the source reference and intentionally omitted server controls.
private enum TrayPalette {
    static let background = Color(red: 28/255, green: 28/255, blue: 30/255)
    static let raised = Color(red: 44/255, green: 44/255, blue: 46/255)
    static let border = Color(red: 56/255, green: 56/255, blue: 58/255)
    static let text = Color(red: 245/255, green: 245/255, blue: 247/255)
    static let muted = Color(red: 161/255, green: 161/255, blue: 170/255)
    static let faint = Color(red: 147/255, green: 152/255, blue: 163/255)
    static let good = Color(red: 34/255, green: 197/255, blue: 94/255)
    static let warning = Color(red: 245/255, green: 158/255, blue: 11/255)
    static let bad = Color(red: 239/255, green: 68/255, blue: 68/255)

    static func quotaColor(_ remaining: Double) -> Color {
        remaining < 20 ? bad : remaining < 50 ? warning : good
    }
}

struct PopoverView: View {
    @ObservedObject var store: QuotaStore
    @AppStorage("quotaShowUsed") private var showUsed = false

    private var groups: [QuotaProviderGroup] { store.visibleGroups }

    private var contentHeight: CGFloat {
        guard !groups.isEmpty else { return 130 }
        let rowHeight = groups.reduce(CGFloat(0)) { total, group in
            total + group.accounts.reduce(CGFloat(0)) { part, account in
                let count = max(1, account.windows.count)
                return part + 21 + CGFloat(count * 15) + CGFloat(max(0, count - 1)) * 3
            } + CGFloat(max(0, group.accounts.count - 1)) * 6 + 8
        }
        let warningHeight: CGFloat = (store.errorMessage == nil && store.refreshWarning == nil) ? 0 : 21
        return min(425, max(130, 55 + rowHeight + warningHeight))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            separator
            if store.showingSettings {
                SettingsView(store: store)
            } else {
                ScrollView(.vertical) {
                    VStack(alignment: .leading, spacing: 0) {
                        statusBand
                        separator
                        usage
                    }
                }
                .frame(height: contentHeight)
                separator
                footer
            }
        }
        .frame(width: 310)
        .background(TrayPalette.background)
        .foregroundStyle(TrayPalette.text)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .preferredColorScheme(.dark)
    }

    private var separator: some View {
        Rectangle()
            .fill(TrayPalette.border)
            .frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(store.connected ? TrayPalette.good : (store.refreshing ? TrayPalette.warning : TrayPalette.bad))
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                .accessibilityHidden(true)

            Text("OmniRoute")
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15)

            Text(store.connected ? "Running" : (store.refreshing ? "Starting…" : "Offline"))
                .font(.system(size: 11))
                .foregroundStyle(TrayPalette.muted)

            Spacer(minLength: 3)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
    }

    private var statusBand: some View {
        HStack(spacing: 6) {
            if store.lastUpdated == nil {
                Text(store.refreshing ? "Reading accounts…" : "Waiting for OmniRoute")
            } else {
                Text("\(store.activeProviderCount)/\(store.providerCount) providers")
                    .help("Providers with an enabled account / configured providers")
                Text("·")
                Text("\(store.accounts.count) accounts")
            }
            Spacer(minLength: 0)
        }
        .font(.system(size: 11))
        .foregroundStyle(TrayPalette.muted)
        .lineLimit(1)
        .padding(.horizontal, 13)
        .padding(.vertical, 7)
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("USAGE")
                    .font(.system(size: 10.5, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(TrayPalette.faint)
                Spacer()
                Button {
                    showUsed.toggle()
                } label: {
                    Text(showUsed ? "% used" : "% left")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(TrayPalette.muted)
                        .frame(minWidth: 49)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(TrayPalette.raised, in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(TrayPalette.border))
                }
                .buttonStyle(.plain)
                .help("Toggle remaining and used quota")
                .accessibilityLabel(showUsed ? "Showing percent used. Switch to percent left." : "Showing percent left. Switch to percent used.")
            }
            .padding(.bottom, 7)

            if store.errorMessage != nil && store.lastUpdated != nil {
                Label("Showing last known quotas", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.warning)
                    .padding(.bottom, 7)
                    .help(store.errorMessage ?? "")
            } else if let warning = store.refreshWarning {
                Label("Some account quotas could not refresh", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.warning)
                    .padding(.bottom, 7)
                    .help(warning)
            }

            if store.accounts.isEmpty && store.lastUpdated == nil {
                firstLoad
            } else if store.visibleAccounts.isEmpty {
                emptyState
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(group.accounts) { account in
                                AccountQuotaRows(account: account, server: store.address, showUsed: showUsed)
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var firstLoad: some View {
        VStack(spacing: 10) {
            Image(systemName: store.refreshing ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .font(.system(size: 20))
                .foregroundStyle(TrayPalette.faint)
            Text(store.refreshing ? "Loading quotas…" : "Can't connect to OmniRoute")
                .font(.system(size: 12, weight: .semibold))
            Text(store.errorMessage ?? "Make sure OmniRoute is running on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(TrayPalette.muted)
                .multilineTextAlignment(.center)
            Button("Retry") { Task { await store.refresh() } }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(store.accounts.isEmpty ? "No accounts connected" : "No quotas to display")
                .font(.system(size: 12, weight: .semibold))
            Text(store.accounts.isEmpty
                 ? "Add a connection in OmniRoute to see its quota."
                 : "All accounts are hidden or have no measurable quota. Adjust display settings to show them.")
                .font(.system(size: 10.5))
                .foregroundStyle(TrayPalette.muted)
                .multilineTextAlignment(.center)
            Button(store.accounts.isEmpty ? "Open OmniRoute" : "Display settings") {
                if store.accounts.isEmpty { store.openDashboard() }
                else { store.showingSettings = true }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 13)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Text(footerRefreshLabel)
                .font(.system(size: 10.5))
                .foregroundStyle(store.errorMessage == nil && store.refreshWarning == nil
                                 ? TrayPalette.faint : TrayPalette.warning)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .help(store.errorMessage ?? store.refreshWarning ??
                      "Last successful quota check from OmniRoute")

            Button { store.openDashboard() } label: {
                Text(":\(serverPort)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(TrayPalette.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(TrayPalette.raised, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(TrayPalette.border))
            }
            .buttonStyle(.plain)
            .help("Open OmniRoute")
            Spacer(minLength: 2)
            if store.refreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(TrayPalette.muted)
                    .frame(width: 24, height: 24)
                    .help(store.forcingRefresh
                          ? "Refreshing live quotas for enabled and disabled accounts…"
                          : "Reading OmniRoute's cached quotas…")
                    .accessibilityLabel(store.forcingRefresh
                                        ? "Refreshing all account quotas" : "Checking cached quotas")
            } else {
                footerButton("arrow.clockwise", "Refresh all account quotas, including disabled") {
                    Task { await store.refresh(force: true) }
                }
            }
            footerButton("arrow.up.right.square", "Open OmniRoute") { store.openDashboard() }
            footerButton("gearshape", "Settings") { store.showingSettings = true }
        }
        .padding(.leading, 13)
        .padding(.trailing, 9)
        .padding(.vertical, 5)
    }

    private var footerRefreshLabel: String {
        if store.refreshing { return "Refreshing…" }
        if store.errorMessage != nil { return "Refresh failed" }
        if store.refreshWarning != nil { return "Partial refresh" }
        if let lastUpdated = store.lastUpdated {
            return "Checked \(lastUpdated.formatted(date: .omitted, time: .shortened))"
        }
        return "OmniRoute"
    }

    private var serverPort: String {
        guard let endpoint = try? OmniRouteEndpoint(store.address),
              let port = endpoint.baseURL.port else { return "local" }
        return String(port)
    }

    private func footerButton(_ systemName: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(TrayPalette.muted)
                .frame(width: 24, height: 24)
                .background(TrayPalette.raised, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(TrayPalette.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct AccountQuotaRows: View {
    let account: QuotaAccount
    let server: String
    let showUsed: Bool

    private var displayName: String {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || ["default", "main"].contains(name.lowercased())
            ? account.providerName : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                ProviderMark(provider: account.provider, server: server)
                Text(displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(account.active ? TrayPalette.text : TrayPalette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(account.name)
                Spacer(minLength: 2)
                if !account.active {
                    Text("OFF")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.35)
                        .foregroundStyle(TrayPalette.faint)
                        .help("Disabled account, showing cached quota when available")
                }
                if account.isStale {
                    Text("STALE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(TrayPalette.warning)
                }
            }
            if account.windows.isEmpty {
                Text(account.active ? "Quota not available" : "No cached quota available")
                    .font(.system(size: 11))
                    .foregroundStyle(TrayPalette.muted)
                    .padding(.leading, 22)
                    .frame(height: 20, alignment: .leading)
            } else {
                VStack(spacing: 3) {
                    ForEach(account.windows) { window in
                        QuotaGridRow(window: window, showUsed: showUsed, inactive: !account.active)
                    }
                }
            }
        }
    }
}

private struct ProviderMark: View {
    let provider: String
    let server: String

    @State private var icon: NSImage?

    private var fallbackTint: Color {
        // OmniRouteTray uses a stable provider hue for unknown providers.
        let hash = provider.utf8.reduce(UInt32(0)) { ($0 &* 31) &+ UInt32($1) }
        return Color(hue: Double(hash % 360) / 360, saturation: 0.52, brightness: 0.82)
    }

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .renderingMode(.original)
                    .interpolation(.high)
                    .scaledToFit()
            } else {
                Text(String(provider.prefix(1)).uppercased())
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(fallbackTint)
                    .frame(width: 16, height: 16)
                    .background(fallbackTint.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
        }
        .frame(width: 16, height: 16)
        .accessibilityHidden(true)
        .task(id: "\(server)|\(provider)") {
            icon = await OmniRouteArtwork.providerIcon(provider, server: server)
        }
    }
}

private struct QuotaGridRow: View {
    let window: QuotaWindow
    let showUsed: Bool
    let inactive: Bool

    private var value: Double { window.displayedPercent(showUsed: showUsed) }
    private var color: Color {
        inactive ? TrayPalette.muted : TrayPalette.quotaColor(window.remainingPercent)
    }

    var body: some View {
        HStack(spacing: 7) {
            Text(window.label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(TrayPalette.muted)
                .frame(width: 22, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(TrayPalette.border)
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * value / 100)
                }
            }
            .frame(height: 6)

            Text(window.unlimited ? "∞" : "\(window.displayedRoundedPercent(showUsed: showUsed))%")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
                .monospacedDigit()
                .frame(width: 34, alignment: .trailing)

            Text(window.resetAt == nil ? "" : window.countdown())
                .font(.system(size: 10))
                .foregroundStyle(TrayPalette.faint)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
                .help(window.resetAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "Reset time unavailable")
        }
        .frame(height: 15)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label): \(window.unlimited ? "unlimited" : "\(window.displayedRoundedPercent(showUsed: showUsed)) percent \(showUsed ? "used" : "remaining")"), resets \(window.countdown())")
    }
}

private struct ArrangementSettings: View {
    @ObservedObject var store: QuotaStore

    private var groups: [QuotaProviderGroup] { store.settingsGroups }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Uncheck to hide · arrows to reorder")
                    .font(.system(size: 10))
                    .foregroundStyle(TrayPalette.muted)
                Spacer(minLength: 0)
                Button("Reset order") { store.resetDisplayOrder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(TrayPalette.muted)
                    .help("Reset provider and account order; keep visibility choices")
            }
            .padding(.bottom, 3)

            if groups.isEmpty {
                Text("Connected accounts will appear here after a refresh.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.muted)
            }

            ForEach(groups) { group in
                let providerIndex = groups.firstIndex(where: { $0.id == group.id }) ?? 0
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 5) {
                        ProviderMark(provider: group.providerID, server: store.address)
                        Toggle(isOn: Binding(
                            get: { !store.displayPreferences.hiddenProviders.contains(group.id) },
                            set: { store.setProviderVisible(group.id, visible: $0) }
                        )) {
                            Text(group.providerName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)

                        Spacer(minLength: 2)
                        moveButton("chevron.up", "Move \(group.providerName) up",
                                   disabled: providerIndex == 0) {
                            store.moveProvider(group.id, by: -1)
                        }
                        moveButton("chevron.down", "Move \(group.providerName) down",
                                   disabled: providerIndex == groups.count - 1) {
                            store.moveProvider(group.id, by: 1)
                        }
                    }

                    ForEach(group.accounts) { account in
                        let accountIndex = group.accounts.firstIndex(where: { $0.id == account.id }) ?? 0
                        HStack(spacing: 4) {
                            Toggle(isOn: Binding(
                                get: { !store.displayPreferences.hiddenAccounts.contains(QuotaDisplayPreferences.accountKey(account)) },
                                set: { store.setAccountVisible(account, visible: $0) }
                            )) {
                                Text(account.name)
                                    .font(.system(size: 10.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .help(account.name)

                            if !QuotaDisplayPreferences.hasMeasurableQuota(account) {
                                Image(systemName: "minus.circle")
                                    .font(.system(size: 10))
                                    .foregroundStyle(TrayPalette.faint)
                                    .help("No finite quota reported; hidden when the no-quota filter is enabled")
                            }
                            Spacer(minLength: 1)
                            moveButton("chevron.up", "Move \(account.name) up",
                                       disabled: accountIndex == 0) {
                                store.moveAccount(account, by: -1)
                            }
                            moveButton("chevron.down", "Move \(account.name) down",
                                       disabled: accountIndex == group.accounts.count - 1) {
                                store.moveAccount(account, by: 1)
                            }
                        }
                        .padding(.leading, 19)
                    }
                }
                .padding(.vertical, 4)

                if providerIndex < groups.count - 1 {
                    Rectangle().fill(TrayPalette.border).frame(height: 1)
                }
            }
        }
    }

    private func moveButton(_ symbol: String, _ title: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(disabled ? TrayPalette.faint.opacity(0.4) : TrayPalette.muted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct SettingsView: View {
    @ObservedObject var store: QuotaStore
    @State private var address: String
    @State private var apiKey: String
    @State private var cliToken: String
    @State private var saveError: String?

    init(store: QuotaStore) {
        self.store = store
        _address = State(initialValue: store.address)
        _apiKey = State(initialValue: store.apiKey)
        _cliToken = State(initialValue: store.tokenOverride)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 9) {
                    Button {
                        store.showingSettings = false
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(TrayPalette.bad)
                    Text("Settings")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.bottom, 4)
                Rectangle().fill(TrayPalette.border).frame(height: 1)

                sectionTitle("CONNECTION")
                TextField("127.0.0.1:20128", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("Only localhost is permitted. Your quota data stays on this Mac.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.muted)

                sectionTitle("DISPLAY")
                Toggle("Hide accounts without quota", isOn: $store.displayPreferences.hideWithoutQuota)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                Toggle("Show disabled accounts", isOn: $store.showDisabledAccounts)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11.5))
                Text("Accounts with no reported finite quota are hidden by default. Empty providers disappear too. Disabled accounts remain optional.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                sectionTitle("ORDER & VISIBILITY")
                ArrangementSettings(store: store)

                sectionTitle("AUTHENTICATION")
                Text("Management API key override")
                    .font(.system(size: 11))
                SecureField("Auto-read from ~/.omniroute/.env", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("Leave empty to read OMNIROUTE_API_KEY locally. Manual overrides are stored in Keychain.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("CLI token override")
                    .font(.system(size: 11))
                SecureField("Derived automatically", text: $cliToken)
                    .textFieldStyle(.roundedBorder)
                Text("Only needed when your OmniRoute installation uses a custom CLI token.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(TrayPalette.muted)

                if let saveError {
                    Text(saveError)
                        .font(.system(size: 11))
                        .foregroundStyle(TrayPalette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Quit app") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(TrayPalette.muted)
                        .font(.system(size: 11))
                    Spacer()
                    Button("Save & connect") {
                        do { try store.save(address: address, apiKey: apiKey, tokenOverride: cliToken) }
                        catch { saveError = error.localizedDescription }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(.top, 5)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: 470)
    }

    private func sectionTitle(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.7)
            .foregroundStyle(TrayPalette.faint)
            .padding(.top, 3)
    }
}
#endif
