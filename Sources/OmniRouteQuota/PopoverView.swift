#if os(macOS)
import AppKit
import QuotaCore
import SwiftUI

private enum Palette {
    static let background = Color(red: 0.090, green: 0.100, blue: 0.115)
    static let foreground = Color(red: 0.955, green: 0.961, blue: 0.969)
    static let muted = Color(red: 0.615, green: 0.650, blue: 0.704)
    static let line = Color.white.opacity(0.095)
    static let track = Color.white.opacity(0.13)
    static let green = Color(red: 0.20, green: 0.81, blue: 0.49)
    static let amber = Color(red: 0.98, green: 0.69, blue: 0.27)
    static let red = Color(red: 1.0, green: 0.38, blue: 0.38)

    static func quota(_ remaining: Double) -> Color {
        remaining < 20 ? red : remaining < 50 ? amber : green
    }
}

struct PopoverView: View {
    @ObservedObject var store: QuotaStore

    private var providerGroups: [QuotaProviderGroup] {
        QuotaProviderGroup.grouped(store.visibleAccounts)
    }

    private var listHeight: CGFloat {
        let rows = providerGroups.reduce(CGFloat(0)) { total, group in
            total + 46 + group.accounts.reduce(CGFloat(0)) { subtotal, account in
                subtotal + 33 + CGFloat(max(1, account.windows.count)) * 25
            }
        }
        return min(500, max(124, rows))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.line).frame(height: 1)
            if store.showingSettings {
                SettingsView(store: store)
            } else {
                dashboard
                Rectangle().fill(Palette.line).frame(height: 1)
                footer
            }
        }
        .frame(width: 410)
        .background(Palette.background)
        .foregroundStyle(Palette.foreground)
        .preferredColorScheme(.dark)
        .onAppear { store.start() }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Group {
                if let icon = OmniRouteArtwork.header {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .padding(5)
                } else {
                    Image(systemName: "circle.hexagongrid.fill")
                        .font(.system(size: 15, weight: .semibold))
                }
            }
            .frame(width: 31, height: 31)
            .background(Palette.track, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 1) {
                Text("OmniRoute")
                    .font(.system(size: 15, weight: .semibold))
                Text(store.showingSettings ? "Connection settings" : "Account quotas")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 6)
            Circle()
                .fill(store.connected ? Palette.green : (store.refreshing ? Palette.amber : Palette.red))
                .frame(width: 6, height: 6)
            Text(store.connected ? "Connected" : (store.refreshing ? "Connecting" : "Offline"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
            if !store.showingSettings {
                iconButton("gearshape", "Settings") { store.showingSettings = true }
            }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 13)
    }

    @ViewBuilder
    private var dashboard: some View {
        if store.accounts.isEmpty && store.lastUpdated == nil {
            initialState
        } else if store.visibleAccounts.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("\(store.visibleAccounts.count) accounts  ·  \(store.visibleProviderCount) providers")
                    Spacer()
                    Text("% left")
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Palette.muted)
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 9)

                if store.errorMessage != nil {
                    HStack(spacing: 7) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Showing last known quotas — refresh failed")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.amber)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 7)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(providerGroups) { group in
                            if group.id != providerGroups.first?.id {
                                Rectangle().fill(Palette.line)
                                    .frame(height: 1)
                                    .padding(.leading, 38)
                                    .padding(.vertical, 3)
                            }
                            ProviderSection(group: group, address: store.address)
                        }
                    }
                    .padding(.horizontal, 17)
                }
                .frame(height: listHeight)
            }
        }
    }

    private var initialState: some View {
        VStack(spacing: 13) {
            Image(systemName: store.refreshing ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(store.refreshing ? Palette.green : Palette.muted)
            Text(store.refreshing ? "Reading local quotas…" : "Can't connect to OmniRoute")
                .font(.system(size: 13, weight: .semibold))
            if let message = store.errorMessage {
                Text(message)
                    .multilineTextAlignment(.center)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Make sure OmniRoute is running on this Mac.")
                    .multilineTextAlignment(.center)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            }
            HStack(spacing: 12) {
                Button("Retry") { Task { await store.refresh() } }
                Button("Settings") { store.showingSettings = true }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30)
        .frame(height: 220)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "tray")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.muted)
            Text(store.accounts.isEmpty ? "No accounts configured" : "No active accounts")
                .font(.system(size: 13, weight: .semibold))
            Text(store.accounts.isEmpty
                 ? "Add an account in OmniRoute to see its quota here."
                 : "Enable disabled accounts to see their last cached quotas.")
                .font(.system(size: 11))
                .foregroundStyle(Palette.muted)
            Button(store.accounts.isEmpty ? "Open OmniRoute" : "Show disabled accounts") {
                if store.accounts.isEmpty { store.openDashboard() }
                else { store.showDisabledAccounts = true }
            }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 190)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let date = store.lastUpdated {
                Text("Updated \(date, style: .time)")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
            } else {
                Text("Local server · \(store.address)")
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .foregroundStyle(Palette.muted)
            }
            Spacer(minLength: 8)
            iconButton("arrow.clockwise", "Refresh quotas") {
                Task { await store.refresh() }
            }
            .disabled(store.refreshing)
            iconButton("arrow.up.right.square", "Open OmniRoute") { store.openDashboard() }
            iconButton("power", "Quit") { NSApplication.shared.terminate(nil) }
        }
        .padding(.horizontal, 17)
        .padding(.vertical, 10)
    }

    private func iconButton(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Palette.muted)
                .frame(width: 25, height: 25)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

