import Foundation

public enum ElevationAction: String, Codable {
    case grant
    case revoke
    case status
    case ping
}

public struct ElevationRequest: Codable {
    public var action: ElevationAction
    public var user: String
    public var seconds: Int

    public init(action: ElevationAction, user: String, seconds: Int = 0) {
        self.action = action
        self.user = user
        self.seconds = seconds
    }
}

public struct ElevationResponse: Codable {
    public var ok: Bool
    public var message: String
    public var isAdmin: Bool
    public var deadlineEpoch: TimeInterval?

    public init(ok: Bool, message: String, isAdmin: Bool, deadlineEpoch: TimeInterval?) {
        self.ok = ok
        self.message = message
        self.isAdmin = isAdmin
        self.deadlineEpoch = deadlineEpoch
    }
}

public enum SharedConfig {
    public static let socketDirectory = "/var/run/quickelevate"
    public static let socketPath = "/var/run/quickelevate/quickelevate.sock"
    public static let defaultElevationSeconds = 60
}
