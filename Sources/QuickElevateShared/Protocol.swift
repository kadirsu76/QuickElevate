import Foundation

public enum ElevationAction: String, Codable {
    case authorizationContext
    case grant
    case revoke
    case status
    case ping
}

public struct ElevationRequest: Codable {
    public var action: ElevationAction
    public var authorizationToken: String?
    public var signingKeyModulus: String?
    public var signingKeyExponent: String?

    public init(
        action: ElevationAction,
        authorizationToken: String? = nil,
        signingKeyModulus: String? = nil,
        signingKeyExponent: String? = nil
    ) {
        self.action = action
        self.authorizationToken = authorizationToken
        self.signingKeyModulus = signingKeyModulus
        self.signingKeyExponent = signingKeyExponent
    }
}

public struct ElevationResponse: Codable {
    public var ok: Bool
    public var message: String
    public var isAdmin: Bool
    public var deadlineEpoch: TimeInterval?
    public var nonce: String?

    public init(ok: Bool, message: String, isAdmin: Bool, deadlineEpoch: TimeInterval?, nonce: String? = nil) {
        self.ok = ok
        self.message = message
        self.isAdmin = isAdmin
        self.deadlineEpoch = deadlineEpoch
        self.nonce = nonce
    }
}

public enum SharedConfig {
    public static let socketDirectory = "/var/run/quickelevate"
    public static let socketPath = "/var/run/quickelevate/quickelevate.sock"
    public static let defaultElevationSeconds = 60
}
