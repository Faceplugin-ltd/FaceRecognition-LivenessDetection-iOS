import XCTest
@testable import FaceRecognitionKit

/// A report is stored with every enrolled person, so it has to survive a round trip as JSON.
final class CallReportTests: XCTestCase {

    private let report = CallReport(
        function: "enroll",
        steps: [
            CallStep(name: "faceDetection", ms: 12.5, detail: "1 face"),
            CallStep(name: "templateExtraction", ms: 30.0, detail: "1040 bytes"),
            CallStep(name: "duplicateCheck", ms: 2.25, detail: "gallery empty", ok: false),
        ],
        progress: "3 of 3 · saved",
        detail: "Saved Mina as ID 7",
        success: true,
        finishedAt: 1_700_000_000_000
    )

    func testTotalTimeIsTheSumOfTheSteps() {
        XCTAssertEqual(report.totalMs, 44.75, accuracy: 1e-9)
    }

    func testAReportSurvivesARoundTrip() throws {
        let back = try XCTUnwrap(CallReport.fromJson(report.toJson()))
        XCTAssertEqual(back.function, report.function)
        XCTAssertEqual(back.progress, report.progress)
        XCTAssertEqual(back.detail, report.detail)
        XCTAssertEqual(back.success, report.success)
        XCTAssertEqual(back.finishedAt, report.finishedAt, accuracy: 1e-6)
        XCTAssertEqual(back.steps.count, report.steps.count)
    }

    func testAFailedStepStaysFailed() throws {
        let back = try XCTUnwrap(CallReport.fromJson(report.toJson()))
        XCTAssertTrue(back.steps[0].ok)
        XCTAssertFalse(back.steps[2].ok)
        XCTAssertEqual(back.steps[2].detail, "gallery empty")
    }

    func testPeopleEnrolledBeforeReportsWereStoredReadBackAsNone() {
        XCTAssertNil(CallReport.fromJson(nil))
        XCTAssertNil(CallReport.fromJson(""))
        XCTAssertNil(CallReport.fromJson("not json"))
    }
}
