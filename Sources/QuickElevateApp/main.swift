import AppKit
import Foundation
import UserNotifications

@main
@MainActor
final class QuickElevateAgent: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = AppModel()

    static func main() {
        let app = NSApplication.shared
        let delegate = QuickElevateAgent()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupNotifications()
        model.startMonitoring()
        NotificationCenter.default.addObserver(forName: .quickElevateStatusDidChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.refreshStatusUI()
            }
        }

        Task {
            await model.refreshStatus()
            await showQuickActionDialog()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { await showQuickActionDialog() }
        return false
    }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        let stateTitle = model.isAdmin ? "Admin: Acik (\(model.secondsLeft) sn)" : "Admin: Kapali"
        let stateItem = NSMenuItem(title: stateTitle, action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)
        menu.addItem(.separator())

        if model.isAdmin {
            menu.addItem(NSMenuItem(title: "Yetkiyi Simdi Birak", action: #selector(handleRevokeFromMenu), keyEquivalent: ""))
        } else {
            menu.addItem(NSMenuItem(title: "60 sn Yetki Iste", action: #selector(handleRequestFromMenu), keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cikis", action: #selector(handleQuit), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    private func setupNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in }
    }

    @objc private func handleRequestFromMenu() {
        Task { await requestFlow() }
    }

    @objc private func handleRevokeFromMenu() {
        Task {
            await model.revokeNow()
            refreshStatusUI()
        }
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }

    func refreshStatusUI() {
        model.applyDockIconAndBadge()
    }

    func showQuickActionDialog() async {
        await model.refreshStatus()
        refreshStatusUI()

        if model.isAdmin {
            let alert = NSAlert()
            alert.messageText = "Yonetici Yetkisi Acik"
            alert.informativeText = "Kalan sure: \(model.secondsLeft) saniye.\nYetkiyi simdi birakmak ister misiniz?"
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Yetkiyi Birak")
            alert.addButton(withTitle: "Kapat")
            if alert.runModal() == .alertFirstButtonReturn {
                await model.revokeNow()
                refreshStatusUI()
            }
            return
        }

        let confirm = NSAlert()
        confirm.messageText = "Yonetici Yetkisi Iste"
        confirm.informativeText = "Bu bilgisayarda politika tarafindan onaylanan kisa sureli yonetici yetkisi almak istiyor musunuz?"
        confirm.alertStyle = .warning
        confirm.addButton(withTitle: "Yetki Iste")
        confirm.addButton(withTitle: "Iptal")

        guard confirm.runModal() == .alertFirstButtonReturn else {
            return
        }

        await requestFlow()
    }

    private func requestFlow() async {
        await model.requestElevation()
        refreshStatusUI()

        if !model.isAdmin, model.statusText != "Hazir" {
            let error = NSAlert()
            error.messageText = "Yonetici Yetkisi Verilmedi"
            error.informativeText = model.statusText
            error.alertStyle = .warning
            error.addButton(withTitle: "Tamam")
            error.runModal()
        }
    }
}
