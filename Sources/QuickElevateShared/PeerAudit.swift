import Foundation
import Darwin

public struct PeerAudit: Sendable {
    public let uid: uid_t
    public let gid: gid_t
    public let pid: pid_t

    public init(uid: uid_t, gid: gid_t, pid: pid_t) {
        self.uid = uid
        self.gid = gid
        self.pid = pid
    }
}

public enum PeerAuditResolver {
    public static func resolve(fd: Int32) throws -> PeerAudit {
        var uid: uid_t = 0
        var gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "cannot resolve peer uid/gid"])
        }

        var pid: pid_t = 0
        var size = socklen_t(MemoryLayout<pid_t>.size)
        let pidResult = withUnsafeMutablePointer(to: &pid) { ptr in
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, ptr, &size)
        }
        guard pidResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "cannot resolve peer pid"])
        }

        return PeerAudit(uid: uid, gid: gid, pid: pid)
    }
}
