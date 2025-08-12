import XCTest
@testable import MUDTapper

final class ANSIProcessorTests: XCTestCase {
    private var theme: ThemeManager!
    private var sut: ANSIProcessor!

    override func setUp() {
        super.setUp()
        theme = ThemeManager.shared
        sut = ANSIProcessor(themeManager: theme)
    }

    func testPlainTextPassesThrough() {
        let text = "hello world"
        let out = sut.processText(text)
        XCTAssertEqual(out.string, text)
    }

    func testSGR_ForegroundRedAndReset() {
        let input = "\u{001B}[31mRED\u{001B}[0mX"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "REDX")
    }

    func testInverseOnOff() {
        let input = "\u{001B}[7mINV\u{001B}[27mNORM"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "INVNORM")
    }

    func testDimOnOff() {
        let input = "\u{001B}[2mdim\u{001B}[22mN"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "dimN")
    }

    func test256ColorForeground() {
        let input = "\u{001B}[38;5;196mX\u{001B}[0m"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "X")
    }

    func testRGBForeground() {
        let input = "\u{001B}[38;2;255;128;64mX\u{001B}[0m"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "X")
    }

    func testTbaMUDShortCodes() {
        let input = "@rRED@N"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "RED")
    }

    func testTbaMUDXtermCode() {
        let input = "@[F196]X@N"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "X")
    }

    func testBlinkIgnored() {
        let input = "\u{001B}[5mB\u{001B}[25mX"
        let out = sut.processText(input)
        XCTAssertEqual(out.string, "BX")
    }
}

