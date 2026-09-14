import Foundation
import MSAL

enum EntraSilentTokenError: LocalizedError {
    case noPlatformSSOAccountFound(Int)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .noPlatformSSOAccountFound(count):
            if count == 0 {
                "No Platform SSO account found. Sign in to Company Portal first."
            } else {
                "Multiple SSO accounts found (\(count)). Keep a single work account on this Mac."
            }
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
            throw EntraSilentTokenError.noPlatformSSOAccountFound(accounts.count)
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
