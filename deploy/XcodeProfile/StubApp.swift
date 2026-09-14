import AppKit

// Profile harvester stub. This target exists only so Xcode automatic signing
// creates a provisioning profile for com.quickelevate.app with the Keychain
// Sharing capability. The real app is built with SwiftPM.
@main
final class StubAppMain: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = StubAppMain()
        app.delegate = delegate
        app.run()
    }
}
