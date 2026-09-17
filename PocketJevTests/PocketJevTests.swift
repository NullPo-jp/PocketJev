import XCTest
@testable import PocketJev

final class PocketJevTests: XCTestCase {
    func testSoftmaxNormalizes() {
        let values = DecisionMath.softmax([1, 2, 3])
        XCTAssertEqual(values.reduce(0, +), 1, accuracy: 0.000001)
        XCTAssertGreaterThan(values[2], values[1])
        XCTAssertGreaterThan(values[1], values[0])
    }

    func testDefaultPresetIsYesNoUnknown() {
        XCTAssertEqual(OptionPreset.yesNoUnknown.options, ["YES", "NO", "判別不能"])
        XCTAssertEqual(OptionPreset.yesNoUnknown.name, "YES / NO / 判別不能")
    }
}
