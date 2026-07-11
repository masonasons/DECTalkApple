import XCTest
@testable import DECtalkKit

final class EncodingTests: XCTestCase {

    func testSmartPunctuationMapping() {
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("it\u{2019}s"), "it's")
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("\u{201C}hi\u{201D}"), "\"hi\"")
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("a\u{2014}b"), "a - b")
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("wait\u{2026}"), "wait...")
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("caf\u{00E9}"), "cafe")
        // A non-mappable symbol (emoji) is dropped, not spoken as a symbol name.
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("hi \u{1F600}!"), "hi  !")
        // Plain ASCII (including engine command brackets) is untouched.
        XCTAssertEqual(DECtalkSynthesizer.engineASCII("[:rate 200] it's fine."), "[:rate 200] it's fine.")
    }

    func testCurlyApostropheNoLongerBloatsAudio() throws {
        let synth = try XCTUnwrap(DECtalkSynthesizer())
        let straight = synth.render("it's fine here").count
        let curly    = synth.render("it\u{2019}s fine here").count
        // Before the fix the curly form spoke the UTF-8 bytes and was ~2x longer.
        XCTAssertLessThan(Double(curly), Double(straight) * 1.3,
                          "curly apostrophe still bloats output (straight=\(straight) curly=\(curly))")
    }
}
