import Foundation
import MSAL

enum EntraSilentTokenError: LocalizedError {
    case noPlatformSSOAccountFound(Int)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case let .noPlatformSSOAccountFound(count):
            if count == 0 {
                "No Platform SSO account found on this Mac. Sign in with your work account via Platform SSO."
            } else {
                "Multiple SSO accounts found (\(count)). Keep a single work account on this Mac."
            }
        case let .unavailable(message):
            message
        }
    }
}

struct DiscoveredAccount {
    let account: MSALAccount
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

        // Platform SSO / Enterprise SSO extension accounts are visible here even
        // when the user never signed in to Company Portal itself. `allAccounts()`
        // only returns MSAL-cached accounts, so it misses pure-PSSO sessions.
        let deviceAccounts = try await enumerateDeviceAccounts(application: application)
        let candidates = deviceAccounts.filter(\.isSSOAccount)
        let usable = candidates.isEmpty ? deviceAccounts : candidates

        guard usable.count == 1, let account = usable.first else {
            throw EntraSilentTokenError.noPlatformSSOAccountFound(usable.count)
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

    private func enumerateDeviceAccounts(application: MSALPublicClientApplication) async throws -> [MSALAccount] {
        let parameters = MSALAccountEnumerationParameters()
        parameters.returnOnlySignedInAccounts = false

        return try await withCheckedThrowingContinuation { continuation in
            application.accountsFromDevice(for: parameters) { accounts, error in
                if let accounts {
                    continuation.resume(returning: accounts)
                } else {
                    let message = error?.localizedDescription ?? "Could not enumerate device accounts."
                    continuation.resume(throwing: EntraSilentTokenError.unavailable(message))
                }
            }
        }
    }
}
