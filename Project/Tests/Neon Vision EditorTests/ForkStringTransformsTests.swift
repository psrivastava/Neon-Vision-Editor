import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ForkStringTransformsTests: XCTestCase {

    // MARK: - Case

    func testUpperLowerTitle() {
        XCTAssertEqual(ForkStringTransform.upperCase.apply(to: "hello world"), "HELLO WORLD")
        XCTAssertEqual(ForkStringTransform.lowerCase.apply(to: "Hello WORLD"), "hello world")
        XCTAssertEqual(ForkStringTransform.titleCase.apply(to: "hello world"), "Hello World")
    }

    func testToggleCase() {
        XCTAssertEqual(ForkStringTransform.toggleCase.apply(to: "Hello"), "hELLO")
        XCTAssertEqual(ForkStringTransform.toggleCase.apply(to: "aB3c"), "Ab3C")
    }

    func testRecaseFromMixedSeparators() {
        XCTAssertEqual(ForkStringTransform.snakeCase.apply(to: "helloWorld foo-bar"), "hello_world_foo_bar")
        XCTAssertEqual(ForkStringTransform.kebabCase.apply(to: "helloWorld foo_bar"), "hello-world-foo-bar")
        XCTAssertEqual(ForkStringTransform.camelCase.apply(to: "hello_world foo-bar"), "helloWorldFooBar")
    }

    // MARK: - Encoding

    func testBase64RoundTrip() {
        let encoded = ForkStringTransform.base64Encode.apply(to: "Neon")
        XCTAssertEqual(encoded, "TmVvbg==")
        XCTAssertEqual(ForkStringTransform.base64Decode.apply(to: encoded), "Neon")
    }

    func testBase64DecodeInvalidReturnsInputUnchanged() {
        // Non-decodable input must be returned unchanged, never destroyed.
        XCTAssertEqual(ForkStringTransform.base64Decode.apply(to: "!!!not base64!!!"), "!!!not base64!!!")
    }

    func testURLEncodeDecodeRoundTrip() {
        let encoded = ForkStringTransform.urlEncode.apply(to: "a b&c")
        XCTAssertEqual(ForkStringTransform.urlDecode.apply(to: encoded), "a b&c")
    }

    func testHTMLEncodeDecode() {
        let raw = "<a href=\"x\">A & B</a>"
        let encoded = ForkStringTransform.htmlEncode.apply(to: raw)
        XCTAssertEqual(encoded, "&lt;a href=&quot;x&quot;&gt;A &amp; B&lt;/a&gt;")
        XCTAssertEqual(ForkStringTransform.htmlDecode.apply(to: encoded), raw)
    }

    // MARK: - Lines

    func testSortAndReverseLines() {
        XCTAssertEqual(ForkStringTransform.sortLinesAscending.apply(to: "b\na\nc"), "a\nb\nc")
        XCTAssertEqual(ForkStringTransform.sortLinesDescending.apply(to: "a\nb\nc"), "c\nb\na")
        XCTAssertEqual(ForkStringTransform.reverseLines.apply(to: "1\n2\n3"), "3\n2\n1")
    }

    func testDeduplicateLinesPreservesFirstOrder() {
        XCTAssertEqual(ForkStringTransform.deduplicateLines.apply(to: "a\nb\na\nc\nb"), "a\nb\nc")
    }

    func testTrimTrailingWhitespace() {
        XCTAssertEqual(ForkStringTransform.trimTrailingWhitespace.apply(to: "a  \nb\t\nc"), "a\nb\nc")
    }

    // MARK: - Numbers

    func testDecimalHexRoundTrip() {
        XCTAssertEqual(ForkStringTransform.decimalToHex.apply(to: "255 16"), "0xff 0x10")
        XCTAssertEqual(ForkStringTransform.hexToDecimal.apply(to: "0xff 0x10"), "255 16")
        // Non-numeric tokens pass through untouched.
        XCTAssertEqual(ForkStringTransform.decimalToHex.apply(to: "255 hello"), "0xff hello")
    }

    func testGroupingCoversAllCases() {
        // Every case must report a group so submenu building never drops one.
        for transform in ForkStringTransform.allCases {
            XCTAssertFalse(transform.title.isEmpty, "\(transform) has empty title")
            _ = transform.group
        }
    }
}
