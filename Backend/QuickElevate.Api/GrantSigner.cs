using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Azure.Identity;
using Azure.Security.KeyVault.Keys.Cryptography;

namespace QuickElevate.Api;

public sealed class GrantSigner(DefaultAzureCredential credential, BackendConfiguration configuration)
{
    public async Task<(string Token, DateTimeOffset ExpiresAt)> SignAsync(
        CallerIdentity caller,
        AuthorizationRequest request,
        int durationSeconds,
        CancellationToken cancellationToken)
    {
        var issuedAt = DateTimeOffset.UtcNow;
        var expiresAt = issuedAt.AddMinutes(2);
        var header = Base64Url(JsonSerializer.SerializeToUtf8Bytes(new { alg = "RS256", typ = "JWT" }));
        var payload = Base64Url(JsonSerializer.SerializeToUtf8Bytes(new
        {
            iss = configuration.GrantIssuer,
            aud = configuration.GrantAudience,
            jti = Guid.NewGuid().ToString("N"),
            iat = issuedAt.ToUnixTimeSeconds(),
            nbf = issuedAt.AddSeconds(-5).ToUnixTimeSeconds(),
            exp = expiresAt.ToUnixTimeSeconds(),
            tid = caller.TenantId,
            oid = caller.ObjectId,
            uid = request.LocalUid,
            nonce = request.HelperNonce,
            request_id = request.RequestId,
            action = "elevate",
            duration_seconds = durationSeconds
        }));

        var unsigned = Encoding.ASCII.GetBytes($"{header}.{payload}");
        var client = new CryptographyClient(new Uri(configuration.KeyVaultKeyId), credential);
        var signed = await client.SignAsync(SignatureAlgorithm.RS256, SHA256.HashData(unsigned), cancellationToken);
        return ($"{header}.{payload}.{Base64Url(signed.Signature)}", expiresAt);
    }

    private static string Base64Url(byte[] data) => Convert.ToBase64String(data).TrimEnd('=').Replace('+', '-').Replace('/', '_');
}
