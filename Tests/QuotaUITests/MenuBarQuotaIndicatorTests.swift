#if os(macOS)
import AppKit
import SwiftUI
import Vision
import XCTest
@testable import OmniRouteQuota
@testable import QuotaCore

final class MenuBarQuotaIndicatorTests: XCTestCase {
    @MainActor
    func testLowIndicatorRendersThreePercentagesVerticallyWithTrailingAlignment() throws {
        let status = makeStatus([35.9, 8.9, 23.9, 72])
        let observations = try percentageObservations(in: render(MenuBarQuotaIndicator(status: status), scale: 4))
        XCTAssertEqual(observations.map(\.text), ["8%", "23%", "35%"])

        let rightEdges = observations.map { $0.boundingBox.maxX }
        XCTAssertEqual(rightEdges.count, 3)
        for edge in rightEdges.dropFirst() {
            XCTAssertEqual(edge, rightEdges[0], accuracy: 0.03)
        }
    }

    @MainActor
    func testIndicatorSizesToVisibleRowsAndWidestPercentage() throws {
        let oneRow = try render(MenuBarQuotaIndicator(status: makeStatus([8])))
        let twoRows = try render(MenuBarQuotaIndicator(status: makeStatus([23, 35])))
        let threeRows = try render(MenuBarQuotaIndicator(status: makeStatus([8, 23, 35])))
        let widerThreeRows = try render(MenuBarQuotaIndicator(status: makeStatus([8, 23, 100])))

        XCTAssertLessThanOrEqual(oneRow.height, twoRows.height)
        XCTAssertLessThan(twoRows.height, threeRows.height)
        XCTAssertLessThanOrEqual(threeRows.height, 22, "Three rows must fit the standard menu-bar height")
        XCTAssertLessThan(oneRow.width, twoRows.width)
        XCTAssertEqual(twoRows.width, threeRows.width)
        XCTAssertLessThan(threeRows.width, widerThreeRows.width)
    }

    @MainActor
    func testHealthyStaticAndUnknownStatesDoNotRenderPercentages() throws {
        var staticPreferences = QuotaMenuPreferences()
        staticPreferences.mode = .staticIcon
        let accounts = makeAccounts([8, 23, 35])
        let statuses = [
            makeStatus([75]),
            QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true, connectionUnavailable: false,
                                     preferences: staticPreferences),
            QuotaMenuStatus.evaluate(accounts: [], hasLoaded: true, connectionUnavailable: false)
        ]

        for status in statuses {
            let image = try render(MenuBarQuotaIndicator(status: status), scale: 4)
            XCTAssertTrue(try percentageObservations(in: image).isEmpty)
        }
    }

    @MainActor
    func testRenderIndicatorStatesForVisualReview() throws {
        guard let path = ProcessInfo.processInfo.environment["QUOTA_MENU_BAR_SNAPSHOT_DIR"] else { return }
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let states = [
            ("one-row", makeStatus([8])),
            ("two-rows", makeStatus([23, 35])),
            ("three-rows", makeStatus([8, 23, 35])),
            ("healthy", makeStatus([75]))
        ]
        for (name, status) in states {
            let image = try render(MenuBarQuotaIndicator(status: status), scale: 4)
            let bitmap = NSBitmapImageRep(cgImage: image)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: directory.appendingPathComponent("menu-bar-\(name).png"))
        }
    }

    private func makeStatus(_ values: [Double]) -> QuotaMenuStatus {
        QuotaMenuStatus.evaluate(accounts: makeAccounts(values), hasLoaded: true, connectionUnavailable: false)
    }

    private func makeAccounts(_ values: [Double]) -> [QuotaAccount] {
        values.enumerated().map { index, value in
            QuotaAccount(id: "account-\(index)", name: "Account \(index)", provider: "openai", active: true,
                         windows: [QuotaWindow(id: "week", label: "wk", remainingPercent: value,
                                               resetAt: nil)], isStale: false)
        }
    }

    @MainActor
    private func render(_ view: MenuBarQuotaIndicator, scale: CGFloat = 1) throws -> CGImage {
        let renderer = ImageRenderer(content: view.background(Color.white))
        renderer.scale = scale
        return try XCTUnwrap(renderer.cgImage, "SwiftUI could not render the menu-bar indicator")
    }

    private func percentageObservations(in image: CGImage) throws -> [(text: String, boundingBox: CGRect)] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0
        try VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let text = observation.topCandidates(1).first?.string
                .filter({ $0.isNumber || $0 == "%" }), text.contains("%") else { return nil }
            return (text: text, boundingBox: observation.boundingBox)
        }
        .sorted { $0.boundingBox.midY > $1.boundingBox.midY }
    }
}
#endif
