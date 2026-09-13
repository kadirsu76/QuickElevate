import Foundation
import Darwin
import OSLog
import Security
import SystemConfiguration
import QuickElevateShared

private let logger = Logger(subsystem: "com.quickelevate.helper", category: "helper")
private let trustedClientExecutablePath = "/Applications/QuickElevate.app/Contents/MacOS/QuickElevateApp"
private let trustedRequirementQueue = DispatchQueue(label: "com.quickelevate.helper.requirement")
private var cachedTrustedRequirement: SecRequirement?

private struct PersistentState: Codable {
    var elevatedUser: String
    var deadlineEpoch: TimeInterval
}

private final class ElevationService {
    private let queue = DispatchQueue(label: "com.quickelevate.helper.state")
    private var deadlineEpoch: TimeInterval?
    private var elevatedUser: String?
    private var timer: DispatchSourceTimer?
    private let stateDirectory = URL(fileURLWithPath: "/Library/Application Support/QuickElevate", isDirectory: true)
    private let stateFile = URL(fileURLWithPath: "/Library/Application Support/QuickElevate/state.json")

    init() {
        createStateDirectoryIfNeeded()
        loadState()
        if let user = elevatedUser {
            if let d = deadlineEpoch, d > Date().timeIntervalSince1970 {
                scheduleTimer(until: d, for: user)
            } else {
                _ = revokeIfPossible(user: user)
                clearState()
            }
        }
    }

    func handle(request: ElevationRequest, peer: PeerAudit) -> ElevationResponse {
        do {
            let peerUser = try usernameFromUID(peer.uid)
            guard request.user == peerUser else {
                throw NSError(domain: "QuickElevateHelper", code: 7, userInfo: [NSLocalizedDescriptionKey: "request user mismatch"])
            }
            try validateConsoleUser(peerUser)
            let isAdminNow = isAdmin(user: peerUser)

            switch request.action {
            case .ping:
                return ElevationResponse(ok: true, message: "pong", isAdmin: isAdminNow, deadlineEpoch: deadlineForUser(peerUser))

            case .status:
                return ElevationResponse(
                    ok: true,
                    message: isAdminNow ? "user is admin" : "user is standard",
                    isAdmin: isAdminNow,
                    deadlineEpoch: deadlineForUser(peerUser)
                )

            case .grant:
                return grant(user: peerUser, seconds: request.seconds)

            case .revoke:
                return revoke(user: peerUser)
            }
        } catch {
            logger.error("request failed: \(error.localizedDescription, privacy: .public)")
            return ElevationResponse(ok: false, message: error.localizedDescription, isAdmin: false, deadlineEpoch: nil)
        }
    }

    private func grant(user: String, seconds: Int) -> ElevationResponse {
        let bounded = max(5, min(seconds == 0 ? SharedConfig.defaultElevationSeconds : seconds, 300))

        if let existingUser = queue.sync(execute: { elevatedUser }), existingUser != user {
            if !revokeIfPossible(user: existingUser) {
                return ElevationResponse(ok: false, message: "cannot revoke previous managed user", isAdmin: isAdmin(user: user), deadlineEpoch: nil)
            }
            queue.sync {
                clearState()
            }
        }

        let isAlreadyAdmin = isAdmin(user: user)
        let isManagedUser = queue.sync { elevatedUser == user }

        if isAlreadyAdmin && !isManagedUser {
            return ElevationResponse(ok: true, message: "user is already admin", isAdmin: true, deadlineEpoch: nil)
        }

        if !isAlreadyAdmin && !addUserToAdmin(user: user) {
            return ElevationResponse(ok: false, message: "cannot add user to admin group", isAdmin: false, deadlineEpoch: nil)
        }

        let deadline = Date().timeIntervalSince1970 + TimeInterval(bounded)
        queue.sync {
            elevatedUser = user
            deadlineEpoch = deadline
            saveState()
            scheduleTimer(until: deadline, for: user)
        }

        logger.log("granted admin to \(user, privacy: .public) for \(bounded, privacy: .public)s")
        return ElevationResponse(ok: true, message: "admin granted for \(bounded)s", isAdmin: true, deadlineEpoch: deadline)
    }

    private func revoke(user: String) -> ElevationResponse {
        let managedUser = queue.sync { elevatedUser }
        guard managedUser == user else {
            return ElevationResponse(ok: false, message: "user is not managed by QuickElevate", isAdmin: isAdmin(user: user), deadlineEpoch: nil)
        }

        guard revokeIfPossible(user: user) else {
            return ElevationResponse(ok: false, message: "cannot revoke admin", isAdmin: isAdmin(user: user), deadlineEpoch: deadlineForUser(user))
        }

        queue.sync {
            if elevatedUser == user {
                clearState()
            }
        }

        logger.log("revoked admin from \(user, privacy: .public)")
        return ElevationResponse(ok: true, message: "admin revoked", isAdmin: false, deadlineEpoch: nil)
    }

