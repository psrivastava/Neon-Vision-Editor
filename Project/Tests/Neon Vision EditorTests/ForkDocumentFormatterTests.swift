import XCTest
@testable import Neon_Vision_Editor

@MainActor
final class ForkDocumentFormatterTests: XCTestCase {

    func testHandlesLanguageGate() {
        XCTAssertTrue(ForkDocumentFormatter.handles(language: "xml"))
        XCTAssertTrue(ForkDocumentFormatter.handles(language: "HTML"))
        XCTAssertTrue(ForkDocumentFormatter.handles(language: "svg"))
        XCTAssertFalse(ForkDocumentFormatter.handles(language: "json"))
        XCTAssertFalse(ForkDocumentFormatter.handles(language: "swift"))
    }

    func testPrettyPrintNestsWithIndentation() throws {
        let input = "<a><b>text</b></a>"
        let output = try ForkDocumentFormatter.prettyPrint(input)
        XCTAssertEqual(output, "<a>\n  <b>\n    text\n  </b>\n</a>\n")
    }

    func testPrettyPrintHandlesVoidElements() throws {
        // <br> and <img> are void: they must not increase indent depth.
        let input = "<p>a<br><img src=\"x\">b</p>"
        let output = try ForkDocumentFormatter.prettyPrint(input)
        let lines = output.split(separator: "\n")
        // <p> opens (depth 0), children at depth 1, </p> back at depth 0.
        XCTAssertEqual(lines.first, "<p>")
        XCTAssertEqual(lines.last, "</p>")
        XCTAssertTrue(output.contains("  <br>"))
        XCTAssertTrue(output.contains("  <img src=\"x\">"))
    }

    func testPrettyPrintSelfClosingTag() throws {
        let input = "<root><item/></root>"
        let output = try ForkDocumentFormatter.prettyPrint(input)
        XCTAssertEqual(output, "<root>\n  <item/>\n</root>\n")
    }

    func testMinifyStripsInterTagWhitespace() throws {
        let input = "<a>\n  <b>  text </b>\n</a>"
        let output = try ForkDocumentFormatter.minify(input)
        XCTAssertEqual(output, "<a><b>text</b></a>")
    }

    func testCommentTreatedAsSelfContained() throws {
        let input = "<a><!-- note --><b>x</b></a>"
        let output = try ForkDocumentFormatter.prettyPrint(input)
        // The comment stays at child depth and does not open a container.
        XCTAssertTrue(output.contains("  <!-- note -->"))
        XCTAssertTrue(output.contains("  <b>"))
    }

    func testEmptyInputThrows() {
        XCTAssertThrowsError(try ForkDocumentFormatter.prettyPrint("   \n  ")) { error in
            XCTAssertEqual(error as? ForkDocumentFormatter.FormatError, .empty)
        }
    }
}
