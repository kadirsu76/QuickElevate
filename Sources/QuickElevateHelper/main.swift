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

private struct HelperConfiguration: Decodable {
    let grantIssuer: String
    let grantAudience: String
    let signingKeyModulus: String
    let signingKeyExponent: String
}

private struct GrantClaims: Decodable {
    let iss: String
    let aud: String
    let jti: String
    let exp: TimeInterval
    let uid: UInt32
    let nonce: String
    let action: String
    let durationSeconds: Int

    enum CodingKeys: String, CodingKey {
        case iss, aud, jti, exp, uid, nonce, action
        case durationSeconds = "duration_seconds"
    }
}

private enum GrantVerificationError: LocalizedError {
    case invalidFormat
    case invalidSignature
    case invalidClaims
    case expired
    case replayed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "authorization grant format is invalid"
        case .invalidSignature: "authorization grant signature is invalid"
        case .invalidClaims: "authorization grant claims are invalid"
        case .expired: "authorization grant has expired"
        case .replayed: "authorization grant was already used"
        }
    }
}

private final class GrantVerifier {
    private let configurationURL = URL(fileURLWithPath: "/Library/Application Support/QuickElevate/grant-verifier.json")
    private let replayURL = URL(fileURLWithPath: "/Library/Application Support/QuickElevate/consumed-grants.json")
    private let queue = DispatchQueue(label: "com.quickelevate.helper.grants")

    func verify(_ token: String, userUID: uid_t, expectedNonce: String) throws -> GrantClaims {
        let config = try loadConfiguration()
        let components = token.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              let header = base64URLDecode(String(components[0])),
              let payload = base64URLDecode(String(components[1])),
              let signature = base64URLDecode(String(components[2])) else {
            throw GrantVerificationError.invalidFormat
        }

        let headerObject = try JSONSerialization.jsonObject(with: header) as? [String: Any]
        guard headerObject?["alg"] as? String == "RS256" else {
            throw GrantVerificationError.invalidClaims
        }

        let publicKey = try makePublicKey(config: config)
        let signedBytes = Data("\(components[0]).\(components[1])".utf8)
        guard SecKeyVerifySignature(publicKey, .rsaSignatureMessagePKCS1v15SHA256, signedBytes as CFData, signature as CFData, nil) else {
            throw GrantVerificationError.invalidSignature
        }

        let claims = try JSONDecoder().decode(GrantClaims.self, from: payload)
        guard claims.iss == config.grantIssuer,
              claims.aud == config.grantAudience,
              claims.uid == UInt32(userUID),
              claims.nonce == expectedNonce,
              claims.action == "elevate",
              claims.durationSeconds >= 5,
              claims.durationSeconds <= 300 else {
            throw GrantVerificationError.invalidClaims
        }
        guard claims.exp >= Date().timeIntervalSince1970 else {
            throw GrantVerificationError.expired
        }

        try consume(jti: claims.jti, expiresAt: claims.exp)
        return claims
    }

    private func loadConfiguration() throws -> HelperConfiguration {
        let attributes = try FileManager.default.attributesOfItem(atPath: configurationURL.path)
        guard let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue,
              (attributes[.ownerAccountID] as? NSNumber)?.intValue == 0,
              permissions & 0o022 == 0 else {
            throw GrantVerificationError.invalidClaims
        }
        return try JSONDecoder().decode(HelperConfiguration.self, from: Data(contentsOf: configurationURL))
    }

