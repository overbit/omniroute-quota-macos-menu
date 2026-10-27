import Foundation
import CoreFoundation

public enum TimelineFailure: Error, Equatable, Sendable {
    case authenticationRequired, unsupported, unavailable

    public var message: String {
        switch self {
        case .authenticationRequired: return "Timeline authentication required. Check Settings."
        case .unsupported: return "Timeline unavailable on this OmniRoute version."
        case .unavailable: return "Timeline unavailable. Reconnecting…"
        }
    }
}

/// Deliberately excludes account identity, paths, bodies and all debug metadata.
public struct TimelineRequest: Identifiable, Equatable, Sendable {
    public let id: String
    public let timestamp: Date
    public let provider: String
    public let model: String
    public let status: Int?
    public let duration: TimeInterval?
    public let active: Bool
    public let completed: Bool

    public var start: Date {
        active || completed ? timestamp : timestamp.addingTimeInterval(-(duration ?? 0))
    }

    /// All row types display the derived local start, never an unlabeled event time.
    public var startTimeLabel: String { "Start \(start.formatted(date: .omitted, time: .standard))" }

    public func end(at now: Date) -> Date {
        if active { return max(timestamp, now) }
        return completed ? timestamp.addingTimeInterval(duration ?? 0) : timestamp
    }

    public var statusText: String {
        if active { return "In progress" }
        guard let status else { return "Unknown" }
        if (200..<300).contains(status) { return "Success · \(status)" }
        if (400..<600).contains(status) { return "Failed · \(status)" }
        return "Unknown"
    }

    public func durationText(at now: Date) -> String {
        let seconds = active ? max(0, now.timeIntervalSince(timestamp)) : duration
        guard let seconds else { return "Duration unavailable" }
        return seconds < 1 ? String(format: "%.0f ms", seconds * 1000) : String(format: "%.1f s", min(seconds, 86_400))
    }

    /// Normalized coordinates, bounded even for future or zero-length intervals.
    public func mark(at now: Date, activeUntil: Date? = nil) -> (offset: Double, width: Double) {
        let lower = now.addingTimeInterval(-300)
        let left = min(1, max(0, start.timeIntervalSince(lower) / 300))
        let right = min(1, max(left, end(at: activeUntil ?? now).timeIntervalSince(lower) / 300))
        return (left, right - left)
    }
}

public enum TimelineParser {
    public static func parse(_ data: Data) throws -> [TimelineRequest] {
        guard let array = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else {
            throw TimelineFailure.unavailable
        }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        return array.compactMap { value in
            guard let row = value as? [String: Any], let id = row["id"] as? String,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, id.count <= 256,
                  let time = row["timestamp"] as? String, time.count <= 64,
                  let timestamp = fractional.date(from: time) ?? plain.date(from: time) else { return nil }
            func number(_ key: String) -> Double? {
                guard let n = row[key] as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
                      n.doubleValue.isFinite else { return nil }
                return n.doubleValue
            }
            func flag(_ key: String) -> Bool {
                guard let n = row[key] as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return false }
                return n.boolValue
            }
            func label(_ key: String) -> String {
                guard let value = row[key] as? String else { return "Unknown \(key)" }
                let safe = String(String.UnicodeScalarView(value.unicodeScalars.filter {
                    !CharacterSet.controlCharacters.contains($0) && !CharacterSet(charactersIn: "\u{202A}\u{202B}\u{202C}\u{202D}\u{202E}\u{2066}\u{2067}\u{2068}\u{2069}").contains($0)
                }).prefix(80)).trimmingCharacters(in: .whitespacesAndNewlines)
                return safe.isEmpty ? "Unknown \(key)" : safe
            }
            let milliseconds = number("duration")
            let duration = milliseconds.flatMap { $0 >= 0 ? min($0 / 1000, 86_400) : nil }
            let status = number("status").flatMap { $0 >= 0 && $0 <= 599 && $0.rounded() == $0 ? Int($0) : nil }
            return TimelineRequest(id: id, timestamp: timestamp, provider: label("provider"), model: label("model"),
                                   status: status, duration: duration, active: flag("active"), completed: flag("completed"))
        }
    }
}

