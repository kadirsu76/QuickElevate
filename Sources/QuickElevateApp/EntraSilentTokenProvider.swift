import Foundation
import MSAL

enum EntraSilentTokenError: LocalizedError {
    case noPlatformSSOAccount
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .noPlatformSSOAccount:
            "Platform SSO is not available for the current user. Complete Company Portal registration."
        case let .unavailable(message):
            message
        }
    }
}

final class EntraSilentTokenProvider {
    func acquireToken(configuration: ManagedConfiguration) async throws -> String {
        let authority = try MSALAADAuthority(url: URL(string: "https://login.microsoftonline.com/\(configuration.tenantId)")!)
        let msalConfiguration = MSALPublicClientApplicationConfig(
            clientId: configuration.nativeClientId,
            redirectUri: nil,
            authority: authority
        )
        let application = try MSALPublicClientApplication(configuration: msalConfiguration)
        let accounts = try application.allAccounts()

        guard accounts.count == 1, let account = accounts.first else {
            throw EntraSilentTokenError.noPlatformSSOAccount
        }

        let parameters = MSALSilentTokenParameters(scopes: [configuration.apiScope], account: account)
        parameters.forceRefresh = true

        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: parameters) { result, error in
                if let token = result?.accessToken {
                    continuation.resume(returning: token)
                } else {
                    let message = error?.localizedDescription ?? "Platform SSO token could not be acquired silently."
                    continuation.resume(throwing: EntraSilentTokenError.unavailable(message))
                }
            }
        }
    }
}