    private func makePublicKey(config: HelperConfiguration) throws -> SecKey {
        guard let modulus = base64URLDecode(config.signingKeyModulus),
              let exponent = base64URLDecode(config.signingKeyExponent) else {
            throw GrantVerificationError.invalidClaims
        }
        let der = rsaPublicKeyDER(modulus: modulus, exponent: exponent)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: modulus.count * 8
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, &error) else {
            throw error?.takeRetainedValue() ?? GrantVerificationError.invalidClaims
        }
        return key
    }

    private func consume(jti: String, expiresAt: TimeInterval) throws {
        try queue.sync {
            var entries = (try? JSONDecoder().decode([String: TimeInterval].self, from: Data(contentsOf: replayURL))) ?? [:]
            let now = Date().timeIntervalSince1970
            entries = entries.filter { $0.value >= now }
            guard entries[jti] == nil else { throw GrantVerificationError.replayed }
            entries[jti] = expiresAt
            let data = try JSONEncoder().encode(entries)
            try data.write(to: replayURL, options: [.atomic])
            chmod(replayURL.path, 0o600)
        }
    }

    private func base64URLDecode(_ value: String) -> Data? {
        let padded = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/") + String(repeating: "=", count: (4 - value.count % 4) % 4)
        return Data(base64Encoded: padded)
    }

    private func rsaPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        func length(_ count: Int) -> Data {
            if count < 128 { return Data([UInt8(count)]) }
            let bytes = withUnsafeBytes(of: UInt32(count).bigEndian, Array.init).drop { $0 == 0 }
            return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
        }
        func integer(_ value: Data) -> Data {
            let normalized = value.first.map { $0 & 0x80 != 0 ? Data([0]) + value : value } ?? Data([0])
            return Data([0x02]) + length(normalized.count) + normalized
        }
        let sequence = integer(modulus) + integer(exponent)
        return Data([0x30]) + length(sequence.count) + sequence
    }
}

private final class ElevationService {
    private let queue = DispatchQueue(label: "com.quickelevate.helper.state")
    private var deadlineEpoch: TimeInterval?
    private var elevatedUser: String?
    private var timer: DispatchSourceTimer?
    private var pendingNonces: [String: (value: String, expiresAt: TimeInterval)] = [:]
    private let grantVerifier = GrantVerifier()
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
            try validateConsoleUser(peerUser)
            let isAdminNow = isAdmin(user: peerUser)

            switch request.action {
            case .authorizationContext:
                return authorizationContext(for: peerUser, isAdmin: isAdminNow)
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
                return grant(user: peerUser, peerUID: peer.uid, request: request)

            case .revoke:
                return revoke(user: peerUser)
            }
        } catch {
            logger.error("request failed: \(error.localizedDescription, privacy: .public)")
            return ElevationResponse(ok: false, message: error.localizedDescription, isAdmin: false, deadlineEpoch: nil)
        }
    }

    private func authorizationContext(for user: String, isAdmin: Bool) -> ElevationResponse {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            return ElevationResponse(ok: false, message: "cannot create authorization nonce", isAdmin: isAdmin, deadlineEpoch: nil)
        }
        let nonce = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        queue.sync {
            pendingNonces[user] = (nonce, Date().timeIntervalSince1970 + 120)
        }
        return ElevationResponse(ok: true, message: "authorization context created", isAdmin: isAdmin, deadlineEpoch: deadlineForUser(user), nonce: nonce)
    }

    private func grant(user: String, peerUID: uid_t, request: ElevationRequest) -> ElevationResponse {
        guard let token = request.authorizationToken, !token.isEmpty else {
            return ElevationResponse(ok: false, message: "backend authorization is required", isAdmin: isAdmin(user: user), deadlineEpoch: deadlineForUser(user))
        }
        guard let pending = queue.sync(execute: { pendingNonces[user] }), pending.expiresAt >= Date().timeIntervalSince1970 else {
            return ElevationResponse(ok: false, message: "authorization nonce expired", isAdmin: isAdmin(user: user), deadlineEpoch: deadlineForUser(user))
        }
        let claims: GrantClaims
        do {
            claims = try grantVerifier.verify(token, userUID: peerUID, expectedNonce: pending.value)
        } catch {
            return ElevationResponse(ok: false, message: error.localizedDescription, isAdmin: isAdmin(user: user), deadlineEpoch: deadlineForUser(user))
        }
        let bounded = claims.durationSeconds

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
            pendingNonces.removeValue(forKey: user)
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
                self.clearState()
            } else {
                logger.error("deadline reached but revoke failed for \(user, privacy: .public)")
            }
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
            do {
                try data.write(to: stateFile, options: [.atomic])
                chmod(stateFile.path, 0o600)
            } catch {
                logger.error("cannot persist elevation state: \(error.localizedDescription, privacy: .public)")
            }
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
