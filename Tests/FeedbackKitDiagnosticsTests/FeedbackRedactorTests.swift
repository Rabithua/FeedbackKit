import FeedbackKitDiagnostics
import Foundation
import Testing

struct FeedbackRedactorTests {
    @Test(arguments: [1, 16, 32])
    func preservesJSONWithinTheDepthLimit(depth: Int) throws {
        let input = String(repeating: "[", count: depth)
            + #""visible""# + String(repeating: "]", count: depth)

        let output = FeedbackRedactor().redact(input)

        #expect(output == input)
        #expect(throws: Never.self) {
            try JSONSerialization.jsonObject(with: Data(output.utf8))
        }
    }

    @Test(arguments: [33, 128, 512, 4_096], [" \n\t", "\u{FEFF}"])
    func omitsOverdeepJSONWithoutExposingEscapedSecrets(depth: Int, prefix: String) {
        let input = prefix + String(repeating: "[", count: depth)
            + #"{"\u0074oken":"private-value"}"#
            + String(repeating: "]", count: depth)

        let output = FeedbackRedactor().redact(input)

        #expect(output == "[REDACTED_JSON_DEPTH_LIMIT]")
        #expect(output.contains("private-value") == false)
    }

    @Test func ignoresBracketsAndEscapedQuotesInsideJSONStrings() throws {
        let visible = String(repeating: #"[\"{}\"\\]"#, count: 100)
        let input = try JSONSerialization.data(withJSONObject: [
            "visible": visible,
            "token": "private-value",
        ])

        let output = FeedbackRedactor().redact(String(decoding: input, as: UTF8.self))
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: String]
        )

        #expect(object["visible"] == visible)
        #expect(object["token"] == "[REDACTED]")
    }

    @Test func handlesDeepMetricKitShapeOnACallbackSizedStack() async {
        let input = String(repeating: #"{"subFrames":["#, count: 128)
            + #"{"binaryName":"Rote","token":"private-value"}"#
            + String(repeating: "]}", count: 128)

        let output = await withCheckedContinuation { continuation in
            let thread = Thread {
                continuation.resume(returning: FeedbackRedactor().redact(input))
            }
            thread.stackSize = 512 * 1_024
            thread.start()
        }

        #expect(output == "[REDACTED_JSON_DEPTH_LIMIT]")
    }
}
