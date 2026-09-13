import Foundation

struct ManagedConfiguration {
    let tenantId: String
    let nativeClientId: String
    let apiScope: String
    let apiBaseURL: URL

    static func load() throws -> ManagedConfiguration {
        let defaults = UserDefaults.standard
        guard let tenantId = defaults.string(forKey: "TenantId"),
              let nativeClientId = defaults.string(forKey: "NativeClientId"),
              let apiAudience = defaults.string(forKey: "ApiAudience"),
              let apiBaseURLString = defaults.string(forKey: "ApiBaseUrl"),
              let apiBaseURL = URL(string: apiBaseURLString) else {
            throw ConfigurationError.missingManagedSettings
        }

        return ManagedConfiguration(
            tenantId: tenantId,
            nativeClientId: nativeClientId,
            apiScope: "\(apiAudience)/Elevation.Request",
            apiBaseURL: apiBaseURL
        )
    }
}

enum ConfigurationError: LocalizedError {
    case missingManagedSettings

    var errorDescription: String? {
        "QuickElevate managed settings are missing. Contact IT."
    }
}
