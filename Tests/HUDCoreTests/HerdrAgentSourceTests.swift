import Testing
import HerdrKit
@testable import HUDCore

@Suite struct HerdrAgentSourceTests {
    @Test(arguments: [
        (HerdrError.notInstalled, "herdr is not installed"),
        (.unreachable("socket missing"), "herdr is not reachable"),
        (.timedOut, "herdr is not responding"),
        (.outputTooLarge, "herdr sent more than the HUD reads"),
        (.unexpectedResponse("bad json"), "herdr sent a reply the HUD does not understand"),
        (.rejected(code: "x", message: "y"), "herdr refused the request"),
    ])
    func explainsAnUnavailableHerdrInPlainWords(error: HerdrError, text: String) {
        #expect(HerdrAgentSource.unavailable(error) == text)
    }
}
