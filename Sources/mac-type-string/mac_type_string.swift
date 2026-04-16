import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

nonisolated(unsafe) var verbose = false

func log(_ msg: @autoclosure () -> String) {
    if verbose {
        fputs("[verbose] \(msg())\n", stderr)
    }
}

@main
struct MacTypeString {
    static func main() {
        var args = Array(CommandLine.arguments.dropFirst())  // drop argv[0]

        if let idx = args.firstIndex(of: "--verbose") {
            verbose = true
            args.remove(at: idx)
        }

        log("PID: \(ProcessInfo.processInfo.processIdentifier)")
        log("args after parsing: \(args)")
        log("UID: \(getuid()), EUID: \(geteuid())")

        guard args.count >= 2 else {
            printUsage()
            exit(1)
        }

        let flag = args[0]
        let value = args[1]
        let textToType: String

        switch flag {
        case "--unicode-char":
            guard let codePoint = UInt32(value, radix: 16),
                  let scalar = Unicode.Scalar(codePoint) else {
                fputs("Error: '\(value)' is not a valid hex Unicode code point.\n", stderr)
                exit(1)
            }
            textToType = String(scalar)
            log("Parsed unicode code point U+\(value.uppercased()) -> '\(textToType)'")
        case "--string":
            textToType = value
            log("Parsed string: '\(textToType)' (length: \(value.count))")
        default:
            fputs("Error: Unknown flag '\(flag)'.\n", stderr)
            printUsage()
            exit(1)
        }

        // Check accessibility trust
        let trusted = AXIsProcessTrusted()
        log("AXIsProcessTrusted(): \(trusted)")
        if !trusted {
            fputs("WARNING: This process is NOT trusted for Accessibility. CGEvent posting may silently fail.\n", stderr)
            fputs("Go to System Settings → Privacy & Security → Accessibility and add this binary or its parent (Terminal, etc.).\n", stderr)
            // Also try the prompting variant for diagnostics
            let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            let trustedWithPrompt = AXIsProcessTrustedWithOptions(opts)
            log("AXIsProcessTrustedWithOptions(prompt=true): \(trustedWithPrompt)")
        }

        // Log frontmost app info
        if let frontApp = NSWorkspace.shared.frontmostApplication {
            log("Frontmost app: \(frontApp.localizedName ?? "<unknown>") (bundle: \(frontApp.bundleIdentifier ?? "<none>"), pid: \(frontApp.processIdentifier))")
        } else {
            log("Frontmost app: <could not determine>")
        }

        // Log CGEvent source info
        log("Creating CGEventSource with stateID: .combinedSessionState")
        let source = CGEventSource(stateID: .combinedSessionState)
        if source == nil {
            log("WARNING: CGEventSource creation returned nil!")
        } else {
            log("CGEventSource created successfully")
        }

        typeString(textToType, source: source)
        log("Done. All events posted.")
    }

    static func printUsage() {
        let usage = """
            Usage:
              mac-type-string [--verbose] --unicode-char <hex>    Type the Unicode character U+<hex>
              mac-type-string [--verbose] --string <text>          Type the given string

            Examples:
              mac-type-string --unicode-char 2192      Types →
              mac-type-string --string '→'             Types →
              mac-type-string --string 'Hello world'   Types Hello world
              mac-type-string --verbose --string test  Types test with debug output
            """
        fputs(usage, stderr)
    }

    static func typeString(_ text: String, source: CGEventSource?) {
        // Type one character at a time — many apps (Electron, browsers, etc.)
        // only read the first character from a multi-char CGEvent.
        let utf16Chars = Array(text.utf16)

        log("Text to type: '\(text)'")
        log("UTF-16 length: \(utf16Chars.count)")
        log("UTF-16 units: \(utf16Chars.map { String(format: "U+%04X", $0) }.joined(separator: " "))")

        var i = 0
        while i < utf16Chars.count {
            // Handle surrogate pairs (emoji, etc.) as a single 2-unit event
            let isSurrogatePair = UTF16.isLeadSurrogate(utf16Chars[i]) && (i + 1) < utf16Chars.count && UTF16.isTrailSurrogate(utf16Chars[i + 1])
            let chunk: [UniChar]
            if isSurrogatePair {
                chunk = [utf16Chars[i], utf16Chars[i + 1]]
                log("Char \(i): surrogate pair U+\(String(format: "%04X", utf16Chars[i])) U+\(String(format: "%04X", utf16Chars[i + 1]))")
                i += 2
            } else {
                chunk = [utf16Chars[i]]
                log("Char \(i): U+\(String(format: "%04X", utf16Chars[i]))")
                i += 1
            }

            guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true) else {
                fputs("Error: Failed to create CGEvent (keyDown). Accessibility permissions likely missing.\n", stderr)
                exit(1)
            }
            guard let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                fputs("Error: Failed to create CGEvent (keyUp). Accessibility permissions likely missing.\n", stderr)
                exit(1)
            }

            // Clear modifier flags so the event looks like a plain keystroke
            keyDown.flags = CGEventFlags(rawValue: 0)
            keyUp.flags = CGEventFlags(rawValue: 0)

            keyDown.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyDown.post(tap: .cghidEventTap)

            keyUp.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            keyUp.post(tap: .cghidEventTap)

            log("  keyDown+keyUp posted")

            // Small delay between characters to let the target app process each event
            usleep(3000)  // 3ms
        }
    }
}
