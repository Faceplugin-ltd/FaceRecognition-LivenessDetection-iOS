import XCTest
@testable import FaceRecognitionApp

final class FaceRecognitionSDKTests: XCTestCase {
    func testAppSettingsDefaults() {
        AppSettings.reset()
        XCTAssertEqual(AppSettings.livenessThreshold, 0.50, accuracy: 0.001)
        XCTAssertEqual(AppSettings.threshold, 0.80, accuracy: 0.001)
        XCTAssertEqual(AppSettings.yaw, 20, accuracy: 0.001)
        XCTAssertEqual(AppSettings.roll, 20, accuracy: 0.001)
        XCTAssertEqual(AppSettings.pitch, 20, accuracy: 0.001)
        XCTAssertFalse(AppSettings.livenessOn)
    }

    func testLivenessLimit() {
        AppSettings.reset()
        XCTAssertTrue(AppSettings.limits.isLive(0.50))
        XCTAssertFalse(AppSettings.limits.isLive(0.49))
        XCTAssertFalse(AppSettings.limits.isLive(Float.nan))
    }
}