private struct ProviderSection: View {
    let group: QuotaProviderGroup
    let address: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                ProviderMark(providerID: group.providerID, providerName: group.providerName,
                             address: address)
                Text(group.providerName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if group.accounts.count > 1 {
                    Text("\(group.accounts.count) accounts")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Palette.muted)
                }
            }
            ForEach(group.accounts) { account in
                AccountRow(account: account)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct AccountRow: View {
    let account: QuotaAccount

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(account.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(account.active ? Palette.foreground : Palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 3)
                if !account.active {
                    Text("DISABLED")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.muted)
                }
                if account.isStale {
                    Text("STALE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.amber)
                }
            }
            .padding(.leading, 34)
            if account.windows.isEmpty {
                Text(account.active ? "Quota not available" : "No cached quota available")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.muted)
                    .padding(.leading, 34)
                    .frame(height: 24, alignment: .leading)
            } else {
                VStack(spacing: 7) {
                    ForEach(account.windows) { window in
                        QuotaBar(window: window, inactive: !account.active)
                    }
                }
            }
        }
        .padding(.vertical, 5)
    }
}

private struct ProviderMark: View {
    let providerID: String
    let providerName: String
    let address: String
    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(3)
            } else {
                Text(String(providerName.prefix(1)).uppercased())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.foreground)
            }
        }
        .frame(width: 25, height: 25)
        .background(Palette.track, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityHidden(true)
        .task(id: "\(address)|\(providerID)") {
            icon = await OmniRouteArtwork.providerIcon(providerID, server: address)
        }
    }
}

private struct QuotaBar: View {
    let window: QuotaWindow
    let inactive: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(window.label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Palette.muted)
                .frame(width: 32, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule()
                        .fill(inactive ? Palette.muted : Palette.quota(window.remainingPercent))
                        .frame(width: max(0, geometry.size.width * window.remainingPercent / 100))
                }
            }
            .frame(height: 7)
            .accessibilityLabel("\(window.roundedRemaining) percent available")

            Text(window.unlimited ? "∞" : "\(window.roundedRemaining)%")
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(inactive ? Palette.muted : Palette.quota(window.remainingPercent))
                .frame(width: 40, alignment: .trailing)

            Text(window.countdown())
                .font(.system(size: 10.5, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Palette.muted)
                .frame(width: 53, alignment: .trailing)
        }
        .frame(height: 18)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(window.label): \(window.unlimited ? "unlimited" : "\(window.roundedRemaining) percent remaining"), resets in \(window.countdown())")
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
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Local server")
                    .font(.system(size: 11, weight: .medium))
                TextField("127.0.0.1:20128", text: $address)
                    .textFieldStyle(.roundedBorder)
                Text("Only localhost connections are allowed. Your quotas stay on this Mac.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
            }
            VStack(alignment: .leading, spacing: 5) {
                Toggle("Show disabled accounts", isOn: $store.showDisabledAccounts)
                    .font(.system(size: 11, weight: .medium))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                Text("Shows their last cached quota, even when the connection is disabled. Figures may be stale.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("Management API key override · optional")
                    .font(.system(size: 11, weight: .medium))
                SecureField("Automatically read from ~/.omniroute/.env", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                Text("If empty, uses OMNIROUTE_API_KEY from the local .env file when available. Overrides are stored in Keychain.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("CLI token override · optional")
                    .font(.system(size: 11, weight: .medium))
                SecureField("Automatically derived on this Mac", text: $cliToken)
                    .textFieldStyle(.roundedBorder)
                Text("A local CLI token is derived automatically. Enter an override only if your OmniRoute installation uses custom authentication.")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let saveError {
                Text(saveError)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Back") { store.showingSettings = false }
                Spacer()
                Button("Save & connect") {
                    do {
                        try store.save(address: address, apiKey: apiKey, tokenOverride: cliToken)
                    } catch {
                        saveError = error.localizedDescription
                    }
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .tint(Palette.green)
            }
            .controlSize(.small)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
#endif
