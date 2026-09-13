namespace QuickElevate.Api;

public sealed record AuthorizationRequest(
    string RequestId,
    string HelperNonce,
    int LocalUid,
    int RequestedDurationSeconds,
    string ClientVersion);

public sealed record AuthorizationResponse(
    string Decision,
    string? ReasonCode,
    int? GrantedDurationSeconds,
    string? AuthorizationToken,
    DateTimeOffset? ExpiresAt,
    string CorrelationId);

public sealed record CallerIdentity(string TenantId, string ObjectId, string ClientId);
