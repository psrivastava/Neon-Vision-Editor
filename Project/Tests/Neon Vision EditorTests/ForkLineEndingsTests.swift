import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ForkLineEndingsTests: XCTestCase {

    func testDetect() {
        XCTAssertEqual(ForkLineEndingConverter.detect("a\nb"), .lf)
        XCTAssertEqual(ForkLineEndingConverter.detect("a\r\nb"), .crlf)
        XCTAssertEqual(ForkLineEndingConverter.detect("a\rb"), .cr)
        XCTAssertEqual(ForkLineEndingConverter.detect("no breaks"), .lf)
        // CRLF takes precedence over bare CR when both patterns could match.
        XCTAssertEqual(ForkLineEndingConverter.detect("a\r\nb\rc"), .crlf)
    }

    func testConvertToCRLF() {
        XCTAssertEqual(ForkLineEndingConverter.convert("a\nb\nc", to: .crlf), "a\r\nb\r\nc")
    }

    func testConvertToLF() {
        XCTAssertEqual(ForkLineEndingConverter.convert("a\r\nb\rc", to: .lf), "a\nb\nc")
    }

    func testConvertToCR() {
        XCTAssertEqual(ForkLineEndingConverter.convert("a\nb", to: .cr), "a\rb")
    }

    func testConvertIsIdempotent() {
        let crlf = ForkLineEndingConverter.convert("a\nb", to: .crlf)
        XCTAssertEqual(ForkLineEndingConverter.convert(crlf, to: .crlf), crlf)
    }

    func testMixedInputNormalizesCleanly() {
        // Mixed CRLF + CR + LF should collapse to exactly one target ending per line.
        XCTAssertEqual(ForkLineEndingConverter.convert("a\r\nb\rc\nd", to: .lf), "a\nb\nc\nd")
    }
}
