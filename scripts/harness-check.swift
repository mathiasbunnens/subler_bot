import Foundation

// Test harnesses only: shadow the stdlib traps so a failed check prints a
// HARNESS_FAIL line and exits with status 1 instead of SIGTRAP. A trap makes
// macOS show a crash report dialog on the user's desktop for an expected
// test failure. Launchers already treat a missing PASS marker as failure.
func precondition(_ condition: @autoclosure () -> Bool, _ message: @autoclosure () -> String = "",
                  file: StaticString = #file, line: UInt = #line) {
    if !condition() { harnessFail(message(), file: file, line: line) }
}

func preconditionFailure(_ message: @autoclosure () -> String = "",
                         file: StaticString = #file, line: UInt = #line) -> Never {
    harnessFail(message(), file: file, line: line)
}

func harnessFail(_ message: String, file: StaticString, line: UInt) -> Never {
    let text = "HARNESS_FAIL \(file):\(line): Precondition failed \(message)\n"
    FileHandle.standardError.write(Data(text.utf8))
    print(text, terminator: "")
    fflush(stdout)
    exit(1)
}