    private func deadlineForUser(_ user: String) -> TimeInterval? {
        queue.sync {
            guard elevatedUser == user else { return nil }
            return deadlineEpoch
        }
    }

    private func scheduleTimer(until deadline: TimeInterval, for user: String) {
        timer?.cancel()
        let source = DispatchSource.makeTimerSource(queue: queue)
        let when = DispatchTime.now() + max(0, deadline - Date().timeIntervalSince1970)
        source.schedule(deadline: when)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            if revokeIfPossible(user: user) {
                logger.log("deadline reached, revoked admin from \(user, privacy: .public)")
            } else {
                logger.error("deadline reached but revoke failed for \(user, privacy: .public)")
            }
            self.clearState()
        }
        timer = source
        source.resume()
    }

    private func clearState() {
        timer?.cancel()
        timer = nil
        elevatedUser = nil
        deadlineEpoch = nil
        try? FileManager.default.removeItem(at: stateFile)
    }

    private func loadState() {
        guard let data = try? Data(contentsOf: stateFile),
              let state = try? JSONDecoder().decode(PersistentState.self, from: data) else {
            return
        }
        elevatedUser = state.elevatedUser
        deadlineEpoch = state.deadlineEpoch
    }

    private func saveState() {
        guard let user = elevatedUser, let deadline = deadlineEpoch else { return }
        let state = PersistentState(elevatedUser: user, deadlineEpoch: deadline)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: stateFile, options: [.atomic])
        }
    }

    private func createStateDirectoryIfNeeded() {
        try? FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0
            ]
        )
    }
}

private func usernameFromUID(_ uid: uid_t) throws -> String {
    guard let pw = getpwuid(uid), let cName = pw.pointee.pw_name else {
        throw NSError(domain: "QuickElevateHelper", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot resolve username for uid \(uid)"])
    }
    return String(cString: cName)
}

private func validateConsoleUser(_ user: String) throws {
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard let cfConsole = SCDynamicStoreCopyConsoleUser(nil, &uid, &gid) else {
        throw NSError(domain: "QuickElevateHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "cannot resolve active console user"])
    }
    let consoleUser = cfConsole as String
    guard consoleUser == user else {
        throw NSError(domain: "QuickElevateHelper", code: 3, userInfo: [NSLocalizedDescriptionKey: "request is not from active console user"])
    }
}

private func validateClientCodeSignature(peer: PeerAudit) throws {
    let executablePath = try resolveProcessPath(pid: peer.pid)
    guard executablePath == trustedClientExecutablePath else {
        throw NSError(domain: "QuickElevateHelper", code: 5, userInfo: [NSLocalizedDescriptionKey: "caller path is not trusted"])
    }

    var guest: SecCode?
    let attributes: [CFString: Any] = [kSecGuestAttributePid: Int(peer.pid)]
    let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes as CFDictionary, SecCSFlags(), &guest)
    guard copyStatus == errSecSuccess, let guest else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(copyStatus), userInfo: [NSLocalizedDescriptionKey: "cannot resolve caller code signature"])
    }

    let requirement = try trustedDesignatedRequirement()
    let checkStatus = SecCodeCheckValidity(guest, SecCSFlags(), requirement)
    guard checkStatus == errSecSuccess else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(checkStatus), userInfo: [NSLocalizedDescriptionKey: "caller signature is not trusted"])
    }

}

private func trustedDesignatedRequirement() throws -> SecRequirement {
    try trustedRequirementQueue.sync {
        if let cachedTrustedRequirement {
            return cachedTrustedRequirement
        }

        var staticCode: SecStaticCode?
        let createStatus = SecStaticCodeCreateWithPath(URL(fileURLWithPath: trustedClientExecutablePath) as CFURL, SecCSFlags(), &staticCode)
        guard createStatus == errSecSuccess, let staticCode else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(createStatus), userInfo: [NSLocalizedDescriptionKey: "cannot inspect trusted client signature"])
        }

        var requirement: SecRequirement?
        let reqStatus = SecCodeCopyDesignatedRequirement(staticCode, SecCSFlags(), &requirement)
        guard reqStatus == errSecSuccess, let requirement else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(reqStatus), userInfo: [NSLocalizedDescriptionKey: "cannot derive trusted requirement"])
        }

        cachedTrustedRequirement = requirement
        return requirement
    }
}

private func resolveProcessPath(pid: pid_t) throws -> String {
    var buffer = [CChar](repeating: 0, count: 4096)
    let result = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard result > 0 else {
        throw NSError(domain: "QuickElevateHelper", code: 6, userInfo: [NSLocalizedDescriptionKey: "cannot resolve caller process path"])
    }
    let path = String(cString: buffer).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !path.isEmpty else {
        throw NSError(domain: "QuickElevateHelper", code: 6, userInfo: [NSLocalizedDescriptionKey: "empty caller process path"])
    }
    return path
}

