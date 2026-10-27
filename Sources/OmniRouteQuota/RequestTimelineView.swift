#if os(macOS)
import SwiftUI
import QuotaCore

/// Shared five-minute axis, not a per-request percentage or decorative sparkline.
struct RequestTimelineView: View {
    let snapshot: TimelineSnapshot
    @Environment(\.trayPalette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.periodic(from: .now, by: reduceMotion ? 2 : 1)) { context in
            // A failed snapshot is explicitly stale; do not pretend active rows
            // are still live by extending their marks during an outage.
            let liveThrough = snapshot.failure == nil ? context.date : (snapshot.lastUpdated ?? context.date)
            let rows = snapshot.rows.filter { $0.end(at: liveThrough) >= context.date.addingTimeInterval(-300) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("LAST 5 MINUTES")
                        Spacer()
                        Text(snapshot.failure != nil ? "Stale" : "2s updates")
                    }
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.muted)

                    if let failure = snapshot.failure {
                        Text(failure.message + (snapshot.lastUpdated == nil ? "" : " Showing last received data."))
                            .font(.system(size: 11))
                            .foregroundStyle(palette.warning)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if snapshot.lastUpdated == nil && snapshot.failure == nil {
                        Text("Reading recent requests…")
                            .font(.system(size: 12))
                    } else if rows.isEmpty && snapshot.failure == nil {
                        Text("No recent requests")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Proxy activity will appear here automatically.")
                            .font(.system(size: 11))
                            .foregroundStyle(palette.muted)
                    }
                    if !rows.isEmpty {
                        HStack {
                            Text("−5m")
                            Spacer()
                            Text("Now")
                        }
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(palette.faint)
                        ForEach(rows) { row in
                            timelineRow(row, now: context.date, liveThrough: liveThrough)
                        }
                    }
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func timelineRow(_ row: TimelineRequest, now: Date, liveThrough: Date) -> some View {
        let mark = row.mark(at: now, activeUntil: liveThrough)
        let color = row.active ? palette.accent : ((200..<300).contains(row.status ?? 0) ? palette.good : ((400..<600).contains(row.status ?? 0) ? palette.bad : palette.muted))
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Text(row.provider).fontWeight(.semibold)
                Text(row.model).foregroundStyle(palette.muted)
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.middle)
            HStack(spacing: 4) {
                Text(row.startTimeLabel)
                Spacer(minLength: 2)
                Text(row.statusText).foregroundStyle(color)
                Text(row.durationText(at: liveThrough)).foregroundStyle(palette.muted)
            }
            .font(.system(size: 9).monospacedDigit())
            .lineLimit(1)
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.border).frame(height: 1)
                    if mark.width > 0 {
                        Capsule().fill(color)
                            .frame(width: width * mark.width, height: 4)
                            .offset(x: width * mark.offset)
                    }
                }
                .frame(height: 4)
            }
            .frame(height: 4)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.provider), \(row.model), \(row.startTimeLabel), \(row.statusText), \(row.durationText(at: liveThrough))")
    }
}
#endif
