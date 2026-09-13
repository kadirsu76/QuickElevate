import Foundation

struct ManagedConfiguration {
    let tenantId: String
    let nativeClientId: String
    let apiScope: String
    let apiBaseURL: URL

    static func load() throws -> ManagedConfiguration {
        let domainName = "com.quickelevate.app"
        let defaults = UserDefaults.standard
        let managedValues = defaults.persistentDomain(forName: domainName) ?? [:]

        func value(_ key: String) -> String? {
            managedValues[key] as? String ?? defaults.string(forKey: key)
        }

        guard let tenantId = value("TenantId"),
              let nativeClientId = value("NativeClientId"),
              let apiAudience = value("ApiAudience"),
              let apiBaseURLString = value("ApiBaseUrl"),
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
