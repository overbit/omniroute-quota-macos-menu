#if os(macOS)
import AppKit
import QuotaCore
import SwiftUI

/// Shared fixed chrome budget; both modes scroll inside a 425-point outer bound.
enum PopoverLayout {
    static let maximumHeight: CGFloat = 425
    static let headerHeight: CGFloat = 38
    static let footerHeight: CGFloat = 34
    static let pickerHeight: CGFloat = 36
    static let statusBandHeight: CGFloat = 32
    static let usageBottomPadding: CGFloat = 10
    static let contentHeight = maximumHeight - headerHeight - footerHeight - pickerHeight - 2
}

/// Compact two-up quota meters with a selectable semantic color palette.
struct PopoverView: View {
    @ObservedObject var store: QuotaStore
    @AppStorage("quotaTheme") private var selectedTheme: QuotaTheme = .oled

    private var palette: TrayPalette { selectedTheme.palette }
    @AppStorage("quotaShowUsed") private var showUsed = false

    private var groups: [QuotaProviderGroup] { store.visibleGroups }

    private var contentHeight: CGFloat {
        guard !groups.isEmpty else { return 130 }
        let rowHeight = groups.reduce(CGFloat(0)) { total, group in
            total + group.accounts.reduce(CGFloat(0)) { part, account in
                part + QuotaMeterLayout.accountHeight(windowCount: account.windows.count)
            } + CGFloat(max(0, group.accounts.count - 1)) * 6
        } + CGFloat(max(0, groups.count - 1)) * 8
        let warningHeight: CGFloat = (store.errorMessage == nil && store.refreshWarning == nil) ? 0 : 21
        // Both modes share the remaining height after fixed chrome and separators.
        // A single 32pt status/mode toolbar replaces the redundant USAGE heading.
        let usageHeight = PopoverLayout.statusBandHeight + PopoverLayout.usageBottomPadding + rowHeight + warningHeight
        return min(PopoverLayout.contentHeight, max(130, usageHeight))
    }