public struct TimelineSnapshot: Equatable, Sendable {
    public private(set) var rows: [TimelineRequest] = []
    public private(set) var lastUpdated: Date?
    public private(set) var failure: TimelineFailure?
    public init() {}

    public mutating func receive(_ incoming: [TimelineRequest], at now: Date) {
        // Each successful response is authoritative, including vanished active IDs.
        var unique: [String: TimelineRequest] = [:]
        for row in incoming {
            // Prefer the completed representation if a merged response repeats an ID.
            if let existing = unique[row.id], !existing.active && row.active { continue }
            unique[row.id] = row
        }
        rows = Array(unique.values)
        failure = nil
        lastUpdated = now
        prune(at: now)
    }

    public mutating func prune(at now: Date) {
        // Retain active rows only while their last server acknowledgement is recent,
        // even if a subsequent request stalls without returning an error.
        let liveThrough = lastUpdated ?? now
        rows = Array(rows.filter {
            $0.start <= now && $0.end(at: liveThrough) >= now.addingTimeInterval(-300)
        }.sorted {
            $0.start == $1.start ? $0.id < $1.id : $0.start > $1.start
        }.prefix(100))
    }

    public mutating func fail(_ failure: TimelineFailure) { self.failure = failure }
}

/// One serial loop per visible surface. Generation checks reject late responses
/// even when an injected transport does not cooperate with task cancellation.
@MainActor
public final class TimelinePoller {
    public typealias Load = @Sendable () async throws -> [TimelineRequest]
    public typealias Sleep = @Sendable () async throws -> Void
    public private(set) var snapshot = TimelineSnapshot()
    public var onChange: ((TimelineSnapshot) -> Void)?
    private var task: Task<Void, Never>?
    private var retentionTask: Task<Void, Never>?
    private var generation = 0
    private let clock: @Sendable () -> Date
    private let sleep: Sleep
    private let retentionSleep: Sleep

    public init(clock: @escaping @Sendable () -> Date = { Date() },
                sleep: @escaping Sleep = { try await Task.sleep(for: .seconds(2)) },
                retentionSleep: @escaping Sleep = { try await Task.sleep(for: .seconds(1)) }) {
        self.clock = clock
        self.sleep = sleep
        self.retentionSleep = retentionSleep
    }

    public func start(load: @escaping Load) {
        guard task == nil else { return }
        generation += 1
        let current = generation
        // Independent local maintenance: a hung transport must not retain old data.
        // This clock exists only while Timeline is visible, never in hidden mode.
        retentionTask = Task { [weak self, retentionSleep] in
            while !Task.isCancelled {
                do { try await retentionSleep() } catch { return }
                guard let self, self.generation == current, !Task.isCancelled else { return }
                let previous = self.snapshot
                self.snapshot.prune(at: self.clock())
                if self.snapshot != previous { self.onChange?(self.snapshot) }
            }
        }
        task = Task { [weak self, sleep] in
            defer {
                if let self, self.generation == current {
                    self.stop()
                }
            }
            while !Task.isCancelled {
                do {
                    let rows = try await load()
                    guard let self, self.generation == current, !Task.isCancelled else { return }
                    self.snapshot.receive(rows, at: self.clock())
                    self.onChange?(self.snapshot)
                } catch {
                    guard let self, self.generation == current, !Task.isCancelled else { return }
                    if error is CancellationError || (error as? URLError)?.code == .cancelled { return }
                    self.snapshot.fail((error as? TimelineFailure) ?? .unavailable)
                    self.snapshot.prune(at: self.clock())
                    self.onChange?(self.snapshot)
                }
                do { try await sleep() } catch { return }
            }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
        retentionTask?.cancel()
        retentionTask = nil
        if snapshot != TimelineSnapshot() {
            snapshot = TimelineSnapshot()
            onChange?(snapshot)
        }
    }

    deinit { task?.cancel(); retentionTask?.cancel() }
}
