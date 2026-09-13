namespace QuickElevate.Api;

public sealed class BackendConfiguration
{
    public string TenantId => Required("TENANT_ID");
    public string PimGroupObjectId => Required("PIM_GROUP_OBJECT_ID");
    public string MembershipMode => Environment.GetEnvironmentVariable("MEMBERSHIP_MODE") ?? "Transitive";
    public int DefaultElevationSeconds => BoundedInt("DEFAULT_ELEVATION_SECONDS", 60, 5, 300);
    public int MaximumElevationSeconds => BoundedInt("MAXIMUM_ELEVATION_SECONDS", 300, 5, 3600);
    public string GrantIssuer => Required("GRANT_ISSUER");
    public string GrantAudience => Environment.GetEnvironmentVariable("GRANT_AUDIENCE") ?? "com.quickelevate.helper";
    public string KeyVaultKeyId => Required("KEY_VAULT_SIGNING_KEY_ID");

    private static string Required(string name) =>
        Environment.GetEnvironmentVariable(name) is { Length: > 0 } value
            ? value
            : throw new InvalidOperationException($"Missing required app setting: {name}");

    private static int BoundedInt(string name, int fallback, int min, int max)
    {
        var value = int.TryParse(Environment.GetEnvironmentVariable(name), out var parsed) ? parsed : fallback;
        return Math.Clamp(value, min, max);
    }
}
