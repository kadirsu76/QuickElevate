using System.Text;
using System.Text.Json;
using Microsoft.Azure.Functions.Worker.Http;

namespace QuickElevate.Api;

public static class EasyAuthIdentityReader
{
    public static CallerIdentity Read(HttpRequestData request, BackendConfiguration config)
    {
        if (!request.Headers.TryGetValues("x-ms-client-principal", out var values))
        {
            throw new UnauthorizedAccessException("Missing Easy Auth principal.");
        }

        var encoded = values.Single();
        var principal = JsonSerializer.Deserialize<ClientPrincipal>(Encoding.UTF8.GetString(Convert.FromBase64String(encoded)))
            ?? throw new UnauthorizedAccessException("Invalid Easy Auth principal.");

        var claims = principal.Claims
            .GroupBy(claim => claim.Typ, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Val, StringComparer.OrdinalIgnoreCase);

        var tenantId = Find(claims, "tid", "http://schemas.microsoft.com/identity/claims/tenantid");
        var objectId = Find(claims, "oid", "http://schemas.microsoft.com/identity/claims/objectidentifier");
        var clientId = Find(claims, "azp", "appid");
        var scope = Find(claims, "scp", "http://schemas.microsoft.com/identity/claims/scope");

        if (!string.Equals(tenantId, config.TenantId, StringComparison.OrdinalIgnoreCase))
        {
            throw new UnauthorizedAccessException("Token tenant is not allowed.");
        }

        if (!string.Equals(clientId, config.NativeClientId, StringComparison.OrdinalIgnoreCase))
        {
            throw new UnauthorizedAccessException("Token client is not allowed.");
        }

        if (!scope.Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains("Elevation.Request", StringComparer.Ordinal))
        {
            throw new UnauthorizedAccessException("Token does not contain the required scope.");
        }

        return new CallerIdentity(tenantId, objectId, clientId);
    }

    private static string Find(IReadOnlyDictionary<string, string> claims, params string[] names)
    {
        foreach (var name in names)
        {
            if (claims.TryGetValue(name, out var value) && !string.IsNullOrWhiteSpace(value))
            {
                return value;
            }
        }
        throw new UnauthorizedAccessException($"Required claim missing: {names[0]}");
    }

    private sealed record ClientPrincipal(string AuthTyp, string NameTyp, string RoleTyp, ClientPrincipalClaim[] Claims);
    private sealed record ClientPrincipalClaim(string Typ, string Val);
}
