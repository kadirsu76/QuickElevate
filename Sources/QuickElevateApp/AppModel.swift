import AppKit
import Foundation
import LocalAuthentication
import UserNotifications
import QuickElevateShared

extension Notification.Name {
    static let quickElevateStatusDidChange = Notification.Name("quickElevate.statusDidChange")
}

@MainActor
final class AppModel {
    private(set) var isAdmin: Bool = false
    private(set) var secondsLeft: Int = 0
    private(set) var statusText: String = "Hazir"

    private var deadlineEpoch: TimeInterval?
    private var timer: Timer?
    private var pollTimer: Timer?

    func startMonitoring() {
        timer?.invalidate()
        pollTimer?.invalidate()

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.recalculateRemaining()
            }
        }

        pollTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshStatus()
            }
        }
    }

    func refreshStatus() async {
        let previousAdmin = isAdmin
        do {
            let response = try SocketTransport.send(.init(action: .status, user: NSUserName()))
            apply(response: response)
        } catch {
            statusText = "Helper ulasilamiyor"
            isAdmin = false
            secondsLeft = 0
            deadlineEpoch = nil
        }

        applyDockIconAndBadge()
        notifyStatusChanged()

        if previousAdmin && !isAdmin {
            notify(title: "QuickElevate", body: "Yonetici yetkisi kaldirildi.")
        }
    }

    func requestElevation() async {
        do {
            try await authenticateWithTouchIDOrPassword()

            let response = try SocketTransport.send(
                .init(action: .grant, user: NSUserName(), seconds: SharedConfig.defaultElevationSeconds)
            )
            let previous = isAdmin
            apply(response: response)
            applyDockIconAndBadge()
            notifyStatusChanged()

            if !previous && isAdmin {
                notify(title: "QuickElevate", body: "Yonetici yetkisi basariyla verildi.")
            }
        } catch {
            statusText = "Dogrulama veya yetki istegi basarisiz"
            await refreshStatus()
        }
    }

    func revokeNow() async {
        do {
            let response = try SocketTransport.send(.init(action: .revoke, user: NSUserName()))
            apply(response: response)
        } catch {
            statusText = "Yetki kaldirilamadi"
        }

        applyDockIconAndBadge()
        notifyStatusChanged()
    }

    func applyDockIconAndBadge() {
        let lockSymbol = isAdmin ? "lock.open.fill" : "lock.fill"
        NSApp.applicationIconImage = NSImage(systemSymbolName: lockSymbol, accessibilityDescription: "QuickElevate")

        if isAdmin && secondsLeft > 0 {
            NSApp.dockTile.badgeLabel = "\(secondsLeft)"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
        NSApp.dockTile.display()
    }

    private func apply(response: ElevationResponse) {
        statusText = response.message
        isAdmin = response.isAdmin
        deadlineEpoch = response.deadlineEpoch
        recalculateRemaining()
    }

    private func recalculateRemaining() {
        guard isAdmin, let deadlineEpoch else {
            secondsLeft = 0
            return
        }

        let remaining = Int(ceil(deadlineEpoch - Date().timeIntervalSince1970))
        if remaining <= 0 {
            secondsLeft = 0
            return
        }
        secondsLeft = remaining
    }

    private func notifyStatusChanged() {
        NotificationCenter.default.post(name: .quickElevateStatusDidChange, object: nil)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func authenticateWithTouchIDOrPassword() async throws {
        let context = LAContext()
        context.localizedCancelTitle = "Iptal"

        var authError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) else {
            throw authError ?? NSError(domain: "QuickElevate", code: 1)
        }

        try await withCheckedThrowingContinuation { continuation in
            context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "60 saniyelik yonetici yetkisi icin kimlik dogrulayin"
            ) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? NSError(domain: "QuickElevate", code: 2))
                }
            }
        }
    }
}
