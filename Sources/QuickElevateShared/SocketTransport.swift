import Foundation
import Darwin

public enum SocketTransport {
    public static func send(_ request: ElevationRequest) throws -> ElevationResponse {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "SocketTransport", code: 1, userInfo: [NSLocalizedDescriptionKey: "cannot create socket"])
        }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = SharedConfig.socketPath.utf8CString
        guard pathBytes.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            throw NSError(domain: "SocketTransport", code: 2, userInfo: [NSLocalizedDescriptionKey: "socket path too long"])
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
        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                connect(fd, sockaddrPtr, len)
            }
        }

        guard connectResult == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "cannot connect to helper"])
        }

        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        let payload = try Codec.encode(request)
        try Codec.writeLine(payload, to: handle)
        let line = try Codec.readLine(from: handle)
        guard !line.isEmpty else {
            throw NSError(domain: "SocketTransport", code: 3, userInfo: [NSLocalizedDescriptionKey: "empty response from helper"])
        }
        return try Codec.decode(ElevationResponse.self, from: line)
    }
}