    var body: some View {
        VStack(spacing: 0) {
            header.frame(height: PopoverLayout.headerHeight)
            separator
            if store.showingSettings {
                SettingsView(store: store, selectedTheme: $selectedTheme)
            } else {
                Picker("View", selection: $store.showingTimeline) {
                    Text("Usage").tag(false)
                    Text("Timeline").tag(true)
                }
                .pickerStyle(.segmented)
                .frame(height: 22)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .frame(height: PopoverLayout.pickerHeight)
                if store.showingTimeline {
                    RequestTimelineView(snapshot: store.timeline)
                        .frame(height: PopoverLayout.contentHeight)
                } else {
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            statusBand
                            usage
                        }
                    }
                    .frame(height: contentHeight)
                }
                separator
                footer.frame(height: PopoverLayout.footerHeight)
            }
        }
        .background(PopoverVisibilityReader { store.popoverVisible = $0 })
        .frame(width: 310)
        .background(palette.background)
        .foregroundStyle(palette.text)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .tint(palette.accent)
        .environment(\.trayPalette, palette)
        .preferredColorScheme(selectedTheme.isLight ? .light : .dark)
    }

    private var separator: some View {
        Rectangle()
            .fill(palette.border)
            .frame(height: 1)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle()
                .fill(store.connected ? palette.good : (store.refreshing ? palette.warning : palette.bad))
                .frame(width: 9, height: 9)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] }
                .accessibilityHidden(true)

            Text("OmniRoute")
                .font(.system(size: 15, weight: .bold))
                .tracking(-0.15)

            Text(store.connected ? "Running" : (store.refreshing ? "Starting…" : "Offline"))
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)

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
            Spacer(minLength: 4)
            quotaModeButton
        }
        .font(.system(size: 10.5))
        .foregroundStyle(palette.muted)
        .lineLimit(1)
        .padding(.horizontal, 13)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private var quotaModeButton: some View {
        Button {
            showUsed.toggle()
        } label: {
            Text(showUsed ? "% used" : "% left")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(palette.muted)
                .frame(width: 58, height: 22)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border.opacity(0.6), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Toggle remaining and used quota")
        .accessibilityLabel(showUsed ? "Showing percent used. Switch to percent left." : "Showing percent left. Switch to percent used.")
    }

    private var usage: some View {
        VStack(alignment: .leading, spacing: 0) {
            if store.errorMessage != nil && store.lastUpdated != nil {
                Label("Showing last known quotas", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.warning)
                    .padding(.bottom, 7)
                    .help(store.errorMessage ?? "")
            } else if let warning = store.refreshWarning {
                Label("Some account quotas could not refresh", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.warning)
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
        .padding(.bottom, PopoverLayout.usageBottomPadding)
    }

    private var firstLoad: some View {
        VStack(spacing: 10) {
            Image(systemName: store.refreshing ? "arrow.triangle.2.circlepath" : "wifi.slash")
                .font(.system(size: 20))
                .foregroundStyle(palette.faint)
            Text(store.refreshing ? "Loading quotas…" : "Can't connect to OmniRoute")
                .font(.system(size: 12, weight: .semibold))
            Text(store.errorMessage ?? "Make sure OmniRoute is running on this Mac.")
                .font(.system(size: 11))
                .foregroundStyle(palette.muted)
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
                .foregroundStyle(palette.muted)
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
                                 ? palette.faint : palette.warning)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .help(store.errorMessage ?? store.refreshWarning ??
                      "Last successful quota check from OmniRoute")

            Button { store.openDashboard() } label: {
                Text(":\(serverPort)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(palette.muted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 5))
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.border))
            }
            .buttonStyle(.plain)
            .help("Open OmniRoute")
            Spacer(minLength: 2)
            if store.refreshing {
                ProgressView()
                    .controlSize(.small)
                    .tint(palette.muted)
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
                .foregroundStyle(palette.muted)
                .frame(width: 24, height: 24)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

struct AccountQuotaRows: View {
    @Environment(\.trayPalette) private var palette
    let account: QuotaAccount
    let server: String
    let showUsed: Bool

    private var displayName: String {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || ["default", "main"].contains(name.lowercased())
            ? account.providerName : name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: QuotaMeterLayout.rowSpacing) {
            HStack(spacing: 6) {
                ProviderMark(provider: account.provider, server: server)
                Text(displayName)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(account.active ? palette.text : palette.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(account.name)
                Spacer(minLength: 2)
                if !account.active {
                    Text("OFF")
                        .font(.system(size: 9, weight: .semibold))
                        .tracking(0.35)
                        .foregroundStyle(palette.faint)
                        .help("Disabled account, showing cached quota when available")
                }
                if account.isStale {
                    Text("STALE")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.warning)
                }
            }
            .frame(height: QuotaMeterLayout.accountHeadingHeight)
            if account.windows.isEmpty {
                Text(account.active ? "Quota not available" : "No cached quota available")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.muted)
                    .padding(.leading, 22)
                    .frame(height: 20, alignment: .leading)
            } else {
                QuotaWindowMeters(windows: account.windows, showUsed: showUsed, inactive: !account.active)
                    .padding(.leading, 22)
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

private struct ArrangementSettings: View {
    @Environment(\.trayPalette) private var palette
    @ObservedObject var store: QuotaStore

    private var groups: [QuotaProviderGroup] { store.settingsGroups }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("Uncheck to hide · arrows to reorder")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.muted)
                Spacer(minLength: 0)
                Button("Reset order") { store.resetDisplayOrder() }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.muted)
                    .help("Reset provider and account order; keep visibility choices")
            }
            .padding(.bottom, 3)

            if groups.isEmpty {
                Text("Connected accounts will appear here after a refresh.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.muted)
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
                                    .foregroundStyle(palette.faint)
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
                    Rectangle().fill(palette.border).frame(height: 1)
                }
            }
        }
    }

    private func moveButton(_ symbol: String, _ title: String, disabled: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(disabled ? palette.faint.opacity(0.4) : palette.muted)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The alert selection is intentionally separate from popover visibility and
/// always lists every configured connection (including disabled or hidden).
private struct MenuBarMonitorSettings: View {
    @Environment(\.trayPalette) private var palette
    @ObservedObject var store: QuotaStore

    private var groups: [QuotaProviderGroup] { store.settingsGroups }
    private var preferences: QuotaMenuPreferences { store.menuPreferences }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Providers include every account, even disabled or future connections. For a smaller selection, check individual accounts instead.")
                .font(.system(size: 10))
                .foregroundStyle(palette.muted)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        ProviderMark(provider: group.providerID, server: store.address)
                        Toggle(isOn: Binding(
                            get: { store.menuPreferences.selectedProviders.contains(group.id) },
                            set: { store.monitorProvider(group.id, selected: $0) }
                        )) {
                            Text(group.providerName)
                                .font(.system(size: 11.5, weight: .semibold))
                                .lineLimit(1)
                        }
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("Monitor all \(group.providerName) accounts")
                    }

                    ForEach(group.accounts) { account in
                        HStack(spacing: 5) {
                            Toggle(isOn: Binding(
                                get: { store.menuPreferences.monitors(account) },
                                set: { store.monitorAccount(account, selected: $0) }
                            )) {
                                Text(account.name)
                                    .font(.system(size: 10.5))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .toggleStyle(.checkbox)
                            .controlSize(.small)
                            .disabled(store.menuPreferences.selectedProviders.contains(group.id))
                            .help(account.name)

                            if !account.active {
                                Text("OFF")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(palette.faint)
                                    .help("Disabled accounts can be monitored using their cached quotas")
                            }
                        }
                        .padding(.leading, 20)
                    }
                }
                .padding(.vertical, 3)
                if group.id != groups.last?.id {
                    Rectangle().fill(palette.border).frame(height: 1)
                }
            }

            if groups.isEmpty {
                Text("Configured accounts will appear after connecting to OmniRoute.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.muted)
            } else if preferences.monitoredAccounts(from: store.accounts).isEmpty {
                Text("Select at least one account or provider to enable quota warnings.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.warning)
            } else {
                Text("\(preferences.monitoredAccounts(from: store.accounts).count) accounts monitored")
                    .font(.system(size: 10))
                    .foregroundStyle(palette.faint)
            }
        }
    }
}

/// Five tap targets with accurate palette miniatures; each selection updates
/// the entire popover immediately and persists through @AppStorage.
private struct ThemeSelector: View {
    @Binding var selection: QuotaTheme
    @Environment(\.trayPalette) private var palette

    var body: some View {
        HStack(spacing: 5) {
            ForEach(QuotaTheme.allCases) { option in
                let preview = option.palette
                Button {
                    selection = option
                } label: {
                    VStack(spacing: 5) {
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 5)
                                .fill(preview.background)
                            VStack(alignment: .leading, spacing: 6) {
                                Capsule()
                                    .fill(preview.text)
                                    .frame(width: 19, height: 3)
                                HStack(spacing: 3) {
                                    Capsule()
                                        .fill(preview.good)
                                        .frame(width: 19, height: 4)
                                    Capsule()
                                        .fill(preview.warning)
                                        .frame(width: 9, height: 4)
                                }
                            }
                            .padding(.leading, 6)
                        }
                        .frame(height: 34)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(preview.border, lineWidth: 1)
                        )

                        Text(option.displayName)
                            .font(.system(size: 9, weight: selection == option ? .semibold : .medium))
                            .foregroundStyle(palette.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity)
                    .background(selection == option ? palette.accent.opacity(0.16) : palette.raised,
                                in: RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(selection == option ? palette.accent : palette.border,
                                    lineWidth: selection == option ? 1.5 : 1)
                    )
                }
                .buttonStyle(.plain)
                .help("Use \(option.displayName) theme")
                .accessibilityLabel("\(option.displayName) theme")
                .accessibilityValue(selection == option ? "Selected" : "Not selected")
            }
        }
    }
}

