import AppKit
@preconcurrency import ApplicationServices

if CommandLine.arguments.contains("--accessibility-status") {
    print("ACCESSIBILITY_TRUSTED=\(AXIsProcessTrusted())")
    exit(EXIT_SUCCESS)
}

if CommandLine.arguments.contains("--request-accessibility") {
    let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    let trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    print("ACCESSIBILITY_TRUSTED=\(trusted)")
    exit(EXIT_SUCCESS)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
