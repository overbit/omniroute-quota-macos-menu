import XCTest
import Network
@testable import QuotaCore

/// Synthetic allowlisted metadata, modeled on RequestTimeline.utils.ts and
/// buildCallLogListRows in the adjacent OmniRoute reference source.
final class TimelineTests: XCTestCase {
    let now = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")!

    func parse(_ text: String) throws -> [TimelineRequest] { try TimelineParser.parse(Data(text.utf8)) }
    func row(_ id: String = "a", timestamp: String = "2026-10-27T11:59:50Z", extra: String = "") throws -> TimelineRequest {
        try parse("[{\"id\":\"\(id)\",\"timestamp\":\"\(timestamp)\"\(extra)}]")[0]
    }

    func testArrayEnvelopeAndMalformedSiblings() throws {
        XCTAssertEqual(try parse("[]"), [])
        for bad in ["{}", "null", "{\"logs\":[]}", "[", "true", "<html>login</html>"] {
            XCTAssertThrowsError(try parse(bad))
        }
        let rows = try parse(#"[null,3,{}, {"id":"","timestamp":"2026-10-27T12:00:00Z"}, {"id":"bad","timestamp":"yesterday"}, {"id":"ok","timestamp":"2026-10-27T12:00:00.123Z","provider":null,"model":null,"duration":null,"active":null,"completed":null}]"#)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].provider, "Unknown provider")
        XCTAssertEqual(rows[0].model, "Unknown model")
        XCTAssertNil(rows[0].duration)
        XCTAssertNil(rows[0].status)
        XCTAssertFalse(rows[0].active)
        XCTAssertEqual(rows[0].statusText, "Unknown")
    }

    func testOnlyRequiredMetadataIsRetainedAndLabelsAreBoundedPlainText() throws {
        let rows = try parse(#"[{"id":"safe","timestamp":"2026-10-27T12:00:00Z","provider":"test\nprovider\u202E","model":"<b>plain</b>","account":"FAKE_PRIVATE_ACCOUNT","error":"FAKE_PRIVATE_ERROR","body":"FAKE_PRIVATE_BODY","headers":{"Authorization":"FAKE_PRIVATE_HEADER"},"apiKeyName":"FAKE_PRIVATE_KEY","sessionTag":"FAKE_PRIVATE_TAG"}]"#)
        XCTAssertEqual(rows[0].provider, "testprovider")
        XCTAssertEqual(rows[0].model, "<b>plain</b>")
        XCTAssertFalse(String(reflecting: rows).contains("FAKE_PRIVATE"))
        let long = try row(extra: ",\"model\":\"\(String(repeating: "x", count: 500))\"")
        XCTAssertEqual(long.model.count, 80)
        XCTAssertTrue(try parse("[{\"id\":\"\(String(repeating: "x", count: 257))\",\"timestamp\":\"2026-10-27T12:00:00Z\"}]").isEmpty)
    }

    func testActiveCompletedHistoricalIntervalsAndStatus() throws {
        let active = try row(extra: #", "active":true,"status":0,"duration":10000"#)
        let complete = try row(extra: #", "completed":true,"status":200,"duration":2000"#)
        let historical = try row(extra: #", "status":500,"duration":2000"#)
        XCTAssertEqual(active.start, now.addingTimeInterval(-10))
        XCTAssertEqual(active.end(at: now), now)
        XCTAssertEqual(active.end(at: now.addingTimeInterval(3)), now.addingTimeInterval(3))
        XCTAssertEqual(active.statusText, "In progress")
        XCTAssertEqual(complete.start, now.addingTimeInterval(-10))
        XCTAssertEqual(complete.end(at: now), now.addingTimeInterval(-8))
        XCTAssertEqual(complete.end(at: now.addingTimeInterval(99)), complete.end(at: now))
        XCTAssertEqual(complete.statusText, "Success · 200")
        XCTAssertEqual(historical.start, now.addingTimeInterval(-12))
        XCTAssertEqual(historical.end(at: now), now.addingTimeInterval(-10))
        XCTAssertEqual(historical.statusText, "Failed · 500")
        XCTAssertEqual(try row(extra: #", "status":0"#).statusText, "Unknown")
        XCTAssertFalse(try row(extra: #", "active":1"#).active)
        XCTAssertNil(try row(extra: #", "status":true"#).status)
    }

    func testUnavailableNegativeInvalidDurationsAndSafeFutureGeometry() throws {
        for extra in ["", #", "duration":null"#, #", "duration":-1"#, #", "duration":"Infinity""#, #", "duration":true"#] {
            let item = try row(extra: extra)
            XCTAssertNil(item.duration)
            XCTAssertEqual(item.start, item.end(at: now))
            XCTAssertEqual(item.durationText(at: now), "Duration unavailable")
        }
        for timestamp in ["2026-10-27T12:10:00Z", "2026-10-27T11:00:00Z"] {
            let item = try row(timestamp: timestamp, extra: #", "active":true"#)
            let mark = item.mark(at: now)
            XCTAssertTrue((0...1).contains(mark.offset))
            XCTAssertTrue((0...1).contains(mark.width))
            XCTAssertLessThanOrEqual(mark.offset + mark.width, 1)
        }
        XCTAssertEqual(try row(extra: #", "duration":1e100"#).duration, 86_400)
        XCTAssertEqual(try row(extra: #", "duration":25"#).durationText(at: now), "25 ms")
    }

    func testDeduplicationCompletionUpdateTieOrderAndAuthoritativeRemoval() throws {
        var snapshot = TimelineSnapshot()
        let active = try row(extra: #", "active":true"#)
        let complete = try row(extra: #", "completed":true,"duration":1000,"status":200"#)
        snapshot.receive([active], at: now)
        snapshot.receive([complete, active, try row("b", extra: #", "completed":true"#)], at: now)
        XCTAssertEqual(snapshot.rows.map(\.id), ["a", "b"])
        XCTAssertEqual(snapshot.rows.first, complete)
        snapshot.receive([active], at: now)
        snapshot.receive([], at: now)
        XCTAssertTrue(snapshot.rows.isEmpty)
    }

    func testFiveMinuteEvictionFutureFilteringAndCapAfterDeduplication() throws {
        var snapshot = TimelineSnapshot()
        let old = try row("old", timestamp: "2026-10-27T11:54:59Z")
        let overlap = try row("overlap", timestamp: "2026-10-27T11:54:59Z", extra: #", "completed":true,"duration":2000"#)
        let future = try row("future", timestamp: "2026-10-27T12:10:00Z")
        snapshot.receive([old, overlap, future], at: now)
        XCTAssertEqual(snapshot.rows.map(\.id), ["overlap"])
        XCTAssertEqual(overlap.mark(at: now).offset, 0)
        XCTAssertEqual(overlap.mark(at: now).width, 1.0 / 300, accuracy: 0.00001)
        let many = try (0..<150).map { try row(String(format: "%03d", $0)) }
        snapshot.receive(many + many, at: now)
        XCTAssertEqual(snapshot.rows.count, 100)
        XCTAssertEqual(snapshot.rows.first?.id, "000")
        XCTAssertEqual(snapshot.rows.last?.id, "099")
        snapshot.prune(at: now.addingTimeInterval(301))
        XCTAssertTrue(snapshot.rows.isEmpty)
    }

    func testStaleActiveRequestsStopGrowingAndEventuallyExpire() throws {
        var snapshot = TimelineSnapshot()
        let active = try row(extra: #", "active":true"#)
        snapshot.receive([active], at: now)
        snapshot.fail(.unavailable)
        let later = now.addingTimeInterval(10)
        let frozen = active.mark(at: later, activeUntil: snapshot.lastUpdated)
        XCTAssertEqual(frozen.width, 10.0 / 300, accuracy: 0.00001)
        snapshot.prune(at: now.addingTimeInterval(301))
        XCTAssertTrue(snapshot.rows.isEmpty)
        XCTAssertEqual(snapshot.failure, .unavailable)
        snapshot.receive([active], at: later)
        XCTAssertNil(snapshot.failure)
        XCTAssertEqual(snapshot.rows.count, 1)
        XCTAssertEqual(active.mark(at: later).width, 20.0 / 300, accuracy: 0.00001)
    }

    func testFailedPollPreservesLastGoodAndSuccessRecovers() throws {
        var snapshot = TimelineSnapshot()
        snapshot.fail(.unavailable)
        XCTAssertNil(snapshot.lastUpdated)
        snapshot.receive([try row()], at: now)
        let good = snapshot.rows
        snapshot.fail(.authenticationRequired)
        XCTAssertEqual(snapshot.rows, good)
        XCTAssertEqual(snapshot.lastUpdated, now)
        XCTAssertEqual(snapshot.failure, .authenticationRequired)
        snapshot.receive([], at: now.addingTimeInterval(2))
        XCTAssertNil(snapshot.failure)
        XCTAssertNotNil(snapshot.lastUpdated)
        XCTAssertTrue(snapshot.rows.isEmpty)
    }
}

private final class TimelineProtocol: URLProtocol {
    static var handler: ((URLRequest, TimelineProtocol) -> Void)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, self) }
    override func stopLoading() {}
    func respond(_ code: Int, body: String = "[]", type: String = "application/json") {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: ["Content-Type": type])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

final class TimelineTransportTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [TimelineProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() {
        session.invalidateAndCancel()
        TimelineProtocol.handler = nil
    }
    func testExactGETCacheAndExistingCredentialHeaders() async throws {
        TimelineProtocol.handler = { request, stub in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "http://127.0.0.1:20128/api/usage/call-logs?limit=200")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fixture-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-omniroute-cli-token"), "fixture-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            XCTAssertNil(request.httpBody)
            stub.respond(200)
        }
        let result = try await TimelineClient(session: session).load(from: OmniRouteEndpoint("127.0.0.1"), credentials: .init(apiKey: "fixture-key", cliToken: "fixture-token"))
        XCTAssertTrue(result.isEmpty)
    }
    func testHTTPAndPayloadFailuresAreGenericAndClassified() async throws {
        let cases: [(Int, String, String, TimelineFailure)] = [
            (401, "PRIVATE_SERVER_ERROR", "application/json", .authenticationRequired),
            (403, "PRIVATE_SERVER_ERROR", "application/json", .authenticationRequired),
            (302, "", "text/html", .authenticationRequired),
            (307, "", "text/html", .authenticationRequired),
            (404, "", "application/json", .unsupported),
            (500, "PRIVATE_SERVER_ERROR", "application/json", .unavailable),
            (200, "{}", "application/json", .unavailable),
            (200, "not json", "application/json", .unavailable),
            (200, "<html>login</html>", "text/html", .authenticationRequired),
            (200, "<html>login</html>", "", .authenticationRequired)
        ]
        for (code, body, type, expected) in cases {
            TimelineProtocol.handler = { _, stub in stub.respond(code, body: body, type: type) }
            do {
                _ = try await TimelineClient(session: session).load(from: OmniRouteEndpoint("localhost"), credentials: .init())
                XCTFail("Expected failure for \(code)")
            } catch {
                XCTAssertEqual(error as? TimelineFailure, expected)
                XCTAssertFalse(expected.message.contains("PRIVATE_SERVER_ERROR"))
            }
        }
    }
    func testTimeoutConnectionRefusalAndCancellation() async throws {
        for code in [URLError.timedOut, .cannotConnectToHost, .cancelled] {
            TimelineProtocol.handler = { _, stub in stub.client?.urlProtocol(stub, didFailWithError: URLError(code)) }
            do {
                _ = try await TimelineClient(session: session).load(from: OmniRouteEndpoint("localhost"), credentials: .init())
                XCTFail("Expected failure")
            } catch {
                if code == .cancelled { XCTAssertTrue(error is CancellationError) }
                else { XCTAssertEqual(error as? TimelineFailure, .unavailable) }
            }
        }
    }
    func testTimelineFailureIsIndependentOfQuotaCacheAndSeverity() async throws {
        TimelineProtocol.handler = { request, stub in
            XCTAssertEqual(request.httpMethod, "GET")
            switch request.url!.path {
            case "/api/providers":
                stub.respond(200, body: #"[{"id":"fixture","provider":"kimi","isActive":true}]"#)
            case "/api/usage/provider-limits":
                stub.respond(200, body: #"{"caches":{"fixture":{"quotas":{"weekly":{"remainingPercentage":15}}}}}"#)
            case "/api/usage/call-logs": stub.respond(500)
            default: XCTFail("Unexpected endpoint"); stub.respond(404)
            }
        }
        let endpoint = try OmniRouteEndpoint("localhost")
        let quotaClient = OmniRouteClient(session: session)
        let accounts = try await quotaClient.load(from: endpoint, credentials: .init())
        let before = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true, connectionUnavailable: false, preferences: .init())
        var timeline = TimelineSnapshot()
        do {
            _ = try await TimelineClient(session: session).load(from: endpoint, credentials: .init())
            XCTFail("Expected timeline failure")
        } catch { timeline.fail((error as? TimelineFailure) ?? .unavailable) }
        XCTAssertEqual(timeline.failure, .unavailable)
        let reloaded = try await quotaClient.load(from: endpoint, credentials: .init())
        let after = QuotaMenuStatus.evaluate(accounts: reloaded, hasLoaded: true, connectionUnavailable: false, preferences: .init())
        XCTAssertEqual(accounts.count, 1)
        XCTAssertEqual(reloaded.first?.windows.first?.roundedRemaining, 15)
        XCTAssertEqual(before, after)
        XCTAssertEqual(after.severity, .critical)
    }

    func testSessionRejectsRedirectBeforeRequestingDestination() async throws {
        // Foundation's custom URLProtocol redirect callback traps on this SDK;
        // exercise the real URLSession redirect path with a loopback-only fixture.
        let ready = expectation(description: "loopback redirect fixture ready")
        let server = try TimelineRedirectServer()
        defer { server.listener.cancel() }
        server.listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
        }
        server.listener.start(queue: server.queue)
        await fulfillment(of: [ready], timeout: 2)
        let port = try XCTUnwrap(server.listener.port)
        let realSession = URLSession(configuration: .ephemeral)
        defer { realSession.invalidateAndCancel() }
        do {
            _ = try await TimelineClient(session: realSession).load(
                from: OmniRouteEndpoint("127.0.0.1:\(port.rawValue)"), credentials: .init(apiKey: "fixture-key"))
            XCTFail("Redirect must fail")
        } catch {
            XCTAssertEqual(error as? TimelineFailure, .authenticationRequired)
        }
        XCTAssertEqual(server.requestCount, 1)
    }

    func testRedirectDelegateRejectsSameAndCrossOriginWithoutForwarding() throws {
        let policy = TimelineRedirectPolicy()
        let origin = URL(string: "http://localhost:20128/api/usage/call-logs")!
        for destination in ["http://localhost:20128/login", "https://example.invalid/collect"] {
            let redirect = HTTPURLResponse(url: origin, statusCode: 307, httpVersion: nil, headerFields: ["Location": destination])!
            var proposed = URLRequest(url: URL(string: destination)!)
            proposed.setValue("Bearer fixture-key", forHTTPHeaderField: "Authorization")
            var called = false
            policy.urlSession(session, task: session.dataTask(with: origin), willPerformHTTPRedirection: redirect, newRequest: proposed) { accepted in
                called = true
                XCTAssertNil(accepted)
            }
            XCTAssertTrue(called)
        }
    }
}

/// Explicitly suspended transport and delay: no wall-clock sleeps, real server,
/// credentials, or provider requests are needed to exercise lifecycle races.
private actor TimelineHarness {
    var loads: [CheckedContinuation<[TimelineRequest], Error>] = []
    var delays: [CheckedContinuation<Void, Error>] = []
    var loadCount = 0
    let started: XCTestExpectation
    let sleeping: XCTestExpectation
    init(started: XCTestExpectation, sleeping: XCTestExpectation) { self.started = started; self.sleeping = sleeping }
    func load() async throws -> [TimelineRequest] {
        loadCount += 1
        started.fulfill()
        return try await withCheckedThrowingContinuation { loads.append($0) }
    }
    func sleep() async throws {
        sleeping.fulfill()
        try await withCheckedThrowingContinuation { delays.append($0) }
    }
    func resolve(_ rows: [TimelineRequest] = []) { loads.removeFirst().resume(returning: rows) }
    func fail() { loads.removeFirst().resume(throwing: TimelineFailure.unavailable) }
    func wake() { delays.removeFirst().resume() }
    func cancelDelay() { if !delays.isEmpty { delays.removeFirst().resume(throwing: CancellationError()) } }
}

@MainActor
final class TimelineLifecycleTests: XCTestCase {
    func testSerialLoopWaitsForResponseThenDelayAndRepeatedStartIsIdempotent() async throws {
        let started = expectation(description: "two loads")
        started.expectedFulfillmentCount = 2
        let sleeping = expectation(description: "delay after each result")
        sleeping.expectedFulfillmentCount = 2
        let harness = TimelineHarness(started: started, sleeping: sleeping)
        let first = expectation(description: "first response")
        let second = expectation(description: "failure isolated in timeline snapshot")
        let now = Date()
        let poller = TimelinePoller(clock: { now }, sleep: { try await harness.sleep() })
        var callbacks = 0
        poller.onChange = { snapshot in
            callbacks += 1
            if callbacks == 1 { XCTAssertNil(snapshot.failure); first.fulfill() }
            else { XCTAssertEqual(snapshot.failure, .unavailable); second.fulfill() }
        }
        poller.start { try await harness.load() }
        poller.start { XCTFail("Duplicate loop"); return [] }
        // Yield only until the controlled request is registered, not elapsed time.
        while await harness.loadCount == 0 { await Task.yield() }
        XCTAssertEqual(callbacks, 0)
        await harness.resolve()
        await fulfillment(of: [first], timeout: 2)
        while await harness.delays.isEmpty { await Task.yield() }
        let count = await harness.loadCount
        XCTAssertEqual(count, 1)
        await harness.wake()
        while await harness.loadCount < 2 { await Task.yield() }
        await harness.fail()
        await fulfillment(of: [started, second, sleeping], timeout: 2)
        poller.stop()
        await harness.cancelDelay()
    }

    func testCloseReopenConfigurationChangeRejectsLateResponseAndClearsRows() async throws {
        let started = expectation(description: "three opens")
        started.expectedFulfillmentCount = 3
        let sleeping = expectation(description: "one accepted response")
        let harness = TimelineHarness(started: started, sleeping: sleeping)
        let now = ISO8601DateFormatter().date(from: "2026-10-27T12:00:00Z")!
        let rows = try TimelineParser.parse(Data(#"[{"id":"old-origin","timestamp":"2026-10-27T11:59:59Z","active":true}]"#.utf8))
        let poller = TimelinePoller(clock: { now }, sleep: { try await harness.sleep() })
        let accepted = expectation(description: "only current response published")
        var nonemptyPublications = 0
        poller.onChange = { snapshot in
            if !snapshot.rows.isEmpty { nonemptyPublications += 1; accepted.fulfill() }
        }
        poller.start { try await harness.load() }
        while await harness.loadCount < 1 { await Task.yield() }
        poller.stop()
        poller.start { try await harness.load() }
        while await harness.loadCount < 2 { await Task.yield() }
        await harness.resolve(rows) // Non-cooperative response from the closed generation.
        await harness.resolve(rows)
        await fulfillment(of: [accepted, sleeping], timeout: 2)
        XCTAssertEqual(nonemptyPublications, 1)
        XCTAssertEqual(poller.snapshot.rows, rows)
        poller.stop(clear: true) // The app calls this before replacing endpoint/credentials.
        XCTAssertTrue(poller.snapshot.rows.isEmpty)
        XCTAssertNil(poller.snapshot.lastUpdated)
        await harness.cancelDelay()
        poller.start { try await harness.load() }
        while await harness.loadCount < 3 { await Task.yield() }
        poller.stop(clear: true)
        await harness.resolve(rows) // Late old-configuration response must not repopulate.
        await fulfillment(of: [started], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(poller.snapshot.rows.isEmpty)
        XCTAssertEqual(nonemptyPublications, 1)
    }

    func testCancellationIsNotAVisibleFailure() async {
        let poller = TimelinePoller()
        let started = expectation(description: "started")
        poller.onChange = { _ in XCTFail("Cancellation must not publish an error") }
        poller.start { started.fulfill(); throw CancellationError() }
        await fulfillment(of: [started], timeout: 2)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertNil(poller.snapshot.failure)
        poller.stop()
    }
}

/// A short-lived local fixture: never reads real service credentials or payloads.
private final class TimelineRedirectServer: @unchecked Sendable {
    let listener: NWListener
    let queue = DispatchQueue(label: "timeline.redirect-fixture")
    private let lock = NSLock()
    private var count = 0
    var requestCount: Int { lock.lock(); defer { lock.unlock() }; return count }

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] _, _, _, _ in
                guard let self else { connection.cancel(); return }
                self.lock.lock()
                self.count += 1
                self.lock.unlock()
                // If followed, this destination would cause a second local call.
                let location = "http://127.0.0.1:\(self.listener.port!.rawValue)/must-not-follow"
                let response = "HTTP/1.1 302 Found\r\nLocation: \(location)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }
}