private struct SettingsView: View {
    @Environment(\.trayPalette) private var palette
    @ObservedObject var store: QuotaStore
    @State private var address: String
    @State private var apiKey: String
    @State private var cliToken: String
    @State private var saveError: String?

    @Binding private var selectedTheme: QuotaTheme

    init(store: QuotaStore, selectedTheme: Binding<QuotaTheme>) {
        self.store = store
        _selectedTheme = selectedTheme
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
                        Label(store.showingTimeline ? "Back to Timeline" : "Back to Usage", systemImage: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(palette.bad)
                    Text("Settings")
                        .font(.system(size: 13, weight: .bold))
                }
                .padding(.bottom, 4)
                Rectangle().fill(palette.border).frame(height: 1)

                sectionTitle("THEME")
                ThemeSelector(selection: $selectedTheme)

                sectionTitle("CONNECTION")
                TextField("127.0.0.1:20128", text: $address)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                Text("Only localhost is permitted. Your quota data stays on this Mac.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.muted)

                sectionTitle("MENU BAR ICON")
                Picker("Menu-bar icon mode", selection: $store.menuPreferences.mode) {
                    Text("Static").tag(QuotaMenuMode.staticIcon)
                    Text("Dynamic").tag(QuotaMenuMode.dynamic)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if store.menuPreferences.mode == .staticIcon {
                    Text("Always show the OmniRoute icon, without quota percentages or warnings.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(palette.muted)
                } else {
                    Picker("Monitor", selection: $store.menuPreferences.scope) {
                        Text("All active").tag(QuotaMonitorScope.allActive)
                        Text("Custom").tag(QuotaMonitorScope.selected)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    if store.menuPreferences.scope == .selected {
                        MenuBarMonitorSettings(store: store)
                    } else {
                        Text("Alerts reflect the lowest quota across active accounts. Use Custom to choose specific providers, accounts, or disabled connections.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

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
                    .foregroundStyle(palette.muted)
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
                    .foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("CLI token override")
                    .font(.system(size: 11))
                SecureField("Derived automatically", text: $cliToken)
                    .textFieldStyle(.roundedBorder)
                Text("Only needed when your OmniRoute installation uses a custom CLI token.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(palette.muted)

                if let saveError {
                    Text(saveError)
                        .font(.system(size: 11))
                        .foregroundStyle(palette.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack {
                    Button("Quit app") { NSApplication.shared.terminate(nil) }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.muted)
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
            .foregroundStyle(palette.faint)
            .padding(.top, 3)
    }
}
#endif
