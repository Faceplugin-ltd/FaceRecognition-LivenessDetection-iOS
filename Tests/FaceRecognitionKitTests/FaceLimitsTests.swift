import XCTest
@testable import FaceRecognitionKit

/// The thresholds decide what the capture guide, identify and the attribute screen all report,
/// so the boundaries are pinned here.
final class FaceLimitsTests: XCTestCase {

    private let limits = FaceLimits(match: 0.80, liveness: 0.50, yaw: 20, roll: 20, pitch: 20)

    func testScoreOnTheLivenessThresholdIsLive() {
        XCTAssertTrue(limits.isLive(0.50))
        XCTAssertTrue(limits.isLive(0.51))
        XCTAssertFalse(limits.isLive(0.49))
    }

    func testLivenessThatWasNeverScoredIsNotLive() {
        XCTAssertFalse(limits.isLive(Float.nan))
    }

    func testScoreOnTheMatchThresholdIsTheSamePerson() {
        XCTAssertTrue(limits.matches(0.80))
        XCTAssertFalse(limits.matches(0.79))
    }

    func testPoseIsCheckedInBothDirections() {
        XCTAssertTrue(limits.poseOk(yaw: 20, roll: -20, pitch: 0))
        XCTAssertFalse(limits.poseOk(yaw: -20.5, roll: 0, pitch: 0))
        XCTAssertFalse(limits.poseOk(yaw: 0, roll: 0, pitch: 25))
    }

    func testEachAngleHasItsOwnLimit() {
        let narrowYaw = FaceLimits(yaw: 5, roll: 40, pitch: 40)
        XCTAssertFalse(narrowYaw.poseOk(yaw: 10, roll: 0, pitch: 0))
        XCTAssertTrue(narrowYaw.poseOk(yaw: 0, roll: 30, pitch: 30))
    }

    func testTheDefaultIsTheEngineOperatingPoint() {
        XCTAssertEqual(FaceLimits.default.match, 0.80, accuracy: 0)
        XCTAssertEqual(FaceLimits.default.liveness, 0.50, accuracy: 0)
    }
}
