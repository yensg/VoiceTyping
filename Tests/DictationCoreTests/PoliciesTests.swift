import Foundation
import DictationCore

var failures = 0
func XCTAssertTrue(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { if !value { failures += 1; print("FAIL \(file):\(line)") } }
func XCTAssertFalse(_ value: Bool, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(!value, file: file, line: line) }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #filePath, line: UInt = #line) { XCTAssertTrue(a == b, file: file, line: line) }


final class PoliciesTests {
    func testDraftCannotCarryReturnOrTerminalControlCharacters() {
        XCTAssertEqual(sanitizeDraft("hello\r\n世界\t café\u{1b}\u{7f}\n"), "hello 世界 café")
        XCTAssertEqual(sanitizeDraft(" \n\t"), "")
        XCTAssertEqual(sanitizeDraft("don't replace my $HOME; `words`"), "don't replace my $HOME; `words`")
    }

    func testSilenceAndShortNoiseAreRejected() {
        XCTAssertFalse(AudioGate.accepts([], sampleRate: 16000))
        XCTAssertFalse(AudioGate.accepts(Array(repeating: 0, count: 16000), sampleRate: 16000))
        XCTAssertFalse(AudioGate.accepts(Array(repeating: 0.2, count: 100), sampleRate: 16000))
        XCTAssertFalse(AudioGate.accepts([.nan, .infinity], sampleRate: 16000))
    }

    func testSustainedSignalPassesEnergyGate() {
        let samples = (0..<16000).map { Float(sin(Double($0) * 0.1) * 0.1) }
        XCTAssertTrue(AudioGate.accepts(samples, sampleRate: 16000))
    }

    func testCancelledStaleAndChangedDestinationCannotInsert() {
        var gate = SessionGate()
        let first = gate.begin(pid: 42)
        XCTAssertTrue(gate.accepts(token: first, pid: 42))
        XCTAssertFalse(gate.accepts(token: first, pid: 99))
        gate.cancel()
        XCTAssertFalse(gate.accepts(token: first, pid: 42))
        let next = gate.begin(pid: 42)
        XCTAssertFalse(gate.accepts(token: first, pid: 42))
        XCTAssertTrue(gate.accepts(token: next, pid: 42))
    }
}

// Hardware flag values from the macOS SDK IOLLEvent.h.
var option = RightOptionState()
XCTAssertEqual(option.update(keyCode: 61, flags: 0x80040), true)
XCTAssertEqual(option.update(keyCode: 61, flags: 0x80040), nil)
XCTAssertEqual(option.update(keyCode: 58, flags: 0x80060), nil)
XCTAssertEqual(option.update(keyCode: 61, flags: 0x80020), false)
XCTAssertEqual(option.update(keyCode: 61, flags: 0), nil)
XCTAssertEqual(option.update(keyCode: 61, flags: 0x80040), true)
option.reset()
XCTAssertEqual(option.update(keyCode: 61, flags: 0), nil)

XCTAssertEqual(option.update(keyCode: 61, flags: 0x80000), true)
XCTAssertEqual(option.update(keyCode: 61, flags: 0), false)

let checks = PoliciesTests()
checks.testDraftCannotCarryReturnOrTerminalControlCharacters()
checks.testSilenceAndShortNoiseAreRejected()
checks.testSustainedSignalPassesEnergyGate()
checks.testCancelledStaleAndChangedDestinationCannotInsert()
print("Policy checks: \(failures) failures")
exit(failures == 0 ? 0 : 1)
