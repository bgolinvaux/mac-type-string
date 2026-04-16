import Foundation
import XCTest

/// Integration tests that use TextEdit as a real typing target.
/// Requirements: Accessibility permissions for the test runner process.
/// These tests are inherently flaky in CI — they need a GUI session.
final class MacTypeStringIntegrationTests: XCTestCase {

    /// Path to the built binary (release build assumed via `just build` or `swift build -c release`)
    private var binaryPath: String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // mac-type-stringTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        return repo.appendingPathComponent(".build/release/mac-type-string").path
    }

    /// Run an AppleScript snippet and return stdout.
    @discardableResult
    private func runAppleScript(_ script: String) throws -> String {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// Run the mac-type-string binary with the given arguments.
    private func runBinary(_ args: [String]) throws {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            XCTFail("mac-type-string exited with \(proc.terminationStatus): \(errStr)")
        }
    }

    /// Helper: create temp file, open in TextEdit, type text, save, read back, clean up.
    private func typeAndVerify(_ args: [String], expected: String) throws {
        // 1. Create a temp file
        let tmpDir = FileManager.default.temporaryDirectory
        let tmpFile = tmpDir.appendingPathComponent("mac-type-string-test-\(UUID().uuidString).txt")
        try "".write(to: tmpFile, atomically: true, encoding: .utf8)

        defer {
            // 4. Close TextEdit document and clean up
            _ = try? runAppleScript("""
                tell application "TextEdit"
                    close every document saving no
                end tell
                """)
            try? FileManager.default.removeItem(at: tmpFile)
        }

        // 1b. Open the file in TextEdit and wait for it to be frontmost
        try runAppleScript("""
            tell application "TextEdit"
                activate
                open POSIX file "\(tmpFile.path)"
            end tell
            """)

        // Wait up to 5 seconds for TextEdit to become frontmost
        var frontApp = ""
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.5)
            frontApp = (try? runAppleScript("""
                tell application "System Events" to get name of first application process whose frontmost is true
                """)) ?? ""
            if frontApp == "TextEdit" { break }
            // Retry activate in case a dialog stole focus
            _ = try? runAppleScript("tell application \"TextEdit\" to activate")
        }
        XCTAssertEqual(frontApp, "TextEdit", "Expected TextEdit to be frontmost, got: \(frontApp)")

        // 2. Run mac-type-string to type the text
        try runBinary(args)

        // Give TextEdit time to process the keystrokes
        Thread.sleep(forTimeInterval: 0.5)

        // 3. Save via AppleScript and read back
        try runAppleScript("""
            tell application "TextEdit"
                save document 1
            end tell
            """)
        Thread.sleep(forTimeInterval: 0.5)

        let contents = try String(contentsOf: tmpFile, encoding: .utf8)
        XCTAssertEqual(contents, expected, "File contents mismatch")
    }

    func testStringASCII() throws {
        try typeAndVerify(["--string", "Hello world"], expected: "Hello world")
    }

    func testUnicodeChar() throws {
        try typeAndVerify(["--unicode-char", "2192"], expected: "→")
    }

    func testStringUnicode() throws {
        try typeAndVerify(["--string", "café → 日本語"], expected: "café → 日本語")
    }

    func testEmoji() throws {
        try typeAndVerify(["--unicode-char", "1F600"], expected: "😀")
    }
}
