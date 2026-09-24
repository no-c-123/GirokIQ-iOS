import XCTest
@testable import GirokIQ_ios

/// Vision requests are deliberately slow, so the flashcards flow retries on a
/// timeout but surfaces every other failure. That hinges on isTimeout.
final class AIServiceErrorTests: XCTestCase {

    func testRecognisesTimeoutFromURLLoading() {
        XCTAssertTrue(AIError.isTimeout(URLError(.timedOut)))
    }

    func testOtherURLErrorsAreNotTimeouts() {
        let others: [URLError.Code] = [
            .notConnectedToInternet,
            .cannotFindHost,
            .networkConnectionLost,
            .badServerResponse,
            .cancelled
        ]
        for code in others {
            XCTAssertFalse(AIError.isTimeout(URLError(code)), "\(code) should not count as a timeout")
        }
    }

    func testAPIErrorsAreNotTimeouts() {
        // A 504 from the edge function is an API error, not a URL-loading timeout:
        // retrying it blindly would hammer the endpoint.
        XCTAssertFalse(AIError.isTimeout(AIError.apiError(statusCode: 504, message: "gateway timeout")))
        XCTAssertFalse(AIError.isTimeout(AIError.unauthorized))
        XCTAssertFalse(AIError.isTimeout(AIError.noAPIKey))
        XCTAssertFalse(AIError.isTimeout(AIError.invalidResponse))
    }

    func testErrorsCarryAUserFacingDescription() {
        let errors: [AIError] = [
            .noAPIKey,
            .invalidResponse,
            .unauthorized,
            .apiError(statusCode: 500, message: "boom")
        ]
        for error in errors {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true)
        }
    }
}
