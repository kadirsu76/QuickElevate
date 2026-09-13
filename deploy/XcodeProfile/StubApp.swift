import AppKit

// Profile harvester stub. This target exists only so Xcode automatic signing
// creates a provisioning profile for com.quickelevate.app with the Keychain
// Sharing capability. The real app is built with SwiftPM.
final class StubDelegate: NSObject, NSApplicationDelegate {}

let delegate = StubDelegate()
NSApplication.shared.delegate = delegate
NSApplication.shared.run()
