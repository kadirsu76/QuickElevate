import Foundation
import MSAL

enum PlatformSSOIdentityError: LocalizedError {
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

struct PlatformSSOIdentity {
    let username: String?
    let objectId: String
    let tenantId: String
    let isSSOAccount: Bool
}

final class EntraSilentTokenProvider {
    func discoverIdentity(configuration: ManagedConfiguration) async throws -> PlatformSSOIdentity {
        let application = try makeApplication(configuration: configuration)
        let deviceAccounts = try await enumerateDeviceAccounts(application: application)
        let ssoAccounts = deviceAccounts.filter(\.isSSOAccount)
        let tenantAccounts = ssoAccounts.filter {
            $0.homeAccountId?.tenantId?.caseInsensitiveCompare(configuration.tenantId) == .orderedSame
        }

        guard tenantAccounts.count == 1,
              let account = tenantAccounts.first,
              let objectId = account.homeAccountId?.objectId,
              let tenantId = account.homeAccountId?.tenantId else {
            throw PlatformSSOIdentityError.noPlatformSSOAccountFound(tenantAccounts.count)
        }

        return PlatformSSOIdentity(
            username: account.username,
            objectId: objectId,
            tenantId: tenantId,
            isSSOAccount: account.isSSOAccount
        )
    }

    func acquireToken(configuration: ManagedConfiguration) async throws -> String {
        let application = try makeApplication(configuration: configuration)
        let identity = try await discoverIdentity(configuration: configuration)

        let accounts = try application.allAccounts()
        guard let account = accounts.first(where: {
            $0.homeAccountId?.objectId == identity.objectId && $0.homeAccountId?.tenantId == identity.tenantId
        }) else {
            throw PlatformSSOIdentityError.unavailable("PSSO identity was found, but no MSAL token cache account is available.")
        }

        let parameters = MSALSilentTokenParameters(scopes: [configuration.apiScope], account: account)
        parameters.forceRefresh = true

        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: parameters) { result, error in
                if let token = result?.accessToken {
                    continuation.resume(returning: token)
                } else {
                    let message = error?.localizedDescription ?? "Platform SSO token could not be acquired silently."
                    continuation.resume(throwing: PlatformSSOIdentityError.unavailable(message))
                }
            }
        }
    }

    private func makeApplication(configuration: ManagedConfiguration) throws -> MSALPublicClientApplication {
        let authority = try MSALAADAuthority(url: URL(string: "https://login.microsoftonline.com/\(configuration.tenantId)")!)
        let msalConfiguration = MSALPublicClientApplicationConfig(
            clientId: configuration.nativeClientId,
            redirectUri: nil,
            authority: authority
        )
        return try MSALPublicClientApplication(configuration: msalConfiguration)
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
                    continuation.resume(throwing: PlatformSSOIdentityError.unavailable(message))
                }
            }
        }
    }
}
