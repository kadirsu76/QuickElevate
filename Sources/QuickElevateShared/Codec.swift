import Foundation

public enum Codec {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        return try encoder.encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    public static func readLine(from handle: FileHandle) throws -> Data {
        var buffer = Data()
        while true {
            let chunk = try handle.read(upToCount: 1) ?? Data()
            if chunk.isEmpty {
                break
            }
            if chunk[0] == 0x0A {
                break
            }
            buffer.append(chunk)
            if buffer.count > 16_384 {
                throw NSError(domain: "Codec", code: 1, userInfo: [NSLocalizedDescriptionKey: "request too large"])
            }
        }
        return buffer
    }

    public static func writeLine(_ data: Data, to handle: FileHandle) throws {
        var out = data
        out.append(0x0A)
        try handle.write(contentsOf: out)
    }
}
