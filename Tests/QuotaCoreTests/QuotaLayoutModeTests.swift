import XCTest
@testable import QuotaCore

final class QuotaLayoutModeTests: XCTestCase {
    func testOnlyApprovedLayoutsAreAvailableAndFullWidthIsTheDefault() {
        XCTAssertEqual(QuotaLayoutMode.allCases, [.fullWidthRows, .quotaLedger])
        XCTAssertEqual(QuotaLayoutMode.defaultMode, .fullWidthRows)
        XCTAssertEqual(QuotaLayoutMode.fullWidthRows.displayName, "Full-width rows")
        XCTAssertEqual(QuotaLayoutMode.quotaLedger.displayName, "Quota ledger")
        XCTAssertNil(QuotaLayoutMode(rawValue: "inline-accounts"))
        XCTAssertNil(QuotaLayoutMode(rawValue: "unknown"))
    }

    func testLayoutsHaveStableDistinctPersistenceValues() throws {
        XCTAssertEqual(QuotaLayoutMode.fullWidthRows.rawValue, "full-width-rows")
        XCTAssertEqual(QuotaLayoutMode.quotaLedger.rawValue, "quota-ledger")
        for mode in QuotaLayoutMode.allCases {
            let restored = try JSONDecoder().decode(QuotaLayoutMode.self, from: JSONEncoder().encode(mode))
            XCTAssertEqual(restored, mode)
            XCTAssertEqual(mode.id, mode.rawValue)
            XCTAssertFalse(mode.detail.isEmpty)
        }
    }
}
