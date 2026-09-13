import Foundation
import QuickElevateShared

private struct BackendAuthorizationRequest: Encodable {
    let requestId: String
    let helperNonce: String
    let localUid: UInt32
    let requestedDurationSeconds: Int
    let clientVersion: String
}

private struct BackendAuthorizationResponse: Decodable {
    let decision: String
    let reasonCode: String?
    let grantedDurationSeconds: Int?
    let authorizationToken: String?
    let correlationId: String
}

enum ElevationAuthorizationError: LocalizedError {
    case denied(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .denied(reason):
            "Elevation was denied: \(reason)"
        case .invalidResponse:
            "The authorization service returned an invalid response."
        }
    }
}

final class ElevationAuthorizationClient {
    func requestGrant(
        configuration: ManagedConfiguration,
        accessToken: String,
        nonce: String
    ) async throws -> String {
        let endpoint = configuration.apiBaseURL.appending(path: "api/v1/elevation-authorizations")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "x-correlation-id")
        request.httpBody = try JSONEncoder().encode(
            BackendAuthorizationRequest(
                requestId: UUID().uuidString,
                helperNonce: nonce,
                localUid: getuid(),
                requestedDurationSeconds: SharedConfig.defaultElevationSeconds,
                clientVersion: "0.1.0-alpha"
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ElevationAuthorizationError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(BackendAuthorizationResponse.self, from: data)
        guard http.statusCode == 200,
              decoded.decision == "allow",
              let token = decoded.authorizationToken,
              !token.isEmpty else {
            throw ElevationAuthorizationError.denied(decoded.reasonCode ?? "HTTP_\(http.statusCode)")
        }

        return token
    }
}
