using System.Net;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;

namespace QuickElevate.Api;

public sealed class AuthorizeElevation(
    BackendConfiguration configuration,
    GraphMembershipService graph,
    GrantSigner signer,
    ILogger<AuthorizeElevation> logger)
{
    [Function("AuthorizeElevation")]
    public async Task<HttpResponseData> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "v1/elevation-authorizations")] HttpRequestData request,
        CancellationToken cancellationToken)
    {
        var correlationId = request.Headers.TryGetValues("x-correlation-id", out var values)
            ? values.FirstOrDefault() ?? Guid.NewGuid().ToString()
            : Guid.NewGuid().ToString();

        try
        {
            var caller = EasyAuthIdentityReader.Read(request, configuration);
            var body = await request.ReadFromJsonAsync<AuthorizationRequest>(cancellationToken: cancellationToken);
            if (body is null || string.IsNullOrWhiteSpace(body.RequestId) || string.IsNullOrWhiteSpace(body.HelperNonce) || body.LocalUid < 500)
            {
                return await WriteAsync(request, HttpStatusCode.BadRequest, new AuthorizationResponse("deny", "INVALID_REQUEST", null, null, null, correlationId));
            }

            var isMember = await graph.IsMemberAsync(caller.ObjectId, cancellationToken);
            if (!isMember)
            {
                logger.LogInformation("Elevation denied. CorrelationId={CorrelationId} Oid={Oid}", correlationId, caller.ObjectId);
                return await WriteAsync(request, HttpStatusCode.Forbidden, new AuthorizationResponse("deny", "NOT_ACTIVE_MEMBER", null, null, null, correlationId));
            }

            var duration = Math.Min(Math.Max(5, body.RequestedDurationSeconds), configuration.MaximumElevationSeconds);
            duration = Math.Min(duration, configuration.DefaultElevationSeconds);
            var grant = await signer.SignAsync(caller, body, duration, cancellationToken);

            logger.LogInformation("Elevation authorized. CorrelationId={CorrelationId} Oid={Oid} Duration={Duration}", correlationId, caller.ObjectId, duration);
            return await WriteAsync(request, HttpStatusCode.OK, new AuthorizationResponse("allow", null, duration, grant.Token, grant.ExpiresAt, correlationId));
        }
        catch (UnauthorizedAccessException)
        {
            return await WriteAsync(request, HttpStatusCode.Unauthorized, new AuthorizationResponse("deny", "UNAUTHENTICATED", null, null, null, correlationId));
        }
        catch (HttpRequestException exception)
        {
            logger.LogWarning(exception, "Graph unavailable. CorrelationId={CorrelationId}", correlationId);
            return await WriteAsync(request, HttpStatusCode.ServiceUnavailable, new AuthorizationResponse("deny", "DIRECTORY_UNAVAILABLE", null, null, null, correlationId));
        }
        catch (Exception exception)
        {
            logger.LogError(exception, "Authorization failed. CorrelationId={CorrelationId}", correlationId);
            return await WriteAsync(request, HttpStatusCode.InternalServerError, new AuthorizationResponse("deny", "AUTHORIZATION_FAILED", null, null, null, correlationId));
        }
    }

    private static async Task<HttpResponseData> WriteAsync(HttpRequestData request, HttpStatusCode status, AuthorizationResponse payload)
    {
        var response = request.CreateResponse(status);
        await response.WriteAsJsonAsync(payload);
        return response;
    }
}
