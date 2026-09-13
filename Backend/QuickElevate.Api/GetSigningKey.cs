using System.Net;
using Azure.Security.KeyVault.Keys;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;

namespace QuickElevate.Api;

public sealed class GetSigningKey(KeyClient keyClient)
{
    [Function("GetSigningKey")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "v1/signing-key")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var key = await keyClient.GetKeyAsync("elevation-grant", cancellationToken: cancellationToken);
        var response = request.CreateResponse(HttpStatusCode.OK);
        await response.WriteAsJsonAsync(new
        {
            kty = key.Value.KeyType.ToString(),
            n = Base64Url(key.Value.Key.N),
            e = Base64Url(key.Value.Key.E)
        });
        return response;
    }

    private static string Base64Url(byte[]? value) => value is { Length: > 0 }
        ? Convert.ToBase64String(value).TrimEnd('=').Replace('+', '-').Replace('/', '_')
        : throw new InvalidOperationException("Key does not expose RSA public material.");
}