private func runCommand(_ launchPath: String, _ args: [String]) -> (Int32, String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args

    let out = Pipe()
    let err = Pipe()
    proc.standardOutput = out
    proc.standardError = err

    do {
        try proc.run()
    } catch {
        return (1, "cannot run \(launchPath): \(error.localizedDescription)")
    }
    proc.waitUntilExit()

    let o = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let e = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (proc.terminationStatus, o + e)
}

private func addUserToAdmin(user: String) -> Bool {
    let (code, output) = runCommand("/usr/sbin/dseditgroup", ["-o", "edit", "-a", user, "-t", "user", "admin"])
    if code != 0 {
        logger.error("dseditgroup add failed: \(output, privacy: .public)")
    }
    return code == 0
}

private func revokeIfPossible(user: String) -> Bool {
    if !isAdmin(user: user) {
        return true
    }

    let (code, output) = runCommand("/usr/sbin/dseditgroup", ["-o", "edit", "-d", user, "-t", "user", "admin"])
    if code != 0 {
        logger.error("dseditgroup remove failed: \(output, privacy: .public)")
    }
    return code == 0
}

private func isAdmin(user: String) -> Bool {
    let (code, output) = runCommand("/usr/sbin/dsmemberutil", ["checkmembership", "-U", user, "-G", "admin"])
    if code != 0 {
        return false
    }
    return output.localizedCaseInsensitiveContains("is a member")
}

private final class UnixSocketServer {
    private let service = ElevationService()
    private var listenerFD: Int32 = -1
    private var source: DispatchSourceRead?

    func start() throws {
        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: SharedConfig.socketDirectory),
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o755,
                .ownerAccountID: 0,
                .groupOwnerAccountID: 0
            ]
        )
        unlink(SharedConfig.socketPath)

        listenerFD = socket(AF_UNIX, SOCK_STREAM, 0)
        guard listenerFD >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "cannot create listener socket"])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = SharedConfig.socketPath.utf8CString
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw NSError(domain: "QuickElevateHelper", code: 2, userInfo: [NSLocalizedDescriptionKey: "socket path too long"])
        }

        let sunPathCapacity = MemoryLayout.size(ofValue: addr.sun_path)
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: sunPathCapacity) { cptr in
                _ = pathBytes.withUnsafeBufferPointer { buf in
                    memcpy(cptr, buf.baseAddress, buf.count)
                }
            }
        }

        let len = socklen_t(MemoryLayout<sa_family_t>.size + pathBytes.count)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sPtr in
                bind(listenerFD, sPtr, len)
            }
        }

        guard bindResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "cannot bind socket"])
        }

        chmod(SharedConfig.socketPath, 0o666)

        guard listen(listenerFD, SOMAXCONN) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "cannot listen on socket"])
        }

        let currentFlags = fcntl(listenerFD, F_GETFL)
        _ = fcntl(listenerFD, F_SETFL, currentFlags | O_NONBLOCK)

        let src = DispatchSource.makeReadSource(fileDescriptor: listenerFD, queue: .global(qos: .userInitiated))
        src.setEventHandler { [weak self] in
            self?.acceptLoop()
        }
        src.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.listenerFD >= 0 {
                close(self.listenerFD)
                self.listenerFD = -1
            }
            unlink(SharedConfig.socketPath)
        }

        source = src
        src.resume()
        logger.log("helper listening at \(SharedConfig.socketPath, privacy: .public)")
    }

    private func acceptLoop() {
        while true {
            var addr = sockaddr()
            var len: socklen_t = socklen_t(MemoryLayout<sockaddr>.size)
            let clientFD = accept(listenerFD, &addr, &len)
            if clientFD < 0 {
                if errno == EWOULDBLOCK || errno == EAGAIN {
                    break
                }
                return
            }

            handleClient(fd: clientFD)
            close(clientFD)
        }
    }

    private func handleClient(fd: Int32) {
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)

        do {
            let peer = try PeerAuditResolver.resolve(fd: fd)
            if peer.uid == 0 {
                throw NSError(domain: "QuickElevateHelper", code: 4, userInfo: [NSLocalizedDescriptionKey: "root caller is not allowed"])
            }
            try validateClientCodeSignature(peer: peer)

            let data = try Codec.readLine(from: handle)
            let request = try Codec.decode(ElevationRequest.self, from: data)
            let response = service.handle(request: request, peer: peer)
            try Codec.writeLine(try Codec.encode(response), to: handle)
        } catch {
            let fallback = ElevationResponse(ok: false, message: error.localizedDescription, isAdmin: false, deadlineEpoch: nil)
            if let encoded = try? Codec.encode(fallback) {
                try? Codec.writeLine(encoded, to: handle)
            }
        }
    }
}

if getuid() != 0 {
    fputs("QuickElevateHelper root olarak calismalidir.\n", stderr)
    exit(1)
}

private let server = UnixSocketServer()
do {
    try server.start()
    dispatchMain()
} catch {
    fputs("Helper baslatilamadi: \(error.localizedDescription)\n", stderr)
    exit(1)
}
